module csa3_32 (
    input  [31:0] x,
    input  [31:0] y,
    input  [31:0] z,
    output [31:0] sum,
    output [31:0] carry
);

    assign sum   = x ^ y ^ z;
    assign carry = ((x & y) | (x & z) | (y & z)) << 1;

endmodule

module mult14_radix4_booth (
    input  [13:0] a,
    input  [13:0] b,
    output [27:0] p
);

    // Radix-4 Booth uses overlapping 3-bit groups from {2'b00, b, 1'b0}
    // for unsigned operands. The extra leading zero makes the top group
    // recode as +1 (not +2) when b is all ones.
    wire [16:0] b_ext = {2'b00, b, 1'b0};
    wire [2:0] grp0 = b_ext[2:0];
    wire [2:0] grp1 = b_ext[4:2];
    wire [2:0] grp2 = b_ext[6:4];
    wire [2:0] grp3 = b_ext[8:6];
    wire [2:0] grp4 = b_ext[10:8];
    wire [2:0] grp5 = b_ext[12:10];
    wire [2:0] grp6 = b_ext[14:12];
    wire [2:0] grp7 = b_ext[16:14];

    function [31:0] booth_term;
        input [2:0] code;
        input [13:0] mul;
        reg signed [31:0] m;
        reg signed [31:0] t;
        begin
            m = $signed({18'd0, 1'b0, mul});
            case (code)
                3'b000,
                3'b111: t = 32'sd0;
                3'b001,
                3'b010: t = m;
                3'b011: t = m <<< 1;
                3'b100: t = -(m <<< 1);
                3'b101,
                3'b110: t = -m;
                default: t = 32'sd0;
            endcase
            booth_term = t;
        end
    endfunction

    wire [31:0] pp0 = booth_term(grp0, a) <<< 0;
    wire [31:0] pp1 = booth_term(grp1, a) <<< 2;
    wire [31:0] pp2 = booth_term(grp2, a) <<< 4;
    wire [31:0] pp3 = booth_term(grp3, a) <<< 6;
    wire [31:0] pp4 = booth_term(grp4, a) <<< 8;
    wire [31:0] pp5 = booth_term(grp5, a) <<< 10;
    wire [31:0] pp6 = booth_term(grp6, a) <<< 12;
    wire [31:0] pp7 = booth_term(grp7, a) <<< 14;

    // Two-level CSA compression tree followed by final CPA.
    wire [31:0] s0, c0;
    wire [31:0] s1, c1;
    wire [31:0] s2, c2;
    wire [31:0] s3, c3;
    wire [31:0] s4, c4;
    wire [31:0] s5, c5;

    csa3_32 u_csa0 (.x(pp0), .y(pp1), .z(pp2), .sum(s0), .carry(c0));
    csa3_32 u_csa1 (.x(pp3), .y(pp4), .z(pp5), .sum(s1), .carry(c1));
    csa3_32 u_csa2 (.x(s0),  .y(c0),  .z(s1),  .sum(s2), .carry(c2));
    csa3_32 u_csa3 (.x(c1),  .y(pp6), .z(pp7), .sum(s3), .carry(c3));
    csa3_32 u_csa4 (.x(s2),  .y(c2),  .z(s3),  .sum(s4), .carry(c4));
    csa3_32 u_csa5 (.x(s4),  .y(c4),  .z(c3),  .sum(s5), .carry(c5));

    wire [31:0] p_cpa = s5 + c5;

    assign p = p_cpa[27:0];

endmodule
