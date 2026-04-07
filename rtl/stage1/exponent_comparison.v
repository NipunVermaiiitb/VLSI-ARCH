module exponent_comparison (

    input  [31:0] A_exp,
    input  [31:0] B_exp,
    input  [31:0] C_exp,

    input  [2:0]  Prec,
    input  [3:0]  Valid,
    input         Para,
    input         Cvt,

    output [31:0] ExpDiff,
    output [31:0] MaxExp,
    output [63:0] ProdASC    // Product alignment shift counts for Stage 2

);

    //----------------------------------------------------------
    // Precision encoding
    //----------------------------------------------------------
    parameter HP    = 3'b000;
    parameter BF16  = 3'b001;
    parameter TF32  = 3'b010;
    parameter SP    = 3'b011;
    parameter DP    = 3'b100;

    // Alignment constants for initial ManC vs ManA*ManB placement.
    parameter signed [13:0] CONST_DP_BASE  = 14'sd0;
    parameter signed [13:0] CONST_PD2_BASE = 14'sd0;
    parameter signed [13:0] CONST_PD4_BASE = 14'sd0;
    parameter signed [13:0] CONST_TF32_BASE = 14'sd0;

    // IEEE-754 exponent biases by format.
    parameter [12:0] BIAS_DP   = 13'd1023;
    parameter [12:0] BIAS_SP   = 13'd127;
    parameter [12:0] BIAS_TF32 = 13'd127;
    parameter [12:0] BIAS_HP   = 13'd15;
    parameter [12:0] BIAS_BF16 = 13'd127;

    function signed [13:0] unpack_exp_unbiased;
        input [10:0] exp_field;
        input [12:0] bias;
        begin
            // For exp==0 (zero/subnormal), use 1-bias effective exponent.
            if (exp_field == 11'd0)
                unpack_exp_unbiased = 14'sd1 - $signed({1'b0, bias});
            else
                unpack_exp_unbiased = $signed({3'd0, exp_field}) - $signed({1'b0, bias});
        end
    endfunction

    //----------------------------------------------------------
    // Per-lane exponents in unified signed space (unbiased)
    //----------------------------------------------------------
    reg signed [13:0] A_e3, A_e2, A_e1, A_e0;
    reg signed [13:0] B_e3, B_e2, B_e1, B_e0;
    reg signed [13:0] C_e3, C_e2, C_e1, C_e0;

    // Product exponents per lane/group
    wire signed [13:0] AB_e3 = A_e3 + B_e3;
    wire signed [13:0] AB_e2 = A_e2 + B_e2;
    wire signed [13:0] AB_e1 = A_e1 + B_e1;
    wire signed [13:0] AB_e0 = A_e0 + B_e0;

    wire en3 = Valid[3];
    wire en2 = Valid[2];
    wire en1 = Valid[1];
    wire en0 = Valid[0];

    wire en_top28 = en3 | en2;
    wire en_bot28 = en1 | en0;

    reg signed [13:0] exp_ab_max;
    reg signed [13:0] exp_c0;
    reg signed [13:0] exp_c1;
    reg signed [13:0] exp_c_max;
    reg signed [13:0] const_term;

    reg [12:0] bias_ab_dbg;
    reg [12:0] bias_c_dbg;

    reg [15:0] asc_c0;
    reg [15:0] asc_c1;

    // Product ASCs for Stage 2
    reg [15:0] asc_p0;
    reg [15:0] asc_p1;
    reg [15:0] asc_p2;
    reg [15:0] asc_p3;
    reg signed [15:0] asc_p_raw0;
    reg signed [15:0] asc_p_raw1;
    reg signed [15:0] asc_p_raw2;
    reg signed [15:0] asc_p_raw3;

    reg signed [15:0] asc_raw0;
    reg signed [15:0] asc_raw1;

    reg signed [15:0] exp_ab_dbg;
    reg signed [15:0] exp_c_dbg;

    always @(*) begin
        // Defaults
        A_e3 = 14'sd0; A_e2 = 14'sd0; A_e1 = 14'sd0; A_e0 = 14'sd0;
        B_e3 = 14'sd0; B_e2 = 14'sd0; B_e1 = 14'sd0; B_e0 = 14'sd0;
        C_e3 = 14'sd0; C_e2 = 14'sd0; C_e1 = 14'sd0; C_e0 = 14'sd0;

        case (Prec)
            DP: begin
                if (Para) begin
                    // DP product path remains DP exponent, but C is two SP addends.
                    A_e0 = unpack_exp_unbiased(A_exp[10:0], BIAS_DP);
                    B_e0 = unpack_exp_unbiased(B_exp[10:0], BIAS_DP);
                    C_e3 = unpack_exp_unbiased({3'd0, C_exp[31:24]}, BIAS_SP);
                    C_e1 = unpack_exp_unbiased({3'd0, C_exp[15:8]},  BIAS_SP);
                end else begin
                    A_e0 = unpack_exp_unbiased(A_exp[10:0], BIAS_DP);
                    B_e0 = unpack_exp_unbiased(B_exp[10:0], BIAS_DP);
                    C_e0 = unpack_exp_unbiased(C_exp[10:0], BIAS_DP);
                end
            end

            SP,
            TF32: begin
                A_e3 = unpack_exp_unbiased({3'd0, A_exp[31:24]}, BIAS_SP);
                A_e1 = unpack_exp_unbiased({3'd0, A_exp[15:8]},  BIAS_SP);
                B_e3 = unpack_exp_unbiased({3'd0, B_exp[31:24]}, BIAS_SP);
                B_e1 = unpack_exp_unbiased({3'd0, B_exp[15:8]},  BIAS_SP);
                C_e3 = unpack_exp_unbiased({3'd0, C_exp[31:24]}, BIAS_SP);
                C_e1 = unpack_exp_unbiased({3'd0, C_exp[15:8]},  BIAS_SP);
            end

            HP: begin
                A_e3 = unpack_exp_unbiased({6'd0, A_exp[28:24]}, BIAS_HP);
                A_e2 = unpack_exp_unbiased({6'd0, A_exp[20:16]}, BIAS_HP);
                A_e1 = unpack_exp_unbiased({6'd0, A_exp[12:8]},  BIAS_HP);
                A_e0 = unpack_exp_unbiased({6'd0, A_exp[4:0]},   BIAS_HP);

                B_e3 = unpack_exp_unbiased({6'd0, B_exp[28:24]}, BIAS_HP);
                B_e2 = unpack_exp_unbiased({6'd0, B_exp[20:16]}, BIAS_HP);
                B_e1 = unpack_exp_unbiased({6'd0, B_exp[12:8]},  BIAS_HP);
                B_e0 = unpack_exp_unbiased({6'd0, B_exp[4:0]},   BIAS_HP);

                // C is always SP format in HP mode (M=1 or 2 SP addends)
                C_e3 = unpack_exp_unbiased({3'd0, C_exp[31:24]}, BIAS_SP);
                C_e1 = unpack_exp_unbiased({3'd0, C_exp[15:8]},  BIAS_SP);
            end

            BF16: begin
                A_e3 = unpack_exp_unbiased({3'd0, A_exp[31:24]}, BIAS_BF16);
                A_e2 = unpack_exp_unbiased({3'd0, A_exp[23:16]}, BIAS_BF16);
                A_e1 = unpack_exp_unbiased({3'd0, A_exp[15:8]},  BIAS_BF16);
                A_e0 = unpack_exp_unbiased({3'd0, A_exp[7:0]},   BIAS_BF16);

                B_e3 = unpack_exp_unbiased({3'd0, B_exp[31:24]}, BIAS_BF16);
                B_e2 = unpack_exp_unbiased({3'd0, B_exp[23:16]}, BIAS_BF16);
                B_e1 = unpack_exp_unbiased({3'd0, B_exp[15:8]},  BIAS_BF16);
                B_e0 = unpack_exp_unbiased({3'd0, B_exp[7:0]},   BIAS_BF16);

                // C is always SP format in BF16 mode (M=1 or 2 SP addends)
                C_e3 = unpack_exp_unbiased({3'd0, C_exp[31:24]}, BIAS_SP);
                C_e1 = unpack_exp_unbiased({3'd0, C_exp[15:8]},  BIAS_SP);
            end

            default: ;
        endcase
    end

    always @(*) begin
        exp_ab_max = -14'sd8192;
        exp_c0     = -14'sd8192;
        exp_c1     = -14'sd8192;
        exp_c_max  = -14'sd8192;
        const_term = 14'sd0;
        bias_ab_dbg = BIAS_DP;
        bias_c_dbg  = BIAS_DP;

        case (Prec)
            DP: begin
                if (Para) begin
                    // DP product + dual SP addends.
                    exp_ab_max = AB_e0;
                    exp_c1 = C_e3;
                    exp_c0 = C_e1;
                    exp_c_max = (exp_c1 > exp_c0) ? exp_c1 : exp_c0;

                    // Para adds +1 for dual-addend path
                    const_term = CONST_DP_BASE + 14'sd1 + $signed({13'd0, Cvt});
                    bias_ab_dbg = BIAS_DP;
                    bias_c_dbg  = BIAS_SP;
                end else begin
                    // Regular DP has one effective lane.
                    if (|Valid) begin
                        exp_ab_max = AB_e0;
                        exp_c0     = C_e0;
                        exp_c1     = C_e0;
                        exp_c_max  = C_e0;
                        const_term = CONST_DP_BASE + $signed({13'd0, Cvt});
                    end
                    bias_ab_dbg = BIAS_DP;
                    bias_c_dbg  = BIAS_DP;
                end
            end

            SP,
            TF32: begin
                if (en_top28) exp_ab_max = AB_e3;
                if (en_bot28 && (AB_e1 > exp_ab_max)) exp_ab_max = AB_e1;

                exp_c1 = en_top28 ? C_e3 : -14'sd8192;
                exp_c0 = en_bot28 ? C_e1 : -14'sd8192;
                exp_c_max = (exp_c1 > exp_c0) ? exp_c1 : exp_c0;

                const_term = CONST_PD2_BASE + $signed({13'd0, Cvt});
                bias_ab_dbg = BIAS_SP;
                bias_c_dbg  = BIAS_SP;
            end

            HP,
            BF16: begin
                if (en3) exp_ab_max = AB_e3;
                if (en2 && (AB_e2 > exp_ab_max)) exp_ab_max = AB_e2;
                if (en1 && (AB_e1 > exp_ab_max)) exp_ab_max = AB_e1;
                if (en0 && (AB_e0 > exp_ab_max)) exp_ab_max = AB_e0;

                // C is SP format: two SP addend lanes mapped to high (C_e3) and low (C_e1).
                // C_e2 and C_e0 are unused (left at 0 default) — do NOT include them.
                exp_c1 = en_top28 ? C_e3 : -14'sd8192;
                exp_c0 = en_bot28 ? C_e1 : -14'sd8192;
                exp_c_max = (exp_c1 > exp_c0) ? exp_c1 : exp_c0;

                const_term = CONST_PD4_BASE + $signed({13'd0, Cvt});
                bias_ab_dbg = (Prec == HP) ? BIAS_HP : BIAS_BF16;
                bias_c_dbg  = BIAS_SP; // C is always SP in HP/BF16 modes
            end

            default: ;
        endcase

        // Guard against invalid groups being disabled.
        if (exp_ab_max == -14'sd8192) begin
            exp_ab_max = 14'sd0;
        end
        if (exp_c1 == -14'sd8192) begin
            exp_c1 = 14'sd0;
        end
        if (exp_c0 == -14'sd8192) begin
            exp_c0 = 14'sd0;
        end
        if (exp_c_max == -14'sd8192) begin
            exp_c_max = 14'sd0;
        end

        asc_raw1 = exp_ab_max - exp_c1 - const_term;
        asc_raw0 = exp_ab_max - exp_c0 - const_term;

        // Saturate at 0. Upper bound clamp is handled in shifter stage.
        asc_c1 = asc_raw1[15] ? 16'd0 : {2'd0, asc_raw1[13:0]};
        asc_c0 = asc_raw0[15] ? 16'd0 : {2'd0, asc_raw0[13:0]};

        // Product ASCs for Stage 2 (inter-product alignment)
        // Calculate shift amount for each product relative to max product exponent
        asc_p_raw0 = $signed({2'd0, exp_ab_max}) - $signed({2'd0, AB_e0});
        asc_p_raw1 = $signed({2'd0, exp_ab_max}) - $signed({2'd0, AB_e1});
        asc_p_raw2 = $signed({2'd0, exp_ab_max}) - $signed({2'd0, AB_e2});
        asc_p_raw3 = $signed({2'd0, exp_ab_max}) - $signed({2'd0, AB_e3});

        asc_p0 = asc_p_raw0[15] ? 16'd0 : {2'd0, asc_p_raw0[13:0]};
        asc_p1 = asc_p_raw1[15] ? 16'd0 : {2'd0, asc_p_raw1[13:0]};
        asc_p2 = asc_p_raw2[15] ? 16'd0 : {2'd0, asc_p_raw2[13:0]};
        asc_p3 = asc_p_raw3[15] ? 16'd0 : {2'd0, asc_p_raw3[13:0]};

        // Re-bias debug exponents for readability in MaxExp.
        exp_ab_dbg = exp_ab_max + $signed({1'b0, bias_ab_dbg});
        exp_c_dbg  = exp_c_max  + $signed({1'b0, bias_c_dbg});
    end

    // ExpDiff packs two Stage1 ASCs: {ASC_C1, ASC_C0}
    assign ExpDiff = {asc_c1, asc_c0};

    // MaxExp packs useful references for downstream debug/processing: {ExpCMax, ExpABMax}
    assign MaxExp = {exp_c_dbg[15:0], exp_ab_dbg[15:0]};

    // ProdASC packs four product ASCs for Stage 2: {ASC_P3, ASC_P2, ASC_P1, ASC_P0}
    assign ProdASC = {asc_p3, asc_p2, asc_p1, asc_p0};

endmodule