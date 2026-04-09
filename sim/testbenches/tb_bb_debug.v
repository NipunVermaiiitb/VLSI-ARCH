`timescale 1ns / 1ps
module tb_bb_exact;
    localparam DP  = 3'b100;
    localparam BF16 = 3'b001;
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
        // Exact same TC-7 sequence from the full TB
        // (after global reset at start)
        rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // Simulate BF16 TC-6 like the full TB does
        begin : bf_sim
            reg [63:0] bf_a;
            bf_a = 64'd0;
            bf_a[62:55]=8'd127; bf_a[46:39]=8'd127; bf_a[30:23]=8'd127; bf_a[14:7]=8'd127;
            A_in=bf_a; B_in=bf_a; C_in=64'd0; Prec=BF16; Para=0; Cvt=0;
            @(posedge clk);
            repeat(5) @(posedge clk);  // SP_LATENCY+1=5
            #1;
            $display("After BF16: result=%h valid=%b", Result_out, Valid_out);
        end

        // Now TC-7: reset for DP
        A_in=0; B_in=0; C_in=0; Prec=DP; Para=0; Cvt=0;
        rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);
        $display("After TC-7 local reset+2 idles");

        // Op1
        A_in=64'h3FF8000000000000; B_in=64'h4000000000000000; C_in=64'h3FE0000000000000;
        Prec=DP; Para=0; Cvt=0;
        $display("Applied Op1. Sweeping pipeline...");
        @(posedge clk); #1; $display("  cyc0: valid_s1=%b result=%h", dut.valid_s1, Result_out);
        @(posedge clk); #1; $display("  cyc1: valid_s1=%b result=%h", dut.valid_s1, Result_out);
        // Apply Op2
        A_in=64'h4000000000000000; B_in=64'h4000000000000000; C_in=64'd0;
        $display("  Applied Op2");
        for (i=2; i<10; i=i+1) begin
            @(posedge clk); #1;
            $display("  cyc%0d: valid_s1=%b result=%h valid=%b", i, dut.valid_s1, Result_out, Valid_out);
        end
        $finish;
    end
    initial begin #400000; $display("TIMEOUT"); $finish; end
endmodule
