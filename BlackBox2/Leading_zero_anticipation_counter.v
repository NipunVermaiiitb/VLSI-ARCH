module LZAC (
    input  [162:0] Sum,
    input  [162:0] Carry,
    output [7:0]   LZA_CNT
);

    // Generate anticipation signals
    wire [162:0] prop;  // Propagate: where a carry can pass through
    wire [162:0] gen;   // Generate: where carry is produced
    wire [162:0] kill;  // Kill: where carry is blocked
    
    assign prop = Sum ^ Carry;              // Bit will be 1 if carry comes in
    assign gen  = Sum & Carry;              // Both 1 → generates carry
    assign kill = ~Sum & ~Carry;            // Both 0 → kills carry
    
    // Predict carries (simplified for timing)
    wire [162:0] carry_pred;
    assign carry_pred[0] = 1'b0;
    
    genvar i;
    generate
        for (i = 1; i < 163; i = i + 1) begin : carry_chain
            assign carry_pred[i] = gen[i-1] | (prop[i-1] & carry_pred[i-1]);
        end
    endgenerate
    
    // Anticipate final result: which bits will be 1?
    wire [162:0] result_bit;
    generate
        for (i = 0; i < 163; i = i + 1) begin : result_pred
            if (i == 0) begin
                assign result_bit[i] = Sum[i];
            end else begin
                assign result_bit[i] = Sum[i] ^ (Carry[i-1] ^ carry_pred[i-1]);
            end
        end
    endgenerate
    
    // Priority encoder: count leading zeros (find first 1 from MSB)
    reg [7:0] lza_cnt_reg;
    
    always @(*) begin
        lza_cnt_reg = 8'd163;  // Default: all zeros
        if (result_bit[162]) lza_cnt_reg = 8'd0;
        else if (result_bit[161]) lza_cnt_reg = 8'd1;
        else if (result_bit[160]) lza_cnt_reg = 8'd2;
        else if (result_bit[159]) lza_cnt_reg = 8'd3;
        else if (result_bit[158]) lza_cnt_reg = 8'd4;
        else if (result_bit[157]) lza_cnt_reg = 8'd5;
        else if (result_bit[156]) lza_cnt_reg = 8'd6;
        else if (result_bit[155]) lza_cnt_reg = 8'd7;
    end
    
    assign LZA_CNT = lza_cnt_reg;

endmodule