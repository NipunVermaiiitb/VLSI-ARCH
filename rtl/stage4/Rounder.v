`timescale 1ns / 1ps

// IEEE 754 Round-to-Nearest-Even Rounder — Stage 4
//
// Takes the normalized mantissa (already shifted) and rounds it using
// the Guard (G), Round (R), and Sticky (S) bits.
//
// Round-to-nearest-even rule:
//   if GRS == 0b100 (exactly halfway):  round up only if LSB of mantissa is 1 (ties-to-even)
//   if GRS  > 0b100 (above halfway):    always round up (increment mantissa)
//   if GRS  < 0b100 (below halfway):    truncate (no action)
//
// The mantissa width passed in is 53 bits (DP). For lower precisions the
// upper slice of Mant_in is used and the rest is 0, so rounding still
// works correctly (the LSB threshold is at bit 0 of whatever you pass in).
//
// Carry-out from rounding (rnd_carry) is used by Output_Formatter to
// bump the exponent when mantissa overflows to 1.0.

module Rounder (

    input  [52:0] Mant_in,   // Mantissa bits to round (53 bits for DP, upper bits for lower prec)
    input         G,          // Guard bit
    input         R,          // Round bit
    input         S,          // Sticky bit

    output [52:0] Mant_out,  // Rounded mantissa
    output        rnd_carry   // 1 if rounding caused mantissa to overflow (1.111…1 → 10.0)

);

    // Round increment: add 1 when GRS indicate round-up
    wire round_up;

    // Halfway: G=1, R=0, S=0 → tie-break: round if LSB=1 (round-to-even)
    wire halfway = G & ~R & ~S;

    // Above halfway: G=1, and (R=1 OR S=1)
    wire above_half = G & (R | S);

    assign round_up = above_half | (halfway & Mant_in[0]);

    // Add increment
    wire [53:0] mant_rounded = {1'b0, Mant_in} + {53'd0, round_up};

    assign Mant_out  = mant_rounded[52:0];
    assign rnd_carry = mant_rounded[53];   // mantissa overflowed

endmodule
