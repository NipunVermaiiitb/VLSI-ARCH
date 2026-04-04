`timescale 1ns / 1ps

// Stage 4 Top — Normalization, Rounding, Output Formatting
//
// This is the final pipeline stage of the DPDAC architecture (paper §III-D).
// It receives the 163-bit unsigned magnitude result from Stage 3 and produces
// the IEEE 754-packed output word(s).
//
// Data flow:
//   Add_Rslt_s3  (163-bit magnitude)
//       ↓
//   Normalization_Shifter  (left-shift by LZA_CNT → Norm_mant, G, R, S)
//       ↓
//   Output_Formatter  (adjusts exp, calls Rounder, packs IEEE 754 word)
//       ↓
//   Stage4_Pipeline_Register  (output register)
//       ↓
//   Result_out (64-bit), Valid_out (4-bit)
//
// The MaxExp value (from exponent_comparison Stage 1) must be pipelined
// through Stages 1-3 and provided here so the formatter can reconstruct
// the biased output exponent.

module Stage4_Top (

    input clk,
    input rst_n,

    //----------------------------------------------------
    // Inputs from Stage 3 pipeline register
    //----------------------------------------------------

    input  [162:0] Add_Rslt_s3,      // Unsigned magnitude
    input  [7:0]   LZA_CNT_s3,       // LZA shift count
    input          Result_sign_s3,   // Sign of result

    // MaxExp pipelined from Stage 1 (biased):
    // [31:16] = biased max C exponent, [15:0] = biased max product exponent
    input  [31:0]  MaxExp_s3,

    input  [2:0]   Prec_s3,
    input  [3:0]   Valid_s3,

    //----------------------------------------------------
    // Registered outputs
    //----------------------------------------------------

    output [63:0]  Result_out,
    output [3:0]   Valid_out,
    output         Result_sign_out

);

    //----------------------------------------------------
    // Normalization Shifter
    //----------------------------------------------------

    wire [162:0] Norm_mant;
    wire         G, R, S;
    wire         overflow_flag;

    Normalization_Shifter u_norm_shift (
        .Add_Rslt     (Add_Rslt_s3),
        .LZA_CNT      (LZA_CNT_s3),
        .Prec         (Prec_s3),
        .Norm_mant    (Norm_mant),
        .G            (G),
        .R            (R),
        .S            (S),
        .overflow_flag(overflow_flag)
    );

    //----------------------------------------------------
    // Output Formatter (includes Rounder instance)
    //----------------------------------------------------

    wire [63:0] Result_comb;
    wire [3:0]  Valid_comb;

    Output_Formatter u_out_fmt (

        .Norm_mant    (Norm_mant),
        .G            (G),
        .R            (R),
        .S            (S),
        .Result_sign  (Result_sign_s3),
        .overflow_flag(overflow_flag),
        .LZA_CNT      (LZA_CNT_s3),
        .MaxExp       (MaxExp_s3),
        .Prec         (Prec_s3),

        .Result_out   (Result_comb),
        .Valid_out    (Valid_comb)

    );

    //----------------------------------------------------
    // Pipeline Output Register
    //----------------------------------------------------

    Stage4_Pipeline_Register u_s4_reg (

        .clk            (clk),
        .rst_n          (rst_n),

        .Result_in      (Result_comb),
        .Valid_in       (Valid_comb),
        .Result_sign_in (Result_sign_s3),

        .Result_out     (Result_out),
        .Valid_out      (Valid_out),
        .Result_sign_out(Result_sign_out)

    );

endmodule
