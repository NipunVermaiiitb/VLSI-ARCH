module Products_Alignment_Shifter (
    input  [106:0] product0,
    input  [106:0] product1,
    input  [106:0] product2,
    input  [106:0] product3,

    input  [63:0]  ProdASC,     // {ASC_P3, ASC_P2, ASC_P1, ASC_P0}
    input          PD_mode,
    input          PD2_mode,
    input          PD4_mode,

    output [162:0] aligned_p0,
    output [162:0] aligned_p1,
    output [162:0] aligned_p2,
    output [162:0] aligned_p3
);

    // Unpack ASCs
    wire [15:0] asc_p0 = ProdASC[15:0];
    wire [15:0] asc_p1 = ProdASC[31:16];
    wire [15:0] asc_p2 = ProdASC[47:32];
    wire [15:0] asc_p3 = ProdASC[63:48];

    // Clamp shift amounts to 163 to avoid invalid shifts
    wire [7:0] shift0 = (asc_p0 > 16'd163) ? 8'd163 : asc_p0[7:0];
    wire [7:0] shift1 = (asc_p1 > 16'd163) ? 8'd163 : asc_p1[7:0];
    wire [7:0] shift2 = (asc_p2 > 16'd163) ? 8'd163 : asc_p2[7:0];
    wire [7:0] shift3 = (asc_p3 > 16'd163) ? 8'd163 : asc_p3[7:0];

    // Extend products to 163 bits: place product at HIGH side of accumulator.
    // The 56-bit LSB pad provides GRS bits below the product mantissa.
    // Mode-specific exponent calibration (accum_offset) is in Output_Formatter.
    wire [162:0] product0_ext = {product0, 56'd0};
    wire [162:0] product1_ext = {product1, 56'd0};
    wire [162:0] product2_ext = {product2, 56'd0};
    wire [162:0] product3_ext = {product3, 56'd0};

    // Mode-based alignment
    assign aligned_p0 = PD_mode ? product0_ext : (product0_ext >>> shift0);
    assign aligned_p1 = (PD_mode || (!PD2_mode && !PD4_mode)) ? 163'd0 : (product1_ext >>> shift1);
    assign aligned_p2 = PD4_mode ? (product2_ext >>> shift2) : 163'd0;
    assign aligned_p3 = (PD2_mode || PD4_mode) ? (product3_ext >>> shift3) : 163'd0;

endmodule