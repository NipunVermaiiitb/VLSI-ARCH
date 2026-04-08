`timescale 1ns / 1ps

module Normalization_Shifter (
    input  [162:0] Add_Rslt,    // Unsigned magnitude from Stage 3
    input  [15:0]  LZA_CNT,     // Dual Number of leading zeros: [15:8] hi, [7:0] lo
    input  [2:0]   Prec,

    output [162:0] Norm_mant,   // Shifted result
    output         G,           // Guard bit
    output         R,           // Round bit
    output         S,           // Sticky bit
    output [1:0]   lza_error    // 2-bit error: [1] hi, [0] lo
);
    localparam DP = 3'b100;

    // 1. Initial Left Shift
    wire [7:0] shift_amt_hi = (LZA_CNT[15:8] > 8'd54) ? 8'd54 : LZA_CNT[15:8];
    wire [7:0] shift_amt_lo = (LZA_CNT[7:0] > 8'd109) ? 8'd109 : LZA_CNT[7:0];
    wire [7:0] shift_amt_dp = (LZA_CNT[15:8] > 8'd162) ? 8'd162 : LZA_CNT[15:8];

    wire [53:0] pre_norm_hi = Add_Rslt[162:109] << shift_amt_hi;
    wire [108:0] pre_norm_lo = Add_Rslt[108:0] << shift_amt_lo;
    wire [162:0] pre_norm_dp = Add_Rslt << shift_amt_dp;

    // 2. LZAC Error Correction
    wire lza_err_hi = ~pre_norm_hi[53] & (|Add_Rslt[162:109]);
    wire lza_err_lo = ~pre_norm_lo[108] & (|Add_Rslt[108:0]);
    wire lza_err_dp = ~pre_norm_dp[162] & (|Add_Rslt);

    assign lza_error = (Prec == DP) ? {1'b0, lza_err_dp} : {lza_err_hi, lza_err_lo};

    // Final 1-bit shift correction
    wire [53:0]  norm_hi = lza_err_hi ? (pre_norm_hi << 1) : pre_norm_hi;
    wire [108:0] norm_lo = lza_err_lo ? (pre_norm_lo << 1) : pre_norm_lo;
    wire [162:0] norm_dp = lza_err_dp ? (pre_norm_dp << 1) : pre_norm_dp;

    assign Norm_mant = (Prec == DP) ? norm_dp : {norm_hi, norm_lo};

    // 3. GRS Bits Extraction (Only used for DP currently in downstream logic)
    assign G = Norm_mant[109];
    assign R = Norm_mant[108];
    assign S = |Norm_mant[107:0];

endmodule
