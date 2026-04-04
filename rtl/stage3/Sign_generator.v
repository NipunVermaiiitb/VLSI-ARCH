`timescale 1ns / 1ps

// Sign Generator for DPDAC Stage 3
//
// Determines the sign of the final result after all products and addends
// have been summed. Uses the CPA result MSB (CPA_neg) as the authoritative
// sign indicator. 
//
// PD_mode (single DP FMA):
//   The accumulator sum is stored as a signed value (two's complement is
//   handled by the product sign inversion in Stage 2). The sign of the result
//   is the MSB of the CPA sum — if it overflowed into bit 162, the net
//   result was negative. Otherwise positive.
//   Additionally, if the product was declared negative (Sign_AB[0]=1) but
//   the addend dominated and flipped the sign back, the CPA MSB captures that.
//
// PD2/PD4 modes (multi-lane accumulation):
//   The net sum sign is simply the CPA MSB.
//
// Zero result: if the CPA result is all-zero, the sign is forced to +0.

module Sign_Generator (
    input  [3:0]   Sign_AB,   // Per-lane product signs
    input  [3:0]   Valid,     // Per-lane valid flags
    input          PD_mode,   // High for single-lane DP FMA
    input          CPA_neg,   // MSB of CPA result (1 = accumulated sum is negative)
    input  [162:0] CPA_result,// Full CPA result (for zero detection)
    output         Result_sign
);

    // Force sign to 0 for exact zero (±0 → +0 per IEEE 754 default)
    wire result_is_zero = (CPA_result === 163'd0);

    // For PD_mode: sign comes from the CPA MSB (post-accumulation sign)
    // For PD2/PD4: same, the dominant term's sign is encoded in CPA_neg
    wire raw_sign = CPA_neg;

    assign Result_sign = result_is_zero ? 1'b0 : raw_sign;

endmodule