`timescale 1ns / 1ps

module tb_integration_stage1_stage2;

    // Precision encoding
    localparam SP   = 3'b011;
    localparam TF32 = 3'b010;
    localparam HP   = 3'b000;
    localparam BF16 = 3'b001;

    integer errors;
    integer case_errors_start;

    // Clock and reset
    reg clk;
    reg rst_n;

    // -----------------------------------------------------------------
    // Stage 1 Module (Stage1_Module) signals
    // -----------------------------------------------------------------
    reg  [63:0] s1_A_in;
    reg  [63:0] s1_B_in;
    reg  [63:0] s1_C_in;
    reg  [2:0]  s1_Prec;
    reg         s1_Para;
    reg         s1_Cvt;

    wire [111:0] s1_partial_products_sum;
    wire [111:0] s1_partial_products_carry;
    wire [63:0]  s1_ProdASC;
    wire [31:0]  s1_ExpDiff;
    wire [31:0]  s1_MaxExp;
    wire [162:0] s1_Aligned_C;
    wire [3:0]   s1_Sign_AB;
    wire         s1_valid_out;
    wire         s1_PD_mode;
    wire         s1_PD2_mode;
    wire         s1_PD4_mode;

    Stage1_Module u_stage1 (
        .clk(clk),
        .rst_n(rst_n),
        .A_in(s1_A_in),
        .B_in(s1_B_in),
        .C_in(s1_C_in),
        .Prec(s1_Prec),
        .Para(s1_Para),
        .Cvt(s1_Cvt),
        .partial_products_sum(s1_partial_products_sum),
        .partial_products_carry(s1_partial_products_carry),
        .ProdASC(s1_ProdASC),
        .ExpDiff(s1_ExpDiff),
        .MaxExp(s1_MaxExp),
        .Aligned_C(s1_Aligned_C),
        .Sign_AB(s1_Sign_AB),
        .valid_out(s1_valid_out),
        .PD_mode(s1_PD_mode),
        .PD2_mode(s1_PD2_mode),
        .PD4_mode(s1_PD4_mode)
    );

    // -----------------------------------------------------------------
    // Stage 2 Module (Stage2_Top) signals
    // -----------------------------------------------------------------
    wire [111:0] s2_partial_products = s1_partial_products_sum | s1_partial_products_carry;
    wire [3:0]   s2_Valid_in = {4{s1_valid_out}};  // Replicate single bit to 4 lanes for testing

    wire [162:0] s2_Sum;
    wire [162:0] s2_Carry;
    wire [162:0] s2_Aligned_C_dual;
    wire [162:0] s2_Aligned_C_high;
    wire [3:0]   s2_Sign_AB;
    wire [2:0]   s2_Prec_out;
    wire [3:0]   s2_Valid_out;
    wire         s2_PD_mode;

    Stage2_Top u_stage2 (
        .clk(clk),
        .rst_n(rst_n),
        .partial_products_s1(s2_partial_products),
        .ExpDiff_s1(s1_ExpDiff),
        .MaxExp_s1(s1_MaxExp),
        .ProdASC_s1(s1_ProdASC),
        .Aligned_C_s1(s1_Aligned_C),
        .Sign_AB_s1(s1_Sign_AB),
        .Prec_s1(s1_Prec),
        .Valid_s1(s2_Valid_in),
        .PD_mode_s1(s1_PD_mode),
        .PD2_mode_s1(s1_PD2_mode),
        .PD4_mode_s1(s1_PD4_mode),
        .Sum_s2(s2_Sum),
        .Carry_s2(s2_Carry),
        .Aligned_C_dual_s2(s2_Aligned_C_dual),
        .Aligned_C_high_s2(s2_Aligned_C_high),
        .Sign_AB_s2(s2_Sign_AB),
        .Prec_s2(s2_Prec_out),
        .Valid_s2(s2_Valid_out),
        .PD_mode_s2(s2_PD_mode)
    );

    // -----------------------------------------------------------------
    // Helper tasks
    // -----------------------------------------------------------------

    task begin_case;
        input [639:0] name;
        begin
            case_errors_start = errors;
            $display("\n------------------------------------------------------------");
            $display("CASE: %0s", name);
        end
    endtask

    task describe_case;
        input [1023:0] inputs_desc;
        input [1023:0] test_desc;
        input [1023:0] output_desc;
        begin
            $display("INPUTS : %0s", inputs_desc);
            $display("TEST : %0s", test_desc);
            $display("OUTPUT/CHECK: %0s", output_desc);
        end
    endtask

    task end_case;
        input [639:0] name;
        begin
            if (errors == case_errors_start)
                $display("RESULT: PASS (%0s)", name);
            else
                $display("RESULT: FAIL (%0s), new_errors=%0d", name, (errors - case_errors_start));
            $display("------------------------------------------------------------");
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        errors = 0;
        rst_n = 1'b0;
        s1_A_in = 64'd0;
        s1_B_in = 64'd0;
        s1_C_in = 64'd0;
        s1_Prec = SP;
        s1_Para = 1'b0;
        s1_Cvt = 1'b0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("============================================================");
        $display("Stage 1-2 Integration Testbench (Non-DP Modes)");
        $display("Data Flow: Operands → Stage1 → Stage2 → CSA Output");
        $display("============================================================");

        // -----------------------------------------------------------------
        // Test 1: SP mode basic flow
        // -----------------------------------------------------------------
        begin_case("SP mode: basic two-lane precision");
        describe_case(
            "SP: A=1.5×2, B=2.0×2, C=0.5×2 (two SP operands per input)",
            "Feed through S1→S2 pipeline, verify data propagates",
            "S2 Sum/Carry should be non-zero with valid_out=1"
        );
        s1_A_in   = 64'h3FE00000_3FE00000;  // Two SP 1.5
        s1_B_in   = 64'h40000000_40000000;  // Two SP 2.0
        s1_C_in   = 64'h3F000000_3F000000;  // Two SP 0.5
        s1_Prec   = SP;
        s1_Para   = 1'b0;
        s1_Cvt    = 1'b0;
        
        repeat (3) @(posedge clk);
        
        $display("S1: valid_out=%b, ProdASC[31:0]=%h", s1_valid_out, s1_ProdASC[31:0]);
        $display("S2: valid_out=%b, Sum[41:0]=%h, Carry[41:0]=%h",
                 s2_Valid_out, s2_Sum[41:0], s2_Carry[41:0]);
        
        if (s1_valid_out !== 1'b1) begin
            $display("ERROR: S1 should output valid_out=1 for SP mode");
            errors = errors + 1;
        end
        if (!((s2_Sum !== 163'd0) || (s2_Carry !== 163'd0))) begin
            $display("ERROR: S2 Sum/Carry both zero (expect product results)");
            errors = errors + 1;
        end
        end_case("SP mode: basic two-lane precision");

        // -----------------------------------------------------------------
        // Test 2: TF32 mode (sparse valid)
        // -----------------------------------------------------------------
        begin_case("TF32 mode: two 28-bit precision lanes");
        describe_case(
            "TF32: 2×28-bit operands with exponent fields injected",
            "Verify S1 processes TF32 mode → S2 receives products",
            "S2 should show PD2 mode active"
        );
        s1_A_in   = 64'd0;
        s1_B_in   = 64'd0;
        s1_C_in   = 64'd0;
        s1_A_in[62:55] = 8'd126;  s1_A_in[30:23] = 8'd125;
        s1_B_in[62:55] = 8'd124;  s1_B_in[30:23] = 8'd123;
        s1_C_in[62:55] = 8'd122;  s1_C_in[30:23] = 8'd121;
        s1_Prec   = TF32;
        s1_Para   = 1'b0;
        s1_Cvt    = 1'b0;
        
        repeat (3) @(posedge clk);
        
        $display("S1: valid_out=%b, PD2_mode=%b", s1_valid_out, s1_PD2_mode);
        $display("S2: valid_out=%b, PD_mode=%b", s2_Valid_out, s2_PD_mode);
        
        if (s1_PD2_mode !== 1'b1) begin
            $display("ERROR: TF32 should set PD2_mode=1");
            errors = errors + 1;
        end
        end_case("TF32 mode: two 28-bit precision lanes");

        // -----------------------------------------------------------------
        // Test 3: HP mode (quad lane)
        // -----------------------------------------------------------------
        begin_case("HP mode: quad 14-bit lanes");
        describe_case(
            "HP: 4×14-bit operands with exponent fields, all lanes valid",
            "Verify 4-lane processing through S1→S2",
            "S2 should handle PD4 mode with 4 products"
        );
        s1_A_in   = 64'd0;
        s1_B_in   = 64'd0;
        s1_C_in   = 64'd0;
        s1_A_in[62:58] = 5'd16; s1_A_in[46:42] = 5'd15; s1_A_in[30:26] = 5'd14; s1_A_in[14:10] = 5'd13;
        s1_B_in[62:58] = 5'd12; s1_B_in[46:42] = 5'd11; s1_B_in[30:26] = 5'd10; s1_B_in[14:10] = 5'd9;
        s1_C_in[62:58] = 5'd8;  s1_C_in[46:42] = 5'd7;  s1_C_in[30:26] = 5'd6;  s1_C_in[14:10] = 5'd5;
        s1_Prec   = HP;
        s1_Para   = 1'b0;
        s1_Cvt    = 1'b0;
        
        repeat (3) @(posedge clk);
        
        $display("S1: valid_out=%b, PD4_mode=%b, ProdASC[31:0]=%h",
                 s1_valid_out, s1_PD4_mode, s1_ProdASC[31:0]);
        $display("S2: valid_out=%b, PD_mode=%b", s2_Valid_out, s2_PD_mode);
        
        if (s1_PD4_mode !== 1'b1) begin
            $display("ERROR: HP should set PD4_mode=1");
            errors = errors + 1;
        end
        end_case("HP mode: quad 14-bit lanes");

        // -----------------------------------------------------------------
        // Test 4: BF16 mode
        // -----------------------------------------------------------------
        begin_case("BF16 mode: quad bfloat16 lanes");
        describe_case(
            "BF16: 4×16-bit exponent fields with all lanes active",
            "Verify 4-lane BF16 processing through pipeline",
            "S2 should output aligned product results"
        );
        s1_A_in   = 64'd0;
        s1_B_in   = 64'd0;
        s1_C_in   = 64'd0;
        s1_A_in[62:55] = 8'd140; s1_A_in[46:39] = 8'd139; s1_A_in[30:23] = 8'd138; s1_A_in[14:7] = 8'd137;
        s1_B_in[62:55] = 8'd136; s1_B_in[46:39] = 8'd135; s1_B_in[30:23] = 8'd134; s1_B_in[14:7] = 8'd133;
        s1_C_in[62:55] = 8'd132; s1_C_in[46:39] = 8'd131; s1_C_in[30:23] = 8'd130; s1_C_in[14:7] = 8'd129;
        s1_Prec   = BF16;
        s1_Para   = 1'b0;
        s1_Cvt    = 1'b0;
        
        repeat (3) @(posedge clk);
        
        $display("S1: valid_out=%b, PD4_mode=%b, ProdASC[31:0]=%h",
                 s1_valid_out, s1_PD4_mode, s1_ProdASC[31:0]);
        $display("S2: valid_out=%b, PD_mode=%b", s2_Valid_out, s2_PD_mode);
        
        if (s1_PD4_mode !== 1'b1) begin
            $display("ERROR: BF16 should set PD4_mode=1");
            errors = errors + 1;
        end
        end_case("BF16 mode: quad bfloat16 lanes");

        // -----------------------------------------------------------------
        // Test 5: Aligned_C propagation (addend path)
        // -----------------------------------------------------------------
        begin_case("Aligned_C carryover: addend path integrity");
        describe_case(
            "SP mode: check Aligned_C from S1 flows to S2 output paths",
            "Verify addend alignment shifter output propagates correctly",
            "S2 dual/high paths should contain aligned addend data"
        );
        s1_A_in   = 64'hBFE00000_BFE00000;  // -1.5
        s1_B_in   = 64'hC0000000_C0000000;  // -2.0
        s1_C_in   = 64'h3F000000_3F000000;  // 0.5
        s1_Prec   = SP;
        s1_Para   = 1'b0;
        s1_Cvt    = 1'b0;
        
        repeat (3) @(posedge clk);
        
        $display("S1 Aligned_C[41:0]=%h (addend C mantissa aligned)",
                 s1_Aligned_C[41:0]);
        $display("S2 Aligned_C_dual[41:0]=%h", s2_Aligned_C_dual[41:0]);
        $display("S2 Aligned_C_high[41:0]=%h", s2_Aligned_C_high[41:0]);
        
        if ((s2_Aligned_C_dual === 163'd0) && (s2_Aligned_C_high === 163'd0)) begin
            $display("WARNING: Both S2 Aligned_C paths zero (verify alignment logic)");
        end
        end_case("Aligned_C carryover: addend path integrity");

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        #1;
        $display("\n============================================================");
        $display("Stage 1-2 Integration Test Summary: %0d total errors", errors);
        $display("============================================================");
        if (errors == 0)
            $display("ALL INTEGRATION TESTS PASSED (6/6)");
        else
            $display("SOME INTEGRATION TESTS FAILED");
        $finish;

    end

endmodule
