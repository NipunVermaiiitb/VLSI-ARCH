`timescale 1ns / 1ps

module CSA_4to2_108bit (
    input  [107:0] in0,
    input  [107:0] in1,
    input  [107:0] in2,
    input  [107:0] in3,

    output [107:0] sum,
    output [107:0] carry
);

    // Level 1: 3-to-2 CSA
    wire [107:0] s1 = in0 ^ in1 ^ in2;
    wire [107:0] c1 = (in0 & in1) | (in0 & in2) | (in1 & in2);

    // Level 2: 3-to-2 CSA (using outputs of Level 1 + in3)
    assign sum   = s1 ^ in3 ^ c1;

    // Note: Carry must be shifted left by 1 in a CSA array
    assign carry = ((s1 & in3) | (s1 & c1) | (in3 & c1)) << 1;

endmodule
