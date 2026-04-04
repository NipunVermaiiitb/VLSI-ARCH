// Leading Zero Anticipation Counter (LZAC)
// Operates on CSA sum/carry before the CPA to predict leading zeros
// in parallel with the final addition (reduces critical path).
// Covers the full 163-bit result vector.
//
// Uses a generate-based priority encoder to avoid casez width issues.

module LZAC (
    input  [162:0] Sum,
    input  [162:0] Carry,
    output [7:0]   LZA_CNT
);

    //----------------------------------------------------------
    // Anticipation signals (per bit)
    //   P = S XOR C : propagate
    //   G = S AND C : generate carry
    //----------------------------------------------------------
    wire [162:0] P = Sum ^ Carry;
    wire [162:0] G = Sum & Carry;

    // Anticipate carry ripple from position 0 upward.
    wire [162:0] carry_ant;
    assign carry_ant[0] = 1'b0;

    genvar i;
    generate
        for (i = 1; i < 163; i = i + 1) begin : ant_carry
            assign carry_ant[i] = G[i-1] | (P[i-1] & carry_ant[i-1]);
        end
    endgenerate

    // Anticipated result bit at each position
    wire [162:0] result_ant;
    generate
        for (i = 0; i < 163; i = i + 1) begin : ant_result
            if (i == 0)
                assign result_ant[i] = Sum[i] ^ G[i];
            else
                assign result_ant[i] = P[i] ^ carry_ant[i];
        end
    endgenerate

    //----------------------------------------------------------
    // Priority Encoder: scan MSB → LSB to find first 1 bit.
    // lza_cnt = number of leading zeros = 162 - (position of MSB 1).
    // Implemented with a generate chain: each bit checks if it is
    // the first 1 from the top without any 1 above it.
    //----------------------------------------------------------

    // "mask[i]" is 1 if bits [162:i+1] are all 0 AND bit[i] is 1
    // (i.e., bit i is the MSB 1)
    wire [162:0] is_msb;
    wire [162:0] no_one_above; // all bits above position i are 0

    generate
        // no_one_above[162] is always 1 (nothing above bit 162)
        assign no_one_above[162] = 1'b1;
        for (i = 161; i >= 0; i = i - 1) begin : noa
            assign no_one_above[i] = no_one_above[i+1] & ~result_ant[i+1];
        end
    endgenerate

    generate
        for (i = 0; i < 163; i = i + 1) begin : msb_det
            assign is_msb[i] = no_one_above[i] & result_ant[i];
        end
    endgenerate

    // Encode the one-hot is_msb vector into a binary count
    // lza_cnt = 162 - position_of_msb_1
    // Implemented as a 163-input OR-priority mux using generate
    reg [7:0] lza_cnt_reg;
    integer j;
    always @(*) begin
        lza_cnt_reg = 8'd163; // default: all zeros (underflow)
        for (j = 0; j < 163; j = j + 1) begin
            if (is_msb[j])
                lza_cnt_reg = 8'(162 - j);
        end
    end

    assign LZA_CNT = lza_cnt_reg;

endmodule