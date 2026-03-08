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
            // DP: one wide product stream.
            mag0 = partial_products[107:0];
        end
        else if (PD2_mode) begin
            // PD2: two packed products from low/high halves.
            mag0 = {52'd0, partial_products[55:0]};
            mag1 = {52'd0, partial_products[111:56]};
        end
        else if (PD4_mode) begin
            // PD4: four packed products, 28 bits each.
            mag0 = {80'd0, partial_products[27:0]};
            mag1 = {80'd0, partial_products[55:28]};
            mag2 = {80'd0, partial_products[83:56]};
            mag3 = {80'd0, partial_products[111:84]};
        end
        else begin
            // Default to PD4-style slicing for robustness.
            mag0 = {80'd0, partial_products[27:0]};
            mag1 = {80'd0, partial_products[55:28]};
            mag2 = {80'd0, partial_products[83:56]};
            mag3 = {80'd0, partial_products[111:84]};
        end
    end

    // Output unsigned magnitudes (sign will be applied AFTER alignment)
    assign product0 = mag0[106:0];
    assign product1 = mag1[106:0];
    assign product2 = mag2[106:0];
    assign product3 = mag3[106:0];

endmodule