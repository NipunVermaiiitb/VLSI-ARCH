`timescale 1ns / 1ps

module exponent_comparison (
    // Inputs from Stage 1 extraction
    input  [31:0] A_exp, // Packed exponent fields for A0-A3
    input  [31:0] B_exp, // Packed exponent fields for B0-B3
    input  [31:0] C_exp, // Packed exponent fields for C0-C1

    input  [2:0]  Prec,  // Mode selection
    input  [3:0]  Valid, // Valid mask for products
    input         Para,  // Dual-path Parallel mode
    input         Cvt,   // Conversion mode

    // Outputs per Figure 5
    output [31:0] ExpDiff, // To Addend Alignment Shifter (Stage 1)
    output [31:0] MaxExp,  // To Stage 1 Register -> Stage 4
    output [63:0] ProdASC  // Product Alignment Shift Counts for Stage 2
);

    // --- Precision Parameters ---
    localparam HP   = 3'b000; // 5-bit exp, 15 bias
    localparam BF16 = 3'b001; // 8-bit exp, 127 bias
    localparam TF32 = 3'b010; // 8-bit exp, 127 bias
    localparam SP   = 3'b011; // 8-bit exp, 127 bias
    localparam DP   = 3'b100; // 11-bit exp, 1023 bias

    // --- Biases ---
    localparam [10:0] BIAS_DP = 11'd1023;
    localparam [10:0] BIAS_SP = 11'd127; // Same for BF16/TF32
    localparam [10:0] BIAS_HP = 11'd15;

    // Internal signed registers (14-bit to handle bias math safely)
    reg signed [13:0] A_e [0:3];
    reg signed [13:0] B_e [0:3];
    reg signed [13:0] C_e [0:1];

    // Product exponents: E_p = E_a + E_b
    wire signed [13:0] AB_e [0:3];
    assign AB_e[0] = A_e[0] + B_e[0];
    assign AB_e[1] = A_e[1] + B_e[1];
    assign AB_e[2] = A_e[2] + B_e[2];
    assign AB_e[3] = A_e[3] + B_e[3];

    reg signed [13:0] exp_ab_max;
    reg signed [13:0] exp_c_max;

    // Which lanes are actually used
    reg [3:0] lane_valid;

    // --- Format-Specific Extraction ---
    // CRITICAL: Bit ranges must match the packing in component_formatter.
    //   component_formatter SP packs as: {A_in[62:55], 8'd0, A_in[30:23], 8'd0}
    //   So: lane3 exp at [31:24], lane1 exp at [15:8]
    always @(*) begin
        // Reset defaults
        {A_e[0], A_e[1], A_e[2], A_e[3]} = {14'sd0, 14'sd0, 14'sd0, 14'sd0};
        {B_e[0], B_e[1], B_e[2], B_e[3]} = {14'sd0, 14'sd0, 14'sd0, 14'sd0};
        {C_e[0], C_e[1]} = {14'sd0, 14'sd0};
        lane_valid = 4'b0000;

        case (Prec)
            DP: begin
                lane_valid = 4'b0001; // Only lane 0 for DP
                A_e[0] = $signed({3'd0, A_exp[10:0]}) - $signed({3'd0, BIAS_DP});
                B_e[0] = $signed({3'd0, B_exp[10:0]}) - $signed({3'd0, BIAS_DP});
                if (Para) begin
                    C_e[1] = $signed({6'd0, C_exp[31:24]}) - $signed({6'd0, BIAS_SP});
                    C_e[0] = $signed({6'd0, C_exp[15:8]})  - $signed({6'd0, BIAS_SP});
                end else begin
                    C_e[0] = $signed({3'd0, C_exp[10:0]}) - $signed({3'd0, BIAS_DP});
                    C_e[1] = -14'sd8192; // No C1 in DP single-path
                end
            end

            SP, TF32: begin
                // SP packing: {exp_upper[31:24], 8'd0, exp_lower[15:8], 8'd0}
                lane_valid = (Prec == TF32) ? 4'b0101 : 4'b1010; // SP: lanes 3,1; TF32: lanes 2,0
                if (Prec == SP) begin
                    A_e[3] = $signed({6'd0, A_exp[31:24]}) - $signed({6'd0, BIAS_SP});
                    A_e[1] = $signed({6'd0, A_exp[15:8]})  - $signed({6'd0, BIAS_SP});
                    B_e[3] = $signed({6'd0, B_exp[31:24]}) - $signed({6'd0, BIAS_SP});
                    B_e[1] = $signed({6'd0, B_exp[15:8]})  - $signed({6'd0, BIAS_SP});
                end else begin
                    // TF32: same packing format as SP
                    A_e[2] = $signed({6'd0, A_exp[31:24]}) - $signed({6'd0, BIAS_SP});
                    A_e[0] = $signed({6'd0, A_exp[15:8]})  - $signed({6'd0, BIAS_SP});
                    B_e[2] = $signed({6'd0, B_exp[31:24]}) - $signed({6'd0, BIAS_SP});
                    B_e[0] = $signed({6'd0, B_exp[15:8]})  - $signed({6'd0, BIAS_SP});
                end
                C_e[1] = $signed({6'd0, C_exp[31:24]}) - $signed({6'd0, BIAS_SP});
                C_e[0] = $signed({6'd0, C_exp[15:8]})  - $signed({6'd0, BIAS_SP});
            end

            BF16: begin
                lane_valid = 4'b1111;
                A_e[3] = $signed({6'd0, A_exp[31:24]}) - $signed({6'd0, BIAS_SP});
                A_e[2] = $signed({6'd0, A_exp[23:16]}) - $signed({6'd0, BIAS_SP});
                A_e[1] = $signed({6'd0, A_exp[15:8]})  - $signed({6'd0, BIAS_SP});
                A_e[0] = $signed({6'd0, A_exp[7:0]})   - $signed({6'd0, BIAS_SP});

                B_e[3] = $signed({6'd0, B_exp[31:24]}) - $signed({6'd0, BIAS_SP});
                B_e[2] = $signed({6'd0, B_exp[23:16]}) - $signed({6'd0, BIAS_SP});
                B_e[1] = $signed({6'd0, B_exp[15:8]})  - $signed({6'd0, BIAS_SP});
                B_e[0] = $signed({6'd0, B_exp[7:0]})   - $signed({6'd0, BIAS_SP});

                C_e[1] = $signed({6'd0, C_exp[31:24]}) - $signed({6'd0, BIAS_SP});
                C_e[0] = $signed({6'd0, C_exp[7:0]})   - $signed({6'd0, BIAS_SP});
            end

            HP: begin
                lane_valid = 4'b1111;
                // HP packing: {3'b000,exp5, 3'b000,exp5, 3'b000,exp5, 3'b000,exp5}
                // Lane 3 at [28:24], Lane 2 at [20:16], Lane 1 at [12:8], Lane 0 at [4:0]
                A_e[3] = $signed({9'd0, A_exp[28:24]}) - $signed({9'd0, BIAS_HP});
                A_e[2] = $signed({9'd0, A_exp[20:16]}) - $signed({9'd0, BIAS_HP});
                A_e[1] = $signed({9'd0, A_exp[12:8]})  - $signed({9'd0, BIAS_HP});
                A_e[0] = $signed({9'd0, A_exp[4:0]})   - $signed({9'd0, BIAS_HP});

                B_e[3] = $signed({9'd0, B_exp[28:24]}) - $signed({9'd0, BIAS_HP});
                B_e[2] = $signed({9'd0, B_exp[20:16]}) - $signed({9'd0, BIAS_HP});
                B_e[1] = $signed({9'd0, B_exp[12:8]})  - $signed({9'd0, BIAS_HP});
                B_e[0] = $signed({9'd0, B_exp[4:0]})   - $signed({9'd0, BIAS_HP});

                C_e[1] = $signed({9'd0, C_exp[28:24]}) - $signed({9'd0, BIAS_HP});
                C_e[0] = $signed({9'd0, C_exp[4:0]})   - $signed({9'd0, BIAS_HP});
            end
            default: ;
        endcase
    end

    // --- Exponent Comparison (Max finding) ---
    // Only consider lanes that are actually valid for the current mode
    always @(*) begin
        exp_ab_max = -14'sd8192;
        if (lane_valid[3] && (AB_e[3] > exp_ab_max)) exp_ab_max = AB_e[3];
        if (lane_valid[2] && (AB_e[2] > exp_ab_max)) exp_ab_max = AB_e[2];
        if (lane_valid[1] && (AB_e[1] > exp_ab_max)) exp_ab_max = AB_e[1];
        if (lane_valid[0] && (AB_e[0] > exp_ab_max)) exp_ab_max = AB_e[0];

        if (exp_ab_max == -14'sd8192) exp_ab_max = 14'sd0;

        // C max: Only consider C lanes that have data
        if (C_e[1] == -14'sd8192)
            exp_c_max = C_e[0];
        else if (C_e[1] > C_e[0])
            exp_c_max = C_e[1];
        else
            exp_c_max = C_e[0];
    end

    // --- Output Assignments ---

    // 1. ExpDiff drives Stage 1 Addend Shifter
    //    Includes format constant: C starts at bit 162, shifted right to land
    //    at the correct position relative to the product.
    //    Updated per user architecture specs:
    wire [7:0] asc_const = (Prec == DP)   ? 8'd2  :
                           (Prec == SP)   ? 8'd3  :
                           (Prec == TF32) ? 8'd16 :
                           (Prec == HP)   ? 8'd6  :
                           8'd12; // BF16

    wire signed [15:0] asc1_raw = $signed({6'd0, asc_const}) + (exp_ab_max - C_e[1]);
    wire signed [15:0] asc0_raw = $signed({6'd0, asc_const}) + (exp_ab_max - C_e[0]);

    assign ExpDiff[31:16] = (asc1_raw > 0) ? asc1_raw[15:0] : 16'd0;
    assign ExpDiff[15:0]  = (asc0_raw > 0) ? asc0_raw[15:0] : 16'd0;

    // 2. MaxExp: pass ref_exp for Stage 4 exponent calculation
    //    ref_exp = max(exp_ab_max + asc_const, exp_c_max) — this is the exponent
    //    that position 162 represents in the magnitude field.
    //    Output biased exp = ref_exp + bias - LZA_CNT
    wire signed [13:0] exp_ab_plus_const = exp_ab_max + $signed({6'd0, asc_const});
    wire signed [13:0] ref_exp = (exp_ab_plus_const > exp_c_max) ? exp_ab_plus_const : exp_c_max;

    assign MaxExp = { {2{ref_exp[13]}}, ref_exp, {2{exp_ab_max[13]}}, exp_ab_max };

    // 3. ProdASC: per-lane product alignment shift counts for Stage 2
    wire signed [13:0] pdiff0 = exp_ab_max - AB_e[0];
    wire signed [13:0] pdiff1 = exp_ab_max - AB_e[1];
    wire signed [13:0] pdiff2 = exp_ab_max - AB_e[2];
    wire signed [13:0] pdiff3 = exp_ab_max - AB_e[3];
    assign ProdASC[15:0]  = (pdiff0 > 0) ? pdiff0[15:0] : 16'd0;
    assign ProdASC[31:16] = (pdiff1 > 0) ? pdiff1[15:0] : 16'd0;
    assign ProdASC[47:32] = (pdiff2 > 0) ? pdiff2[15:0] : 16'd0;
    assign ProdASC[63:48] = (pdiff3 > 0) ? pdiff3[15:0] : 16'd0;

endmodule
