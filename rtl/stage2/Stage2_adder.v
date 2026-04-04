module Stage2_Adder (

    input  [111:0] partial_products,

    input          PD_mode,
    input          PD2_mode,
    input          PD4_mode,

    output [106:0] product0,
    output [106:0] product1,
    output [106:0] product2,
    output [106:0] product3

);

    // Unpack the Stage-1 product bus into mode-dependent magnitudes.
    reg [107:0] mag0;
    reg [107:0] mag1;
    reg [107:0] mag2;
    reg [107:0] mag3;

    always @(*) begin
        mag0 = 108'd0;
        mag1 = 108'd0;
        mag2 = 108'd0;
        mag3 = 108'd0;

        if (PD_mode) begin
            // DP: one wide 107-bit product stream, already from high of partial_products
            mag0 = partial_products[107:0];
        end
        else if (PD2_mode) begin
            // PD2 (SP/TF32): two 56-bit products from low/high halves
            // Place at HIGH side of 108-bit mag so leading bit is near bit 107
            // (after {mag, 56'zeros} in product0_ext → leading bit at ~bit 163 = top)
            mag0 = {partial_products[55:0],  52'd0};
            mag1 = {partial_products[111:56], 52'd0};
        end
        else begin  // PD4_mode (HP/BF16)
            // PD4: four 28-bit products, each placed at HIGH side of 108-bit mag
            mag0 = {partial_products[27:0],  80'd0};
            mag1 = {partial_products[55:28], 80'd0};
            mag2 = {partial_products[83:56], 80'd0};
            mag3 = {partial_products[111:84],80'd0};
        end
    end

    // Output unsigned magnitudes (sign will be applied AFTER alignment)
    assign product0 = mag0[106:0];
    assign product1 = mag1[106:0];
    assign product2 = mag2[106:0];
    assign product3 = mag3[106:0];

endmodule