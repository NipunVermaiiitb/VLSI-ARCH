module CSA_4to2 (

    input  [162:0] in0,
    input  [162:0] in1,
    input  [162:0] in2,
    input  [162:0] in3,

    output [162:0] sum,
    output [162:0] carry

);
    wire [162:0] s1, c1;
    assign s1    = in0 ^ in1 ^ in2;
    assign c1    = (in0 & in1) | (in0 & in2) | (in1 & in2);

    assign sum   = s1 ^ in3 ^ c1;
    assign carry = (s1 & in3) | (s1 & c1) | (in3 & c1);

endmodule