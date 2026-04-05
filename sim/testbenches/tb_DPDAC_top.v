`timescale 1ns / 1ps
// ============================================================
// tb_DPDAC_top.v — Full Pipeline Integration Testbench
//
// Tests the complete 4-stage DPDAC pipeline:
//   DP  : 1.5 × 2.0 + 0.5  = 3.5   (5-cycle: 2-cycle multiply + 3 pipeline regs)
//   SP  : lane0: 2.0×0.5+1.0=2.0, lane1: 1.5×2.0+0.5=3.5  (4-cycle)
//   HP  : 4-lane all-ones  (4-cycle, structural check)
//   BF16: 4-lane structural check
//   Neg : DP  -1.5 × 2.0 + 0.0 = -3.0  (sign check)
// ============================================================
module tb_DPDAC_top;

    // Precision encodings
    localparam HP   = 3'b000;
    localparam BF16 = 3'b001;
    localparam TF32 = 3'b010;
    localparam SP   = 3'b011;
    localparam DP   = 3'b100;

    localparam CLK_PERIOD = 10;

    // DP pipe latency: 2 (Stage1 2-cycle multiply) + 1 (S1 reg) + 1 (S2→S3 reg) + 1 (S3 reg) + 1 (S4 reg) = 6
    // SP/HP/BF16 latency: 1+1+1+1 = 4 (Stage1 is 1 cycle for non-DP)
    localparam DP_LATENCY  = 6;
    localparam SP_LATENCY  = 4;

    reg clk, rst_n;

    reg [63:0] A_in, B_in, C_in;
    reg [2:0]  Prec;
    reg        Para, Cvt;

    wire [63:0] Result_out;
    wire [3:0]  Valid_out;
    wire        Result_sign_out;

    integer errors, tc_errors;

    // DP IEEE 754 constants
    localparam DP_1P5  = 64'h3FF8000000000000; // 1.5
    localparam DP_2P0  = 64'h4000000000000000; // 2.0
    localparam DP_1P0  = 64'h3FF0000000000000; // 1.0
    localparam DP_0P5  = 64'h3FE0000000000000; // 0.5
    localparam DP_3P5  = 64'h400C000000000000; // 3.5  (expected: 1.5×2.0+0.5)
    localparam DP_N1P5 = 64'hBFF8000000000000; // -1.5
    localparam DP_N1P0 = 64'hBFF0000000000000; // -1.0
    localparam DP_0P0  = 64'h0000000000000000; // 0.0
    localparam DP_N3P0 = 64'hC008000000000000; // -3.0 (expected: -1.5×2.0+0.0)

    // SP IEEE 754 constants (packed two per 64-bit word: upper[63:32], lower[31:0])
    // SP 1.0=0x3F800000, 2.0=0x40000000, 0.5=0x3F000000, 1.5=0x3FC00000, 3.5=0x40600000, 2.5=0x40200000
    localparam SP_DUAL_A = {32'h3FC00000, 32'h40000000}; // upper:1.5, lower:2.0
    localparam SP_DUAL_B = {32'h40000000, 32'h3F000000}; // upper:2.0, lower:0.5
    localparam SP_DUAL_C = {32'h3F000000, 32'h3F800000}; // upper:0.5, lower:1.0

    DPDAC_top dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .A_in           (A_in),
        .B_in           (B_in),
        .C_in           (C_in),
        .Prec           (Prec),
        .Para           (Para),
        .Cvt            (Cvt),
        .Result_out     (Result_out),
        .Valid_out      (Valid_out),
        .Result_sign_out(Result_sign_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Drive inputs for one cycle, then hold while pipeline drains
    task drive_and_wait;
        input [63:0] a, b, c;
        input [2:0]  prec;
        input        para, cvt;
        input integer latency;
        begin
            // DP mode uses a 2-cycle iterative multiplier controlled by Stage1 cnt.
            // Align launches to cnt==0 so each DP transaction starts on capture phase.
            if (prec == DP) begin
                while (dut.u_stage1.cnt !== 1'b0) @(posedge clk);
            end

            A_in = a; B_in = b; C_in = c;
            Prec = prec; Para = para; Cvt = cvt;
            @(posedge clk);
            // Hold inputs stable (DP needs 2 cycles for multiply)
            if (prec == DP) @(posedge clk);
            // Wait for pipeline to produce output
            repeat(latency) @(posedge clk);
            #1;
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
            end else
                $display("  PASS [%0s]", name);
        end
    endtask

    function [7:0] lzc163_tb;
        input [162:0] v;
        integer k;
        begin
            lzc163_tb = 8'd163;
            for (k = 162; k >= 0; k = k - 1) begin
                if (v[k]) begin
                    lzc163_tb = 8'(162 - k);
                    k = -1;
                end
            end
        end
    endfunction

    function [162:0] csa4_sum_ref;
        input [162:0] in0, in1, in2, in3;
        reg [162:0] s1, c1;
        begin
            s1 = in0 ^ in1 ^ in2;
            c1 = (in0 & in1) | (in0 & in2) | (in1 & in2);
            csa4_sum_ref = s1 ^ in3 ^ c1;
        end
    endfunction

    function [162:0] csa4_carry_ref;
        input [162:0] in0, in1, in2, in3;
        reg [162:0] s1, c1;
        begin
            s1 = in0 ^ in1 ^ in2;
            c1 = (in0 & in1) | (in0 & in2) | (in1 & in2);
            csa4_carry_ref = (s1 & in3) | (s1 & c1) | (in3 & c1);
        end
    endfunction

    task check_stage_invariants;
        input [256*8-1:0] tag;
        input integer cyc;
        reg [162:0] sum_ref;
        reg [162:0] carry_ref;
        reg [162:0] mag_ref;
        reg [7:0]   lzc_comb_exact;
        reg [7:0]   shift_amt;
        reg         expected_sign;
        integer     lzc_diff;
        begin
            // ---------------- Stage 2 CSA ----------------
            sum_ref   = csa4_sum_ref(dut.u_stage2.signed_p0, dut.u_stage2.signed_p1,
                                     dut.u_stage2.signed_p2, dut.u_stage2.signed_p3);
            carry_ref = csa4_carry_ref(dut.u_stage2.signed_p0, dut.u_stage2.signed_p1,
                                       dut.u_stage2.signed_p2, dut.u_stage2.signed_p3);
            if ((dut.Sum_s2 !== sum_ref) || (dut.Carry_s2 !== carry_ref)) begin
                $display("    CHK FAIL [%0s c%0d] S2 4:2 CSA mismatch", tag, cyc);
                errors = errors + 1;
            end else begin
                $display("    CHK PASS [%0s c%0d] S2 4:2 CSA", tag, cyc);
            end

            // ---------------- Stage 2 C routing ----------------
            if (dut.PD_mode_s2) begin
                if (dut.Aligned_C_high_s2 !== 163'd0) begin
                    $display("    CHK FAIL [%0s c%0d] PD-mode expects C_high path gated to zero", tag, cyc);
                    errors = errors + 1;
                end else begin
                    $display("    CHK PASS [%0s c%0d] PD-mode C routing", tag, cyc);
                end
            end else begin
                if ((dut.Aligned_C_dual_s2[81:0] !== 82'd0) || (dut.Aligned_C_high_s2[162:82] !== 81'd0)) begin
                    $display("    CHK FAIL [%0s c%0d] non-PD C split shape mismatch", tag, cyc);
                    errors = errors + 1;
                end else begin
                    $display("    CHK PASS [%0s c%0d] non-PD C split shape", tag, cyc);
                end
            end

            // ---------------- Stage 3 CSA + CPA ----------------
            sum_ref   = csa4_sum_ref(dut.u_stage3.Sum, dut.u_stage3.Carry,
                                     dut.u_stage3.Aligned_C_dual, dut.u_stage3.Aligned_C_high);
            carry_ref = csa4_carry_ref(dut.u_stage3.Sum, dut.u_stage3.Carry,
                                       dut.u_stage3.Aligned_C_dual, dut.u_stage3.Aligned_C_high);
            if ((dut.u_stage3.Sum2 !== sum_ref) || (dut.u_stage3.Carry2 !== carry_ref)) begin
                $display("    CHK FAIL [%0s c%0d] S3 4:2 CSA mismatch", tag, cyc);
                errors = errors + 1;
            end else begin
                $display("    CHK PASS [%0s c%0d] S3 4:2 CSA", tag, cyc);
            end

            if (dut.u_stage3.Add_Rslt_comb !== (dut.u_stage3.Sum2 + dut.u_stage3.Carry2)) begin
                $display("    CHK FAIL [%0s c%0d] S3 CPA mismatch", tag, cyc);
                errors = errors + 1;
            end else begin
                $display("    CHK PASS [%0s c%0d] S3 CPA", tag, cyc);
            end

            // ---------------- SignGen + Complement/INC+1 ----------------
            expected_sign = (dut.u_stage3.Add_Rslt_comb === 163'd0) ? 1'b0 : dut.u_stage3.Add_Rslt_comb[162];
            if (dut.u_stage3.Result_sign_comb !== expected_sign) begin
                $display("    CHK FAIL [%0s c%0d] Sign_Gen mismatch (exp=%b got=%b)",
                         tag, cyc, expected_sign, dut.u_stage3.Result_sign_comb);
                errors = errors + 1;
            end else begin
                $display("    CHK PASS [%0s c%0d] Sign_Gen", tag, cyc);
            end

            mag_ref = expected_sign ? ((~dut.u_stage3.Add_Rslt_comb) + 163'd1) : dut.u_stage3.Add_Rslt_comb;
            if (dut.u_stage3.Add_Rslt_mag !== mag_ref) begin
                $display("    CHK FAIL [%0s c%0d] Complement/INC+1 magnitude mismatch", tag, cyc);
                errors = errors + 1;
            end else begin
                $display("    CHK PASS [%0s c%0d] Complement/INC+1", tag, cyc);
            end

            // ---------------- LZAC ----------------
            lzc_comb_exact = lzc163_tb(dut.u_stage3.Add_Rslt_comb);
            lzc_diff = (dut.u_stage3.LZA_CNT_comb > lzc_comb_exact) ?
                       (dut.u_stage3.LZA_CNT_comb - lzc_comb_exact) :
                       (lzc_comb_exact - dut.u_stage3.LZA_CNT_comb);

            if (lzc_diff > 1) begin
                $display("    CHK FAIL [%0s c%0d] LZAC error >1 (pred=%0d exact=%0d)",
                         tag, cyc, dut.u_stage3.LZA_CNT_comb, lzc_comb_exact);
                errors = errors + 1;
            end else begin
                $display("    CHK PASS [%0s c%0d] LZAC error<=1 (pred=%0d exact=%0d)",
                         tag, cyc, dut.u_stage3.LZA_CNT_comb, lzc_comb_exact);
            end

            if (dut.LZA_CNT_s3 !== lzc163_tb(dut.Add_Rslt_s3)) begin
                $display("    CHK FAIL [%0s c%0d] S3 registered LZA mismatch", tag, cyc);
                errors = errors + 1;
            end else begin
                $display("    CHK PASS [%0s c%0d] S3 registered LZA", tag, cyc);
            end

            // ---------------- Stage 4 normalization + GRS ----------------
            shift_amt = (dut.LZA_CNT_s3 > 8'd162) ? 8'd162 : dut.LZA_CNT_s3;
            if (dut.u_stage4.Norm_mant !== (dut.Add_Rslt_s3 << shift_amt)) begin
                $display("    CHK FAIL [%0s c%0d] S4 normalization shift mismatch", tag, cyc);
                errors = errors + 1;
            end else begin
                $display("    CHK PASS [%0s c%0d] S4 normalization shift", tag, cyc);
            end

            if ((dut.u_stage4.G !== dut.u_stage4.Norm_mant[109]) ||
                (dut.u_stage4.R !== dut.u_stage4.Norm_mant[108]) ||
                (dut.u_stage4.S !== |dut.u_stage4.Norm_mant[107:0])) begin
                $display("    CHK FAIL [%0s c%0d] S4 G/R/S extraction mismatch", tag, cyc);
                errors = errors + 1;
            end else begin
                $display("    CHK PASS [%0s c%0d] S4 G/R/S extraction", tag, cyc);
            end
        end
    endtask

    task print_stage_snapshot;
        input integer cyc;
        begin
            $display("  [cycle %0d] S1: cnt=%b valid=%b mode(DP/PD2/PD4)=%b/%b/%b SignAB=%b SignC=%b",
                     cyc, dut.u_stage1.cnt, dut.valid_s1, dut.PD_mode_s1, dut.PD2_mode_s1, dut.PD4_mode_s1,
                     dut.Sign_AB_s1, dut.Sign_C_s1);
            $display("             S1: MaxExp=%h ExpDiff=%h ProdASC[31:0]=%h pp_sum[31:0]=%h pp_carry[31:0]=%h",
                     dut.MaxExp_s1, dut.ExpDiff_s1, dut.ProdASC_s1[31:0], dut.pp_sum_s1[31:0], dut.pp_carry_s1[31:0]);
            $display("             S2: Sum[127:96]=%h Carry[127:96]=%h C_dual[162:140]=%h C_high[162:140]=%h",
                     dut.Sum_s2[127:96], dut.Carry_s2[127:96], dut.Aligned_C_dual_s2[162:140], dut.Aligned_C_high_s2[162:140]);
            $display("             S3: Add_Rslt[162:140]=%h LZA=%0d Sign=%b",
                     dut.Add_Rslt_s3[162:140], dut.LZA_CNT_s3, dut.Result_sign_s3);
            $display("             S4: MaxExp_s4=%h Result_out=%h Valid=%b Sign=%b",
                     dut.MaxExp_s4_reg, Result_out, Valid_out, Result_sign_out);
            $display("             S4: exp_ab=%0d exp_c=%0d exp_raw=%0d exp_adj=%0d ovf=%b rnd_carry=%b",
                     $signed(dut.u_stage4.u_out_fmt.exp_ab_raw),
                     $signed(dut.u_stage4.u_out_fmt.exp_c_raw),
                     $signed(dut.u_stage4.u_out_fmt.exp_raw),
                     $signed(dut.u_stage4.u_out_fmt.exp_adj),
                     dut.u_stage4.overflow_flag,
                     dut.u_stage4.u_out_fmt.rnd_carry);
        end
    endtask

    initial begin
        errors = 0;
        A_in = 0; B_in = 0; C_in = 0;
        Prec = DP; Para = 0; Cvt = 0;
        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("===================================================");
        $display("DPDAC Full Pipeline Integration Testbench");
        $display("===================================================");

        // ----------------------------------------------------------
        // TC-DPDAC-1: DP: 1.5 × 2.0 + 0.5 = 3.5
        // Expected: 0x400C000000000000
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-DPDAC-1: DP 1.5*2.0+0.5 = 3.5 ---");
        drive_and_wait(DP_1P5, DP_2P0, DP_0P5, DP, 0, 0, DP_LATENCY);
        $display("  Result_out   = 0x%016h", Result_out);
        $display("  Expected     = 0x%016h", DP_3P5);
        $display("  Sign_out     = %b (expect 0)", Result_sign_out);
        $display("  Valid_out    = %b", Valid_out);
        check("DP_3.5",    (Result_out === DP_3P5),    "DP: 1.5*2.0+0.5 should be 3.5");
        check("DP_PosSign",(Result_sign_out === 1'b0), "Should be positive");
        if (errors == tc_errors) $display("  TC-DPDAC-1: PASS");
        else                     $display("  TC-DPDAC-1: FAIL");

        // ----------------------------------------------------------
        // TC-DPDAC-2: DP: -1.5 × 2.0 + 0.0 = -3.0
        // Expected: 0xC008000000000000
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-DPDAC-2: DP -1.5*2.0+0.0 = -3.0 ---");
        drive_and_wait(DP_N1P5, DP_2P0, DP_0P0, DP, 0, 0, DP_LATENCY);
        $display("  Result_out   = 0x%016h", Result_out);
        $display("  Expected     = 0x%016h", DP_N3P0);
        $display("  Sign_out     = %b (expect 1)", Result_sign_out);
        check("DP_neg3.0", (Result_out === DP_N3P0),   "DP: -1.5*2.0 should be -3.0");
        check("DP_NegSign",(Result_sign_out === 1'b1), "Should be negative");
        if (errors == tc_errors) $display("  TC-DPDAC-2: PASS");
        else                     $display("  TC-DPDAC-2: FAIL");

        // ----------------------------------------------------------
        // TC-DPDAC-3: DP zero: 0.0 × anything + 0.0 = 0.0
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-DPDAC-3: DP 0.0*2.0+0.0 = 0.0 ---");
        drive_and_wait(DP_0P0, DP_2P0, DP_0P0, DP, 0, 0, DP_LATENCY);
        $display("  Result_out   = 0x%016h (expect 0)", Result_out);
        check("DP_zero", (Result_out[62:0] === 63'd0), "Zero product should give zero");
        if (errors == tc_errors) $display("  TC-DPDAC-3: PASS");
        else                     $display("  TC-DPDAC-3: FAIL");

        // ----------------------------------------------------------
        // TC-DPDAC-4: SP dual-lane
        //   Lane high [63:32]: A=1.5f, B=2.0f, C=0.5f → 3.5f (0x40600000)
        //   Lane low  [31:0]:  A=2.0f, B=0.5f, C=1.0f → 2.0f (0x40000000)
        // Shared-exponent design: both share same normalized exponent
        // Expected: {0x40600000, 0x40600000} or structural non-zero check
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-DPDAC-4: SP dual-lane structural check ---");
        drive_and_wait(SP_DUAL_A, SP_DUAL_B, SP_DUAL_C, SP, 0, 0, SP_LATENCY);
        $display("  Result_out   = 0x%016h", Result_out);
        $display("  Valid_out    = %b (expect 0101)", Valid_out);
        $display("  Sign_out     = %b (expect 0)", Result_sign_out);
        check("SP_nonzero", (Result_out !== 64'd0), "SP result should be non-zero");
        check("SP_valid",   (Valid_out === 4'b0101), "SP valid should be 0101 (lanes 0 and 2)");
        check("SP_sign",    (Result_sign_out === 1'b0), "SP result should be positive");
        if (errors == tc_errors) $display("  TC-DPDAC-4: PASS");
        else                     $display("  TC-DPDAC-4: FAIL");

        // ----------------------------------------------------------
        // TC-DPDAC-5: HP quad-lane structural check
        // A = B = four HP 1.0 = {1.0,1.0,1.0,1.0} in packed format
        // HP 1.0 = 5-bit exp=15, mant=0 → packed in 14-bit slots: {0,15[4:0],0[9:0]}
        //   segment = {sign=0, exp=15, frac=0} but in component_formatter HP layout:
        //   A_in[62:58]=exp3[4:0], A_in[57:48]=frac3[9:0] etc.
        //   For 1.0 HP: exp=15 (bias), frac=0
        //   A_in[62:58]=5'd15, A_in[46:42]=5'd15, A_in[30:26]=5'd15, A_in[14:10]=5'd15
        // C = 0 (no addend)
        // Expected: 4 HP 1.0*1.0+0 = 1.0 → Valid=1111, non-zero output
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-DPDAC-5: HP quad-lane 1.0*1.0+0 structural check ---");
        begin : tc5
            reg [63:0] hp_a;
            hp_a = 64'd0;
            hp_a[62:58] = 5'd15;  // Lane3 exp=15 (1.0 HP)
            hp_a[46:42] = 5'd15;  // Lane2
            hp_a[30:26] = 5'd15;  // Lane1
            hp_a[14:10] = 5'd15;  // Lane0
            // HP uses SP_LATENCY+1=5 because after the SP test the pipeline
            // needs 1 extra cycle for Stage1's double-register path to settle.
            drive_and_wait(hp_a, hp_a, 64'd0, HP, 0, 0, SP_LATENCY+1);
            $display("  Result_out   = 0x%016h", Result_out);
            $display("  Valid_out    = %b (expect 1111)", Valid_out);
            check("HP_nonzero", (Result_out !== 64'd0), "HP product should be non-zero");
            check("HP_valid",   (Valid_out === 4'b1111), "HP valid should be 1111");
            check("HP_positive",(Result_sign_out === 1'b0), "HP 1*1 should be positive");
            if (errors == tc_errors) $display("  TC-DPDAC-5: PASS");
            else                     $display("  TC-DPDAC-5: FAIL");
        end

        // ----------------------------------------------------------
        // TC-DPDAC-6: BF16 quad-lane structural check
        // BF16 1.0 = exp=127, frac=0
        // component_formatter BF16: A_in[62:55]=exp3, A_in[54:48]=frac3 etc.
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-DPDAC-6: BF16 quad-lane 1.0*1.0+0 structural check ---");
        begin : tc6
            reg [63:0] bf16_a;
            bf16_a = 64'd0;
            bf16_a[62:55] = 8'd127;  // Lane3 exp=127 (1.0 BF16)
            bf16_a[46:39] = 8'd127;  // Lane2
            bf16_a[30:23] = 8'd127;  // Lane1
            bf16_a[14:7]  = 8'd127;  // Lane0
            drive_and_wait(bf16_a, bf16_a, 64'd0, BF16, 0, 0, SP_LATENCY);
            $display("  Result_out   = 0x%016h", Result_out);
            $display("  Valid_out    = %b (expect 1111)", Valid_out);
            check("BF16_nonzero", (Result_out !== 64'd0), "BF16 product should be non-zero");
            check("BF16_valid",   (Valid_out === 4'b1111), "BF16 valid should be 1111");
            if (errors == tc_errors) $display("  TC-DPDAC-6: PASS");
            else                     $display("  TC-DPDAC-6: FAIL");
        end

        // ----------------------------------------------------------
        // TC-DPDAC-7: Pipeline flush — apply multiple back-to-back DP ops
        //   Op1: 1.5 × 2.0 + 0.5 = 3.5
        //   Op2: 2.0 × 2.0 + 0.0 = 4.0
        // Verify output ordering is preserved
        // ----------------------------------------------------------
        // ----------------------------------------------------------
        // TC-DPDAC-7: Pipeline flush — apply multiple back-to-back DP ops
        //   Op1: 1.5 × 2.0 + 0.5 = 3.5
        //   Op2: 2.0 × 2.0 + 0.0 = 4.0
        // Verify output ordering is preserved
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-DPDAC-7: Back-to-back DP operations ---");
        // Drain pipeline and reset DUT to get cnt=0 on the next Op1 application
        A_in = 0; B_in = 0; C_in = 0; Prec = DP; Para = 0; Cvt = 0;
        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
        // Now cnt=0 at the start of the next posedge after idle
        // Op1: apply 1.5*2.0+0.5
        A_in = DP_1P5; B_in = DP_2P0; C_in = DP_0P5;
        Prec = DP; Para = 0; Cvt = 0;
        @(posedge clk);           // posedge: accept_inputs=1 (cnt=0), latch Op1
        @(posedge clk); #1;       // posedge: cnt=1, valid_s1=1 (Op1 product ready)
        // Op2 inputs (start inserting Op2 while Op1 is in stages 2-4)
        // #1 ensures the assignment comes strictly AFTER the posedge clock edge
        A_in = DP_2P0; B_in = DP_2P0; C_in = DP_0P0;
        // Wait DP_LATENCY-2=4 more posedges for Op1 to reach output
        repeat(DP_LATENCY-2) @(posedge clk); #1;
        $display("  Op1 Result = 0x%016h (expect 0x%016h)", Result_out, DP_3P5);
        check("BB_op1", (Result_out === DP_3P5), "Op1 should be 3.5");
        // Wait 4 more for Op2 (Op2 exits pipeline 4 cycles after Op1)
        @(posedge clk); @(posedge clk); @(posedge clk); @(posedge clk); #1;
        $display("  Op2 Result = 0x%016h (expect 0x4010000000000000 = 4.0)", Result_out);
        check("BB_op2", (Result_out === 64'h4010000000000000), "Op2 should be 4.0");
        if (errors == tc_errors) $display("  TC-DPDAC-7: PASS");
        else                     $display("  TC-DPDAC-7: FAIL");

        // ----------------------------------------------------------
        // TC-DPDAC-8: DP C-only pass-through
        //   0.0 × 0.0 + 1.0 = 1.0
        // Stresses Stage3 addend path correctness.
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-DPDAC-8: DP C-only +1.0 passthrough ---");
        drive_and_wait(DP_0P0, DP_0P0, DP_1P0, DP, 0, 0, DP_LATENCY);
        $display("  Result_out   = 0x%016h", Result_out);
        $display("  Expected     = 0x%016h", DP_1P0);
        $display("  DBG MaxExp_s4=0x%08h LZA=%0d Sign=%b", dut.MaxExp_s4_reg, dut.LZA_CNT_s3, dut.Result_sign_s3);
        $display("  DBG Add_Rslt_s3[162:140]=0x%h", dut.Add_Rslt_s3[162:140]);
        $display("  DBG exp_ab=%0d exp_c=%0d exp_raw=%0d exp_adj=%0d",
             $signed(dut.u_stage4.u_out_fmt.exp_ab_raw),
             $signed(dut.u_stage4.u_out_fmt.exp_c_raw),
             $signed(dut.u_stage4.u_out_fmt.exp_raw),
             $signed(dut.u_stage4.u_out_fmt.exp_adj));
        check("DP_C_only_pos1", (Result_out === DP_1P0), "DP: 0*0 + 1.0 should be 1.0");
        if (errors == tc_errors) $display("  TC-DPDAC-8: PASS");
        else                     $display("  TC-DPDAC-8: FAIL");

        // ----------------------------------------------------------
        // TC-DPDAC-9: DP C-only pass-through (negative)
        //   0.0 × 0.0 + (-1.0) = -1.0
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-DPDAC-9: DP C-only -1.0 passthrough ---");
        drive_and_wait(DP_0P0, DP_0P0, DP_N1P0, DP, 0, 0, DP_LATENCY);
        $display("  Result_out   = 0x%016h", Result_out);
        $display("  Expected     = 0x%016h", DP_N1P0);
        $display("  DBG MaxExp_s4=0x%08h LZA=%0d Sign=%b", dut.MaxExp_s4_reg, dut.LZA_CNT_s3, dut.Result_sign_s3);
        $display("  DBG Add_Rslt_s3[162:140]=0x%h", dut.Add_Rslt_s3[162:140]);
        check("DP_C_only_neg1", (Result_out === DP_N1P0), "DP: 0*0 + (-1.0) should be -1.0");
        if (errors == tc_errors) $display("  TC-DPDAC-9: PASS");
        else                     $display("  TC-DPDAC-9: FAIL");

        // ----------------------------------------------------------
        // TC-DPDAC-10: DP C-only fractional pass-through
        //   0.0 × 0.0 + 0.5 = 0.5
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-DPDAC-10: DP C-only +0.5 passthrough ---");
        drive_and_wait(DP_0P0, DP_0P0, DP_0P5, DP, 0, 0, DP_LATENCY);
        $display("  Result_out   = 0x%016h", Result_out);
        $display("  Expected     = 0x%016h", DP_0P5);
        check("DP_C_only_pos05", (Result_out === DP_0P5), "DP: 0*0 + 0.5 should be 0.5");
        if (errors == tc_errors) $display("  TC-DPDAC-10: PASS");
        else                     $display("  TC-DPDAC-10: FAIL");

        // ----------------------------------------------------------
        // TC-DPDAC-11: SP exact dual-lane numeric check
        // Paper claim: parallel SP operations should preserve independent lane results.
        // Expected lane1=3.5f (upper), lane0=2.0f (lower).
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-DPDAC-11: SP exact lane-value check (paper-claim stress) ---");
        $display("  EXPECTED DATAFLOW: independent SP lane math through S1-S4, not structural-only.");
        A_in = SP_DUAL_A; B_in = SP_DUAL_B; C_in = SP_DUAL_C;
        Prec = SP; Para = 0; Cvt = 0;
        for (integer cyc11 = 0; cyc11 < (SP_LATENCY + 3); cyc11 = cyc11 + 1) begin
            @(posedge clk); #1;
            print_stage_snapshot(cyc11);
            check_stage_invariants("TC11", cyc11);
        end
        $display("  Final Result_out = 0x%016h", Result_out);
        $display("  Expected         = 0x4060000040000000 (upper=3.5f, lower=2.0f)");
        check("SP_exact_dual_lane", (Result_out === 64'h4060000040000000),
              "SP dual-lane exact numeric mismatch vs paper parallel-lane claim");
        if (errors == tc_errors) $display("  TC-DPDAC-11: PASS");
        else                     $display("  TC-DPDAC-11: FAIL (use stage trace above to debug)");

        // ----------------------------------------------------------
        // TC-DPDAC-12: BF16 exact quad-lane numeric check
        // Paper claim: BF16 mode supported in DPDAC path; 1.0*1.0+0 should remain 1.0 in each lane.
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-DPDAC-12: BF16 exact lane-value check (paper-claim stress) ---");
        begin : tc12
            reg [63:0] bf16_a;
            bf16_a = 64'd0;
            bf16_a[62:55] = 8'd127;
            bf16_a[46:39] = 8'd127;
            bf16_a[30:23] = 8'd127;
            bf16_a[14:7]  = 8'd127;
            A_in = bf16_a; B_in = bf16_a; C_in = 64'd0;
            Prec = BF16; Para = 0; Cvt = 0;
            for (integer cyc12 = 0; cyc12 < (SP_LATENCY + 3); cyc12 = cyc12 + 1) begin
                @(posedge clk); #1;
                print_stage_snapshot(cyc12);
                check_stage_invariants("TC12", cyc12);
            end
            $display("  Final Result_out = 0x%016h", Result_out);
            $display("  Expected         = 0x3f803f803f803f80 (BF16 1.0 per lane)");
            check("BF16_exact_quad_lane", (Result_out === 64'h3f803f803f803f80),
                  "BF16 lane-value mismatch vs paper supported-format claim");
            if (errors == tc_errors) $display("  TC-DPDAC-12: PASS");
            else                     $display("  TC-DPDAC-12: FAIL (use stage trace above to debug)");
        end

        // ----------------------------------------------------------
        // TC-DPDAC-13: TF32 exact dual-lane numeric check
        // Paper claim: 2-term TF32 dot-product supported in PD2_mode.
        // Here we stress identity behavior: 1.0*1.0+0.0 per active lane.
        // ----------------------------------------------------------
        tc_errors = errors;
        $display("\n--- TC-DPDAC-13: TF32 exact lane-value check (paper-claim stress) ---");
        begin : tc13
            reg [63:0] tf32_one;
            tf32_one = 64'd0;
            tf32_one[62:55] = 8'd127;
            tf32_one[41:32] = 10'd0;
            tf32_one[30:23] = 8'd127;
            tf32_one[9:0]   = 10'd0;

            A_in = tf32_one; B_in = tf32_one; C_in = 64'd0;
            Prec = TF32; Para = 0; Cvt = 0;
            for (integer cyc13 = 0; cyc13 < (SP_LATENCY + 3); cyc13 = cyc13 + 1) begin
                @(posedge clk); #1;
                print_stage_snapshot(cyc13);
                check_stage_invariants("TC13", cyc13);
            end
            $display("  Final Result_out = 0x%016h", Result_out);
            $display("  Expected         = 0x3f8000003f800000 (TF32 1.0 in active lanes)");
            check("TF32_exact_dual_lane", (Result_out === 64'h3f8000003f800000),
                  "TF32 lane-value mismatch vs paper supported-format claim");
            if (errors == tc_errors) $display("  TC-DPDAC-13: PASS");
            else                     $display("  TC-DPDAC-13: FAIL (use stage trace above to debug)");
        end


        // ----------------------------------------------------------
        // Summary
        // ----------------------------------------------------------
        repeat(4) @(posedge clk);
        $display("\n===================================================");
        $display("Full Pipeline Results:");
        if (errors == 0)
            $display("  ALL TESTS PASSED (13/13)");
        else
            $display("  FAILED: %0d errors", errors);
        $display("===================================================");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #500000;
        $display("WATCHDOG TIMEOUT — simulation exceeded 500us");
        $finish;
    end

endmodule
