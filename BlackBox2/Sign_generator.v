module Sign_Generator (
    input  [3:0] Sign_AB,
    input  [3:0] Valid,
    input        PD_mode,
    output       Result_sign
);

    // Extract valid operands and their signs
    wire valid_neg_0 = Valid[0] & Sign_AB[0];
    wire valid_neg_1 = Valid[1] & Sign_AB[1];
    wire valid_neg_2 = Valid[2] & Sign_AB[2];
    wire valid_neg_3 = Valid[3] & Sign_AB[3];
    
    wire valid_pos_0 = Valid[0] & ~Sign_AB[0];
    wire valid_pos_1 = Valid[1] & ~Sign_AB[1];
    wire valid_pos_2 = Valid[2] & ~Sign_AB[2];
    wire valid_pos_3 = Valid[3] & ~Sign_AB[3];
    
    // Count valid negative and positive operands
    wire [1:0] neg_operands = valid_neg_0 + valid_neg_1 + valid_neg_2 + valid_neg_3;
    wire [1:0] pos_operands = valid_pos_0 + valid_pos_1 + valid_pos_2 + valid_pos_3;
    
    // Determine result sign based on operand dominance
    wire sign_by_count = (neg_operands > pos_operands) ? 1'b1 : 1'b0;
    
    // In PD_mode (partial dot-product), prioritize earlier operands
    // In accumulation mode, use operand count
    assign Result_sign = PD_mode ? Sign_AB[0] : sign_by_count;

endmodule