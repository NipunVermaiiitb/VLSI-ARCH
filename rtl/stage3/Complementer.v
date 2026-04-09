`timescale 1ns / 1ps

module Complementer (
    input  [162:0] In,
    input          Invert,
    input          Plus1,
    output [162:0] Out
);
    // Combined logic for magnitudal inversion and two's complement increment
    wire [162:0] pre_val = Invert ? ~In : In;
    assign Out = pre_val + {162'd0, Plus1};
endmodule
