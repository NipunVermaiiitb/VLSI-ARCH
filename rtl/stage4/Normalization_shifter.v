// Normalization Shifter — Stage 4
//
// Left-shifts the 163-bit unsigned magnitude result by LZA_CNT positions
// to move the leading 1 to bit [162] (the implicit integer bit position
// at the top of the accumulator after normalization).
//
// After normalization (left-shift by LZA_CNT):
//   Norm_mant[162]    = implicit 1 (should be 1 for non-zero result)
//   Norm_mant[161:110] = 52 DP explicit mantissa bits
//   Norm_mant[109]    = guard bit  (G)
//   Norm_mant[108]    = round bit  (R)
//   Norm_mant[107:0]  = sticky sources (S = OR of these)
//
// The IEEE 754 exponent adjustment:
//   exp_final = MaxExp - LZA_CNT + overflow_flag + rnd_carry
// where overflow_flag = 1 when the implicit 1 was already at bit 162
// before shifting (i.e., LZA_CNT would have been 0 but the implicit
// bit position was already at the top, meaning an extra MSB is present
// -- in our case this doesn't happen because 163-bit accumulator can
// always accommodate the leading 1 >= 1 bit below the top during normal
// operation; bit 162 overflow means the true result was 2x larger and
// exponent += 1).

`timescale 1ns / 1ps

module Normalization_Shifter (

    input  [162:0] Add_Rslt,    // Unsigned magnitude from Stage 3
    input  [7:0]   LZA_CNT,    // Number of leading zeros (from LZAC)
    input  [2:0]   Prec,        // Precision mode (needed for overflow_flag)

    output [162:0] Norm_mant,  // Shifted result: implicit 1 at bit [162]
    output         G,          // Guard bit  (Norm_mant[109])
    output         R,          // Round bit  (Norm_mant[108])
    output         S,          // Sticky = OR(Norm_mant[107:0])
    output         overflow_flag // Implicit bit already at [162] before shift

);

    localparam DP = 3'b100;

    // Clamp shift to avoid undefined behavior
    wire [7:0] shift_amt = (LZA_CNT > 8'd162) ? 8'd162 : LZA_CNT;

    // Left-shift: brings the leading 1 to bit [162]
    assign Norm_mant = Add_Rslt << shift_amt;

    // Overflow flag: implicit bit was already at [162] before normalization.
    // For DP: natural unit product is at ~161, so bit 162 being set = mantissa overflow (+exponent).
    // For non-DP modes: unit products are well below 162 (154-156 range), so bit 162=1 with LZA=0
    //   means a very large addend C dominates (ASC=0), not a mantissa overflow — suppress flag.
    assign overflow_flag = (Prec == DP) ? ((LZA_CNT == 8'd0) & Add_Rslt[162]) : 1'b0;


    //----------------------------------------------------------
    // Guard / Round / Sticky after normalization
    //
    // DP: 52 explicit mantissa bits at Norm_mant[161:110]
    //     Implicit 1 at Norm_mant[162]
    //     G = Norm_mant[109]
    //     R = Norm_mant[108]
    //     S = |Norm_mant[107:0]
    //
    // SP/TF32 (23 explicit bits): mantissa at Norm_mant[161:139]
    //     G = Norm_mant[138]
    //     (for G/R/S we expose DP-window here; formatter selects per-prec)
    //
    // We expose DP-compatible G/R/S; the Output_Formatter uses the
    // same window for all modes (rounding is done at the DP boundary
    // and the SP/HP/BF16 formatter takes only the upper mantissa bits).
    //----------------------------------------------------------

    assign G = Norm_mant[109];
    assign R = Norm_mant[108];
    assign S = |Norm_mant[107:0];

endmodule
