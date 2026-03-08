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
// Outputs 4 separate 56-bit partial products positioned correctly
// for 28x28 decomposition
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

    // Four 14x14 multipliers produce 28-bit results
    wire [27:0] prod0, prod1, prod2, prod3;

    mult14_radix4_booth m0 (.a(A0), .b(B0), .p(prod0));  // A0×B0
    mult14_radix4_booth m1 (.a(A0), .b(B1), .p(prod1));  // A0×B1
    mult14_radix4_booth m2 (.a(A1), .b(B0), .p(prod2));  // A1×B0
    mult14_radix4_booth m3 (.a(A1), .b(B1), .p(prod3));  // A1×B1

    // Position each product in its correct 56-bit range for 28×28
    // PP0: A0×B0 at [27:0]
    assign PP0 = {28'd0, prod0[27:0]};

    // PP1: A0×B1 at [41:14]
    assign PP1 = {14'd0, prod1[27:0], 14'd0};

    // PP2: A1×B0 at [41:14]
    assign PP2 = {14'd0, prod2[27:0], 14'd0};

    // PP3: A1×B1 at [55:28]
    assign PP3 = {prod3[27:0], 28'd0};

endmodule

//----------------------------------------------------------
// low_cost_multiplier_array: orchestrates two blocks
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

    //----------------------------------------------------------
    // Precision and mode control
    //----------------------------------------------------------
    localparam HP   = 3'b000;
    localparam BF16 = 3'b001;
    localparam TF32 = 3'b010;
    localparam SP   = 3'b011;
    localparam DP   = 3'b100;

    wire en3 = Valid[3];
    wire en2 = Valid[2];
    wire en1 = Valid[1];
    wire en0 = Valid[0];

    wire dp_c0 = PD_mode & ~Cnt0;
    wire dp_c1 = PD_mode &  Cnt0;

    //----------------------------------------------------------
    // Split mantissas for the two multiplier array blocks
    //----------------------------------------------------------
    // A0 = A_mantissa[27:0], A1 = A_mantissa[55:28]
    // B0 = B_mantissa[27:0], B1 = B_mantissa[55:28]
    wire [27:0] A0 = A_mantissa[27:0];
    wire [27:0] A1 = A_mantissa[55:28];
    wire [27:0] B0 = B_mantissa[27:0];
    wire [27:0] B1 = B_mantissa[55:28];

    //----------------------------------------------------------
    // Multiplier Array Block 0 (lower 28 bits: A0, A1, B0, B1)
    //----------------------------------------------------------
    wire [55:0] pp0_blk0, pp1_blk0, pp2_blk0, pp3_blk0;
    multiplier_array_block u_block0 (
        .A_in(A0),
        .B_in(B0),
        .Valid({en1, en0, en1, en0}),
        .PP0(pp0_blk0),
        .PP1(pp1_blk0),
        .PP2(pp2_blk0),
        .PP3(pp3_blk0)
    );

    //----------------------------------------------------------
    // Multiplier Array Block 1 (upper 28 bits: A2, A3, B2, B3)
    //----------------------------------------------------------
    wire [55:0] pp0_blk1, pp1_blk1, pp2_blk1, pp3_blk1;
    multiplier_array_block u_block1 (
        .A_in(A1),
        .B_in(B1),
        .Valid({en3, en2, en3, en2}),
        .PP0(pp0_blk1),
        .PP1(pp1_blk1),
        .PP2(pp2_blk1),
        .PP3(pp3_blk1)
    );

    //----------------------------------------------------------
    // MUX and Rearrangement: Create 4 × 112-bit partial product buses
    // Each PPi_112bit[111:56] = Block1 tier i
    // Each PPi_112bit[55:0]   = Block0 tier i
    //----------------------------------------------------------
    wire [111:0] PP0_112bit = {pp0_blk1, pp0_blk0};
    wire [111:0] PP1_112bit = {pp1_blk1, pp1_blk0};
    wire [111:0] PP2_112bit = {pp2_blk1, pp2_blk0};
    wire [111:0] PP3_112bit = {pp3_blk1, pp3_blk0};

    //----------------------------------------------------------
    // Global 112-bit 4:2 CSA Stage 1 (takes 4 inputs)
    //----------------------------------------------------------
    wire [111:0] gsum0, gcarry0;
    csa4_2 #(.W(112)) u_csa112_stage1 (
        .x(PP0_112bit),
        .y(PP1_112bit),
        .z(PP2_112bit),
        .w(PP3_112bit),
        .sum(gsum0),
        .carry(gcarry0)
    );

    //----------------------------------------------------------
    // DP cycle 0 registers: hold sum/carry for inter-cycle merge
    //----------------------------------------------------------
    reg [111:0] reg_sum0_dp;
    reg [111:0] reg_carry0_dp;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_sum0_dp   <= 112'd0;
            reg_carry0_dp <= 112'd0;
        end
        else if (dp_c0) begin
            reg_sum0_dp   <= gsum0;
            reg_carry0_dp <= gcarry0;
        end
    end

    //----------------------------------------------------------
    // DP cycle 1: Merge path with 56-bit partial CSA
    //----------------------------------------------------------
    // Split into high/low halves for intermediate compression
    wire [55:0] sum_hi, carry_hi, sum_lo, carry_lo;
    csa4_2 #(.W(56)) u_csa56_hi (
        .x(reg_sum0_dp[111:56]),
        .y(reg_carry0_dp[111:56]),
        .z(gsum0[111:56]),
        .w(56'd0),
        .sum(sum_hi),
        .carry(carry_hi)
    );

    csa4_2 #(.W(56)) u_csa56_lo (
        .x(reg_sum0_dp[55:0]),
        .y(reg_carry0_dp[55:0]),
        .z(gsum0[55:0]),
        .w(56'd0),
        .sum(sum_lo),
        .carry(carry_lo)
    );

    // Final 112-bit compression on merged data
    wire [111:0] merged_data = {sum_hi + carry_hi, sum_lo + carry_lo};
    wire [111:0] gsum1, gcarry1;
    csa4_2 #(.W(112)) u_csa112_stage2 (
        .x(merged_data),
        .y(112'd0),
        .z(112'd0),
        .w(112'd0),
        .sum(gsum1),
        .carry(gcarry1)
    );

    //----------------------------------------------------------
    // Output routing by mode (paper-style carry-save interface)
    //----------------------------------------------------------
    // DP cycle0 is masked at the output; cycle1 emits merged CSA sum/carry.
    assign partial_sum   = PD_mode ? (Cnt0 ? gsum1   : 112'd0) : gsum0;
    assign partial_carry = PD_mode ? (Cnt0 ? gcarry1 : 112'd0) : gcarry0;

endmodule
