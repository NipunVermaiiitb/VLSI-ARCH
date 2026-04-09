`timescale 1ns / 1ps
// Isolated SP test — fresh reset, apply SP inputs only
module tb_sp_isolated;
    localparam SP = 3'b011;
    reg clk, rst_n;
    reg [63:0] A_in, B_in, C_in;
    reg [2:0]  Prec; reg Para, Cvt;
    wire [63:0] Result_out;
    wire [3:0]  Valid_out;
    wire        Result_sign_out;

    DPDAC_top dut (.clk(clk),.rst_n(rst_n),.A_in(A_in),.B_in(B_in),.C_in(C_in),
        .Prec(Prec),.Para(Para),.Cvt(Cvt),.Result_out(Result_out),
        .Valid_out(Valid_out),.Result_sign_out(Result_sign_out));

    initial clk=0; always #5 clk=~clk;
    integer i;
    initial begin
        // SP 1.0 x 1.0 + 0 — all four versions
        rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // Test 1: SP 1.0 × 1.0
        A_in = {32'h3F800000, 32'h3F800000};  // SP 1.0 both lanes
        B_in = {32'h3F800000, 32'h3F800000};
        C_in = 64'd0;
        Prec = SP; Para=0; Cvt=0;
        $display("--- SP 1.0 x 1.0 + 0 (expect 1.0 = 0x3F8000003F800000) ---");
        for (i=0; i<8; i=i+1) begin
            @(posedge clk); #1;
            $display("  cyc%0d: pp[55:20]=%h valid_s1=%b S2sum[162:139]=%h S3add[162:139]=%h lza=%d maxexp_s4=%h result=%h",
                i,
                dut.pp_sum_s1[55:20],
                dut.valid_s1,
                dut.u_stage2.Sum_s2[162:139],
                dut.u_stage3.Add_Rslt_s3[162:139],
                dut.u_stage3.LZA_CNT_s3,
                dut.MaxExp_s4_reg,
                Result_out);
        end

        // Test 2: SP 2.0 x 0.5 + 1.0
        $display("\n--- SP 2.0x0.5+1.0 (lane0 expect 2.0=0x40000000) ---");
        rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);
        A_in = {32'h3FC00000, 32'h40000000};  // upper=1.5, lower=2.0
        B_in = {32'h40000000, 32'h3F000000};  // upper=2.0, lower=0.5
        C_in = {32'h3F000000, 32'h3F800000};  // upper=0.5, lower=1.0
        Prec = SP; Para=0; Cvt=0;
        for (i=0; i<7; i=i+1) begin
            @(posedge clk); #1;
            $display("  cyc%0d: pp[55:20]=%h S3add[162:139]=%h lza=%d exp_s4=%h result=%h",
                i, dut.pp_sum_s1[55:20],
                dut.u_stage3.Add_Rslt_s3[162:139],
                dut.u_stage3.LZA_CNT_s3,
                dut.MaxExp_s4_reg[15:0],
                Result_out);
        end

        $finish;
    end
    initial begin #200000; $display("TIMEOUT"); $finish; end
endmodule
