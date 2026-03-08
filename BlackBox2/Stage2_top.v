module Stage2_Top (

    input clk,
    input rst_n,

    //------------------------------------------------
    // Inputs directly from Stage 1 modules
    //------------------------------------------------

    input  [111:0] partial_products_s1,
    input  [31:0]  ExpDiff_s1,
    input  [31:0]  MaxExp_s1,
    input  [63:0]  ProdASC_s1,

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
    output [162:0] Aligned_C_high_s2,

    output [3:0]   Sign_AB_s2,

    output [2:0]   Prec_s2,
    output [3:0]   Valid_s2,

    output         PD_mode_s2

);

    //------------------------------------------------
    // Direct wire assignments (Stage1_Module already has pipeline register)
    //------------------------------------------------

    wire [111:0] partial_products = partial_products_s1;
    wire [31:0]  ExpDiff          = ExpDiff_s1;
    wire [31:0]  MaxExp           = MaxExp_s1;
    wire [63:0]  ProdASC          = ProdASC_s1;

    wire [162:0] Aligned_C        = Aligned_C_s1;

    wire [3:0]   Sign_AB          = Sign_AB_s1;

    wire [2:0]   Prec             = Prec_s1;
    wire [3:0]   Valid            = Valid_s1;

    wire         PD_mode          = PD_mode_s1;
    wire         PD2_mode         = PD2_mode_s1;
    wire         PD4_mode         = PD4_mode_s1;

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

        .ProdASC(ProdASC),
        .PD_mode(PD_mode),
        .PD2_mode(PD2_mode),
        .PD4_mode(PD4_mode),

        .aligned_p0(aligned_p0),
        .aligned_p1(aligned_p1),
        .aligned_p2(aligned_p2),
        .aligned_p3(aligned_p3)

    );

    //------------------------------------------------
    // Apply signs to aligned products (two's complement inversion)
    //------------------------------------------------

    wire [162:0] signed_p0 = Sign_AB[0] ? (~aligned_p0 + 163'd1) : aligned_p0;
    wire [162:0] signed_p1 = Sign_AB[1] ? (~aligned_p1 + 163'd1) : aligned_p1;
    wire [162:0] signed_p2 = Sign_AB[2] ? (~aligned_p2 + 163'd1) : aligned_p2;
    wire [162:0] signed_p3 = Sign_AB[3] ? (~aligned_p3 + 163'd1) : aligned_p3;

    //------------------------------------------------
    // First CSA (4-to-2)
    //------------------------------------------------

    CSA_4to2 u_csa (

        .in0(signed_p0),
        .in1(signed_p1),
        .in2(signed_p2),
        .in3(signed_p3),

        .sum(Sum_s2),
        .carry(Carry_s2)

    );

    //------------------------------------------------
    // Forward C operand
    //------------------------------------------------

    assign Aligned_C_dual_s2 = Aligned_C;
    assign Aligned_C_high_s2 = Aligned_C;

    //------------------------------------------------
    // Forward control signals to Stage 3
    //------------------------------------------------

    assign Sign_AB_s2 = Sign_AB;
    assign Prec_s2    = Prec;
    assign Valid_s2   = Valid;
    assign PD_mode_s2 = PD_mode;

endmodule