`timescale 1ns / 1ps
// ============================================================
// tb_stage3_top.v  — Stage 3 Unit Testbench
// Tests: Stage2 pipeline register, 4:2 CSA merge,
//        Final adder (CPA), LZAC, Sign generator,
//        Complementer + INC+1, Stage3 pipeline register
// ============================================================
module tb_stage3_top;

    localparam DP   = 3'b100;
    localparam SP   = 3'b011;
    localparam CLK_PERIOD = 10;

    reg clk, rst_n;

    // Stage3 inputs
    reg [162:0] Sum_s2, Carry_s2;
    reg [162:0] Aligned_C_dual_s2, Aligned_C_high_s2;
    reg [3:0]   Sign_AB_s2, Valid_s2;
    reg [2:0]   Prec_s2;
    reg         PD_mode_s2;

    // Stage3 outputs
    wire [162:0] Add_Rslt_s3;
    wire [7:0]   LZA_CNT_s3;
    wire         Result_sign_s3;
    wire [2:0]   Prec_s3;
    wire [3:0]   Valid_s3;

    integer errors, tc_errors;

    Stage3_Top dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .Sum_s2            (Sum_s2),
        .Carry_s2          (Carry_s2),
        .Aligned_C_dual_s2 (Aligned_C_dual_s2),
        .Aligned_C_high_s2 (Aligned_C_high_s2),
        .Sign_AB_s2        (Sign_AB_s2),
        .Prec_s2           (Prec_s2),
        .Valid_s2          (Valid_s2),
        .PD_mode_s2        (PD_mode_s2),
        .valid_s1          (1'b1),   // Always enable for unit test
        .Add_Rslt_s3       (Add_Rslt_s3),
        .LZA_CNT_s3        (LZA_CNT_s3),
        .Result_sign_s3    (Result_sign_s3),
        .Prec_s3           (Prec_s3),
        .Valid_s3          (Valid_s3)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Apply inputs and wait for outputs to settle through Stage3_top:
    // Stage3_top contains: Stage2_PipeReg → CSA → CPA+LZAC → Sign → Comp+INC → Stage3_PipeReg
    // That is 2 pipeline registers, so we need 2 @posedge clk after applying inputs.
    // Plus 1 extra cycle margin for combinational settling.
    task apply_and_wait;
        input [162:0] sum_in, carry_in, c_dual_in, c_high_in;
        input [3:0]   sign_in, valid_in;
        input [2:0]   prec_in;
        input         pd_in;
        begin
            Sum_s2            = sum_in;
            Carry_s2          = carry_in;
            Aligned_C_dual_s2 = c_dual_in;
            Aligned_C_high_s2 = c_high_in;
            Sign_AB_s2        = sign_in;
            Valid_s2          = valid_in;
            Prec_s2           = prec_in;
            PD_mode_s2        = pd_in;
            @(posedge clk);   // Stage2_Pipeline_Register inside Stage3_top captures
            @(posedge clk);   // Stage3 combinational completes
            @(posedge clk);   // Stage3_Pipeline_Register captures
            #1;               // sample after clock edge
        end
    endtask

    task check;
        input [256*8-1:0] name;
        input             cond;
        input [256*8-1:0] msg;
        begin
            if (!cond) begin
                $display("  FAIL [%0s]: %0s", name, msg);
                errors = errors + 1;
            end else begin
                $display("  PASS [%0s]", name);
            end
        end
    endtask

    initial begin
        errors = 0;
        // Init
        {Sum_s2, Carry_s2, Aligned_C_dual_s2, Aligned_C_high_s2} = 0;
        {Sign_AB_s2, Valid_s2} = 0;
        Prec_s2    = DP;  PD_mode_s2 = 1;
        rst_n = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("===================================================");
        $display("Stage 3 Unit Testbench");
        $display("===================================================");

        // ----------------------------------------------------------
        // TC-S3-1: Zero inputs → zero output, sign=0
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-S3-1: Zero Inputs ---");
        apply_and_wait(0, 0, 0, 0, 4'b0001, 4'b0001, DP, 1);
        $display("  Add_Rslt_s3=%h  LZA_CNT=%d  sign=%b",
                 Add_Rslt_s3, LZA_CNT_s3, Result_sign_s3);
        check("Zero→Zero",  (Add_Rslt_s3 === 163'd0),   "Expected zero output");
        check("Zero→NoSign",(Result_sign_s3 === 1'b0),   "Expected positive sign");
        if (errors == tc_errors) $display("  TC-S3-1: PASS");
        else                     $display("  TC-S3-1: FAIL");

        // ----------------------------------------------------------
        // TC-S3-2: Positive product, no addend, no carry
        // Place 1.0 (implicit bit at [106])
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-S3-2: Positive product at bit[106], no addend ---");
        begin : tc2
            reg [162:0] prod;
            prod = 163'd0;
            prod[106] = 1'b1;   // Implicit 1 at accumulator bit 106
            prod[105] = 1'b1;   // Fraction → represents 1.5 magnitude pattern
            apply_and_wait(prod, 163'd0, 163'd0, 163'd0,
                           4'b0001, 4'b0001, DP, 1);
            $display("  Add_Rslt[107:104]=%b  LZA_CNT=%d  sign=%b",
                     Add_Rslt_s3[107:104], LZA_CNT_s3, Result_sign_s3);
            check("PosSign",  (Result_sign_s3 === 1'b0), "Expected positive");
            check("BitPreserved", (Add_Rslt_s3[106] === 1'b1 && Add_Rslt_s3[105] === 1'b1),
                  "Bits 106:105 should be preserved");
            if (errors == tc_errors) $display("  TC-S3-2: PASS");
            else                     $display("  TC-S3-2: FAIL");
        end

        // ----------------------------------------------------------
        // TC-S3-3: CPA result MSB=1 → negative result detected
        // Inject a value with bit 162=1 (which would represent a very large
        // positive number in the raw accumulator; CPA_neg triggers negate).
        // After Complementer+INC the magnitude is 2^163 - input.
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-S3-3: CPA MSB=1 → Complementer+INC negation ---");
        begin : tc3
            reg [162:0] neg_val;
            neg_val = 163'd0;
            neg_val[162] = 1'b1;  // MSB set → CPA_neg=1 → negative sign
            neg_val[0]   = 1'b1;  // LSB set (so ~val+1 = 163'd0 + extra = nice value)
            apply_and_wait(neg_val, 163'd0, 163'd0, 163'd0,
                           4'b0000, 4'b0001, DP, 1);
            $display("  Result_sign = %b (expect 1 = negative, since CPA MSB=1)",
                     Result_sign_s3);
            check("NegSign", (Result_sign_s3 === 1'b1),
                  "CPA MSB=1 should give negative result sign");
            if (errors == tc_errors) $display("  TC-S3-3: PASS");
            else                     $display("  TC-S3-3: FAIL");
        end

        // ----------------------------------------------------------
        // TC-S3-4: Sum + addend accumulation (CSA merge)
        // Product bit[106]=1, Addend bit[105]=1 in BOTH C_dual and C_high
        // CSA: sum + 0 + c_dual + c_high → bit107=1 carry from double addend
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-S3-4: Product + Addend CSA merge ---");
        begin : tc4
            reg [162:0] prod, addend;
            prod   = 163'd0; prod[106]   = 1'b1;
            addend = 163'd0; addend[104] = 1'b1; // Small addend below implicit bit
            apply_and_wait(prod, 163'd0, addend, 163'd0,
                           4'b0000, 4'b0001, DP, 1);
            $display("  Add_Rslt[108:102]=%b  sign=%b",
                     Add_Rslt_s3[108:102], Result_sign_s3);
            check("AccumNonZero", (Add_Rslt_s3 !== 163'd0),
                  "Sum+addend should be non-zero");
            // Result = 1.0 + 0.25 = 1.25 at bit positions, bit106=1, bit104=1
            check("AccumBit106", (Add_Rslt_s3[106] === 1'b1),
                  "Bit 106 (implicit) should be set");
            if (errors == tc_errors) $display("  TC-S3-4: PASS");
            else                     $display("  TC-S3-4: FAIL");
        end

        // ----------------------------------------------------------
        // TC-S3-5: Prec/Valid passthrough to Stage4
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-S3-5: Prec/Valid passthrough ---");
        apply_and_wait(163'd0, 163'd0, 163'd0, 163'd0,
                       4'b0001, 4'b1111, SP, 0);
        $display("  Prec_s3=%b (expect SP=011)  Valid_s3=%b (expect 1111)",
                 Prec_s3, Valid_s3);
        check("PrecPass",  (Prec_s3  === SP),     "Prec should be SP");
        check("ValidPass", (Valid_s3 === 4'b1111), "Valid should be 1111");
        if (errors == tc_errors) $display("  TC-S3-5: PASS");
        else                     $display("  TC-S3-5: FAIL");

        // ----------------------------------------------------------
        // Summary
        // ----------------------------------------------------------
        repeat(2) @(posedge clk);
        $display("\n===================================================");
        if (errors == 0) $display("Stage 3 Tests: ALL PASSED (%0d/5)", 5);
        else             $display("Stage 3 Tests: FAILED (%0d errors)", errors);
        $display("===================================================");
        $finish;
    end

    initial begin #100000; $display("TIMEOUT"); $finish; end

endmodule
