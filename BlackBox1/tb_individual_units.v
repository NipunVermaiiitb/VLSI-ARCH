`timescale 1ns / 1ps

module tb_individual_units;

    // Precision encoding
    localparam HP   = 3'b000;
    localparam BF16 = 3'b001;
    localparam TF32 = 3'b010;
    localparam SP   = 3'b011;
    localparam DP   = 3'b100;

    integer errors;
    integer case_errors_start;

    // Unit-test local clock/reset for sequential blocks (multiplier_array DP iteration)
    reg unit_clk;
    reg unit_rst_n;

    // -----------------------------------------------------------------
    // component_formatter DUT signals
    // -----------------------------------------------------------------
    reg  [63:0] cf_A_in, cf_B_in, cf_C_in;
    reg  [2:0]  cf_Prec;
    reg  [3:0]  cf_Valid;
    reg         cf_Para;
    wire [3:0]  cf_A_sign, cf_B_sign, cf_C_sign;
    wire [31:0] cf_A_exp, cf_B_exp, cf_C_exp;
    wire [55:0] cf_A_mant, cf_B_mant, cf_C_mant;

    component_formatter u_cf (
        .A_in(cf_A_in),
        .B_in(cf_B_in),
        .C_in(cf_C_in),
        .Prec(cf_Prec),
        .Valid(cf_Valid),
        .Para(cf_Para),
        .A_sign(cf_A_sign),
        .B_sign(cf_B_sign),
        .C_sign(cf_C_sign),
        .A_exponent_ext(cf_A_exp),
        .B_exponent_ext(cf_B_exp),
        .C_exponent_ext(cf_C_exp),
        .A_mantissa_ext(cf_A_mant),
        .B_mantissa_ext(cf_B_mant),
        .C_mantissa_ext(cf_C_mant)
    );

    // -----------------------------------------------------------------
    // sign_logic DUT signals
    // -----------------------------------------------------------------
    reg  [3:0] sl_A_sign, sl_B_sign, sl_Valid;
    wire [3:0] sl_Sign_AB;

    sign_logic u_sl (
        .A_sign(sl_A_sign),
        .B_sign(sl_B_sign),
        .Valid(sl_Valid),
        .Sign_AB(sl_Sign_AB)
    );

    // -----------------------------------------------------------------
    // exponent_comparison DUT signals
    // -----------------------------------------------------------------
    reg  [31:0] ec_A_exp, ec_B_exp, ec_C_exp;
    reg  [2:0]  ec_Prec;
    reg  [3:0]  ec_Valid;
    reg         ec_Para, ec_Cvt;
    wire [31:0] ec_ExpDiff, ec_MaxExp;
    wire [63:0] ec_ProdASC;

    exponent_comparison u_ec (
        .A_exp(ec_A_exp),
        .B_exp(ec_B_exp),
        .C_exp(ec_C_exp),
        .Prec(ec_Prec),
        .Valid(ec_Valid),
        .Para(ec_Para),
        .Cvt(ec_Cvt),
        .ExpDiff(ec_ExpDiff),
        .MaxExp(ec_MaxExp),
        .ProdASC(ec_ProdASC)
    );

    // -----------------------------------------------------------------
    // addend_alignment_shifter DUT signals
    // -----------------------------------------------------------------
    reg  [55:0]  as_C_mant;
    reg  [31:0]  as_ExpDiff;
    reg  [2:0]   as_Prec;
    reg          as_Para;
    wire [162:0] as_Aligned_C;

    addend_alignment_shifter u_as (
        .C_mantissa(as_C_mant),
        .ExpDiff(as_ExpDiff),
        .Prec(as_Prec),
        .Para(as_Para),
        .Aligned_C(as_Aligned_C)
    );

    // -----------------------------------------------------------------
    // mult14_radix4_booth DUT signals
    // -----------------------------------------------------------------
    reg  [13:0] m14_a, m14_b;
    wire [27:0] m14_p;

    mult14_radix4_booth u_m14 (
        .a(m14_a),
        .b(m14_b),
        .p(m14_p)
    );

    // -----------------------------------------------------------------
    // low_cost_multiplier_array DUT signals
    // -----------------------------------------------------------------
    reg  [55:0] ma_A_mant, ma_B_mant;
    reg  [2:0]  ma_Prec;
    reg  [3:0]  ma_Valid;
    reg         ma_PD_mode, ma_PD2_mode, ma_PD4_mode;
    reg         ma_Cnt0;
    wire [111:0] ma_partial_sum;
    wire [111:0] ma_partial_carry;
    wire [111:0] ma_partial_products;

    low_cost_multiplier_array u_ma (
        .clk(unit_clk),
        .rst_n(unit_rst_n),
        .A_mantissa(ma_A_mant),
        .B_mantissa(ma_B_mant),
        .Prec(ma_Prec),
        .Valid(ma_Valid),
        .PD_mode(ma_PD_mode),
        .PD2_mode(ma_PD2_mode),
        .PD4_mode(ma_PD4_mode),
        .Cnt0(ma_Cnt0),
        .partial_sum(ma_partial_sum),
        .partial_carry(ma_partial_carry)
    );

    assign ma_partial_products = ma_partial_sum + ma_partial_carry;

    task set_ma_mode;
        input [2:0] p;
        begin
            ma_Prec    = p;
            ma_PD_mode = (p == DP);
            ma_PD2_mode = (p == SP) || (p == TF32);
            ma_PD4_mode = (p == HP) || (p == BF16);
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
        unit_clk = 1'b0;
        forever #5 unit_clk = ~unit_clk;
    end

    initial begin
        errors = 0;
        unit_rst_n = 1'b0;
        ma_A_mant = 56'd0;
        ma_B_mant = 56'd0;
        ma_Valid = 4'b0000;
        ma_Cnt0 = 1'b0;
        set_ma_mode(DP);

        repeat (2) @(posedge unit_clk);
        unit_rst_n = 1'b1;
        repeat (1) @(posedge unit_clk);

        $display("============================================================");
        $display("Individual Unit Testbench");
        $display("============================================================");

        // 1) component_formatter: DP basic decode
        begin_case("component_formatter DP decode");
        describe_case(
            "A=1.5(DP), B=2.0(DP), C=0.5(DP), Prec=DP, Valid=1111, Para=0",
            "Decode DP exponents from IEEE-754 fields",
            "A_exp=1023, B_exp=1024, C_exp=1022"
        );
        cf_A_in   = 64'h3FF8_0000_0000_0000; // 1.5
        cf_B_in   = 64'h4000_0000_0000_0000; // 2.0
        cf_C_in   = 64'h3FE0_0000_0000_0000; // 0.5
        cf_Prec   = DP;
        cf_Valid  = 4'b1111;
        cf_Para   = 1'b0;
        #1;
        $display("A_exp=%0d B_exp=%0d C_exp=%0d", cf_A_exp[10:0], cf_B_exp[10:0], cf_C_exp[10:0]);
        if (cf_A_exp[10:0] !== 11'd1023 || cf_B_exp[10:0] !== 11'd1024 || cf_C_exp[10:0] !== 11'd1022) begin
            $display("ERROR: component_formatter DP exponent decode mismatch");
            errors = errors + 1;
        end
        end_case("component_formatter DP decode");

        // 2) component_formatter: DP Para dual-addend packing
        begin_case("component_formatter DP Para packing");
        describe_case(
            "A=1.0(DP), B=2.0(DP), C={3.0_SP,1.0_SP}, Prec=DP, Para=1",
            "Check Para mode packs two SP exponents into C_exp_ext",
            "C_exp_ext[31:24]=128 and C_exp_ext[15:8]=127"
        );
        cf_A_in   = 64'h3FF0_0000_0000_0000;
        cf_B_in   = 64'h4000_0000_0000_0000;
        cf_C_in   = 64'h4040_0000_3F80_0000; // {3.0_SP, 1.0_SP}
        cf_Prec   = DP;
        cf_Valid  = 4'b1111;
        cf_Para   = 1'b1;
        #1;
        $display("C_exp_ext=%h (expect top=128, low=127)", cf_C_exp);
        if (cf_C_exp[31:24] !== 8'd128 || cf_C_exp[15:8] !== 8'd127) begin
            $display("ERROR: component_formatter Para C exponent packing mismatch");
            errors = errors + 1;
        end
        end_case("component_formatter DP Para packing");

        // 2b) component_formatter: SP decode
        begin_case("component_formatter SP decode");
        describe_case(
            "SP exponent bytes inserted in upper/lower 32-bit lanes for A/B/C",
            "Decode SP lane exponents into packed 32-bit exponent buses",
            "A/B/C exponent bytes match injected lane values"
        );
        cf_A_in   = 64'd0;
        cf_B_in   = 64'd0;
        cf_C_in   = 64'd0;
        cf_A_in[62:55] = 8'd130;
        cf_A_in[30:23] = 8'd128;
        cf_B_in[62:55] = 8'd127;
        cf_B_in[30:23] = 8'd129;
        cf_C_in[62:55] = 8'd125;
        cf_C_in[30:23] = 8'd126;
        cf_Prec   = SP;
        cf_Valid  = 4'b1111;
        cf_Para   = 1'b0;
        #1;
        $display("A_exp_ext=%h B_exp_ext=%h C_exp_ext=%h", cf_A_exp, cf_B_exp, cf_C_exp);
        if (cf_A_exp[31:24] !== 8'd130 || cf_A_exp[15:8] !== 8'd128 ||
            cf_B_exp[31:24] !== 8'd127 || cf_B_exp[15:8] !== 8'd129 ||
            cf_C_exp[31:24] !== 8'd125 || cf_C_exp[15:8] !== 8'd126) begin
            $display("ERROR: component_formatter SP exponent decode mismatch");
            errors = errors + 1;
        end
        end_case("component_formatter SP decode");

        // 2c) component_formatter: TF32 decode with valid pattern 0101
        begin_case("component_formatter TF32 decode");
        describe_case(
            "TF32-like exponent bytes for A/B/C, Prec=TF32, Valid=0101",
            "Decode TF32 exponents while respecting sparse valid pattern",
            "A/B/C exponent bytes in ext buses match programmed values"
        );
        cf_A_in   = 64'd0;
        cf_B_in   = 64'd0;
        cf_C_in   = 64'd0;
        cf_A_in[62:55] = 8'd126;
        cf_A_in[30:23] = 8'd124;
        cf_B_in[62:55] = 8'd125;
        cf_B_in[30:23] = 8'd123;
        cf_C_in[62:55] = 8'd122;
        cf_C_in[30:23] = 8'd121;
        cf_Prec   = TF32;
        cf_Valid  = 4'b0101;
        cf_Para   = 1'b0;
        #1;
        $display("A_exp_ext=%h B_exp_ext=%h C_exp_ext=%h", cf_A_exp, cf_B_exp, cf_C_exp);
        if (cf_A_exp[31:24] !== 8'd126 || cf_A_exp[15:8] !== 8'd124 ||
            cf_B_exp[31:24] !== 8'd125 || cf_B_exp[15:8] !== 8'd123 ||
            cf_C_exp[31:24] !== 8'd122 || cf_C_exp[15:8] !== 8'd121) begin
            $display("ERROR: component_formatter TF32 exponent decode mismatch");
            errors = errors + 1;
        end
        end_case("component_formatter TF32 decode");

        // 2d) component_formatter: HP decode
        begin_case("component_formatter HP decode");
        describe_case(
            "Four 5-bit HP exponent fields per operand, Prec=HP, Valid=1111",
            "Expand HP exponent fields into 8-bit packed exponent lanes",
            "A_exp_ext lanes are 16,15,14,13"
        );
        cf_A_in   = 64'd0;
        cf_B_in   = 64'd0;
        cf_C_in   = 64'd0;
        cf_A_in[62:58] = 5'd16; cf_A_in[46:42] = 5'd15; cf_A_in[30:26] = 5'd14; cf_A_in[14:10] = 5'd13;
        cf_B_in[62:58] = 5'd12; cf_B_in[46:42] = 5'd11; cf_B_in[30:26] = 5'd10; cf_B_in[14:10] = 5'd9;
        cf_C_in[62:58] = 5'd8;  cf_C_in[46:42] = 5'd7;  cf_C_in[30:26] = 5'd6;  cf_C_in[14:10] = 5'd5;
        cf_Prec   = HP;
        cf_Valid  = 4'b1111;
        cf_Para   = 1'b0;
        #1;
        $display("A_exp_ext=%h", cf_A_exp);
        if (cf_A_exp[31:24] !== 8'd16 || cf_A_exp[23:16] !== 8'd15 || cf_A_exp[15:8] !== 8'd14 || cf_A_exp[7:0] !== 8'd13) begin
            $display("ERROR: component_formatter HP exponent decode mismatch");
            errors = errors + 1;
        end
        end_case("component_formatter HP decode");

        // 2e) component_formatter: BF16 decode
        begin_case("component_formatter BF16 decode");
        describe_case(
            "Four BF16 exponent bytes in A_in, Prec=BF16, Valid=1111",
            "Decode BF16 lane exponents into A_exp_ext",
            "A_exp_ext lanes are 130,129,128,127"
        );
        cf_A_in   = 64'd0;
        cf_A_in[62:55] = 8'd130; cf_A_in[46:39] = 8'd129; cf_A_in[30:23] = 8'd128; cf_A_in[14:7] = 8'd127;
        cf_Prec   = BF16;
        cf_Valid  = 4'b1111;
        cf_Para   = 1'b0;
        #1;
        $display("A_exp_ext=%h", cf_A_exp);
        if (cf_A_exp[31:24] !== 8'd130 || cf_A_exp[23:16] !== 8'd129 || cf_A_exp[15:8] !== 8'd128 || cf_A_exp[7:0] !== 8'd127) begin
            $display("ERROR: component_formatter BF16 exponent decode mismatch");
            errors = errors + 1;
        end
        end_case("component_formatter BF16 decode");

        // 3) sign_logic
        begin_case("sign_logic masked XOR");
        describe_case(
            "A_sign=1010, B_sign=1100, Valid=1011",
            "Compute sign as (A_sign XOR B_sign) masked by Valid",
            "Sign_AB equals ((A_sign^B_sign)&Valid)"
        );
        sl_A_sign = 4'b1010;
        sl_B_sign = 4'b1100;
        sl_Valid  = 4'b1011;
        #1;
        $display("Sign_AB=%b", sl_Sign_AB);
        if (sl_Sign_AB !== ((sl_A_sign ^ sl_B_sign) & sl_Valid)) begin
            $display("ERROR: sign_logic mismatch");
            errors = errors + 1;
        end
        end_case("sign_logic masked XOR");

        // 3b) sign_logic TF32 masking example (only seg2/seg0 active)
        begin_case("sign_logic TF32 valid mask");
        describe_case(
            "A_sign=0101, B_sign=0001, Valid=0101 (segments 2 and 0 active)",
            "Verify valid-mask behavior for sparse TF32 lanes",
            "Only active lanes contribute to Sign_AB"
        );
        sl_A_sign = 4'b0101;
        sl_B_sign = 4'b0001;
        sl_Valid  = 4'b0101;
        #1;
        $display("Sign_AB=%b expected=%b", sl_Sign_AB, ((sl_A_sign ^ sl_B_sign) & sl_Valid));
        if (sl_Sign_AB !== ((sl_A_sign ^ sl_B_sign) & sl_Valid)) begin
            $display("ERROR: sign_logic TF32-mask mismatch");
            errors = errors + 1;
        end
        end_case("sign_logic TF32 valid mask");

        // 4) exponent_comparison DP
        begin_case("exponent_comparison DP baseline");
        describe_case(
            "A_exp=1024, B_exp=1025, C_exp=1023, Prec=DP, Valid=1111",
            "Compute max exponent and alignment shift counts",
            "ExpDiff halves remain in sane range (<=162)"
        );
        ec_A_exp  = 32'd1024;
        ec_B_exp  = 32'd1025;
        ec_C_exp  = 32'd1023;
        ec_Prec   = DP;
        ec_Valid  = 4'b1111;
        ec_Para   = 1'b0;
        ec_Cvt    = 1'b0;
        #1;
        $display("ExpDiff=%h MaxExp=%h", ec_ExpDiff, ec_MaxExp);
        if (ec_ExpDiff[31:16] > 16'd162 || ec_ExpDiff[15:0] > 16'd162) begin
            $display("ERROR: unexpected huge ASC in DP baseline");
            errors = errors + 1;
        end
        end_case("exponent_comparison DP baseline");

        // 4b) exponent_comparison SP
        begin_case("exponent_comparison SP");
        describe_case(
            "Packed SP exponents in 2 lanes for A/B/C, Prec=SP",
            "Check SP max-exponent and shift-difference generation",
            "ExpDiff halves remain <=162"
        );
        ec_A_exp  = {8'd130,8'd0,8'd128,8'd0};
        ec_B_exp  = {8'd127,8'd0,8'd129,8'd0};
        ec_C_exp  = {8'd125,8'd0,8'd126,8'd0};
        ec_Prec   = SP;
        ec_Valid  = 4'b1111;
        ec_Para   = 1'b0;
        ec_Cvt    = 1'b0;
        #1;
        $display("ExpDiff=%h MaxExp=%h", ec_ExpDiff, ec_MaxExp);
        if (ec_ExpDiff[31:16] > 16'd162 || ec_ExpDiff[15:0] > 16'd162) begin
            $display("ERROR: unexpected huge ASC in SP");
            errors = errors + 1;
        end
        end_case("exponent_comparison SP");

        // 4c) exponent_comparison TF32
        begin_case("exponent_comparison TF32");
        describe_case(
            "Packed TF32 exponents, Prec=TF32, Valid=0101",
            "Check TF32 lane handling with sparse valid mask",
            "ExpDiff halves remain <=162"
        );
        ec_A_exp  = {8'd126,8'd0,8'd124,8'd0};
        ec_B_exp  = {8'd125,8'd0,8'd123,8'd0};
        ec_C_exp  = {8'd122,8'd0,8'd121,8'd0};
        ec_Prec   = TF32;
        ec_Valid  = 4'b0101;
        ec_Para   = 1'b0;
        ec_Cvt    = 1'b0;
        #1;
        $display("ExpDiff=%h MaxExp=%h", ec_ExpDiff, ec_MaxExp);
        if (ec_ExpDiff[31:16] > 16'd162 || ec_ExpDiff[15:0] > 16'd162) begin
            $display("ERROR: unexpected huge ASC in TF32");
            errors = errors + 1;
        end
        end_case("exponent_comparison TF32");

        // 4d) exponent_comparison HP
        begin_case("exponent_comparison HP");
        describe_case(
            "Four HP 5-bit exponents packed in A/B/C, Prec=HP",
            "Check HP expansion and exponent-difference limits",
            "ExpDiff halves remain <=162"
        );
        ec_A_exp = 32'd0;
        ec_B_exp = 32'd0;
        ec_C_exp = 32'd0;
        ec_A_exp[28:24]=5'd16; ec_A_exp[20:16]=5'd15; ec_A_exp[12:8]=5'd14; ec_A_exp[4:0]=5'd13;
        ec_B_exp[28:24]=5'd12; ec_B_exp[20:16]=5'd11; ec_B_exp[12:8]=5'd10; ec_B_exp[4:0]=5'd9;
        ec_C_exp[28:24]=5'd8;  ec_C_exp[20:16]=5'd7;  ec_C_exp[12:8]=5'd6;  ec_C_exp[4:0]=5'd5;
        ec_Prec   = HP;
        ec_Valid  = 4'b1111;
        ec_Para   = 1'b0;
        ec_Cvt    = 1'b0;
        #1;
        $display("ExpDiff=%h MaxExp=%h", ec_ExpDiff, ec_MaxExp);
        if (ec_ExpDiff[31:16] > 16'd162 || ec_ExpDiff[15:0] > 16'd162) begin
            $display("ERROR: unexpected huge ASC in HP");
            errors = errors + 1;
        end
        end_case("exponent_comparison HP");

        // 4e) exponent_comparison BF16
        begin_case("exponent_comparison BF16");
        describe_case(
            "Four BF16 exponent lanes for A/B/C, Prec=BF16",
            "Check BF16 max exponent and shift-difference behavior",
            "ExpDiff halves remain <=162"
        );
        ec_A_exp  = {8'd130,8'd129,8'd128,8'd127};
        ec_B_exp  = {8'd127,8'd126,8'd125,8'd124};
        ec_C_exp  = {8'd123,8'd122,8'd121,8'd120};
        ec_Prec   = BF16;
        ec_Valid  = 4'b1111;
        ec_Para   = 1'b0;
        ec_Cvt    = 1'b0;
        #1;
        $display("ExpDiff=%h MaxExp=%h", ec_ExpDiff, ec_MaxExp);
        if (ec_ExpDiff[31:16] > 16'd162 || ec_ExpDiff[15:0] > 16'd162) begin
            $display("ERROR: unexpected huge ASC in BF16");
            errors = errors + 1;
        end
        end_case("exponent_comparison BF16");

        // 5) alignment shifter sanity
        begin_case("addend_alignment_shifter non-zero output");
        describe_case(
            "C_mant non-zero, ExpDiff={0,0}, Prec=DP",
            "Check aligned addend path for zero shift",
            "Aligned_C is non-zero"
        );
        as_C_mant = 56'h01_8000_0000_0000;
        as_ExpDiff = {16'd0, 16'd0};
        as_Prec   = DP;
        as_Para   = 1'b0;
        #1;
        $display("Aligned_C=%h", as_Aligned_C);
        if (as_Aligned_C == 163'd0) begin
            $display("ERROR: aligned C unexpectedly zero");
            errors = errors + 1;
        end
        end_case("addend_alignment_shifter non-zero output");

        // 5b) alignment shifter SP
        begin_case("addend_alignment_shifter SP");
        describe_case(
            "C_mant=0x00_00FF_FF00_FFFF, ExpDiff={8,4}, Prec=SP",
            "Check SP alignment shifting across packed lanes",
            "Aligned_C is non-zero"
        );
        as_C_mant  = 56'h00_00FF_FF00_FFFF;
        as_ExpDiff = {16'd8, 16'd4};
        as_Prec    = SP;
        as_Para    = 1'b0;
        #1;
        $display("Aligned_C=%h", as_Aligned_C);
        if (as_Aligned_C == 163'd0) begin
            $display("ERROR: SP aligned C unexpectedly zero");
            errors = errors + 1;
        end
        end_case("addend_alignment_shifter SP");

        // 5c) alignment shifter TF32
        begin_case("addend_alignment_shifter TF32");
        describe_case(
            "C_mant=0x00_1234_5678_9ABC, ExpDiff={12,8}, Prec=TF32",
            "Check TF32 alignment behavior",
            "Aligned_C is non-zero"
        );
        as_C_mant  = 56'h00_1234_5678_9ABC;
        as_ExpDiff = {16'd12, 16'd8};
        as_Prec    = TF32;
        as_Para    = 1'b0;
        #1;
        $display("Aligned_C=%h", as_Aligned_C);
        if (as_Aligned_C == 163'd0) begin
            $display("ERROR: TF32 aligned C unexpectedly zero");
            errors = errors + 1;
        end
        end_case("addend_alignment_shifter TF32");

        // 5d) alignment shifter HP
        begin_case("addend_alignment_shifter HP");
        describe_case(
            "C_mant=0xAA_BBCC_DDEE_FF00, ExpDiff={6,3}, Prec=HP",
            "Check HP packed-lane alignment shifting",
            "Aligned_C is non-zero"
        );
        as_C_mant  = 56'hAA_BBCC_DDEE_FF00;
        as_ExpDiff = {16'd6, 16'd3};
        as_Prec    = HP;
        as_Para    = 1'b0;
        #1;
        $display("Aligned_C=%h", as_Aligned_C);
        if (as_Aligned_C == 163'd0) begin
            $display("ERROR: HP aligned C unexpectedly zero");
            errors = errors + 1;
        end
        end_case("addend_alignment_shifter HP");

        // 5e) alignment shifter BF16
        begin_case("addend_alignment_shifter BF16");
        describe_case(
            "C_mant=0x12_3456_789A_BCDE, ExpDiff={7,5}, Prec=BF16",
            "Check BF16 packed-lane alignment shifting",
            "Aligned_C is non-zero"
        );
        as_C_mant  = 56'h12_3456_789A_BCDE;
        as_ExpDiff = {16'd7, 16'd5};
        as_Prec    = BF16;
        as_Para    = 1'b0;
        #1;
        $display("Aligned_C=%h", as_Aligned_C);
        if (as_Aligned_C == 163'd0) begin
            $display("ERROR: BF16 aligned C unexpectedly zero");
            errors = errors + 1;
        end
        end_case("addend_alignment_shifter BF16");

        // 6) multiplier_array mode/precision coverage
        begin_case("multiplier_array PD4 HP lanes");
        describe_case(
            "Prec=HP(PD4), Valid=1111, A={10,20,30,40}, B={5,6,7,8}, Cnt0=0",
            "Check compressed output from two multiplier blocks (internal CSA + global compression)",
            "PP output should be non-zero (sum+carry after compression)"
        );
        set_ma_mode(HP);
        ma_Valid = 4'b1111;
        ma_A_mant = {14'd10,14'd20,14'd30,14'd40};
        ma_B_mant = {14'd5,14'd6,14'd7,14'd8};
        ma_Cnt0 = 1'b0;
        @(posedge unit_clk); #1;
        $display("PP={%0d,%0d,%0d,%0d}", ma_partial_products[111:84], ma_partial_products[83:56], ma_partial_products[55:28], ma_partial_products[27:0]);
        if (ma_partial_products == 112'd0) begin
            $display("ERROR: multiplier_array PD4 HP output unexpectedly zero (no data flow)");
            errors = errors + 1;
        end
        end_case("multiplier_array PD4 HP lanes");

        begin_case("multiplier_array PD4 BF16 lanes");
        describe_case(
            "Prec=BF16(PD4), Valid=1111, A={50,60,70,80}, B={2,3,4,5}",
            "Check compressed output (internal block CSA + global reduction)",
            "PP output should be non-zero"
        );
        set_ma_mode(BF16);
        ma_Valid = 4'b1111;
        ma_A_mant = {14'd50,14'd60,14'd70,14'd80};
        ma_B_mant = {14'd2,14'd3,14'd4,14'd5};
        ma_Cnt0 = 1'b0;
        @(posedge unit_clk); #1;
        if (ma_partial_products == 112'd0) begin
            $display("ERROR: multiplier_array PD4 BF16 output unexpectedly zero");
            errors = errors + 1;
        end
        end_case("multiplier_array PD4 BF16 lanes");

        begin_case("multiplier_array PD2 SP diagonal segments");
        describe_case(
            "Prec=SP(PD2), Valid=1111, A={10,20,30,40}, B={2,3,4,5}",
            "Check SP 28-bit pair compression and output",
            "PP output should be non-zero and within expected range"
        );
        set_ma_mode(SP);
        ma_Valid = 4'b1111;
        ma_A_mant = {14'd10,14'd20,14'd30,14'd40};
        ma_B_mant = {14'd2,14'd3,14'd4,14'd5};
        ma_Cnt0 = 1'b0;
        @(posedge unit_clk); #1;
        // Output is sum+carry after CSA compression, not raw products
        if (ma_partial_products == 112'd0 || ma_partial_products > 112'hFFFFFFFFFFFFFFFF_FFFFFFFF) begin
            $display("ERROR: multiplier_array PD2 SP output out of range");
            errors = errors + 1;
        end
        end_case("multiplier_array PD2 SP diagonal segments");

        begin_case("multiplier_array PD2 TF32 valid gating");
        describe_case(
            "Prec=TF32(PD2), Valid=0101, A={7,0,9,0}, B={8,0,6,0}",
            "Check TF32 segmented output and valid gating",
            "Top and mid segments expected 56 and 54"
        );
        set_ma_mode(TF32);
        ma_Valid = 4'b0101; // en_top28 and en_bot28 both active by OR grouping
        ma_A_mant = {14'd7,14'd0,14'd9,14'd0};
        ma_B_mant = {14'd8,14'd0,14'd6,14'd0};
        ma_Cnt0 = 1'b0;
        @(posedge unit_clk); #1;
        if (ma_partial_products[111:84] !== 28'd56 ||
            ma_partial_products[55:28]  !== 28'd54) begin
            $display("ERROR: multiplier_array TF32 segmented output mismatch");
            errors = errors + 1;
        end
        end_case("multiplier_array PD2 TF32 valid gating");

        begin_case("multiplier_array DP cycle gating");
        describe_case(
            "Prec=DP(PD), Valid=1111, A={4,3,2,1}, B={8,7,6,5}, Cnt0 toggled",
            "Verify DP two-cycle timing: cycle0 masked, cycle1 has merged compressed result",
            "Cycle0 should output zero; cycle1 should output non-zero merged sum+carry"
        );
        set_ma_mode(DP);
        ma_Valid = 4'b1111;
        ma_A_mant = {14'd4,14'd3,14'd2,14'd1};
        ma_B_mant = {14'd8,14'd7,14'd6,14'd5};

        ma_Cnt0 = 1'b0; // DP cycle0 should be masked to zero on output
        @(posedge unit_clk); #1;
        if (ma_partial_products !== 112'd0) begin
            $display("ERROR: multiplier_array DP cycle0 should output zero");
            errors = errors + 1;
        end

        ma_Cnt0 = 1'b1; // DP cycle1: merged compressed result should appear
        @(posedge unit_clk); #1;
        // After inter-cycle merge through 56-bit CSA and final 112-bit CSA, output is compressed sum+carry
        if (ma_partial_products == 112'd0) begin
            $display("ERROR: multiplier_array DP cycle1 should output non-zero merged result");
            errors = errors + 1;
        end
        end_case("multiplier_array DP cycle gating");

        // 7) 14x14 multiplier checks
        begin_case("mult14 simple multiply");
        describe_case(
            "a=100, b=50",
            "Check basic 14x14 multiplication",
            "p=5000"
        );
        m14_a = 14'd100;
        m14_b = 14'd50;
        #1;
        $display("p=%0d expected=5000", m14_p);
        if (m14_p !== 28'd5000) begin
            $display("ERROR: mult14 100*50 mismatch");
            errors = errors + 1;
        end
        end_case("mult14 simple multiply");

        begin_case("mult14 max multiply");
        describe_case(
            "a=0x3FFF, b=0x3FFF (max 14-bit unsigned)",
            "Check full-range corner case",
            "p=16383*16383"
        );
        m14_a = 14'h3FFF;
        m14_b = 14'h3FFF;
        #1;
        $display("p=%0d expected=%0d", m14_p, (28'd16383 * 28'd16383));
        if (m14_p !== (28'd16383 * 28'd16383)) begin
            $display("ERROR: mult14 max multiply mismatch");
            errors = errors + 1;
        end
        end_case("mult14 max multiply");

        $display("\n============================================================");
        if (errors == 0)
            $display("ALL INDIVIDUAL UNIT TESTS PASSED");
        else
            $display("INDIVIDUAL UNIT TESTS FAILED: %0d errors", errors);
        $display("============================================================");
        $finish;
    end

endmodule
