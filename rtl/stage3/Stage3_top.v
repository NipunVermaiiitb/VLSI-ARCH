module Stage3_Top (

    input clk,
    input rst_n,

    //------------------------------------------------
    // Inputs from Stage 2 pipeline register
    //------------------------------------------------

    input [162:0] Sum_s2,
    input [162:0] Carry_s2,

    input [162:0] Aligned_C_dual_s2,
    input [162:0] Aligned_C_high_s2,

    input [3:0]   Sign_AB_s2,

    input [2:0]   Prec_s2,
    input [3:0]   Valid_s2,

    input         PD_mode_s2,
    input         valid_s1,     // Stage1 valid_out: gates Stage2_PipeReg for DP

    //------------------------------------------------
    // Outputs to Stage 4 (via Stage3 pipeline register)
    //------------------------------------------------

    output [162:0] Add_Rslt_s3,
    output [7:0]   LZA_CNT_s3,
    output         Result_sign_s3,

    // Forward precision/valid for Stage 4 output formatting
    output [2:0]   Prec_s3,
    output [3:0]   Valid_s3

);

    //------------------------------------------------
    // Stage 2 pipeline register
    //------------------------------------------------

    wire [162:0] Sum;
    wire [162:0] Carry;

    wire [162:0] Aligned_C_dual;
    wire [162:0] Aligned_C_high;

    wire [3:0]   Sign_AB;

    wire [2:0]   Prec;
    wire [3:0]   Valid;

    wire         PD_mode;

    Stage2_Pipeline_Register u_stage2_reg (

        .clk(clk),
        .rst_n(rst_n),
        .enable(valid_s1),

        .Sum_in(Sum_s2),
        .Carry_in(Carry_s2),

        .Aligned_C_dual_in(Aligned_C_dual_s2),
        .Aligned_C_high_in(Aligned_C_high_s2),

        .Sign_AB_in(Sign_AB_s2),

        .Prec_in(Prec_s2),
        .Valid_in(Valid_s2),

        .PD_mode_in(PD_mode_s2),

        .Sum_out(Sum),
        .Carry_out(Carry),

        .Aligned_C_dual_out(Aligned_C_dual),
        .Aligned_C_high_out(Aligned_C_high),

        .Sign_AB_out(Sign_AB),

        .Prec_out(Prec),
        .Valid_out(Valid),

        .PD_mode_out(PD_mode)

    );

    //------------------------------------------------
    // Second CSA stage: merge product sum/carry with
    // the two aligned addend paths (dual-C)
    //------------------------------------------------

    wire [162:0] Sum2;
    wire [162:0] Carry2;

    CSA_4to2 u_csa_stage3 (

        .in0(Sum),
        .in1(Carry),
        .in2(Aligned_C_dual),
        .in3(Aligned_C_high),

        .sum(Sum2),
        .carry(Carry2)

    );

    //------------------------------------------------
    // LZAC: runs in parallel with the CPA
    //------------------------------------------------

    wire [7:0] LZA_CNT_comb;

    LZAC u_lzac (

        .Sum(Sum2),
        .Carry(Carry2),

        .LZA_CNT(LZA_CNT_comb)

    );

    //------------------------------------------------
    // Final 163-bit carry-propagate adder (CPA)
    //------------------------------------------------

    wire [162:0] Add_Rslt_comb;

    Final_Adder u_final_adder (

        .A(Sum2),
        .B(Carry2),

        .SUM(Add_Rslt_comb)

    );

    //------------------------------------------------
    // Sign determination: MSB of the CPA result
    // (the combined dot-product sum is stored as
    //  unsigned magnitude with explicit sign tracking,
    //  so if result MSB is set the word overflowed into
    //  the sign region meaning the result is negative
    //  when PD_mode, or use lane 0 product sign otherwise)
    //------------------------------------------------

    wire result_negative = Add_Rslt_comb[162];

    wire Result_sign_comb;

    Sign_Generator u_sign_gen (

        .Sign_AB(Sign_AB),
        .Valid(Valid),
        .PD_mode(PD_mode),
        .CPA_neg(result_negative),
        .CPA_result(Add_Rslt_comb),

        .Result_sign(Result_sign_comb)

    );

    //------------------------------------------------
    // Complementer + INC+1: conditionally negate result
    // to get unsigned magnitude + separate sign
    //------------------------------------------------

    wire [162:0] Complemented_Rslt;

    Complementer u_complementer (

        .In(Add_Rslt_comb),
        .Negate(Result_sign_comb),
        .Out(Complemented_Rslt)

    );

    wire [162:0] Add_Rslt_mag;

    INC_Plus1 u_inc (

        .In(Complemented_Rslt),
        .Enable(Result_sign_comb),
        .Out(Add_Rslt_mag)

    );

    //------------------------------------------------
    // Stage 3 pipeline register → Stage 4
    //------------------------------------------------

    Stage3_Pipeline_Register u_stage3_reg (

        .clk(clk),
        .rst_n(rst_n),

        .Add_Rslt_in(Add_Rslt_mag),
        .Result_sign_in(Result_sign_comb),
        // LZA correction for negative results:
        // LZAC runs on two's complement form (MSB=1 → LZA=0).
        // After Complementer+INC the true leading bit is 1 position lower,
        // so we increment LZA_CNT by 1 when sign=1 to compensate.
        .LZA_CNT_in(Result_sign_comb ? (LZA_CNT_comb + 8'd1) : LZA_CNT_comb),

        .Prec_in(Prec),
        .Valid_in(Valid),

        .Add_Rslt_out(Add_Rslt_s3),
        .Result_sign_out(Result_sign_s3),
        .LZA_CNT_out(LZA_CNT_s3),

        .Prec_out(Prec_s3),
        .Valid_out(Valid_s3)

    );

endmodule