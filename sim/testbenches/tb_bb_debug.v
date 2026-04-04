`timescale 1ns / 1ps
module tb_bb_debug;
    localparam DP = 3'b100;
    reg clk, rst_n;
    reg [63:0] A_in, B_in, C_in;
    reg [2:0] Prec; reg Para, Cvt;
    wire [63:0] Result_out;
    wire [3:0]  Valid_out;
    wire        Result_sign_out;

    DPDAC_top dut (.clk(clk),.rst_n(rst_n),.A_in(A_in),.B_in(B_in),.C_in(C_in),
        .Prec(Prec),.Para(Para),.Cvt(Cvt),.Result_out(Result_out),
        .Valid_out(Valid_out),.Result_sign_out(Result_sign_out));

    initial clk=0; always #5 clk=~clk;
    integer i;

    initial begin
        rst_n=0; Prec=DP; Para=0; Cvt=0; A_in=0; B_in=0; C_in=0;
        repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // Op1: 1.5*2.0+0.5 = 3.5
        A_in=64'h3FF8000000000000; B_in=64'h4000000000000000; C_in=64'h3FE0000000000000;
        Prec=DP; Para=0; Cvt=0;
        $display("Applying Op1 (1.5*2.0+0.5=3.5) and watching pipeline...");
        // Sweep 14 cycles, applying Op2 at cycle 2
        for (i=0; i<14; i=i+1) begin
            @(posedge clk); #1;
            if (i==1) begin
                A_in=64'h4000000000000000; B_in=64'h4000000000000000; C_in=64'd0;
                $display("  cyc%0d: Applied Op2 (2.0*2.0+0.0=4.0)", i);
            end
            $display("  cyc%0d: valid_s1=%b result=%h valid=%b",
                i, dut.valid_s1, Result_out, Valid_out);
        end
        $finish;
    end
    initial begin #300000; $display("TIMEOUT"); $finish; end
endmodule
