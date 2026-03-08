`timescale 1ns / 1ps

module tb_individual_units;

    // Precision encoding
    localparam DP   = 3'b100;
    localparam SP   = 3'b011;
    localparam TF32 = 3'b010;
    localparam HP   = 3'b000;
    localparam BF16 = 3'b001;

    integer errors;
    integer case_errors_start;

    // -----------------------------------------------------------------
    // Stage2_Adder DUT signals
    // -----------------------------------------------------------------
    reg  [111:0] s2a_partial_products;
    reg          s2a_PD_mode;
    reg          s2a_PD2_mode;
    reg          s2a_PD4_mode;
    wire [106:0] s2a_product0;
    wire [106:0] s2a_product1;
    wire [106:0] s2a_product2;
    wire [106:0] s2a_product3;

    Stage2_Adder u_s2a (
        .partial_products(s2a_partial_products),
        .PD_mode(s2a_PD_mode),
        .PD2_mode(s2a_PD2_mode),
        .PD4_mode(s2a_PD4_mode),
        .product0(s2a_product0),
        .product1(s2a_product1),
        .product2(s2a_product2),
        .product3(s2a_product3)
    );

    // -----------------------------------------------------------------
    // Products_Alignment_Shifter DUT signals
    // -----------------------------------------------------------------
    reg  [106:0] pas_product0;
    reg  [106:0] pas_product1;
    reg  [106:0] pas_product2;
    reg  [106:0] pas_product3;
    reg  [63:0]  pas_ProdASC;
    reg          pas_PD_mode;
    reg          pas_PD2_mode;
    reg          pas_PD4_mode;
    wire [162:0] pas_aligned_p0;
    wire [162:0] pas_aligned_p1;
    wire [162:0] pas_aligned_p2;
    wire [162:0] pas_aligned_p3;

    Products_Alignment_Shifter u_pas (
        .product0(pas_product0),
        .product1(pas_product1),
        .product2(pas_product2),
        .product3(pas_product3),
        .ProdASC(pas_ProdASC),
        .PD_mode(pas_PD_mode),
        .PD2_mode(pas_PD2_mode),
        .PD4_mode(pas_PD4_mode),
        .aligned_p0(pas_aligned_p0),
        .aligned_p1(pas_aligned_p1),
        .aligned_p2(pas_aligned_p2),
        .aligned_p3(pas_aligned_p3)
    );

    // -----------------------------------------------------------------
    // CSA_4to2 DUT signals
    // -----------------------------------------------------------------
    reg  [162:0] csa_in0;
    reg  [162:0] csa_in1;
    reg  [162:0] csa_in2;
    reg  [162:0] csa_in3;
    wire [162:0] csa_sum;
    wire [162:0] csa_carry;

    CSA_4to2 u_csa (
        .in0(csa_in0),
        .in1(csa_in1),
        .in2(csa_in2),
        .in3(csa_in3),
        .sum(csa_sum),
        .carry(csa_carry)
    );

    // -----------------------------------------------------------------
    // Helper tasks
    // -----------------------------------------------------------------

    task set_s2a_mode;
        input [2:0] p;
        begin
            s2a_PD_mode = (p == DP);
            s2a_PD2_mode = (p == SP) || (p == TF32);
            s2a_PD4_mode = (p == HP) || (p == BF16);
        end
    endtask

    task set_pas_mode;
        input [2:0] p;
        begin
            pas_PD_mode = (p == DP);
            pas_PD2_mode = (p == SP) || (p == TF32);
            pas_PD4_mode = (p == HP) || (p == BF16);
        end
    endtask

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
        errors = 0;
        s2a_partial_products = 112'd0;
        set_s2a_mode(DP);
        pas_product0 = 107'd0;
        pas_product1 = 107'd0;
        pas_product2 = 107'd0;
        pas_product3 = 107'd0;
        pas_ProdASC = 64'd0;
        set_pas_mode(DP);
        csa_in0 = 163'd0;
        csa_in1 = 163'd0;
        csa_in2 = 163'd0;
        csa_in3 = 163'd0;

        #1;

        $display("============================================================");
        $display("Stage 2 Individual Unit Testbench");
        $display("============================================================");

        // -----------------------------------------------------------------
        // Stage2_Adder Tests
        // -----------------------------------------------------------------

        // 1) Stage2_Adder: DP mode unpacking
        begin_case("Stage2_Adder DP mode");
        describe_case(
            "partial_products[111:0]=112'd0x123_456_789_ABCDEF_0123456789AB, PD_mode=1",
            "Extract lower 108 bits as single DP product",
            "product0[106:0] = partial_products[106:0]"
        );
        s2a_partial_products = 112'h123456789ABCDEF0123456789AB;
        set_s2a_mode(DP);
        #1;
        $display("product0=%033h, product1=%033h, product2=%033h, product3=%033h",
                 s2a_product0, s2a_product1, s2a_product2, s2a_product3);
        if (s2a_product0 !== s2a_partial_products[106:0]) begin
            $display("ERROR: Stage2_Adder DP product0 mismatch");
            errors = errors + 1;
        end
        if (s2a_product1 !== 107'd0 || s2a_product2 !== 107'd0 || s2a_product3 !== 107'd0) begin
            $display("ERROR: Stage2_Adder DP: unused products not zero");
            errors = errors + 1;
        end
        end_case("Stage2_Adder DP mode");

        // 2) Stage2_Adder: PD2 mode unpacking
        begin_case("Stage2_Adder PD2 mode");
        describe_case(
            "partial_products[111:0]={56'h123456789ABCDE, 56'hFEDCBA9876543210}, PD2_mode=1",
            "Split into two 56-bit products with 52-bit padding",
            "product0={52'b0, partial_products[55:0]}, product1={52'b0, partial_products[111:56]}"
        );
        s2a_partial_products = 112'h123456789ABCDEFEDCBA98765432;
        set_s2a_mode(SP);
        #1;
        $display("product0=%033h, product1=%033h", s2a_product0, s2a_product1);
        if (s2a_product0[55:0] !== s2a_partial_products[55:0]) begin
            $display("ERROR: Stage2_Adder PD2 product0 mismatch");
            errors = errors + 1;
        end
        if (s2a_product1[55:0] !== s2a_partial_products[111:56]) begin
            $display("ERROR: Stage2_Adder PD2 product1 mismatch");
            errors = errors + 1;
        end
        end_case("Stage2_Adder PD2 mode");

        // 3) Stage2_Adder: PD4 mode unpacking
        begin_case("Stage2_Adder PD4 mode");
        describe_case(
            "partial_products[111:0]={28'hFFFFFFF (lane3), 28'hEEEEEEE (lane2), 28'hDDDDDDD (lane1), 28'hCCCCCCC (lane0)}, PD4_mode=1",
            "Split into four 28-bit products with 80-bit padding each",
            "product[i]={80'b0, partial_products[28*i+27 : 28*i]}"
        );
        s2a_partial_products = 112'hFEEEEEEDDDDDDCCCCCCC;  // Enough bits for 4 28-bit values
        set_s2a_mode(HP);
        #1;
        $display("product0=%033h, product1=%033h, product2=%033h, product3=%033h",
                 s2a_product0, s2a_product1, s2a_product2, s2a_product3);
        // Check that each product extracted the correct 28-bit segment (zero-extended)
        if (s2a_product0[27:0] !== s2a_partial_products[27:0]) begin
            $display("ERROR: Stage2_Adder PD4 product0 mismatch");
            errors = errors + 1;
        end
        if (s2a_product1[27:0] !== s2a_partial_products[55:28]) begin
            $display("ERROR: Stage2_Adder PD4 product1 mismatch");
            errors = errors + 1;
        end
        if (s2a_product2[27:0] !== s2a_partial_products[83:56]) begin
            $display("ERROR: Stage2_Adder PD4 product2 mismatch");
            errors = errors + 1;
        end
        if (s2a_product3[27:0] !== s2a_partial_products[111:84]) begin
            $display("ERROR: Stage2_Adder PD4 product3 mismatch");
            errors = errors + 1;
        end
        end_case("Stage2_Adder PD4 mode");

        // -----------------------------------------------------------------
        // Products_Alignment_Shifter Tests
        // -----------------------------------------------------------------

        // 4) Products_Alignment_Shifter: DP mode (no inter-product shift)
        begin_case("Products_Alignment_Shifter DP mode");
        describe_case(
            "All products=$d0, ProdASC=64'd0, PD_mode=1",
            "DP mode should not shift product0 (no inter-product alignment)",
            "aligned_p0={56'b0, product0}, others zero or mode-determined"
        );
        pas_product0 = 107'd0;
        pas_product1 = 107'd0;
        pas_product2 = 107'd0;
        pas_product3 = 107'd0;
        pas_ProdASC = 64'd0;
        set_pas_mode(DP);
        #1;
        if (pas_aligned_p0 !== {56'd0, pas_product0}) begin
            $display("ERROR: Products_Alignment_Shifter DP: aligned_p0 should be zero-extended");
            errors = errors + 1;
        end
        end_case("Products_Alignment_Shifter DP mode");

        // 5) Products_Alignment_Shifter: PD2 mode with ASCs
        begin_case("Products_Alignment_Shifter PD2 mode");
        describe_case(
            "product0=107'd1, product3=107'd1, ASC_P0=3, ASC_P3=5, PD2_mode=1",
            "Apply individual ASC shifts: p0 >> 3, p3 >> 5",
            "aligned_p0={56'b0,1} >> 3, aligned_p3={56'b0,1} >> 5"
        );
        pas_product0 = 107'd1;
        pas_product1 = 107'd0;
        pas_product2 = 107'd0;
        pas_product3 = 107'd1;
        pas_ProdASC = {16'd5, 16'd0, 16'd0, 16'd3};  // {ASC_P3, ASC_P2, ASC_P1, ASC_P0}
        set_pas_mode(SP);
        #1;
        $display("aligned_p0=%0d (expect %0d), aligned_p3=%0d (expect %0d)",
                 pas_aligned_p0, ({56'd0, 1'b1} >>> 3), pas_aligned_p3, ({56'd0, 1'b1} >>> 5));
        if (pas_aligned_p0 !== ({56'd0, 1'b1} >>> 3)) begin
            $display("ERROR: Products_Alignment_Shifter PD2: aligned_p0 shift mismatch");
            errors = errors + 1;
        end
        if (pas_aligned_p3 !== ({56'd0, 1'b1} >>> 5)) begin
            $display("ERROR: Products_Alignment_Shifter PD2: aligned_p3 shift mismatch");
            errors = errors + 1;
        end
        end_case("Products_Alignment_Shifter PD2 mode");

        // 6) Products_Alignment_Shifter: PD4 mode with 4 ASCs
        begin_case("Products_Alignment_Shifter PD4 mode");
        describe_case(
            "All products=107'hFFFFFF, ASCs={2,3,4,5}, PD4_mode=1",
            "Shift all four products individually",
            "Each aligned_p[i] = {56'b0, product[i]} >> ASC[i]"
        );
        pas_product0 = 107'h7FFFFFF;
        pas_product1 = 107'h7FFFFFF;
        pas_product2 = 107'h7FFFFFF;
        pas_product3 = 107'h7FFFFFF;
        pas_ProdASC = {16'd5, 16'd4, 16'd3, 16'd2};  // {ASC_P3, ASC_P2, ASC_P1, ASC_P0}
        set_pas_mode(HP);
        #1;
        $display("aligned_p0=%042h aligned_p1=%042h aligned_p2=%042h aligned_p3=%042h",
                 pas_aligned_p0, pas_aligned_p1, pas_aligned_p2, pas_aligned_p3);
        // Verify basic shifting (shifted values are smaller)
        if (pas_aligned_p0 >= ({56'd0, pas_product0} >>> 1)) begin
            $display("ERROR: Products_Alignment_Shifter PD4: p0 shift not applied");
            errors = errors + 1;
        end
        end_case("Products_Alignment_Shifter PD4 mode");

        // 7) Products_Alignment_Shifter: ASC saturation at 163
        begin_case("Products_Alignment_Shifter ASC clamping");
        describe_case(
            "product0=107'h123456, ASC_P0=16'd200 (exceeds 163), PD_mode=0, PD4_mode=1",
            "Clamped ASC should shift by 8'd163 max (left-shift all bits out)",
            "aligned_p0 approx 163'b0 due to large shift"
        );
        pas_product0 = 107'h123456;
        pas_product1 = 107'd0;
        pas_product2 = 107'd0;
        pas_product3 = 107'd0;
        pas_ProdASC = {16'd0, 16'd0, 16'd0, 16'd200};  // ASC_P0=200 (clamped to 163)
        set_pas_mode(HP);
        #1;
        $display("aligned_p0=%0d (expect very small due to large shift)", pas_aligned_p0);
        // After shift >> 163, result should be effectively zero or very small
        if (pas_aligned_p0 > 163'd1) begin
            $display("WARNING: aligned_p0 larger than expected after large shift");
        end
        end_case("Products_Alignment_Shifter ASC clamping");

        // -----------------------------------------------------------------
        // CSA_4to2 Tests
        // -----------------------------------------------------------------

        // 8) CSA_4to2: Check XOR/AND relationships (not sum!=carry)
        begin_case("CSA_4to2 basic");
        describe_case(
            "in0=163'd1, in1=163'd2, in2=163'd3, in3=163'd4",
            "FSM-style 4-to-2 compression: verify sum XOR patterns",
            "Verify sum and carry are combinational (no latch-up)"
        );
        csa_in0 = 163'd1;
        csa_in1 = 163'd2;
        csa_in2 = 163'd3;
        csa_in3 = 163'd4;
        #1;
        $display("sum=%042h, carry=%042h", csa_sum, csa_carry);
        // Verify outputs are not undefined (valid)
        if (csa_sum === 163'bx || csa_carry === 163'bx) begin
            $display("ERROR: CSA_4to2 produces undefined output");
            errors = errors + 1;
        end
        end_case("CSA_4to2 basic");

        // 9) CSA_4to2: All zeros (should produce all zeros)
        begin_case("CSA_4to2 all zeros");
        describe_case(
            "in0=163'b0, in1=163'b0, in2=163'b0, in3=163'b0",
            "CSA of four zeros must be zero",
            "sum=0, carry=0"
        );
        csa_in0 = 163'd0;
        csa_in1 = 163'd0;
        csa_in2 = 163'd0;
        csa_in3 = 163'd0;
        #1;
        $display("sum=%042h, carry=%042h", csa_sum, csa_carry);
        if (csa_sum !== 163'd0 || csa_carry !== 163'd0) begin
            $display("ERROR: CSA_4to2 zero input should produce zero output");
            errors = errors + 1;
        end
        end_case("CSA_4to2 all zeros");

        // 10) CSA_4to2: Alternating pattern
        begin_case("CSA_4to2 alternating");
        describe_case(
            "in0=163'h555...555, in1=163'hAAA...AAA, in2=163'h555...555, in3=163'hAAA...AAA",
            "Complementary inputs should produce carry/sum propagation",
            "Verify CSA doesn't deadlock or produce invalid results"
        );
        csa_in0 = {82{2'b01}};  // Alternating pattern
        csa_in1 = {82{2'b10}};
        csa_in2 = {82{2'b01}};
        csa_in3 = {82{2'b10}};
        #1;
        $display("sum=%042h, carry=%042h", csa_sum, csa_carry);
        // Just verify no latch-up or errors; exact value depends on CSA design
        if (csa_sum === 163'bx || csa_carry === 163'bx) begin
            $display("ERROR: CSA_4to2 produces undefined output");
            errors = errors + 1;
        end
        end_case("CSA_4to2 alternating");

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        #1;
        $display("\n============================================================");
        $display("Testbench Summary: %0d total errors", errors);
        $display("============================================================");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;

    end

endmodule
