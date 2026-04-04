module Complementer (

    input  [162:0] In,
    input          Negate,

    output [162:0] Out

);

    // When Negate=1: bitwise invert (one's complement step)
    // INC_Plus1 follows to add 1, completing two's complement negation.
    // When Negate=0: pass through unchanged.
    assign Out = Negate ? (~In) : In;

endmodule