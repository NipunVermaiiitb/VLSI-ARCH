module Products_Alignment_Shifter (
    input  [106:0] product0,
    input  [106:0] product1,
    input  [106:0] product2,
    input  [106:0] product3,

    input  [31:0]  MaxExp,
    input  [31:0]  ExpDiff,

    output [162:0] aligned_p0,
    output [162:0] aligned_p1,
    output [162:0] aligned_p2,
    output [162:0] aligned_p3
);

    // Extend products to 163 bits with leading zeros
    wire [162:0] product0_ext = {56'b0, product0};
    wire [162:0] product1_ext = {56'b0, product1};
    wire [162:0] product2_ext = {56'b0, product2};
    wire [162:0] product3_ext = {56'b0, product3};

    // Determine shift amount (clamped to 163 to avoid invalid shifts)
    wire [7:0] shift_amount = (ExpDiff > 8'd163) ? 8'd163 : ExpDiff[7:0];

    // Barrel shifter for each product (right shift to align to MaxExp)
    assign aligned_p0 = product0_ext >> shift_amount;
    assign aligned_p1 = product1_ext >> shift_amount;
    assign aligned_p2 = product2_ext >> shift_amount;
    assign aligned_p3 = product3_ext >> shift_amount;

endmodule