module low_cost_multiplier_array (

    input  [55:0] A_mantissa,
    input  [55:0] B_mantissa,

    input  [2:0]  Prec,
    input  [3:0]  Valid,

    input         PD_mode,
    input         PD2_mode,
    input         PD4_mode,

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

    //----------------------------------------------------------
    // 14x14 multipliers
    //----------------------------------------------------------

    wire [27:0] P0 = Valid[0] ? (A0 * B0) : 28'd0;
    wire [27:0] P1 = Valid[1] ? (A1 * B1) : 28'd0;
    wire [27:0] P2 = Valid[2] ? (A2 * B2) : 28'd0;
    wire [27:0] P3 = Valid[3] ? (A3 * B3) : 28'd0;

    //----------------------------------------------------------
    // Combine depending on mode
    //----------------------------------------------------------

    reg [111:0] result;

    always @(*) begin

        //------------------------------------------------------
        // DP MODE (full 56x56 multiply)
        //------------------------------------------------------
        if (PD_mode) begin
            result = A_mantissa * B_mantissa;
        end

        //------------------------------------------------------
        // PD2 MODE (two 28x28 multiplies)
        //------------------------------------------------------
        else if (PD2_mode) begin
            result = {56'd0, ( {A3,A2} * {B3,B2} ) } |
                     { ( {A1,A0} * {B1,B0} ), 56'd0 };
        end

        //------------------------------------------------------
        // PD4 MODE (four 14x14 multiplies)
        //------------------------------------------------------
        else if (PD4_mode) begin
            result = {P3, P2, P1, P0};
        end

        else begin
            result = 112'd0;
        end

    end

    assign partial_products = result;

endmodule