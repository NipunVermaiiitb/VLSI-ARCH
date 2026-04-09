module Final_Adder_108bit (
    input  [107:0] A,
    input  [107:0] B,
    input          Cin,

    output [107:0] SUM,
    output         Cout
);
    assign {Cout, SUM} = A + B + Cin;
endmodule
