`timescale 1ns / 1ps

module sign_logic (

    input        A_sign,
    input        B_sign,
    input  [3:0] Valid,

    output [3:0] Sign_AB

);

    //----------------------------------------------------------
    // Product Sign
    //----------------------------------------------------------
    wire product_sign;

    assign product_sign = A_sign ^ B_sign;

    //----------------------------------------------------------
    // Replicate across lanes and mask with Valid
    //----------------------------------------------------------
    assign Sign_AB = {4{product_sign}} & Valid;

endmodule