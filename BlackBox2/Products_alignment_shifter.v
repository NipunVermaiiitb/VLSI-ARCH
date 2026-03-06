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

endmodule