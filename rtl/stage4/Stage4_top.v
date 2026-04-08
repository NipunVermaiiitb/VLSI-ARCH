`timescale 1ns / 1ps

module Stage4_Top (
    input clk,
    input rst_n,

    // Inputs from Stage 3 pipeline register
    input  [162:0] Add_Rslt_s3,
    input  [15:0]  LZA_CNT_s3,
    input  [3:0]   Result_sign_s3,
    input  [31:0]  MaxExp_s3,
    input  [2:0]   Prec_s3,
    input  [3:0]   Valid_s3,
    input          Cvt_s3,         // ADDED: Needed for NPCv mapping

    // Registered outputs
    output [63:0]  Result_out,
    output [3:0]   Valid_out,
    output         Result_sign_out
);

    //----------------------------------------------------
    // Normalization Shifter
    //----------------------------------------------------
    wire [162:0] Norm_mant;
    wire         G, R, S;
    wire [1:0]   lza_error;

    Normalization_Shifter u_norm_shift (
        .Add_Rslt     (Add_Rslt_s3),
        .LZA_CNT      (LZA_CNT_s3),
        .Prec         (Prec_s3),
        .Norm_mant    (Norm_mant),
        .G            (G),
        .R            (R),
        .S            (S),
        .lza_error    (lza_error)      // NEW
    );

    //----------------------------------------------------
    // Output Formatter & Exponent Logic
    //----------------------------------------------------
    wire [63:0] Result_comb;
    wire [3:0]  Valid_comb;

    Output_Formatter u_out_fmt (
        .Norm_mant    (Norm_mant),
        .G            (G),
        .R            (R),
        .S            (S),
        .Result_sign  (Result_sign_s3),
        .lza_error    (lza_error),      // NEW
        .LZA_CNT      (LZA_CNT_s3),
        .MaxExp       (MaxExp_s3),
        .Prec         (Prec_s3),
        .Cvt          (Cvt_s3),         // NEW
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
        .Result_sign_in (Result_sign_s3[0]), // Final scalar sign (usually Lane 0 or for DP)

        .Result_out     (Result_out),
        .Valid_out      (Valid_out),
        .Result_sign_out(Result_sign_out)
    );

endmodule
