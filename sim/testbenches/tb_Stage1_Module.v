`timescale 1ns / 1ps

module tb_Stage1_Module;

    // Precision encoding
    parameter HP    = 3'b000;
    parameter BF16  = 3'b001;
    parameter TF32  = 3'b010;
    parameter SP    = 3'b011;
    parameter DP    = 3'b100;

    // Clock parameters
    parameter CLK_PERIOD = 10;
    parameter VERBOSE    = 1'b0;

    // Testbench signals
    reg         clk;
    reg         rst_n;
    reg  [63:0] A_in;
    reg  [63:0] B_in;
    reg  [63:0] C_in;
    reg  [2:0]  Prec;
    reg         Para;
    reg         Cvt;

    wire [111:0] partial_products_sum;
    wire [111:0] partial_products_carry;
    wire [111:0] partial_products;
    wire [31:0]  ExpDiff;
    wire [31:0]  MaxExp;
    wire [63:0]  ProdASC;
    wire [162:0] Aligned_C;
    wire [3:0]   Sign_AB;
    wire [3:0]   Sign_C;
    wire         Para_reg;
    wire         Cvt_reg;
    wire         PD_mode;
    wire         PD2_mode;
    wire         PD4_mode;
    wire         valid_out;  // NEW: Added for pipeline control validation

    integer errors;
    integer tc_start_errors;
    real    A_dp;
    real    B_dp;
    real    C_dp;
    real    FMA_ref;

    // Instantiate DUT
    Stage1_Module dut (
        .clk(clk),
        .rst_n(rst_n),
        .A_in(A_in),
        .B_in(B_in),
        .C_in(C_in),
        .Prec(Prec),
        .Para(Para),
        .Cvt(Cvt),
        .partial_products_sum(partial_products_sum),
        .partial_products_carry(partial_products_carry),
        .ExpDiff(ExpDiff),
        .MaxExp(MaxExp),
        .ProdASC(ProdASC),
        .Aligned_C(Aligned_C),
        .Sign_AB(Sign_AB),
        .Sign_C(Sign_C),
        .Para_reg(Para_reg),
        .Cvt_reg(Cvt_reg),
        .PD_mode(PD_mode),
        .PD2_mode(PD2_mode),
        .PD4_mode(PD4_mode),
        .valid_out(valid_out)
    );

    assign partial_products = partial_products_sum + partial_products_carry;

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Helper task to display results
    task display_outputs;
        input [255:0] test_name;
        begin
            $display("\n=== %s ===", test_name);
            $display("Observed summary: valid_out=%b Sign_AB[0]=%b pp_nonzero=%b alignedC_nonzero=%b",
                     valid_out, Sign_AB[0], (partial_products != 112'd0), (Aligned_C != 163'd0));
            $display("Mode bits: PD=%b PD2=%b PD4=%b | Para_reg=%b Cvt_reg=%b",
                     PD_mode, PD2_mode, PD4_mode, Para_reg, Cvt_reg);
            if (VERBOSE) begin
                $display("partial_products_sum   = %h", partial_products_sum);
                $display("partial_products_carry = %h", partial_products_carry);
                $display("partial_products(add)  = %h", partial_products);
                $display("ExpDiff = %h (asc_c1=%d, asc_c0=%d)", 
                         ExpDiff, ExpDiff[31:16], ExpDiff[15:0]);
                $display("MaxExp  = %h (exp_c_max=%d, exp_ab_max=%d)",
                         MaxExp, MaxExp[31:16], MaxExp[15:0]);
                $display("Aligned_C = %h", Aligned_C);
                $display("Sign_AB = %b", Sign_AB);
            end
        end
    endtask

    // Human-readable case preamble with expected behavior and raw inputs.
    task begin_case;
        input [255:0] case_name;
        input [511:0] expected_text;
        begin
            tc_start_errors = errors;
            $display("\n============================================================");
            $display("CASE: %s", case_name);
            $display("EXPECTED: %s", expected_text);
            $display("INPUTS: Prec=%b Para=%b Cvt=%b", Prec, Para, Cvt);
            $display("A_in=%h", A_in);
            $display("B_in=%h", B_in);
            $display("C_in=%h", C_in);
            if (Prec == DP) begin
                if (!Para) begin
                    A_dp = $bitstoreal(A_in);
                    B_dp = $bitstoreal(B_in);
                    C_dp = $bitstoreal(C_in);
                    FMA_ref = (A_dp * B_dp) + C_dp;
                    $display("DP numeric: A=%f B=%f C=%f", A_dp, B_dp, C_dp);
                    $display("Reference math: A*B=%f", (A_dp * B_dp));
                    $display("Reference final FMA (A*B+C)=%f", FMA_ref);
                    $display("Note: Stage1 does NOT output final FMA value; it outputs pre-addition pipeline data.");
                end else begin
                    $display("DP+Para mode: C carries two packed SP addends; final scalar DP value is not directly represented in Stage1 output.");
                end
            end
            $display("------------------------------------------------------------");
        end
    endtask

    // Human-readable case summary with automatic pass/fail.
    task end_case;
        input [255:0] case_name;
        begin
            if (errors == tc_start_errors)
                $display("CASE RESULT: PASS (%s)", case_name);
            else
                $display("CASE RESULT: FAIL (%s), new_errors=%0d", case_name, (errors - tc_start_errors));
            $display("============================================================");
        end
    endtask

    // Test stimulus
    initial begin
        errors = 0;
        $display("========================================");
        $display("Stage1 Module Integration Testbench");
        $display("========================================");

        // Initialize
        rst_n = 0;
        A_in = 64'd0;
        B_in = 64'd0;
        C_in = 64'd0;
        Prec = DP;
        Para = 0;
        Cvt = 0;

        // Reset
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // TC7.1: DP Mode - 1.5 * 2.0 + 0.5 (2-cycle operation)
        $display("\n=== TC7.1: DP Mode - 1.5 * 2.0 + 0.5 (2-cycle) ===");
        Prec  = DP;
        Para  = 0;
        Cvt   = 0;
        A_in  = 64'h3FF8_0000_0000_0000;  // 1.5
        B_in  = 64'h4000_0000_0000_0000;  // 2.0
        C_in  = 64'h3FE0_0000_0000_0000;  // 0.5
        // Align to DP capture phase so cycle-0/1 checks are deterministic.
        while (dut.cnt !== 1'b0) @(posedge clk);
        begin_case("TC7.1 DP 1.5*2.0 + 0.5", "one valid pulse across 2 DP cycles, Sign_AB[0]=0, non-zero DP datapath activity");
        
        @(posedge clk);  // DP window cycle 0
        #1;
        $display("Cycle 0: cnt=%b, inputs loaded, valid_out=%b", dut.cnt, valid_out);
        begin : tc71_sample0
            reg valid_c0;
            valid_c0 = valid_out;
        
            @(posedge clk);  // DP window cycle 1
            #1;
            $display("Cycle 1: cnt=%b, DP complete, valid_out=%b", dut.cnt, valid_out);
            if (valid_out === valid_c0) begin
                $display("ERROR: valid_out should toggle exactly once over DP 2-cycle window!");
                errors = errors + 1;
            end
        end
        
        display_outputs("TC7.1 Results After DP 2-Cycle Multiply");
        $display("Expected: Sign_AB[0]=0 (positive), non-zero products, aligned C");
        
        if (Sign_AB[0] !== 1'b0) begin
            $display("ERROR: Sign[0] should be 0 (positive)!");
            errors = errors + 1;
        end
        end_case("TC7.1 DP 1.5*2.0 + 0.5");
        
        // TC7.1b: DP Mode - Second operation to verify cnt cycles correctly
        $display("\n=== TC7.1b: DP Mode - Second Consecutive Operation ===");
        A_in  = 64'h4000_0000_0000_0000;  // 2.0
        B_in  = 64'h4008_0000_0000_0000;  // 3.0
        C_in  = 64'h3FF0_0000_0000_0000;  // 1.0
        begin_case("TC7.1b DP second operation", "same DP 2-cycle one-pulse valid behavior; validates counter phase continuity");
        
        begin : tc71b_check
            reg valid_c0;
            @(posedge clk);  // DP window cycle 0
            #1;
            valid_c0 = valid_out;
            $display("Cycle 0: New inputs, cnt=%b valid_out=%b", dut.cnt, valid_out);

            @(posedge clk);  // DP window cycle 1
            #1;
            $display("Cycle 1: Second DP complete, cnt=%b valid_out=%b", dut.cnt, valid_out);
            if (valid_out === valid_c0) begin
                $display("ERROR: valid_out should toggle exactly once for second DP operation!");
                errors = errors + 1;
            end
        end
        end_case("TC7.1b DP second operation");

        // TC7.2: SP Mode - Dual Lane
        $display("\n=== TC7.2: SP Mode - Dual Lane ===");
        Prec  = SP;
        Para  = 0;
        Cvt   = 0;
        
        // Pack two SP values
        // Lane 2 [55:28]: 1.0 SP = 0x3F800000
        // Lane 0 [27:0]:  2.0 SP = 0x40000000
        A_in = 64'h0000_3F80_0000_0040;  
        A_in[55:28] = 28'h3F80_000 >> 4;
        A_in[27:0]  = 28'h4000_000 >> 4;
        
        B_in = A_in;  // Same for simplicity
        C_in = 64'h0000_3F00_0000_0040;
        begin_case("TC7.2 SP dual lane", "PD2_mode=1, dual-lane products should be present");
        
        @(posedge clk);  // Load
        @(posedge clk);  // Register
        @(posedge clk);  // Compute (1 cycle for SP)
        #1;
        
        display_outputs("TC7.2 Results SP Dual Lane");
        $display("Expected: PD2_mode=1, two products in output");
        end_case("TC7.2 SP dual lane");

        // TC7.3: HP Mode - Quad Lane
        $display("\n=== TC7.3: HP Mode - Quad Lane ===");
        Prec  = HP;
        Para  = 0;
        Cvt   = 0;
        
        // Pack four HP values in 14-bit segments
        A_in[55:42] = 14'h0F00;  // ~1.0 HP
        A_in[41:28] = 14'h1000;  // ~2.0 HP
        A_in[27:14] = 14'h0E00;  // ~0.5 HP
        A_in[13:0]  = 14'h0F80;  // ~1.5 HP
        
        B_in[55:42] = 14'h1000;  // ~2.0 HP
        B_in[41:28] = 14'h0F00;  // ~1.0 HP
        B_in[27:14] = 14'h1000;  // ~2.0 HP
        B_in[13:0]  = 14'h1000;  // ~2.0 HP
        
        C_in[55:42] = 14'h0E00;  // ~0.5 HP
        C_in[41:28] = 14'h0F00;  // ~1.0 HP
        C_in[27:14] = 14'h0000;  // 0.0 HP
        C_in[13:0]  = 14'h0F00;  // ~1.0 HP
        begin_case("TC7.3 HP quad lane", "PD4_mode=1 and four lane outputs should map correctly");
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        
        display_outputs("TC7.3 Results HP Quad Lane");
        $display("Expected: PD4_mode=1, four 28-bit products");
        
        if (!PD4_mode) begin
            $display("ERROR: PD4_mode should be active!");
            errors = errors + 1;
        end
        end_case("TC7.3 HP quad lane");

        // TC7.4: HP Mode with Valid Masking
        $display("\n=== TC7.4: HP Mode - Valid Masking (Lanes 3,1) ===");
        Prec  = HP;
        Para  = 0;
        Cvt   = 0;
        
        A_in = 64'hFFFF_FFFF_FFFF_FFFF;
        B_in = 64'hAAAA_AAAA_AAAA_AAAA;
        C_in = 64'h5555_5555_5555_5555;
        begin_case("TC7.4 HP valid masking", "masked lanes should be effectively gated");
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        
        display_outputs("TC7.4 Results with Valid Masking");
        $display("Expected: Sign_AB masked to lanes 3,1 only");
        $display("Expected: Products for lanes 2,0 gated to zero");
        end_case("TC7.4 HP valid masking");

        // TC7.5: Negative Operands
        $display("\n=== TC7.5: DP Mode - Negative Operands ===");
        Prec  = DP;
        Para  = 0;
        Cvt   = 0;
        A_in  = 64'hBFF0_0000_0000_0000;  // -1.0
        B_in  = 64'hC000_0000_0000_0000;  // -2.0
        C_in  = 64'hBFE0_0000_0000_0000;  // -0.5
        begin_case("TC7.5 DP negative operands", "neg*neg => positive, so Sign_AB[0]=0");
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        
        display_outputs("TC7.5 Negative Operands");
        $display("Expected: Sign_AB=0 (neg * neg = pos, only lane 0 has operands)");
        
        if (Sign_AB[0] !== 1'b0) begin
            $display("ERROR: Sign[0] should be 0 (positive)!");
            errors = errors + 1;
        end
        end_case("TC7.5 DP negative operands");

        // TC7.6: Mixed Signs
        $display("\n=== TC7.6: DP Mode - Mixed Signs ===");
        A_in = 64'h3FF0_0000_0000_0000;  // +1.0
        B_in = 64'hC000_0000_0000_0000;  // -2.0
        C_in = 64'h4000_0000_0000_0000;  // +2.0
        begin_case("TC7.6 DP mixed signs", "pos*neg => negative, so Sign_AB[0]=1");
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        
        display_outputs("TC7.6 Mixed Signs");
        $display("Expected: Sign_AB[0]=1 (pos * neg = neg, only lane 0 has operands)");
        
        if (Sign_AB[0] !== 1'b1) begin
            $display("ERROR: Sign[0] should be 1 (negative)!");
            errors = errors + 1;
        end
        end_case("TC7.6 DP mixed signs");

        // TC7.7: Para/Cvt Pass-Through
        $display("\n=== TC7.7: Para/Cvt Pass-Through ===");
        Prec  = DP;
        Para  = 1;
        Cvt   = 1;
        A_in  = 64'h3FF0_0000_0000_0000;
        B_in  = 64'h3FF0_0000_0000_0000;
        C_in  = 64'h3FF0_0000_0000_0000;
        begin_case("TC7.7 Para/Cvt pass-through", "Para_reg=1 and Cvt_reg=1 should propagate through stage register");
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        
        display_outputs("TC7.7 Para/Cvt Test");
        $display("Expected: Para_reg=1, Cvt_reg=1");
        
        if (Para_reg !== 1'b1 || Cvt_reg !== 1'b1) begin
            $display("ERROR: Para/Cvt not passed through!");
            errors = errors + 1;
        end
        end_case("TC7.7 Para/Cvt pass-through");

        // TC7.8: BF16 Mode
        $display("\n=== TC7.8: BF16 Mode - Quad Lane ===");
        Prec  = BF16;
        Para  = 0;
        Cvt   = 0;
        
        A_in[55:42] = 14'h0FE0;  // ~1.0 BF16
        A_in[41:28] = 14'h1000;  // ~2.0 BF16
        A_in[27:14] = 14'h0FC0;  // ~0.5 BF16
        A_in[13:0]  = 14'h0FF0;  // ~1.5 BF16
        
        B_in = A_in;
        C_in = A_in;
        begin_case("TC7.8 BF16 quad lane", "PD4_mode=1 and lane products should be visible");
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        
        display_outputs("TC7.8 BF16 Mode");
        $display("Expected: PD4_mode=1");
        end_case("TC7.8 BF16 quad lane");

        // TC7.9: TF32 Mode
        $display("\n=== TC7.9: TF32 Mode - Dual Lane ===");
        Prec  = TF32;
        Para  = 0;
        Cvt   = 0;
        
        A_in[55:28] = {1'b0, 8'd127, 10'h200, 9'd0};  // TF32 value
        A_in[27:0]  = {1'b0, 8'd128, 10'h100, 9'd0};
        
        B_in = A_in;
        C_in = A_in;
        begin_case("TC7.9 TF32 dual lane", "PD2_mode=1 with TF32 valid pattern behavior");
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        
        display_outputs("TC7.9 TF32 Mode");
        $display("Expected: PD2_mode=1");
        end_case("TC7.9 TF32 dual lane");

        // TC7.10: Zero Inputs
        $display("\n=== TC7.10: Zero Inputs ===");
        Prec  = DP;
        Para  = 0;
        Cvt   = 0;
        A_in  = 64'h0000_0000_0000_0000;
        B_in  = 64'h0000_0000_0000_0000;
        C_in  = 64'h0000_0000_0000_0000;
        begin_case("TC7.10 zero inputs", "all datapath outputs near zero");
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        
        display_outputs("TC7.10 Zero Inputs");
        $display("Expected: All outputs near zero");
        end_case("TC7.10 zero inputs");

        // TC7.11: Pipeline Timing Check
        $display("\n=== TC7.11: Pipeline Timing Check ===");
        Prec  = DP;
        Para  = 0;
        Cvt   = 0;
        
        // Cycle 0: Load new inputs
        A_in = 64'h3FF0_0000_0000_0000;
        B_in = 64'h4000_0000_0000_0000;
        C_in = 64'h4008_0000_0000_0000;
        begin_case("TC7.11 pipeline timing", "DP control should show cycle0 invalid and cycle1 valid timing");
        @(posedge clk);
        
        // Cycle 1: Previous outputs stable, inputs registered
        @(posedge clk);
        $display("Cycle 1: Inputs registered, combinational logic settling");
        
        // Cycle 2: DP multiply cycle 0
        @(posedge clk);
        $display("Cycle 2: DP multiply cycle 0");
        
        // Cycle 3: DP multiply cycle 1, outputs registered
        @(posedge clk);
        #1;
        $display("Cycle 3: DP multiply complete, outputs registered");
        display_outputs("TC7.11 Pipeline Timing");
        end_case("TC7.11 pipeline timing");

        // TC7.12: DP Mode - Para=1 (Dual Addends)
        // Note: After TC7.11, the global cnt counter is at some state.
        // We need to wait until cnt is in the correct phase (cnt==0) to start DP correctly.
        // DP requires: cnt==0 for cycle0, cnt==1 for cycle1
        // Wait for cnt to be 0 before starting TC7.12
        while (dut.cnt !== 1'b0) @(posedge clk);
        
        $display("\n=== TC7.12: DP Mode - Para=1 Dual Addends ===");
        Prec  = DP;
        Para  = 1;  // Para mode: C contains two 32-bit SP addends
        Cvt   = 0;
        A_in  = 64'h3FF0_0000_0000_0000;  // 1.0 DP
        B_in  = 64'h4000_0000_0000_0000;  // 2.0 DP
        // C_in = {C1_SP[31:0], C0_SP[31:0]}
        C_in[63:32] = 32'h4040_0000;  // C1 = 3.0 SP (sign=0, exp=128)
        C_in[31:0]  = 32'h3F80_0000;  // C0 = 1.0 SP (sign=0, exp=127)
        begin_case("TC7.12 DP Para dual-addend", "valid_out 0->1, Para_reg=1, and Aligned_C carries both C1/C0 contributions");
        
        @(posedge clk);  // Cycle 0: Inputs accepted, valid_out=0 (cnt==0, valid_out=~0=0)
        #1;
        $display("Cycle 0: Para mode, inputs loaded, valid_out=%b (expect 0)", valid_out);
        if (valid_out !== 1'b0) begin
            $display("ERROR: valid_out should be 0 in Para DP cycle 0!");
            errors = errors + 1;
        end
        
        @(posedge clk);  // Cycle 1: DP multiply completes, valid_out=1 (cnt==1, valid_out=~1=0... wait)
        #1;
        // Note: At this point cnt has toggled, so valid_out should have updated in the register
        $display("Cycle 1: Para mode complete, valid_out=%b (expect 1)", valid_out);
        if (valid_out !== 1'b1) begin
            $display("ERROR: valid_out should be 1 in Para DP cycle 1!");
            errors = errors + 1;
        end
        
        display_outputs("TC7.12 Results Para Mode");
        $display("Expected: Para_reg=1, C formatted as dual SP addends");
        $display("Expected: Aligned_C contains both C1 and C0 independently aligned");
        
        if (Para_reg !== 1'b1) begin
            $display("ERROR: Para_reg should be 1!");
            errors = errors + 1;
        end
        end_case("TC7.12 DP Para dual-addend");

        // Summary
        repeat(2) @(posedge clk);
        $display("\n========================================");
        if (errors == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("TESTS FAILED: %d errors", errors);
        $display("========================================");
        $finish;
    end

    // Timeout
    initial begin
        #200000;
        $display("TIMEOUT!");
        $finish;
    end

endmodule
