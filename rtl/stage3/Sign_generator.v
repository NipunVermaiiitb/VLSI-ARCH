`timescale 1ns / 1ps

module Sign_Generator (
    input  [3:0]   Sign_AB,
    input  [3:0]   Sign_C,
    input  [2:0]   Prec,
    input  [1:0]   cout_vector,  // [1]: Lane 1 (bit 163), [0]: Lane 0 (bit 109)
    input  [162:0] CPA_result,
    output [3:0]   Result_sign   
);

    parameter DP = 3'b100;

    // Determine which sign bits to use based on mode
    // In DP: sign is always at [0].
    // In SIMD: lane 1 is at [3], lane 0 is at [0].
    wire [1:0] s_ab = (Prec == DP) ? {Sign_AB[0], Sign_AB[0]} : {Sign_AB[3], Sign_AB[0]};
    wire [1:0] s_c  = (Prec == DP) ? {Sign_C[0], Sign_C[0]}   : {Sign_C[3], Sign_C[0]};

    wire [1:0] eff_sub = s_ab ^ s_c;

    // Lane 1 (Upper) Sign
    wire raw_sign_l1 = (eff_sub[1]) ? ~cout_vector[1] : s_ab[1];
    // Lane 0 (Lower) Sign
    wire raw_sign_l0 = (eff_sub[0]) ? ~cout_vector[0] : s_ab[0];

    // Distribute sign vectors
    assign Result_sign = (Prec == DP) ? {3'b0, raw_sign_l1} : 
                         {raw_sign_l1, raw_sign_l1, raw_sign_l0, raw_sign_l0};

endmodule