`timescale 1ns / 1ps

module sign_logic (

    input  [3:0] A_sign,
    input  [3:0] B_sign,
    input  [3:0] Valid,

    output [3:0] Sign_AB

);

    //----------------------------------------------------------
    // Per-lane Product Sign (XOR for each lane)
    //----------------------------------------------------------
    wire [3:0] product_sign;

    assign product_sign[0] = A_sign[0] ^ B_sign[0];
    assign product_sign[1] = A_sign[1] ^ B_sign[1];
    assign product_sign[2] = A_sign[2] ^ B_sign[2];
    assign product_sign[3] = A_sign[3] ^ B_sign[3];

    //----------------------------------------------------------
    // Mask with Valid
    //----------------------------------------------------------
    assign Sign_AB = product_sign & Valid;

endmodule