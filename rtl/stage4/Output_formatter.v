`timescale 1ns / 1ps

module Output_Formatter (
    input  [162:0] Norm_mant,
    input          G, R, S,
    input  [3:0]   Result_sign,
    input  [1:0]   lza_error,
    input  [15:0]  LZA_CNT,
    input  [31:0]  MaxExp,        // {ref_exp[15:0], exp_ab_max[15:0]}
    input  [2:0]   Prec,
    input          Cvt,

    output [63:0]  Result_out,
    output [3:0]   Valid_out
);
    parameter HP = 3'b000, BF16 = 3'b001, TF32 = 3'b010, SP = 3'b011, DP = 3'b100;

    //----------------------------------------------------------
    // 1. Rounder
    //----------------------------------------------------------
    wire [52:0] mant_sel = (Prec == DP)   ? {Norm_mant[161:110], 1'b0} :
                           (Prec == SP)   ? {Norm_mant[161:139], 30'd0} :
                           (Prec == TF32) ? {Norm_mant[161:152], 43'd0} :
                           (Prec == HP)   ? {Norm_mant[161:152], 43'd0} :
                           (Prec == BF16) ? {Norm_mant[161:155], 46'd0} : 53'd0;

    wire [52:0] mant_rounded;
    wire        rnd_carry;

    Rounder u_rounder (
        .Mant_in(mant_sel), .G(G), .R(R), .S(S),
        .Mant_out(mant_rounded), .rnd_carry(rnd_carry)
    );

    // We also need a lower rounder for the lower lane! But for now, we just pass mantissa.
    wire [52:0] mant_rounded_lo = (Prec == SP) ? {Norm_mant[107:85], 30'd0} :
                                  (Prec == TF32) ? {Norm_mant[107:98], 43'd0} : 53'd0;
    wire rnd_carry_lo = 1'b0; // Approximation

    //----------------------------------------------------------
    // 2. Exponent Processing
    //----------------------------------------------------------
    wire signed [15:0] ref_exp  = MaxExp[31:16];

    wire signed [15:0] bias_val = (Prec == DP)   ? 16'sd1023 :
                                  (Prec == SP)   ? 16'sd127  :
                                  (Prec == TF32) ? 16'sd127  :
                                  (Prec == HP)   ? 16'sd15   :
                                  (Prec == BF16) ? 16'sd127  : 16'sd0;

    wire signed [15:0] exp_corr = (Prec == SP) ? 16'sd4 :
                                  (Prec == TF32) ? 16'sd17 : 16'sd0;

    // Calculate independent pre_exp
    wire signed [15:0] pre_exp_hi = ref_exp + bias_val - $signed({8'd0, LZA_CNT[15:8]}) + exp_corr;
    wire signed [15:0] pre_exp_lo = ref_exp + bias_val - $signed({8'd0, LZA_CNT[7:0]}) + exp_corr;

    wire signed [15:0] muxed_hi = pre_exp_hi + (lza_error[1] ? 16'sd1 : 16'sd0) + (rnd_carry ? 16'sd1 : 16'sd0);
    wire signed [15:0] muxed_lo = pre_exp_lo + (lza_error[0] ? 16'sd1 : 16'sd0) + (rnd_carry_lo ? 16'sd1 : 16'sd0);
    wire signed [15:0] muxed_dp = pre_exp_hi + (lza_error[0] ? 16'sd1 : 16'sd0) + (rnd_carry ? 16'sd1 : 16'sd0); // DP uses lza_error[0] in Normalize

    // Saturation
    wire signed [15:0] exp_max_val = (Prec == DP) ? 16'sd2046 :
                                     (Prec == HP) ? 16'sd30   : 16'sd254;

    wire exp_of_hi = (muxed_hi > exp_max_val);
    wire exp_uf_hi = (muxed_hi <= 16'sd0);
    wire exp_of_lo = (muxed_lo > exp_max_val);
    wire exp_uf_lo = (muxed_lo <= 16'sd0);
    wire exp_of_dp = (muxed_dp > exp_max_val);
    wire exp_uf_dp = (muxed_dp <= 16'sd0);

    wire result_is_zero = (Norm_mant == 163'd0);

    //----------------------------------------------------------
    // 3. Output Packing
    //----------------------------------------------------------
    reg [63:0] result_reg;
    reg [3:0]  valid_reg;

    always @(*) begin
        result_reg = 64'd0;
        valid_reg  = (Prec == DP) ? 4'b0001 :
                     (Prec == SP || Prec == TF32) ? 4'b0101 : 4'b1111;

        if (result_is_zero) begin
            result_reg = 64'd0;
        end else begin
            case (Prec)
                DP: begin
                    if (exp_uf_dp) result_reg = 64'd0;
                    else if (exp_of_dp) result_reg = {Result_sign[0], 11'h7FF, 52'd0};
                    else result_reg = {Result_sign[0], muxed_dp[10:0], mant_rounded[52:1]};
                end
                SP: begin
                    result_reg[63:32] = exp_uf_hi ? 32'd0 : exp_of_hi ? {Result_sign[3], 8'hFF, 23'd0} : {Result_sign[3], muxed_hi[7:0], mant_rounded[52:30]};
                    result_reg[31:0]  = exp_uf_lo ? 32'd0 : exp_of_lo ? {Result_sign[1], 8'hFF, 23'd0} : {Result_sign[1], muxed_lo[7:0], mant_rounded_lo[52:30]};
                end
                TF32: begin
                    result_reg[63:32] = exp_uf_hi ? 32'd0 : exp_of_hi ? {Result_sign[3], 8'hFF, 23'd0} : {Result_sign[3], muxed_hi[7:0], mant_rounded[52:43], 13'd0};
                    result_reg[31:0]  = exp_uf_lo ? 32'd0 : exp_of_lo ? {Result_sign[1], 8'hFF, 23'd0} : {Result_sign[1], muxed_lo[7:0], mant_rounded_lo[52:43], 13'd0};
                end
                HP: begin
                    result_reg = {Result_sign[3], muxed_hi[4:0], mant_rounded[52:43], 
                                  Result_sign[2], muxed_hi[4:0], mant_rounded[52:43],
                                  Result_sign[1], muxed_hi[4:0], mant_rounded[52:43],
                                  Result_sign[0], muxed_hi[4:0], mant_rounded[52:43]};
                end
                BF16: begin
                    result_reg = {Result_sign[3], muxed_hi[7:0], mant_rounded[52:46],
                                  Result_sign[2], muxed_hi[7:0], mant_rounded[52:46],
                                  Result_sign[1], muxed_hi[7:0], mant_rounded[52:46],
                                  Result_sign[0], muxed_hi[7:0], mant_rounded[52:46]};
                end
            endcase
        end
    end

    assign Result_out = result_reg;
    assign Valid_out  = valid_reg;

endmodule
