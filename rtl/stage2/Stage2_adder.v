module Stage2_Adder (
    input [107:0] unified_product_108,
    input         PD4_mode,
    input         PD2_mode,

    output [58:0] sum,
    output [58:0] carry
);

    //---------------------------------------------------------
    // 1. Path for PD4 (4-term): 4 x 27-bit -> 4-to-2 CSA
    //---------------------------------------------------------
    // In PD4, we only use the lower 27-30 bits of the logic.
    wire [29:0] pd4_pp0 = {3'b0, unified_product_108[26:0]};
    wire [29:0] pd4_pp1 = {3'b0, unified_product_108[53:27]};
    wire [29:0] pd4_pp2 = {3'b0, unified_product_108[80:54]};
    wire [29:0] pd4_pp3 = {3'b0, unified_product_108[107:81]};

    wire [29:0] s42, c42;
    assign s42 = pd4_pp0 ^ pd4_pp1 ^ pd4_pp2 ^ pd4_pp3;
    assign c42 = ((pd4_pp0 & pd4_pp1) | (pd4_pp2 & pd4_pp3) | ((pd4_pp0^pd4_pp1)&(pd4_pp2^pd4_pp3))) << 1;

    //---------------------------------------------------------
    // 2. Path for PD2 (2-term): 2 x 54-bit -> 4:2 + 3:2 CSA
    //---------------------------------------------------------
    // PP1 (bits 53:0) and PP3 (bits 107:54)
    wire [29:0] pd2_pp1_lo = unified_product_108[29:0];
    wire [29:0] pd2_pp3_lo = unified_product_108[83:54]; // bits 0-29 of PP3

    wire [28:0] pd2_pp1_hi = unified_product_108[53:30];
    wire [28:0] pd2_pp3_hi = unified_product_108[107:84]; // bits 30-53 of PP3

    // Lower Segment (4-to-2 used as 2-input adder)
    wire [29:0] s_lo = pd2_pp1_lo ^ pd2_pp3_lo;
    wire [29:0] c_lo = (pd2_pp1_lo & pd2_pp3_lo) << 1;

    // The Bridge: 1-bit Cin generated from the carry out of bit 29
    // In a CSA, the carry bit at index N is the carry INTO index N+1.
    wire pd2_cin = c_lo[29];

    // Upper Segment (3-to-2 CSA)
    // x = PP1_hi, y = PP3_hi, z = Bridge Carry
    wire [28:0] s_hi, c_hi;
    assign s_hi = pd2_pp1_hi ^ pd2_pp3_hi ^ {28'b0, pd2_cin};
    assign c_hi = ((pd2_pp1_hi & pd2_pp3_hi) | (pd2_pp1_hi & {28'b0, pd2_cin}) | (pd2_pp3_hi & {28'b0, pd2_cin})) << 1;

    //---------------------------------------------------------
    // 3. Final 59-bit Output Assignment
    //---------------------------------------------------------
    assign sum   = PD2_mode ? {s_hi, s_lo} : {29'b0, s42};
    assign carry = PD2_mode ? {c_hi, c_lo} : {29'b0, c42};

endmodule
