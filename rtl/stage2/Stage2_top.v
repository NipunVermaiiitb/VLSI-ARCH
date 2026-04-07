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

    // Two independent aligned C paths from addend_alignment_shifter
    input  [162:0] Aligned_C_hi_s1,   // sht_rc1
    input  [162:0] Aligned_C_lo_s1,   // sht_rc0
    input          Para_s1,            // Para flag (registered from Stage1)

    input  [3:0]   Sign_AB_s1,
    input  [3:0]   Sign_C_s1,

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
    // Direct wire assignments
    //------------------------------------------------

    wire [111:0] partial_products = partial_products_s1;
    wire [31:0]  ExpDiff          = ExpDiff_s1;
    wire [31:0]  MaxExp           = MaxExp_s1;
    wire [63:0]  ProdASC          = ProdASC_s1;

    // C routing:
    // DP FMA (PD_mode=1, Para=0): recombine hi/lo into a single 163-bit C on one input,
    //   zero the other input. The addend_alignment_shifter splits single C into a hi half
    //   (bits[162:81]) via sht_rc1 and a lo half (bits[80:0]) via sht_rc0.
    // DPDAC / Para=1 / PD2 / PD4: feed hi and lo independently as two addends.
    wire [162:0] Aligned_C_dual_raw = (Prec_s1 == 3'b100 && Para_s1 == 0) ? Aligned_C_lo_s1 : Aligned_C_lo_s1;
    wire [162:0] Aligned_C_high_raw = (Prec_s1 == 3'b100 && Para_s1 == 0) ? 163'd0 : Aligned_C_hi_s1;

    // Apply two's complement inversion for negative C addends
    wire [162:0] Aligned_C_dual = Sign_C_s1[0] ? (~Aligned_C_dual_raw + 163'd1) : Aligned_C_dual_raw;
    wire [162:0] Aligned_C_high = Sign_C_s1[1] ? (~Aligned_C_high_raw + 163'd1) : Aligned_C_high_raw;

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

    // reg [31:0] dbg_cnt2 = 0;
    // always @(posedge clk) begin
    //     if (Prec_s1 == 3'b100 && Valid_s1 == 4'b1111 && Para_s1 == 0) begin
    //         $display("[DEBUG S2 %d] cnt0=%b signed_p0[161:159]=%b, C_dual[161:159]=%b, C_hi_s1[161:159]=%b, C_lo_s1[161:159]=%b, asc_c1=%d asc_c0=%d",
    //                  dbg_cnt2, (Sum_s2[0] ^ Sum_s2[0]), signed_p0[161:159], Aligned_C_dual[161:159], Aligned_C_hi_s1[161:159], Aligned_C_lo_s1[161:159], ExpDiff_s1[31:16], ExpDiff_s1[15:0]);
    //     end
    //     dbg_cnt2 <= dbg_cnt2 + 1;
    // end

    //------------------------------------------------
    // Forward C operand paths to Stage 3 pipeline register
    //------------------------------------------------

    assign Aligned_C_dual_s2 = Aligned_C_dual;
    assign Aligned_C_high_s2 = Aligned_C_high;

    //------------------------------------------------
    // Forward control signals to Stage 3
    //------------------------------------------------

    assign Sign_AB_s2 = Sign_AB;
    assign Prec_s2    = Prec;
    assign Valid_s2   = Valid;
    assign PD_mode_s2 = PD_mode;

endmodule