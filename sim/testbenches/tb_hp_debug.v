`timescale 1ns / 1ps
// HP isolation after SP sequence (mimics full TB TC-4 then TC-5)
module tb_hp_after_sp;
    localparam HP   = 3'b000;
    localparam SP   = 3'b011;
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
        rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // TC-4 SP: 1+4 clocks (drives then waits)
        A_in = {32'h3FC00000, 32'h40000000};
        B_in = {32'h40000000, 32'h3F000000};
        C_in = {32'h3F000000, 32'h3F800000};
        Prec = SP; Para=0; Cvt=0;
        @(posedge clk);          // 1 apply clock
        repeat(4) @(posedge clk); // 4 wait clocks
        #1;
        $display("After SP (TC-4): result=%h valid=%b", Result_out, Valid_out);

        // TC-5 HP: apply hp_a inputs
        begin : hp_b
            reg [63:0] hp_a;
            hp_a = 64'd0;
            hp_a[62:58]=5'd15; hp_a[46:42]=5'd15; hp_a[30:26]=5'd15; hp_a[14:10]=5'd15;
            A_in=hp_a; B_in=hp_a; C_in=64'd0; Prec=HP; Para=0; Cvt=0;
            $display("\nApplied HP inputs. Watching pipeline...");
            for (i=0; i<8; i=i+1) begin
                @(posedge clk); #1;
                $display("  HP cyc%0d: valid_s1=%b pp_s1[27:0]=%h S2sum[162:130]=%h S2reg[162:130]=%h S3add[162:130]=%h lza=%d maxexp_s2=%h maxexp_s4=%h result=%h valid=%b",
                    i, dut.valid_s1,
                    dut.pp_sum_s1[27:0],
                    dut.u_stage2.Sum_s2[162:130],
                    dut.u_stage3.u_stage2_reg.Sum_out[162:130],
                    dut.u_stage3.Add_Rslt_s3[162:130],
                    dut.u_stage3.LZA_CNT_s3,
                    dut.MaxExp_s2_reg[15:0],
                    dut.MaxExp_s4_reg[15:0],
                    Result_out, Valid_out);
            end
        end

        $finish;
    end
    initial begin #200000; $display("TIMEOUT"); $finish; end
endmodule
