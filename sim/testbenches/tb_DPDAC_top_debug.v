`timescale 1ns / 1ps
// ============================================================
// tb_DPDAC_top_deep_debug.v — Deeper pipeline debug
// Monitors every pipeline stage's registered outputs cycle by cycle
// ============================================================
module tb_DPDAC_top_deep_debug;

    localparam DP = 3'b100;
    localparam CLK_PERIOD = 10;

    reg clk, rst_n;
    reg [63:0] A_in, B_in, C_in;
    reg [2:0]  Prec;
    reg        Para, Cvt;

    wire [63:0] Result_out;
    wire [3:0]  Valid_out;
    wire        Result_sign_out;

    DPDAC_top dut (
        .clk(clk), .rst_n(rst_n),
        .A_in(A_in), .B_in(B_in), .C_in(C_in),
        .Prec(Prec), .Para(Para), .Cvt(Cvt),
        .Result_out(Result_out), .Valid_out(Valid_out),
        .Result_sign_out(Result_sign_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer cyc;
    initial begin
        A_in = 0; B_in = 0; C_in = 0;
        Prec = DP; Para = 0; Cvt = 0;
        rst_n = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // Apply DP inputs
        A_in = 64'h3FF8000000000000; B_in = 64'h4000000000000000;
        C_in = 64'h3FE0000000000000;
        Prec = DP; Para = 0; Cvt = 0;

        $display("=== Per-cycle pipeline trace: DP 1.5*2.0+0.5 ===");
        $display("Cycle | pp_sum_nonzero | S3_Add_Rslt[162:107] | S3_LZA | Result");
        for (cyc = 0; cyc < 10; cyc = cyc + 1) begin
            @(posedge clk); #1;
            $display("%5d | pp_sum=%h | s3=%h | lza=%d | result=%h",
                cyc,
                dut.pp_sum_s1[111:80],         // top 32 bits of partial_sum
                dut.u_stage3.Add_Rslt_s3[162:131], // top 32 bits of S3 result
                dut.u_stage3.LZA_CNT_s3,
                Result_out
            );
        end

        // Now print the Stage2 inputs to Stage3 (after Stage2_PipeReg in Stage3_top)
        $display("\n=== Stage2 → Stage3 registered transfer ===");
        // Access Stage2_Pipeline_Register outputs inside Stage3_top
        $display("  S3top.u_stage2_reg.Sum_out[162:131]   = %h",
                 dut.u_stage3.u_stage2_reg.Sum_out[162:131]);
        $display("  S3top.u_stage2_reg.Carry_out[162:131] = %h",
                 dut.u_stage3.u_stage2_reg.Carry_out[162:131]);
        $display("  S3top.u_stage2_reg.Aligned_C_dual[162:131] = %h",
                 dut.u_stage3.u_stage2_reg.Aligned_C_dual_out[162:131]);

        // Stage2_Top outputs (before the register)
        $display("\n=== Stage2_Top combinational outputs ===");
        $display("  Stage2.Sum_s2[162:131]   = %h", dut.u_stage2.Sum_s2[162:131]);
        $display("  Stage2.Carry_s2[162:131] = %h", dut.u_stage2.Carry_s2[162:131]);
        $display("  Stage2.Sum_s2[106:75]    = %h", dut.u_stage2.Sum_s2[106:75]);
        $display("  Stage2.Carry_s2[106:75]  = %h", dut.u_stage2.Carry_s2[106:75]);
        $display("  partial_products_s1[111:80] = %h", dut.partial_products_s1[111:80]);
        $display("  partial_products_s1[107:76] = %h", dut.partial_products_s1[107:76]);
        $display("  partial_products_s1[55:24]  = %h", dut.partial_products_s1[55:24]);
        $display("  pp_sum_s1[111:80]           = %h", dut.pp_sum_s1[111:80]);
        $display("  pp_sum_s1[107:76]           = %h", dut.pp_sum_s1[107:76]);
        $display("  pp_carry_s1[111:80]         = %h", dut.pp_carry_s1[111:80]);

        $display("\n=== MaxExp ===");
        $display("  MaxExp_s4 = %h (expect 0x03fe0400)", dut.MaxExp_s4_reg);

        $finish;
    end

    initial begin #200000; $display("TIMEOUT"); $finish; end

endmodule
