module LZAC_108bit (
    input  [107:0] Sum,
    input  [107:0] Carry,
    output [7:0]   LZA_CNT
);
    wire [107:0] P = Sum ^ Carry;
    wire [107:0] G = Sum & Carry;
    wire [107:0] carry_ant;

    assign carry_ant[0] = 1'b0;

    genvar i;
    generate
        for (i = 1; i < 108; i = i + 1) begin : ant_carry
            assign carry_ant[i] = G[i-1] | (P[i-1] & carry_ant[i-1]);
        end
    endgenerate

    wire [107:0] result_ant;
    generate
        for (i = 0; i < 108; i = i + 1) begin : ant_result
            if (i == 0)
                assign result_ant[i] = Sum[i] ^ G[i];
            else
                assign result_ant[i] = P[i] ^ carry_ant[i];
        end
    endgenerate

    wire [107:0] is_msb;
    wire [107:0] no_one_above;

    assign no_one_above[107] = 1'b1;
    generate
        for (i = 106; i >= 0; i = i - 1) begin : noa
            assign no_one_above[i] = no_one_above[i+1] & ~result_ant[i+1];
        end
    endgenerate

    generate
        for (i = 0; i < 108; i = i + 1) begin : msb_det
            assign is_msb[i] = no_one_above[i] & result_ant[i];
        end
    endgenerate

    reg [7:0] lza_cnt_reg;
    integer j;
    always @(*) begin
        lza_cnt_reg = 8'd108;
        for (j = 0; j < 108; j = j + 1) begin
            if (is_msb[j])
                lza_cnt_reg = 8'(107 - j);
        end
    end

    assign LZA_CNT = lza_cnt_reg;
endmodule
