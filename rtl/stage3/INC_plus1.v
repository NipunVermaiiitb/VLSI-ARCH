module INC_Plus1 (

    input  [162:0] In,
    input          Enable,

    output [162:0] Out

);

    // When Enable=1: add 1 to complete two's complement (after Complementer bit-invert).
    // When Enable=0: pass through unchanged.
    assign Out = Enable ? (In + 163'd1) : In;

endmodule