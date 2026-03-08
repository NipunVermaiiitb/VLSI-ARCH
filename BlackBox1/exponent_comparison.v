module exponent_comparison (

    input  [31:0] A_exp,
    input  [31:0] B_exp,
    input  [31:0] C_exp,

    input  [2:0]  Prec,
    input  [3:0]  Valid,
    input         Para,
    input         Cvt,

    output [31:0] ExpDiff,
    output [31:0] MaxExp

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
    parameter CONST_DP_BASE  = 13'd2;
    parameter CONST_PD2_BASE = 13'd2;
    parameter CONST_PD4_BASE = 13'd2;

    //----------------------------------------------------------
    // Per-lane exponents in unified 13-bit space
    //----------------------------------------------------------
    reg [12:0] A_e3, A_e2, A_e1, A_e0;
    reg [12:0] B_e3, B_e2, B_e1, B_e0;
    reg [12:0] C_e3, C_e2, C_e1, C_e0;

    // Product exponents per lane/group
    wire [12:0] AB_e3 = A_e3 + B_e3;
    wire [12:0] AB_e2 = A_e2 + B_e2;
    wire [12:0] AB_e1 = A_e1 + B_e1;
    wire [12:0] AB_e0 = A_e0 + B_e0;

    wire en3 = Valid[3];
    wire en2 = Valid[2];
    wire en1 = Valid[1];
    wire en0 = Valid[0];

    wire en_top28 = en3 | en2;
    wire en_bot28 = en1 | en0;

    reg [12:0] exp_ab_max;
    reg [12:0] exp_c0;
    reg [12:0] exp_c1;
    reg [12:0] exp_c_max;
    reg [12:0] const_term;

    reg [15:0] asc_c0;
    reg [15:0] asc_c1;

    reg signed [14:0] asc_raw0;
    reg signed [14:0] asc_raw1;

    always @(*) begin
        // Defaults
        A_e3 = 13'd0; A_e2 = 13'd0; A_e1 = 13'd0; A_e0 = 13'd0;
        B_e3 = 13'd0; B_e2 = 13'd0; B_e1 = 13'd0; B_e0 = 13'd0;
        C_e3 = 13'd0; C_e2 = 13'd0; C_e1 = 13'd0; C_e0 = 13'd0;

        case (Prec)
            DP: begin
                // DP uses full 11-bit exponent in the low field.
                A_e0 = {2'b00, A_exp[10:0]};
                B_e0 = {2'b00, B_exp[10:0]};
                C_e0 = {2'b00, C_exp[10:0]};
            end

            SP,
            TF32: begin
                // Packed as {exp_top, 8'd0, exp_bot, 8'd0}
                A_e3 = {5'd0, A_exp[31:24]};
                A_e1 = {5'd0, A_exp[15:8]};
                B_e3 = {5'd0, B_exp[31:24]};
                B_e1 = {5'd0, B_exp[15:8]};
                C_e3 = {5'd0, C_exp[31:24]};
                C_e1 = {5'd0, C_exp[15:8]};
            end

            HP: begin
                // Packed as bytes with 3'b0 + 5-bit exponent per lane.
                A_e3 = {8'd0, A_exp[28:24]};
                A_e2 = {8'd0, A_exp[20:16]};
                A_e1 = {8'd0, A_exp[12:8]};
                A_e0 = {8'd0, A_exp[4:0]};

                B_e3 = {8'd0, B_exp[28:24]};
                B_e2 = {8'd0, B_exp[20:16]};
                B_e1 = {8'd0, B_exp[12:8]};
                B_e0 = {8'd0, B_exp[4:0]};

                C_e3 = {8'd0, C_exp[28:24]};
                C_e2 = {8'd0, C_exp[20:16]};
                C_e1 = {8'd0, C_exp[12:8]};
                C_e0 = {8'd0, C_exp[4:0]};
            end

            BF16: begin
                // Packed as four contiguous exponent bytes.
                A_e3 = {5'd0, A_exp[31:24]};
                A_e2 = {5'd0, A_exp[23:16]};
                A_e1 = {5'd0, A_exp[15:8]};
                A_e0 = {5'd0, A_exp[7:0]};

                B_e3 = {5'd0, B_exp[31:24]};
                B_e2 = {5'd0, B_exp[23:16]};
                B_e1 = {5'd0, B_exp[15:8]};
                B_e0 = {5'd0, B_exp[7:0]};

                C_e3 = {5'd0, C_exp[31:24]};
                C_e2 = {5'd0, C_exp[23:16]};
                C_e1 = {5'd0, C_exp[15:8]};
                C_e0 = {5'd0, C_exp[7:0]};
            end

            default: ;
        endcase
    end

    always @(*) begin
        exp_ab_max = 13'd0;
        exp_c0     = 13'd0;
        exp_c1     = 13'd0;
        exp_c_max  = 13'd0;
        const_term = 13'd0;

        case (Prec)
            DP: begin
                // DP has one effective lane.
                if (|Valid) begin
                    exp_ab_max = AB_e0;
                    exp_c0     = C_e0;
                    exp_c1     = 13'd0;
                    exp_c_max  = C_e0;
                    // +1 for Para (carry-growth path), +1 for Cvt (mixed-precision hook)
                    const_term = CONST_DP_BASE + {12'd0, Para} + {12'd0, Cvt};
                end
            end

            SP,
            TF32: begin
                if (en_top28) exp_ab_max = AB_e3;
                if (en_bot28 && (AB_e1 > exp_ab_max)) exp_ab_max = AB_e1;

                exp_c1 = en_top28 ? C_e3 : 13'd0;
                exp_c0 = en_bot28 ? C_e1 : 13'd0;
                exp_c_max = (exp_c1 > exp_c0) ? exp_c1 : exp_c0;

                const_term = CONST_PD2_BASE + {12'd0, Cvt};
            end

            HP,
            BF16: begin
                if (en3) exp_ab_max = AB_e3;
                if (en2 && (AB_e2 > exp_ab_max)) exp_ab_max = AB_e2;
                if (en1 && (AB_e1 > exp_ab_max)) exp_ab_max = AB_e1;
                if (en0 && (AB_e0 > exp_ab_max)) exp_ab_max = AB_e0;

                // Stage1 addend alignment uses two C paths; group lanes into high/low halves.
                exp_c1 = ((en3 ? C_e3 : 13'd0) > (en2 ? C_e2 : 13'd0)) ? (en3 ? C_e3 : 13'd0) : (en2 ? C_e2 : 13'd0);
                exp_c0 = ((en1 ? C_e1 : 13'd0) > (en0 ? C_e0 : 13'd0)) ? (en1 ? C_e1 : 13'd0) : (en0 ? C_e0 : 13'd0);
                exp_c_max = (exp_c1 > exp_c0) ? exp_c1 : exp_c0;

                const_term = CONST_PD4_BASE + {12'd0, Cvt};
            end

            default: ;
        endcase

        asc_raw1 = $signed({1'b0, exp_ab_max}) - $signed({1'b0, exp_c1}) - $signed({1'b0, const_term});
        asc_raw0 = $signed({1'b0, exp_ab_max}) - $signed({1'b0, exp_c0}) - $signed({1'b0, const_term});

        // Saturate at 0. Upper bound clamp is handled in shifter stage.
        asc_c1 = asc_raw1[14] ? 16'd0 : {3'd0, asc_raw1[12:0]};
        asc_c0 = asc_raw0[14] ? 16'd0 : {3'd0, asc_raw0[12:0]};
    end

    // ExpDiff packs two Stage1 ASCs: {ASC_C1, ASC_C0}
    assign ExpDiff = {asc_c1, asc_c0};

    // MaxExp packs useful references for downstream debug/processing: {ExpCMax, ExpABMax}
    assign MaxExp = {3'd0, exp_c_max, 3'd0, exp_ab_max};

endmodule