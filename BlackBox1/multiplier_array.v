module low_cost_multiplier_array (

    input  [55:0] A_mantissa,
    input  [55:0] B_mantissa,

    input  [2:0]  Prec,
    input  [3:0]  Valid,

    input         PD_mode,
    input         PD2_mode,
    input         PD4_mode,

    output [111:0] partial_products

);

endmodule