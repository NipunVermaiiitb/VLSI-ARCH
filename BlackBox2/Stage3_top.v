module Stage3_Top (

    input clk,
    input rst_n,

    //------------------------------------------------
    // Inputs from Stage 2
    //------------------------------------------------

    input [162:0] Sum_s2,
    input [162:0] Carry_s2,

    input [162:0] Aligned_C_dual_s2,
    input [162:0] Aligned_C_high_s2,

    input [3:0]   Sign_AB_s2,

    input [2:0]   Prec_s2,
    input [3:0]   Valid_s2,

    input         PD_mode_s2,

    //------------------------------------------------
    // Outputs to Stage 4
    //------------------------------------------------

    output [162:0] Add_Rslt_s3,
    output [7:0]   LZA_CNT_s3,
    output         Result_sign_s3

);

    //------------------------------------------------
    // Stage 2 pipeline register wires
    //------------------------------------------------

    wire [162:0] Sum;
    wire [162:0] Carry;

    wire [162:0] Aligned_C_dual;
    wire [162:0] Aligned_C_high;

    wire [3:0]   Sign_AB;

    wire [2:0]   Prec;
    wire [3:0]   Valid;

    wire         PD_mode;

    //------------------------------------------------
    // Instantiate Stage2 register
    //------------------------------------------------

    Stage2_Pipeline_Register u_stage2_reg (

        .clk(clk),
        .rst_n(rst_n),

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
    // Second CSA stage
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
    // Final carry propagate adder
    //------------------------------------------------

    wire [162:0] Add_Rslt;

    Final_Adder u_final_adder (

        .A(Sum2),
        .B(Carry2),

        .SUM(Add_Rslt)

    );

    //------------------------------------------------
    // Leading Zero Anticipation Counter
    //------------------------------------------------

    LZAC u_lzac (

        .Sum(Sum2),
        .Carry(Carry2),

        .LZA_CNT(LZA_CNT_s3)

    );

    //------------------------------------------------
    // Sign Generator
    //------------------------------------------------

    Sign_Generator u_sign_gen (

        .Sign_AB(Sign_AB),
        .Valid(Valid),
        .PD_mode(PD_mode),

        .Result_sign(Result_sign_s3)

    );

    //------------------------------------------------
    // Complementer
    //------------------------------------------------

    wire [162:0] Complemented_Rslt;

    Complementer u_complementer (

        .In(Add_Rslt),
        .Negate(Result_sign_s3),
        .Out(Complemented_Rslt)

    );

    //------------------------------------------------
    // INC+1 block
    //------------------------------------------------

    INC_Plus1 u_inc (

        .In(Complemented_Rslt),
        .Enable(Result_sign_s3),
        .Out(Add_Rslt_s3)

    );

endmodule