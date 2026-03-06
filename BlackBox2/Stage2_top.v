module Stage2_Top (

    input clk,
    input rst_n,

    //------------------------------------------------
    // Inputs directly from Stage 1 modules
    //------------------------------------------------

    input  [111:0] partial_products_s1,
    input  [31:0]  ExpDiff_s1,
    input  [31:0]  MaxExp_s1,

    input  [162:0] Aligned_C_s1,

    input  [3:0]   Sign_AB_s1,

    input  [2:0]   Prec_s1,
    input  [3:0]   Valid_s1,

    input          PD_mode_s1,
    input          PD2_mode_s1,
    input          PD4_mode_s1,

    //------------------------------------------------
    // Outputs after Stage 2
    //------------------------------------------------

    output [162:0] Sum_s2,
    output [162:0] Carry_s2,

    output [162:0] Aligned_C_dual_s2,
    output [162:0] Aligned_C_high_s2

);

    //------------------------------------------------
    // Stage-1 pipeline register outputs
    //------------------------------------------------

    wire [111:0] partial_products;
    wire [31:0]  ExpDiff;
    wire [31:0]  MaxExp;

    wire [162:0] Aligned_C;

    wire [3:0]   Sign_AB;

    wire [2:0]   Prec;
    wire [3:0]   Valid;

    wire         PD_mode;
    wire         PD2_mode;
    wire         PD4_mode;

    //------------------------------------------------
    // Instantiate Stage-1 Pipeline Register
    //------------------------------------------------

    Stage1_Pipeline_Register u_stage1_reg (

        .clk(clk),
        .rst_n(rst_n),

        .partial_products_in(partial_products_s1),
        .ExpDiff_in(ExpDiff_s1),
        .MaxExp_in(MaxExp_s1),

        .Aligned_C_in(Aligned_C_s1),

        .Sign_AB_in(Sign_AB_s1),

        .Prec_in(Prec_s1),
        .Valid_in(Valid_s1),

        .PD_mode_in(PD_mode_s1),
        .PD2_mode_in(PD2_mode_s1),
        .PD4_mode_in(PD4_mode_s1),

        .partial_products_out(partial_products),
        .ExpDiff_out(ExpDiff),
        .MaxExp_out(MaxExp),

        .Aligned_C_out(Aligned_C),

        .Sign_AB_out(Sign_AB),

        .Prec_out(Prec),
        .Valid_out(Valid),

        .PD_mode_out(PD_mode),
        .PD2_mode_out(PD2_mode),
        .PD4_mode_out(PD4_mode)

    );

    //------------------------------------------------
    // Stage 2 internal wires
    //------------------------------------------------

    wire [106:0] product0;
    wire [106:0] product1;
    wire [106:0] product2;
    wire [106:0] product3;

    wire [162:0] aligned_p0;
    wire [162:0] aligned_p1;
    wire [162:0] aligned_p2;
    wire [162:0] aligned_p3;

    //------------------------------------------------
    // Stage2 Adder
    //------------------------------------------------

    Stage2_Adder u_stage1_adder (

        .partial_products(partial_products),

        .PD_mode(PD_mode),
        .PD2_mode(PD2_mode),
        .PD4_mode(PD4_mode),

        .product0(product0),
        .product1(product1),
        .product2(product2),
        .product3(product3)

    );

    //------------------------------------------------
    // Product Alignment Shifter
    //------------------------------------------------

    Products_Alignment_Shifter u_prod_align (

        .product0(product0),
        .product1(product1),
        .product2(product2),
        .product3(product3),

        .MaxExp(MaxExp),
        .ExpDiff(ExpDiff),

        .aligned_p0(aligned_p0),
        .aligned_p1(aligned_p1),
        .aligned_p2(aligned_p2),
        .aligned_p3(aligned_p3)

    );

    //------------------------------------------------
    // First CSA (4-to-2)
    //------------------------------------------------

    CSA_4to2 u_csa (

        .in0(aligned_p0),
        .in1(aligned_p1),
        .in2(aligned_p2),
        .in3(aligned_p3),

        .sum(Sum_s2),
        .carry(Carry_s2)

    );

    //------------------------------------------------
    // Forward C operand
    //------------------------------------------------

    assign Aligned_C_dual_s2 = Aligned_C;
    assign Aligned_C_high_s2 = Aligned_C;

endmodule