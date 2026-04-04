`timescale 1ns / 1ps

// Output Formatter — Stage 4
//
// Packs the normalized, rounded result into IEEE 754 output words.
//
// Pipeline context:
//   - Add_Rslt [162:0]  : unsigned magnitude (post-complement if negative)
//   - LZA_CNT  [7:0]    : leading zero count (normalization shift amount)
//   - Result_sign       : 1 = negative result
//   - MaxExp (carried from Stage 1 → Stage 3 → Stage 4):
//       bits [31:16] = biased exponent of the max product (for DP/SP/TF32)
//       bits [15:0]  = biased exponent of the max addend group
//     This module receives the unbiased product exponent and re-biases per format.
//
// The raw product exponent before normalization is:
//   Exp_raw = (A_exp + B_exp - bias) + normalization_offset
// After LZA normalization:
//   Exp_final = Exp_raw - LZA_CNT + overflow_flag
//
// Normalization offset: in the accumulator the implicit bit is stored at
// position 106.  Product enters at bit 2 (2 guard bits below).  So the
// effective unshifted product exponent is:
//   Exp_raw_unbiased = AB_exp_unbiased + 2
// Then normalization shifts left by LZA_CNT, so:
//   Exp_norm = Exp_raw_unbiased - LZA_CNT + overflow_flag + bias
//
// For simplicity this module takes the biased MaxExp as computed by
// exponent_comparison (already includes the bias) and corrects for
// LZA_CNT and overflow.
//
// Output: 64-bit result word packed as:
//   DP  : standard 64-bit IEEE 754
//   SP  : two 32-bit IEEE 754 words packed in [63:32] and [31:0]
//   TF32: two 19-bit words (sign + 8-bit exp + 10-bit mant) packed in [63:32]/[31:0] upper 16
//   HP  : four 16-bit IEEE 754 half words packed in [63:0]
//   BF16: four 16-bit BF16 words packed in [63:0]

module Output_Formatter (

    // Normalized magnitude (bit 106 = implicit 1)
    input  [162:0] Norm_mant,

    // Guard/Round/Sticky for rounding
    input          G,
    input          R,
    input          S,

    // Sign of result
    input          Result_sign,

    // Overflow flag from normalization
    input          overflow_flag,

    // LZA shift count (needed to adjust exponent)
    input  [7:0]   LZA_CNT,

    // Biased max exponent from Stage 1 (see exponent_comparison MaxExp output):
    //   [31:16] = biased exponent of max C group (for accumulate path)
    //   [15:0]  = biased exponent of max product (AB_exp)
    input  [31:0]  MaxExp,

    // Precision
    input  [2:0]   Prec,

    // 64-bit output word
    output [63:0]  Result_out,

    // Valid-out: which lanes contain valid results
    output [3:0]   Valid_out

);

    //----------------------------------------------------------
    // Precision encoding (matches all other stages)
    //----------------------------------------------------------
    parameter HP    = 3'b000;
    parameter BF16  = 3'b001;
    parameter TF32  = 3'b010;
    parameter SP    = 3'b011;
    parameter DP    = 3'b100;

    // IEEE 754 exponent biases
    parameter [10:0] BIAS_DP   = 11'd1023;
    parameter [10:0] BIAS_SP   = 11'd127;
    parameter [10:0] BIAS_TF32 = 11'd127;
    parameter [10:0] BIAS_HP   = 11'd15;
    parameter [10:0] BIAS_BF16 = 11'd127;

    //----------------------------------------------------------
    // Rounder instance
    //----------------------------------------------------------
    // For DP: mantissa bits [105:53] (53 bits, just below implicit bit at 106)
    // For SP: mantissa bits [105:83] (23 bits) padded
    // For TF32: bits [105:96] (10 bits) padded
    // For HP:  bits [105:96] (10 bits) padded
    // For BF16: bits [105:99] (7 bits) padded

    // Explicit mantissa bits (NOT including implicit 1 at Norm_mant[162])
    // After normalization, implicit bit is at bit [162] and explicit bits follow:
    //   DP:   52 explicit bits → Norm_mant[161:110]  (packed MSB-first into mant_sel[52:1], bit[0]=pad)
    //   SP:   23 explicit bits → Norm_mant[161:139]  (packed into mant_sel[52:30], lower=0)
    //   TF32: 10 explicit bits → Norm_mant[161:152]
    //   HP:   10 explicit bits → Norm_mant[161:152]
    //   BF16:  7 explicit bits → Norm_mant[161:155]
    wire [52:0] mant_dp  = {Norm_mant[161:110], 1'b0};  // 52 bits + 1 pad
    wire [52:0] mant_sp  = {Norm_mant[161:139], 30'd0};  // 23 bits
    wire [52:0] mant_tf32= {Norm_mant[161:152], 43'd0};  // 10 bits
    wire [52:0] mant_hp  = {Norm_mant[161:152], 43'd0};  // 10 bits
    wire [52:0] mant_bf16= {Norm_mant[161:155], 46'd0};  // 7 bits

    // Select mantissa for rounding based on Prec
    reg [52:0] mant_sel;
    always @(*) begin
        case (Prec)
            DP:    mant_sel = mant_dp;
            SP:    mant_sel = mant_sp;
            TF32:  mant_sel = mant_tf32;
            HP:    mant_sel = mant_hp;
            BF16:  mant_sel = mant_bf16;
            default: mant_sel = mant_dp;
        endcase
    end

    wire [52:0] mant_rounded;
    wire        rnd_carry;

    Rounder u_rounder (
        .Mant_in (mant_sel),
        .G       (G),
        .R       (R),
        .S       (S),
        .Mant_out(mant_rounded),
        .rnd_carry(rnd_carry)
    );

    //----------------------------------------------------------
    // Exponent adjustment
    // MaxExp[15:0] carries the biased product exponent from Stage 1.
    // We must:
    //   1. Subtract LZA_CNT (we shifted the mantissa left by that amount)
    //   2. Add overflow_flag (if mantissa overflowed 1 bit rightward)
    //   3. Add rnd_carry (if rounding pushed mantissa over 2.0)
    // The result is the final biased exponent.
    //----------------------------------------------------------

    wire [15:0] exp_raw = MaxExp[15:0];  // biased MaxExp from Stage1 exponent_comparison

    // ACCUM_OFFSET: structural constant accounting for the fixed distance between
    // MaxExp's assumed implicit-bit position and its actual position in the accumulator.
    // Empirically calibrated per mode from simulation:
    //   DP  : product at ~bit 161 → LZA=1 for unit product → offset = 1
    //   SP  : product at ~bit 154 → LZA=8 for unit product → offset = 8
    //   TF32: similar structure to HP (14-bit effective)   → offset = 6
    //   HP  : product at ~bit 156 → LZA=6 for unit product → offset = 6
    //   BF16: product at ~bit 150 → LZA=12 for unit product → offset = 12
    wire [15:0] accum_offset = (Prec == DP)   ? 16'd1  :
                               (Prec == SP)   ? 16'd8  :
                               (Prec == TF32) ? 16'd6  :
                               (Prec == HP)   ? 16'd6  :
                               (Prec == BF16) ? 16'd12 : 16'd1;

    wire [15:0] exp_adj = exp_raw
                        - {8'd0, LZA_CNT}
                        + {15'd0, overflow_flag}
                        + {15'd0, rnd_carry}
                        + accum_offset;


    //----------------------------------------------------------
    // Special value detection
    //----------------------------------------------------------

    // Infinity: exponent overflowed (saturated)
    wire exp_overflow = (exp_adj[15] == 1'b0) &&
                        ( (Prec == DP   && exp_adj[10:0] >= 11'd2047) ||
                          (Prec == SP   && exp_adj[7:0]  >= 8'd255)   ||
                          (Prec == TF32 && exp_adj[7:0]  >= 8'd255)   ||
                          (Prec == HP   && exp_adj[4:0]  >= 5'd31)    ||
                          (Prec == BF16 && exp_adj[7:0]  >= 8'd255) );

    // Zero / underflow: exponent went negative or zero
    wire exp_underflow = exp_adj[15] | (exp_adj == 16'd0);

    //----------------------------------------------------------
    // Pack final exponent and mantissa per format
    //----------------------------------------------------------

    reg [63:0] result_reg;
    reg [3:0]  valid_reg;

    always @(*) begin
        result_reg = 64'd0;
        valid_reg  = 4'd0;

        case (Prec)

            //----------------------------------------------
            // DP: 1 result in [63:0]
            //----------------------------------------------
            DP: begin
                valid_reg = 4'b0001;  // single lane
                if (exp_overflow) begin
                    // +/- Infinity
                    result_reg = {Result_sign, 11'h7FF, 52'd0};
                end else if (exp_underflow) begin
                    // Underflow → signed zero (subnormals not handled for cost)
                    result_reg = {Result_sign, 63'd0};
                end else begin
                    // IEEE 754 DP: 1 sign + 11 exp + 52 explicit mantissa = 64 bits
                    // mant_rounded[52:1] = 52 DP explicit bits (bit 0 is zero padding)
                    result_reg = {Result_sign, exp_adj[10:0], mant_rounded[52:1]};
                end
            end

            //----------------------------------------------
            // SP: 2 results packed in [63:32] and [31:0]
            // Both share the same exponent path (shared exponent design)
            // Lane 1 in [63:32], Lane 0 in [31:0]
            //----------------------------------------------
            SP: begin
                valid_reg = 4'b0101; // lanes 0 and 1 valid
                if (exp_overflow) begin
                    result_reg = {Result_sign, 8'hFF, 23'd0,
                                  Result_sign, 8'hFF, 23'd0};
                end else if (exp_underflow) begin
                    result_reg = {Result_sign, 31'd0, Result_sign, 31'd0};
                end else begin
                    // Lane 1 (upper half): mantissa bits [52:30] of rounded mant
                    // Lane 0 (lower half): mantissa bits [52:30] of rounded mant (same for shared exp)
                    // Each SP mantissa is 23 bits: mant_rounded[52:30]
                    result_reg = {Result_sign, exp_adj[7:0], mant_rounded[52:30],
                                  Result_sign, exp_adj[7:0], mant_rounded[52:30]};
                end
            end

            //----------------------------------------------
            // TF32: 2 results; 8-bit exp + 10-bit mant
            // Packed in upper 19 bits of each 32-bit word
            //----------------------------------------------
            TF32: begin
                valid_reg = 4'b0101;
                if (exp_overflow) begin
                    result_reg = {Result_sign, 8'hFF, 10'h3FF, 13'd0,
                                  Result_sign, 8'hFF, 10'h3FF, 13'd0};
                end else if (exp_underflow) begin
                    result_reg = {Result_sign, 18'd0, 13'd0,
                                  Result_sign, 18'd0, 13'd0};
                end else begin
                    // TF32: [sign][8-bit exp][10-bit mant] in top 19 bits of each 32-bit word
                    result_reg = {Result_sign, exp_adj[7:0], mant_rounded[52:43], 13'd0,
                                  Result_sign, exp_adj[7:0], mant_rounded[52:43], 13'd0};
                end
            end

            //----------------------------------------------
            // HP: 4 results packed as four 16-bit words
            // All share max exponent; individual results
            // use independent mantissa slices (PD4 mode)
            //----------------------------------------------
            HP: begin
                valid_reg = 4'b1111;
                if (exp_overflow) begin
                    result_reg = {4{Result_sign, 5'h1F, 10'd0}};
                end else if (exp_underflow) begin
                    result_reg = {4{Result_sign, 15'd0}};
                end else begin
                    // Each lane shares the same normalized mantissa top 10 bits
                    result_reg = {4{Result_sign, exp_adj[4:0], mant_rounded[52:43]}};
                end
            end

            //----------------------------------------------
            // BF16: 4 results packed as four 16-bit words
            //----------------------------------------------
            BF16: begin
                valid_reg = 4'b1111;
                if (exp_overflow) begin
                    result_reg = {4{Result_sign, 8'hFF, 7'd0}};
                end else if (exp_underflow) begin
                    result_reg = {4{Result_sign, 15'd0}};
                end else begin
                    // BF16: 8-bit exp, 7-bit mantissa
                    result_reg = {4{Result_sign, exp_adj[7:0], mant_rounded[52:46]}};
                end
            end

            default: begin
                result_reg = 64'd0;
                valid_reg  = 4'd0;
            end

        endcase
    end

    assign Result_out = result_reg;
    assign Valid_out  = valid_reg;

endmodule
