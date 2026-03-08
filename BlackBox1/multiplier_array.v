module low_cost_multiplier_array (

    input         clk,
    input         rst_n,

    input  [55:0] A_mantissa,
    input  [55:0] B_mantissa,

    input  [2:0]  Prec,
    input  [3:0]  Valid,

    input         PD_mode,
    input         PD2_mode,
    input         PD4_mode,
    input         Cnt0,

    output [111:0] partial_products

);

    //----------------------------------------------------------
    // Segment the operands into 14-bit lanes
    //----------------------------------------------------------

    wire [13:0] A0 = A_mantissa[13:0];
    wire [13:0] A1 = A_mantissa[27:14];
    wire [13:0] A2 = A_mantissa[41:28];
    wire [13:0] A3 = A_mantissa[55:42];

    wire [13:0] B0 = B_mantissa[13:0];
    wire [13:0] B1 = B_mantissa[27:14];
    wire [13:0] B2 = B_mantissa[41:28];
    wire [13:0] B3 = B_mantissa[55:42];

    wire en3 = Valid[3];
    wire en2 = Valid[2];
    wire en1 = Valid[1];
    wire en0 = Valid[0];

    wire en_top28 = en3 | en2;
    wire en_bot28 = en1 | en0;

    // DP iterative control
    wire dp_c0 = PD_mode & ~Cnt0;
    wire dp_c1 = PD_mode &  Cnt0;

    // Per-cell enables for operand gating (reduce switching activity)
    wire en_p00 = dp_c0 | (PD2_mode & en_bot28) | (PD4_mode & en0);
    wire en_p01 = dp_c0 | (PD2_mode & en_bot28);
    wire en_p10 = dp_c0 | (PD2_mode & en_bot28);
    wire en_p11 = dp_c0 | (PD2_mode & en_bot28) | (PD4_mode & en1);

    wire en_p22 = dp_c0 | (PD2_mode & en_top28) | (PD4_mode & en2);
    wire en_p23 = dp_c0 | (PD2_mode & en_top28);
    wire en_p32 = dp_c0 | (PD2_mode & en_top28);
    wire en_p33 = dp_c0 | (PD2_mode & en_top28) | (PD4_mode & en3);

    wire en_p02 = dp_c1;
    wire en_p03 = dp_c1;
    wire en_p12 = dp_c1;
    wire en_p13 = dp_c1;


    wire en_p20 = dp_c1;
    wire en_p21 = dp_c1;
    wire en_p30 = dp_c1;
    wire en_p31 = dp_c1;

    //----------------------------------------------------------
    // 14x14 multipliers (radix-4 Booth cells)
    //----------------------------------------------------------
    wire [27:0] p00, p01, p10, p11;
    wire [27:0] p22, p23, p32, p33;
    wire [27:0] p02, p03, p12, p13;
    wire [27:0] p20, p21, p30, p31;

    mult14_radix4_booth u_mul00 (.a(en_p00 ? A0 : 14'd0), .b(en_p00 ? B0 : 14'd0), .p(p00));
    mult14_radix4_booth u_mul01 (.a(en_p01 ? A0 : 14'd0), .b(en_p01 ? B1 : 14'd0), .p(p01));
    mult14_radix4_booth u_mul10 (.a(en_p10 ? A1 : 14'd0), .b(en_p10 ? B0 : 14'd0), .p(p10));
    mult14_radix4_booth u_mul11 (.a(en_p11 ? A1 : 14'd0), .b(en_p11 ? B1 : 14'd0), .p(p11));

    mult14_radix4_booth u_mul22 (.a(en_p22 ? A2 : 14'd0), .b(en_p22 ? B2 : 14'd0), .p(p22));
    mult14_radix4_booth u_mul23 (.a(en_p23 ? A2 : 14'd0), .b(en_p23 ? B3 : 14'd0), .p(p23));
    mult14_radix4_booth u_mul32 (.a(en_p32 ? A3 : 14'd0), .b(en_p32 ? B2 : 14'd0), .p(p32));
    mult14_radix4_booth u_mul33 (.a(en_p33 ? A3 : 14'd0), .b(en_p33 ? B3 : 14'd0), .p(p33));

    mult14_radix4_booth u_mul02 (.a(en_p02 ? A0 : 14'd0), .b(en_p02 ? B2 : 14'd0), .p(p02));
    mult14_radix4_booth u_mul03 (.a(en_p03 ? A0 : 14'd0), .b(en_p03 ? B3 : 14'd0), .p(p03));
    mult14_radix4_booth u_mul12 (.a(en_p12 ? A1 : 14'd0), .b(en_p12 ? B2 : 14'd0), .p(p12));
    mult14_radix4_booth u_mul13 (.a(en_p13 ? A1 : 14'd0), .b(en_p13 ? B3 : 14'd0), .p(p13));

    mult14_radix4_booth u_mul20 (.a(en_p20 ? A2 : 14'd0), .b(en_p20 ? B0 : 14'd0), .p(p20));
    mult14_radix4_booth u_mul21 (.a(en_p21 ? A2 : 14'd0), .b(en_p21 ? B1 : 14'd0), .p(p21));
    mult14_radix4_booth u_mul30 (.a(en_p30 ? A3 : 14'd0), .b(en_p30 ? B0 : 14'd0), .p(p30));
    mult14_radix4_booth u_mul31 (.a(en_p31 ? A3 : 14'd0), .b(en_p31 ? B1 : 14'd0), .p(p31));

    // PD4 direct products with lane-level valid gating
    wire [27:0] P0 = en0 ? p00 : 28'd0;
    wire [27:0] P1 = en1 ? p11 : 28'd0;
    wire [27:0] P2 = en2 ? p22 : 28'd0;
    wire [27:0] P3 = en3 ? p33 : 28'd0;

    // 28x28 products built from 14x14 terms
    wire [55:0] prod_bot28 = ({28'd0, p00}) + ({p01, 14'd0}) + ({p10, 14'd0}) + ({p11, 28'd0});
    wire [55:0] prod_top28 = ({28'd0, p22}) + ({p23, 14'd0}) + ({p32, 14'd0}) + ({p33, 28'd0});

    wire [55:0] prod_lh28  = ({28'd0, p02}) + ({p03, 14'd0}) + ({p12, 14'd0}) + ({p13, 28'd0});
    wire [55:0] prod_hl28  = ({28'd0, p20}) + ({p21, 14'd0}) + ({p30, 14'd0}) + ({p31, 28'd0});

    wire [111:0] dp_base_cycle0  = ({56'd0, prod_bot28}) + ({prod_top28, 56'd0});
    wire [111:0] dp_cross_cycle1 = ({28'd0, (prod_lh28 + prod_hl28), 28'd0});

    reg [111:0] dp_base_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dp_base_reg <= 112'd0;
        end
        else if (PD_mode && (Cnt0 == 1'b0)) begin
            // Cycle0 stores LL and HH terms; cycle1 adds cross terms.
            dp_base_reg <= dp_base_cycle0;
        end
    end

    //----------------------------------------------------------
    // Combine depending on mode
    //----------------------------------------------------------

    reg [111:0] result;

    always @(*) begin

        //------------------------------------------------------
        // DP MODE (full 56x56 multiply)
        //------------------------------------------------------
        if (PD_mode) begin
            if (Cnt0) begin
                result = dp_base_reg + dp_cross_cycle1;
            end
            else begin
                result = 112'd0;
            end
        end
        ///
        // A, B = {a3, a2, a1, a0} , {b3, b2, b1, b0}
        // {a3, a2, a1, a0} * {b3, b2, b1, b0}
        // a3*b3 shifted + a3*b2 shifted + a3*b1 + a3*b0 + a2*b3 + a2*b2 + a2*b1 + a2*b0
        // + a1*b3 + a1*b2 + a1*b1 + a1*b0 + a0*b3 + a0*b2 + a0*b1 + a0*b0

        //------------------------------------------------------
        // PD2 MODE (two 28x28 multiplies)
        //------------------------------------------------------
        else if (PD2_mode) begin
            result = { (en_top28 ? prod_top28 : 56'd0),
                       (en_bot28 ? prod_bot28 : 56'd0) };
        end

        //------------------------------------------------------
        // PD4 MODE (four 14x14 multiplies)
        //------------------------------------------------------
        // A3, A2, A1, A0
        // B3, B2. B1, B0
        else if (PD4_mode) begin
            result = {P3, P2, P1, P0};
        end

        else begin
            result = 112'd0;
        end

    end

    assign partial_products = result;

endmodule