`timescale 1ns / 1ps

// ============================================================
// DPDAC_top — Dot-Product-Dual-Accumulate Top-Level Integration
//
// 4-stage pipeline:
//   S1: Input formatting, Multiplier array, Exponent comparison,
//       Addend alignment, Sign logic                    [Stage1_Module]
//   S2: Product unpacking, Product alignment shift,
//       Sign application, 4:2 CSA (products only)       [Stage2_Top]
//   S3: 4:2 CSA (products+addends), LZAC, CPA,
//       Sign determination, Complement/INC              [Stage3_Top]
//   S4: Normalization shift, Rounding, Output packing   [Stage4_Top]
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
    wire [1:0]   Sticky_C_s1;
    wire [3:0]   Sign_AB_s1;
    wire [3:0]   Sign_C_s1;

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
        .Sticky_C              (Sticky_C_s1),   // FIXED: Added Sticky
        .Sign_AB               (Sign_AB_s1),
        .Sign_C                (Sign_C_s1),

        .Para_reg              (Para_s1),
        .Cvt_reg               (Cvt_s1),
        .valid_out             (valid_s1),

        .PD_mode               (PD_mode_s1),
        .PD2_mode              (PD2_mode_s1),
        .PD4_mode              (PD4_mode_s1)
    );

    wire [111:0] partial_products_sum_s1   = pp_sum_s1;
    wire [111:0] partial_products_carry_s1 = pp_carry_s1;
    wire [2:0]   Prec_s1_wire  = Prec;
    wire [3:0]   Valid_s1_wire = (Prec == 3'b010) ? 4'b0101 : 4'b1111;

    // --------------- Sideband Pipeline S1 -> S2 ---------------
    // Gated by valid_s1 for DP mode multi-cycle handling
    reg [31:0] MaxExp_s2_reg;
    reg        Cvt_s2_reg;
    reg [2:0]  Prec_s2_pipe;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            MaxExp_s2_reg <= 32'd0;
            Cvt_s2_reg    <= 1'b0;
            Prec_s2_pipe  <= 3'd0;
        end else if (valid_s1) begin
            MaxExp_s2_reg <= MaxExp_s1;
            Cvt_s2_reg    <= Cvt_s1;
            Prec_s2_pipe  <= Prec_s1_wire;
        end
    end

    // =========================================================
    // STAGE 2: Product alignment + MUXing
    // =========================================================

    wire [162:0] Sum_s2, Carry_s2, Aligned_C_s2;
    wire [3:0]   Sign_AB_s2, Sign_C_s2;
    wire [1:0]   Sticky_C_s2;
    wire [2:0]   Prec_s2;
    wire [3:0]   Valid_s2;
    wire         PD_mode_s2;

    Stage2_Top u_stage2 (
        .clk                      (clk),
        .rst_n                    (rst_n),
        .partial_products_sum_s1  (partial_products_sum_s1),
        .partial_products_carry_s1(partial_products_carry_s1),
        .ExpDiff_s1               (ExpDiff_s1),
        .MaxExp_s1                (MaxExp_s1),
        .ProdASC_s1               (ProdASC_s1),
        .Aligned_C_s1             (Aligned_C_s1),

        .Sign_AB_s1               (Sign_AB_s1),
        .Sign_C_s1                (Sign_C_s1),
        .Sticky_C_s1              (Sticky_C_s1), // FIXED

        .Prec_s1                  (Prec_s1_wire),
        .Valid_s1                 (Valid_s1_wire),

        .PD_mode_s1               (PD_mode_s1),
        .PD2_mode_s1              (PD2_mode_s1),
        .PD4_mode_s1              (PD4_mode_s1),

        .Sum_s2                   (Sum_s2),
        .Carry_s2                 (Carry_s2),
        .Aligned_C_s2             (Aligned_C_s2), // FIXED: Unified

        .Sign_AB_s2               (Sign_AB_s2),
        .Sign_C_s2                (Sign_C_s2),    // FIXED
        .Sticky_C_s2              (Sticky_C_s2),  // FIXED

        .Prec_s2                  (Prec_s2),
        .Valid_s2                 (Valid_s2),
        .PD_mode_s2               (PD_mode_s2)
    );

    // --------------- Sideband Pipeline S2 -> S3 -> S4 ---------------
    reg [31:0] MaxExp_s3_reg, MaxExp_s4_reg;
    reg        Cvt_s3_reg, Cvt_s4_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            MaxExp_s3_reg <= 32'd0; Cvt_s3_reg <= 1'b0;
            MaxExp_s4_reg <= 32'd0; Cvt_s4_reg <= 1'b0;
        end else begin
            MaxExp_s3_reg <= MaxExp_s2_reg;
            Cvt_s3_reg    <= Cvt_s2_reg;

            MaxExp_s4_reg <= MaxExp_s3_reg;
            Cvt_s4_reg    <= Cvt_s3_reg;
        end
    end

    // =========================================================
    // STAGE 3: CSA merge, LZAC, CPA, Sign/Complement
    // =========================================================

    wire [162:0] Add_Rslt_s3;
    wire [15:0]  LZA_CNT_s3;
    wire [3:0]   Result_sign_s3;
    wire [2:0]   Prec_s3;
    wire [3:0]   Valid_s3;

    Stage3_Top u_stage3 (
        .clk                (clk),
        .rst_n              (rst_n),

        .Sum_s2             (Sum_s2),
        .Carry_s2           (Carry_s2),
        .Aligned_C_s2       (Aligned_C_s2), // FIXED: Unified

        .Sign_AB_s2         (Sign_AB_s2),
        .Sign_C_s2          (Sign_C_s2),    // FIXED
        .Sticky_C_s2        (Sticky_C_s2),  // FIXED

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

    // =========================================================
    // STAGE 4: Normalization, Rounding, Output Formatter
    // =========================================================

    Stage4_Top u_stage4 (
        .clk            (clk),
        .rst_n          (rst_n),

        .Add_Rslt_s3    (Add_Rslt_s3),
        .LZA_CNT_s3     (LZA_CNT_s3),
        .Result_sign_s3 (Result_sign_s3),

        .MaxExp_s3      (MaxExp_s3_reg),
        .Prec_s3        (Prec_s3),
        .Valid_s3       (Valid_s3),
        .Cvt_s3         (Cvt_s3_reg), // FIXED: Aligned with data pipeline depth

        .Result_out     (Result_out),
        .Valid_out      (Valid_out),
        .Result_sign_out(Result_sign_out)
    );

endmodule
