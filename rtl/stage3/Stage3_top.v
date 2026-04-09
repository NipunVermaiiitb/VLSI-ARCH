`timescale 1ns / 1ps

module Stage3_Top (
    input clk,
    input rst_n,

    //------------------------------------------------
    // Inputs from Stage 2 pipeline register
    //------------------------------------------------
    input [162:0] Sum_s2,
    input [162:0] Carry_s2,
    input [162:0] Aligned_C_s2,

    input [3:0]   Sign_AB_s2,
    input [3:0]   Sign_C_s2,
    input [1:0]   Sticky_C_s2,

    input [2:0]   Prec_s2,
    input [3:0]   Valid_s2,
    input         PD_mode_s2,
    input         valid_s1,

    //------------------------------------------------
    // Outputs to Stage 4
    //------------------------------------------------
    output [162:0] Add_Rslt_s3,
    output [15:0]  LZA_CNT_s3,      // Dual 8-bit counts [15:8]:Lane1, [7:0]:Lane0
    output [3:0]   Result_sign_s3, // 4ndndndnd bit vectndndNDnd
    output [2:0]   Prec_s3,
    output [3:0]   Valid_s3
);

    function [7:0] lzc54;
        input [53:0] v;
        integer k;
        begin
            lzc54 = 8'd54;
            for (k = 53; k >= 0; k = k - 1) begin
                if (v[k]) begin
                    lzc54 = 8'(53 - k);
                    k = -1;
                end
            end
        end
    endfunction

    function [7:0] lzc109;
        input [108:0] v;
        integer k;
        begin
            lzc109 = 8'd109;
            for (k = 108; k >= 0; k = k - 1) begin
                if (v[k]) begin
                    lzc109 = 8'(108 - k);
                    k = -1;
                end
            end
        end
    endfunction

    //------------------------------------------------
    // Stage 2 Pipeline Register
    //------------------------------------------------
    wire [162:0] Sum, Carry, Aligned_C;
    wire [3:0]   Sign_AB, Sign_C;
    wire [1:0]   Sticky_C;
    wire [2:0]   Prec;
    wire [3:0]   Valid;
    wire         PD_mode;

    Stage2_Pipeline_Register u_stage2_reg (
        .clk(clk), .rst_n(rst_n), .enable(valid_s1),
        .Sum_in(Sum_s2), .Carry_in(Carry_s2),
        .Aligned_C_in(Aligned_C_s2),
        .Sign_AB_in(Sign_AB_s2), .Sign_C_in(Sign_C_s2), .Sticky_C_in(Sticky_C_s2),
        .Prec_in(Prec_s2), .Valid_in(Valid_s2), .PD_mode_in(PD_mode_s2),

        .Sum_out(Sum), .Carry_out(Carry),
        .Aligned_C_out(Aligned_C),
        .Sign_AB_out(Sign_AB), .Sign_C_out(Sign_C), .Sticky_C_out(Sticky_C),
        .Prec_out(Prec), .Valid_out(Valid), .PD_mode_out(PD_mode)
    );

    //------------------------------------------------
    // 163-bit Unified Carry Propagate Adder
    //------------------------------------------------
    // As per the DPDAC architecture, Stage 3 performs the final accumulation.
    // We utilize a single wide 163-bit adder for Sum + Carry + Aligned_C + Cin.
    wire         eff_sub = Sign_AB[0] ^ Sign_C[0];
    wire         injection_cin = eff_sub;

    wire [164:0] full_cpa_sum = Sum + Carry + Aligned_C + {162'd0, Sign_AB[0]} + {162'd0, Sign_C[0]};
                                
    wire [162:0] Raw_Result = full_cpa_sum[162:0];
    wire         cout_163   = full_cpa_sum[163];

    // Lane 0 Carry-out calculation for SIMD
    wire [109:0] lane0_cpa = Sum[108:0] + Carry[108:0] + Aligned_C[108:0] + {108'd0, Sign_AB[0]} + {108'd0, Sign_C[0]};
    wire         cout_108  = lane0_cpa[109];

    //------------------------------------------------
    // Sign Determination & Final Complementer
    //------------------------------------------------
    wire [3:0] Result_sign_comb;

    Sign_Generator u_sign_gen (
        .Sign_AB(Sign_AB), .Sign_C(Sign_C), .Prec(Prec),
        .cout_vector({cout_163, cout_108}), .CPA_result(Raw_Result),
        .Result_sign(Result_sign_comb)
    );

    // Complementer Control (Two's Complement Magnitude Extraction):
    // For Signed Addition: Result is negative if:
    //  1. Both were negative
    //  2. Signs were different and cout=0 (Negative dominant)
    wire need_negate = (Sign_AB[0] & Sign_C[0]) | (eff_sub & ~cout_163);

    wire [162:0] Add_Rslt_mag;
    Complementer u_complementer (
        .In(Raw_Result),
        .Invert(need_negate),
        .Plus1(need_negate),
        .Out(Add_Rslt_mag)
    );

    // Dual LZC for SIMD lanes
    wire [7:0] lza_hi = lzc54(Add_Rslt_mag[162:109]);
    wire [7:0] lza_lo = lzc109(Add_Rslt_mag[108:0]);
    wire [15:0] LZA_CNT_dual = {lza_hi, lza_lo};

    //------------------------------------------------
    // Stage 3 Pipeline Register
    //------------------------------------------------
    Stage3_Pipeline_Register u_stage3_reg (
        .clk(clk), .rst_n(rst_n),
        .Add_Rslt_in(Add_Rslt_mag),
        .Result_sign_in(Result_sign_comb),
        .LZA_CNT_in(LZA_CNT_dual),
        .Prec_in(Prec), .Valid_in(Valid),

        .Add_Rslt_out(Add_Rslt_s3),
        .Result_sign_out(Result_sign_s3),
        .LZA_CNT_out(LZA_CNT_s3),
        .Prec_out(Prec_s3), .Valid_out(Valid_s3)
    );

endmodule
