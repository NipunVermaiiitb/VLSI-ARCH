// Helper 4:2 CSA module
module csa4_2 #(parameter W = 32) (
    input  [W-1:0] x,
    input  [W-1:0] y,
    input  [W-1:0] z,
    input  [W-1:0] w,
    output [W-1:0] sum,
    output [W-1:0] carry
);
    wire [W-1:0] s1;
    wire [W-1:0] c1;
    wire [W-1:0] c1_shift;
    wire [W-1:0] c2;

    assign s1       = x ^ y ^ z;
    assign c1       = (x & y) | (x & z) | (y & z);
    assign c1_shift = {c1[W-2:0], 1'b0};

    assign sum   = s1 ^ w ^ c1_shift;
    assign c2    = (s1 & w) | (s1 & c1_shift) | (w & c1_shift);
    assign carry = {c2[W-2:0], 1'b0};
endmodule

//----------------------------------------------------------
// multiplier_array_block: 4x14x14 with 56-bit positioning
//----------------------------------------------------------
module multiplier_array_block (
    input  [27:0] A_in,
    input  [27:0] B_in,
    input  [3:0]  Valid,
    output [55:0] PP0,  // A0×B0 positioned at [27:0]
    output [55:0] PP1,  // A0×B1 positioned at [41:14]
    output [55:0] PP2,  // A1×B0 positioned at [41:14]
    output [55:0] PP3   // A1×B1 positioned at [55:28]
);

    wire [13:0] A0 = A_in[13:0];
    wire [13:0] A1 = A_in[27:14];
    wire [13:0] B0 = B_in[13:0];
    wire [13:0] B1 = B_in[27:14];

    wire [27:0] prod0, prod1, prod2, prod3;
    mult14_radix4_booth m0 (.a(A0), .b(B0), .p(prod0));
    mult14_radix4_booth m1 (.a(A0), .b(B1), .p(prod1));
    mult14_radix4_booth m2 (.a(A1), .b(B0), .p(prod2));
    mult14_radix4_booth m3 (.a(A1), .b(B1), .p(prod3));

    assign PP0 = {28'd0, prod0[27:0]};
    assign PP1 = {14'd0, prod1[27:0], 14'd0};
    assign PP2 = {14'd0, prod2[27:0], 14'd0};
    assign PP3 = {prod3[27:0], 28'd0};

endmodule

//----------------------------------------------------------
// low_cost_multiplier_array: orchestrates two blocks
//
// DP mode (Eq. 8 from paper):
//   {a1,a0} × {b1,b0} = a0×b0 + (a0×b1 + a1×b0)<<28 + a1×b1<<56
//   Cycle 0 (cnt=0): Block0 = A0×B0, Block1 = A1×B1
//   Cycle 1 (cnt=1): Block0 = A0×B1, Block1 = A1×B0 (cross-products!)
//
// SIMD modes:
//   PD2: Block0 = A0×B0 (lower lane), Block1 = A1×B1 (upper lane)
//   PD4: 4 independent 14×14 products across both blocks
//----------------------------------------------------------
module low_cost_multiplier_array (

    input         clk,
    input         rst_n,

    input  [55:0] A_mantissa,
    input  [55:0] B_mantissa,

    input  [2:0]  Prec,
    input  [3:0]  Valid,

    input         PD_mode,
    input         PD2_mode,
    input         PD4_mode,
    input         Cnt0,

    output [111:0] partial_sum,
    output [111:0] partial_carry

);

    localparam HP   = 3'b000;
    localparam BF16 = 3'b001;
    localparam TF32 = 3'b010;
    localparam SP   = 3'b011;
    localparam DP   = 3'b100;

    wire dp_c0 = PD_mode & ~Cnt0;
    wire dp_c1 = PD_mode &  Cnt0;

    //----------------------------------------------------------
    // Split mantissas into 28-bit halves
    //----------------------------------------------------------
    wire [27:0] A0 = A_mantissa[27:0];
    wire [27:0] A1 = A_mantissa[55:28];
    wire [27:0] B0 = B_mantissa[27:0];
    wire [27:0] B1 = B_mantissa[55:28];

    //----------------------------------------------------------
    // Input MUX for DP cross-products
    // Cycle 0: Block0 = A0×B0, Block1 = A1×B1
    // Cycle 1: Block0 = A0×B1, Block1 = A1×B0
    //----------------------------------------------------------
    wire [27:0] blk0_a = A0;
    wire [27:0] blk0_b = dp_c1 ? B1 : B0;  // Swap B for cross-product
    wire [27:0] blk1_a = A1;
    wire [27:0] blk1_b = dp_c1 ? B0 : B1;  // Swap B for cross-product

    //----------------------------------------------------------
    // Multiplier Array Block 0
    //----------------------------------------------------------
    wire [55:0] pp0_blk0, pp1_blk0, pp2_blk0, pp3_blk0;
    multiplier_array_block u_block0 (
        .A_in(blk0_a),
        .B_in(blk0_b),
        .Valid({Valid[1], Valid[0], Valid[1], Valid[0]}),
        .PP0(pp0_blk0),
        .PP1(pp1_blk0),
        .PP2(pp2_blk0),
        .PP3(pp3_blk0)
    );

    //----------------------------------------------------------
    // Multiplier Array Block 1
    //----------------------------------------------------------
    wire [55:0] pp0_blk1, pp1_blk1, pp2_blk1, pp3_blk1;
    multiplier_array_block u_block1 (
        .A_in(blk1_a),
        .B_in(blk1_b),
        .Valid({Valid[3], Valid[2], Valid[3], Valid[2]}),
        .PP0(pp0_blk1),
        .PP1(pp1_blk1),
        .PP2(pp2_blk1),
        .PP3(pp3_blk1)
    );

    //----------------------------------------------------------
    // Combine each block's 4 PPs into 56-bit compressed results
    //----------------------------------------------------------
    wire [55:0] blk0_sum, blk0_carry;
    csa4_2 #(.W(56)) u_csa_blk0 (
        .x(pp0_blk0), .y(pp1_blk0), .z(pp2_blk0), .w(pp3_blk0),
        .sum(blk0_sum), .carry(blk0_carry)
    );

    wire [55:0] blk1_sum, blk1_carry;
    csa4_2 #(.W(56)) u_csa_blk1 (
        .x(pp0_blk1), .y(pp1_blk1), .z(pp2_blk1), .w(pp3_blk1),
        .sum(blk1_sum), .carry(blk1_carry)
    );

    // Resolve each block to a single 56-bit value
    wire [55:0] blk0_product = blk0_sum + blk0_carry;
    wire [55:0] blk1_product = blk1_sum + blk1_carry;

    //----------------------------------------------------------
    // DP Mode: Two-cycle accumulation
    //----------------------------------------------------------
    // Cycle 0: A0×B0 -> blk0_product (56-bit), A1×B1 -> blk1_product (56-bit)
    //   Full product contribution: blk0 at [55:0], blk1 at [111:56]
    // Cycle 1: A0×B1 -> blk0_product (56-bit), A1×B0 -> blk1_product (56-bit)
    //   Cross-products go at [83:28] (shifted left by 28)
    //   cross_sum = (A0×B1 + A1×B0) placed at [83:28]

    // Cycle 0: Store direct products
    reg [55:0] dp_c0_lo;  // A0×B0
    reg [55:0] dp_c0_hi;  // A1×B1

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dp_c0_lo <= 56'd0;
            dp_c0_hi <= 56'd0;
        end else if (dp_c0) begin
            dp_c0_lo <= blk0_product; // A0×B0
            dp_c0_hi <= blk1_product; // A1×B1
        end
    end

    // Cycle 1: Combine all terms
    // Full DP product = A0×B0 + (A0×B1 + A1×B0)<<28 + A1×B1<<56
    // We build a 112-bit result:
    //   bits[55:0]   = A0×B0
    //   bits[111:56] = A1×B1
    //   bits[83:28]  += (A0×B1 + A1×B0) (cross-products from cycle 1)

    wire [55:0] cross_sum = blk0_product + blk1_product; // A0×B1 + A1×B0
    
    // Position the three components in a 112-bit field
    wire [111:0] dp_direct = {dp_c0_hi, dp_c0_lo}; // A1×B1 at [111:56], A0×B0 at [55:0]
    wire [111:0] dp_cross  = {28'd0, cross_sum, 28'd0}; // Cross at [83:28]

    // Final DP product in carry-save format (use CSA to avoid 112-bit CPA)
    wire [111:0] dp_final_sum, dp_final_carry;
    csa4_2 #(.W(112)) u_csa_dp_merge (
        .x(dp_direct),
        .y(dp_cross),
        .z(112'd0),
        .w(112'd0),
        .sum(dp_final_sum),
        .carry(dp_final_carry)
    );

    //----------------------------------------------------------
    // SIMD Mode: Single-cycle, two independent products
    //----------------------------------------------------------
    // PD2: {blk1_product, blk0_product} — two 56-bit products
    // PD4: Same structure but each block produces 2 independent 28-bit products
    wire [111:0] simd_sum   = {blk1_sum, blk0_sum};
    wire [111:0] simd_carry = {blk1_carry, blk0_carry};

    //----------------------------------------------------------
    // Output routing
    //----------------------------------------------------------
    // DP: Output only on cycle 1 (cnt=1), zero on cycle 0
    // SIMD: Output every cycle
    assign partial_sum   = PD_mode ? (Cnt0 ? dp_final_sum   : 112'd0) : simd_sum;
    assign partial_carry = PD_mode ? (Cnt0 ? dp_final_carry : 112'd0) : simd_carry;

endmodule
