module Products_Alignment_Shifter (
    input  [111:0] unaligned_112, // Raw 112-bit bus from Multiplier Stage 2 CPA
    input  [63:0]  ProdASC,       // {ASC_P3, ASC_P2, ASC_P1, ASC_P0}
    input  [3:0]   Sign_AB,       // Product signs
    input          PD_mode,       // DP
    input          PD2_mode,      // SP/TF32
    input          PD4_mode,      // HP/BF16
    input  [2:0]   Prec,          // ADDED: Prec mode

    output [107:0] unified_product_108 // 108-bit Unified Product
);
    localparam TF32 = 3'b010;

    wire [27:0] p_raw [0:3];
    assign p_raw[0] = unaligned_112[27:0];
    assign p_raw[1] = unaligned_112[55:28];
    assign p_raw[2] = unaligned_112[83:56];
    assign p_raw[3] = unaligned_112[111:84];

    wire [26:0] p_aligned_HP [0:3];
    function [26:0] shift_and_flip_HP;
        input [27:0] data_in;
        input [15:0] shift_amt;
        input        sign_bit;
        reg   [27:0] shifted;
        begin
            shifted = data_in >> shift_amt[4:0];
            shift_and_flip_HP = (sign_bit) ? ~shifted[26:0] : shifted[26:0];
        end
    endfunction

    assign p_aligned_HP[0] = shift_and_flip_HP(p_raw[0], ProdASC[15:0],  Sign_AB[0]);
    assign p_aligned_HP[1] = shift_and_flip_HP(p_raw[1], ProdASC[31:16], Sign_AB[1]);
    assign p_aligned_HP[2] = shift_and_flip_HP(p_raw[2], ProdASC[47:32], Sign_AB[2]);
    assign p_aligned_HP[3] = shift_and_flip_HP(p_raw[3], ProdASC[63:48], Sign_AB[3]);

    wire [55:0] p_raw_SP [0:1];
    assign p_raw_SP[0] = unaligned_112[55:0];
    assign p_raw_SP[1] = unaligned_112[111:56];

    wire [53:0] p_aligned_SP [0:1];
    function [53:0] shift_and_flip_SP;
        input [55:0] data_in;
        input [15:0] shift_amt;
        input        sign_bit;
        reg   [55:0] shifted;
        begin
            shifted = data_in >> shift_amt[5:0];
            shift_and_flip_SP = (sign_bit) ? ~shifted[53:0] : shifted[53:0];
        end
    endfunction
    
    // PD2 modes use two packed 56-bit lanes. Their exponent/sign indices differ by format:
    // SP   : lower->lane1, upper->lane3
    // TF32 : lower->lane0, upper->lane2
    wire [15:0] sp_lower_asc  = (Prec == TF32) ? ProdASC[15:0]  : ProdASC[31:16];
    wire [15:0] sp_upper_asc  = (Prec == TF32) ? ProdASC[47:32] : ProdASC[63:48];
    wire        sp_lower_sign = (Prec == TF32) ? Sign_AB[0]     : Sign_AB[1];
    wire        sp_upper_sign = (Prec == TF32) ? Sign_AB[2]     : Sign_AB[3];

    assign p_aligned_SP[0] = shift_and_flip_SP(p_raw_SP[0], sp_lower_asc, sp_lower_sign);
    assign p_aligned_SP[1] = shift_and_flip_SP(p_raw_SP[1], sp_upper_asc, sp_upper_sign);

    reg [107:0] unified_out;

    always @(*) begin
        if (PD4_mode) begin
            unified_out = {p_aligned_HP[3], p_aligned_HP[2], p_aligned_HP[1], p_aligned_HP[0]};
        end
        else if (PD2_mode) begin
            unified_out = {p_aligned_SP[1], p_aligned_SP[0]};
        end
        else begin
            unified_out = (Sign_AB[0]) ? ~unaligned_112[107:0] : unaligned_112[107:0];
        end
    end

    assign unified_product_108 = unified_out;

endmodule
