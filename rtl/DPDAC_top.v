`timescale 1ns / 1ps

// ============================================================
// DPDAC_top — Dot-Product-Dual-Accumulate Top-Level Integration
//
// Paper: "A Low-Cost Floating-Point Dot-Product-Dual-Accumulate
//         Architecture for HPC-Enabled AI", IEEE TCAD 2023.
//
// 4-stage pipeline:
//   S1: Input formatting, Multiplier array, Exponent comparison,
//       Addend alignment, Sign logic                    [Stage1_Module]
//   S2: Product unpacking, Product alignment shift,
//       Sign application, 4:2 CSA (products only)      [Stage2_Top]
//   S3: 4:2 CSA (products+addends), LZAC, CPA,
//       Sign determination, Complement/INC              [Stage3_Top]
//   S4: Normalization shift, Rounding, Output packing   [Stage4_Top]
//
// Precision modes (Prec[2:0]):
//   3'b000 = HP    (Half Precision,   4-lane)
//   3'b001 = BF16  (BFloat16,         4-lane)
//   3'b010 = TF32  (TensorFloat-32,   2-lane)
//   3'b011 = SP    (Single Precision, 2-lane)
//   3'b100 = DP    (Double Precision, 1-lane, 2-cycle multiply)
//
// Control signals:
//   Para = 1: in DP mode, C holds TWO SP addends (dual-accumulate in DP)
//   Cvt  = 1: conversion mode (precision down-cast, adjusts ASC by 1)
// ============================================================

module DPDAC_top (

    input              clk,
    input              rst_n,

    // Primary operand inputs (64-bit unified words)
    input  [63:0]      A_in,
    input  [63:0]      B_in,
    input  [63:0]      C_in,

    // Control
    input  [2:0]       Prec,
    input              Para,
    input              Cvt,

    // Outputs
    output [63:0]      Result_out,
    output [3:0]       Valid_out,
    output             Result_sign_out

);

    // =========================================================
    // STAGE 1: Input formatting + multiplier + exp compare
    // =========================================================

    wire [111:0] pp_sum_s1, pp_carry_s1;
    wire [31:0]  ExpDiff_s1, MaxExp_s1;
    wire [63:0]  ProdASC_s1;
    wire [162:0] Aligned_C_s1;
    wire [3:0]   Sign_AB_s1;
    wire         Para_s1, Cvt_s1, valid_s1;
    wire         PD_mode_s1, PD2_mode_s1, PD4_mode_s1;

    Stage1_Module u_stage1 (

        .clk                   (clk),
        .rst_n                 (rst_n),

        .A_in                  (A_in),
        .B_in                  (B_in),
        .C_in                  (C_in),

        .Prec                  (Prec),
        .Para                  (Para),
        .Cvt                   (Cvt),

        .partial_products_sum  (pp_sum_s1),
        .partial_products_carry(pp_carry_s1),

        .ExpDiff               (ExpDiff_s1),
        .MaxExp                (MaxExp_s1),
        .ProdASC               (ProdASC_s1),

        .Aligned_C             (Aligned_C_s1),
        .Sign_AB               (Sign_AB_s1),

        .Para_reg              (Para_s1),
        .Cvt_reg               (Cvt_s1),
        .valid_out             (valid_s1),

        .PD_mode               (PD_mode_s1),
        .PD2_mode              (PD2_mode_s1),
        .PD4_mode              (PD4_mode_s1)

    );

    // Combine carry-save partial products from Stage 1 into a single value.
    // Stage2_Adder expects a combined product (not carry-save form), so we
    // must do a binary addition here. For PD2/PD4 the lane products are packed
    // in the lower bits and adding sum+carry gives the correct per-lane products.
    wire [111:0] partial_products_s1 = pp_sum_s1 + pp_carry_s1;

    // Determine Prec and Valid for downstream stages from Stage1 internals
    // Stage1_Module re-registers Prec internally; we need to pass it forward.
    // For simplicity: re-decode from Prec (combinational — matches Stage1 internal state)
    wire [2:0]  Prec_s1_wire  = Prec;  // Prec is already stable when Stage1 output arrives
    wire [3:0]  Valid_s1_wire = (Prec == 3'b010) ? 4'b0101 : 4'b1111; // TF32 uses lanes 0,2

    // MaxExp must be pipelined to Stage 4 (3 more registers: S1→S2, S2→S3, S3→S4)
    // We pipeline it separately alongside the main data path.

    // --------------- MaxExp pipeline registers S1→S2 (gated by valid_s1) ---------------
    reg [31:0] MaxExp_s2_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) MaxExp_s2_reg <= 32'd0;
        else if (valid_s1) MaxExp_s2_reg <= MaxExp_s1;
    end

    // --------------- Prec pipeline register S1→S2 (gated by valid_s1) ---------------
    reg [2:0] Prec_s2_pipe;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) Prec_s2_pipe <= 3'd0;
        else if (valid_s1) Prec_s2_pipe <= Prec_s1_wire;
    end

    // =========================================================
    // STAGE 2: Product alignment + 4:2 CSA on products
    // =========================================================

    wire [162:0] Sum_s2, Carry_s2;
    wire [162:0] Aligned_C_dual_s2, Aligned_C_high_s2;
    wire [3:0]   Sign_AB_s2;
    wire [2:0]   Prec_s2;
    wire [3:0]   Valid_s2;
    wire         PD_mode_s2;

    Stage2_Top u_stage2 (

        .clk                (clk),
        .rst_n              (rst_n),

        .partial_products_s1(partial_products_s1),
        .ExpDiff_s1         (ExpDiff_s1),
        .MaxExp_s1          (MaxExp_s1),
        .ProdASC_s1         (ProdASC_s1),

        .Aligned_C_s1       (Aligned_C_s1),

        .Sign_AB_s1         (Sign_AB_s1),

        .Prec_s1            (Prec_s1_wire),
        .Valid_s1           (Valid_s1_wire),

        .PD_mode_s1         (PD_mode_s1),
        .PD2_mode_s1        (PD2_mode_s1),
        .PD4_mode_s1        (PD4_mode_s1),

        .Sum_s2             (Sum_s2),
        .Carry_s2           (Carry_s2),

        .Aligned_C_dual_s2  (Aligned_C_dual_s2),
        .Aligned_C_high_s2  (Aligned_C_high_s2),

        .Sign_AB_s2         (Sign_AB_s2),

        .Prec_s2            (Prec_s2),
        .Valid_s2           (Valid_s2),

        .PD_mode_s2         (PD_mode_s2)

    );

    // --------------- MaxExp pipeline register S2→S3 ---------------
    reg [31:0] MaxExp_s3_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) MaxExp_s3_reg <= 32'd0;
        else        MaxExp_s3_reg <= MaxExp_s2_reg;
    end

    // =========================================================
    // STAGE 3: CSA merge with addends, LZAC, CPA, sign/complement
    // =========================================================

    wire [162:0] Add_Rslt_s3;
    wire [7:0]   LZA_CNT_s3;
    wire         Result_sign_s3;
    wire [2:0]   Prec_s3;
    wire [3:0]   Valid_s3;

    Stage3_Top u_stage3 (

        .clk                (clk),
        .rst_n              (rst_n),

        .Sum_s2             (Sum_s2),
        .Carry_s2           (Carry_s2),

        .Aligned_C_dual_s2  (Aligned_C_dual_s2),
        .Aligned_C_high_s2  (Aligned_C_high_s2),

        .Sign_AB_s2         (Sign_AB_s2),

        .Prec_s2            (Prec_s2),
        .Valid_s2           (Valid_s2),

        .PD_mode_s2         (PD_mode_s2),
        .valid_s1           (valid_s1),

        .Add_Rslt_s3        (Add_Rslt_s3),
        .LZA_CNT_s3         (LZA_CNT_s3),
        .Result_sign_s3     (Result_sign_s3),

        .Prec_s3            (Prec_s3),
        .Valid_s3           (Valid_s3)

    );

    // --------------- MaxExp pipeline register S3→S4 ---------------
    reg [31:0] MaxExp_s4_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) MaxExp_s4_reg <= 32'd0;
        else        MaxExp_s4_reg <= MaxExp_s3_reg;
    end

    // =========================================================
    // STAGE 4: Normalization, Rounding, Output formatting
    // =========================================================

    Stage4_Top u_stage4 (

        .clk            (clk),
        .rst_n          (rst_n),

        .Add_Rslt_s3    (Add_Rslt_s3),
        .LZA_CNT_s3     (LZA_CNT_s3),
        .Result_sign_s3 (Result_sign_s3),

        .MaxExp_s3      (MaxExp_s4_reg),

        .Prec_s3        (Prec_s3),
        .Valid_s3       (Valid_s3),

        .Result_out     (Result_out),
        .Valid_out      (Valid_out),
        .Result_sign_out(Result_sign_out)

    );

endmodule
