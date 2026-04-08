module INC_Plus1_55bit (
    input  [54:0] In,
    output [54:0] Out
);
    assign Out = In + 55'd1;
endmodule
