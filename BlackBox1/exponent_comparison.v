module exponent_comparison (

    input  [31:0] A_exp,
    input  [31:0] B_exp,
    input  [31:0] C_exp,

    input  [2:0]  Prec,

    output [31:0] ExpDiff,
    output [31:0] MaxExp

);

    //----------------------------------------------------------
    // Product exponent = A_exp + B_exp
    //----------------------------------------------------------
    wire [31:0] product_exp;

    assign product_exp = A_exp + B_exp;

    //----------------------------------------------------------
    // Maximum exponent
    //----------------------------------------------------------
    assign MaxExp = (product_exp > C_exp) ? product_exp : C_exp;

    //----------------------------------------------------------
    // Exponent difference (used for shifting C)
    //----------------------------------------------------------
    assign ExpDiff = MaxExp - C_exp;

endmodule