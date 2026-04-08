module Stage2_Top (
    input clk,
    input rst_n,

    //------------------------------------------------
    // Inputs directly from Stage 1 modules
    //------------------------------------------------
    input  [111:0] partial_products_sum_s1,
    input  [111:0] partial_products_carry_s1,
    input  [31:0]  ExpDiff_s1,
    input  [31:0]  MaxExp_s1,
    input  [63:0]  ProdASC_s1,

    input  [162:0] Aligned_C_s1,

    input  [3:0]   Sign_AB_s1,
    input  [3:0]   Sign_C_s1,
    input  [1:0]   Sticky_C_s1,   // Sticky bits for IEEE rounding in Stage 3

    input  [2:0]   Prec_s1,
    input  [3:0]   Valid_s1,

    input          PD_mode_s1,
    input          PD2_mode_s1,
    input          PD4_mode_s1,

    //------------------------------------------------
    // Outputs after Stage 2 (To Stage 3)
    //------------------------------------------------
    output [162:0] Sum_s2,
    output [162:0] Carry_s2,
    output [162:0] Aligned_C_s2,

    output [3:0]   Sign_AB_s2,    // Forwarded
    output [3:0]   Sign_C_s2,     // Forwarded
    output [1:0]   Sticky_C_s2,   // Forwarded

    output [2:0]   Prec_s2,
    output [3:0]   Valid_s2,
    output         PD_mode_s2
);

    //------------------------------------------------
    // Direct wire assignments
    //------------------------------------------------
    wire [111:0] partial_products_sum   = partial_products_sum_s1;
    wire [111:0] partial_products_carry = partial_products_carry_s1;
    wire [63:0]  ProdASC          = ProdASC_s1;

    wire         PD_mode          = PD_mode_s1;
    wire         PD2_mode         = PD2_mode_s1;
    wire         PD4_mode         = PD4_mode_s1;

    //------------------------------------------------
    // 1. Stage 2 Pre-Adder (Sum + Carry -> Magnitude)
    //------------------------------------------------
    wire [111:0] unaligned_products;

    Stage2PreAdderCPA u_stage2_preadder (
        .partial_products_sum(partial_products_sum),
        .partial_products_carry(partial_products_carry),
        .sum(unaligned_products)
    );

    //------------------------------------------------
    // 2. Product Alignment Shifter
    //------------------------------------------------
    wire [107:0] unified_product_108;

    Products_Alignment_Shifter u_prod_align (
        .unaligned_112(unaligned_products), // FIX: Corrected wire name
        .ProdASC(ProdASC),                  // FIX: Added missing shift counts
        .Sign_AB(Sign_AB_s1),
        .PD_mode(PD_mode),
        .PD2_mode(PD2_mode),
        .PD4_mode(PD4_mode),
        .Prec(Prec_s1),
        .unified_product_108(unified_product_108)
    );

    //------------------------------------------------
    // 3. Stage2 Adder (4-to-2 / 3-to-2 CSA)
    //------------------------------------------------
    wire [58:0] stage2_added_sum;
    wire [58:0] stage2_added_carry;

    Stage2_Adder u_stage2_adder (
        .unified_product_108(unified_product_108),
        .PD2_mode(PD2_mode),
        .PD4_mode(PD4_mode),
        .sum(stage2_added_sum),
        .carry(stage2_added_carry)
    );

    //------------------------------------------------
    // 4. Output MUX (Figure 11: Path 0 vs Path 1)
    //------------------------------------------------
    // In DP mode (Path 0), the adder is bypassed.
    // In DPDAC modes (Path 1), the 59-bit CSA results are used.
    // Zero-padded to 163 bits to fit the Stage 3 unified CPA interface.

    assign Sum_s2   = PD_mode  ? {unified_product_108[106:0], 56'd0} :
                      PD2_mode ? {unified_product_108[107:0], 55'd0} : // SP (Align MSB to 162)
                      PD4_mode ? {unified_product_108[107:0], 55'd0} : // HP (Align MSB to 162)
                      {stage2_added_sum, 104'd0}; 
    assign Carry_s2 = 163'd0; 


    //------------------------------------------------
    // 5. Forwarding control signals to Stage 3
    //------------------------------------------------
    assign Aligned_C_s2 = Aligned_C_s1;
    assign Sticky_C_s2  = Sticky_C_s1;  // FIX: Forwarded
    assign Sign_AB_s2   = Sign_AB_s1;   // FIX: Forwarded
    assign Sign_C_s2    = Sign_C_s1;    // FIX: Forwarded

    assign Prec_s2      = Prec_s1;
    assign Valid_s2     = Valid_s1;
    assign PD_mode_s2   = PD_mode;

endmodule
