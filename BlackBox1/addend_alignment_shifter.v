module addend_alignment_shifter (

    input  [55:0]  C_mantissa,
    input  [31:0]  ExpDiff,
    input  [2:0]   Prec,

    output [162:0] Aligned_C

);

    //----------------------------------------------------------
    // Extend mantissa to CSA datapath width
    //----------------------------------------------------------
    wire [162:0] extended_C;

    assign extended_C = {C_mantissa, 107'b0};

    //----------------------------------------------------------
    // Shift amount (limit to datapath width)
    //----------------------------------------------------------
    wire [7:0] shift_amt;

    assign shift_amt = (ExpDiff > 8'd162) ? 8'd162 : ExpDiff[7:0];

    //----------------------------------------------------------
    // Right shift alignment
    //----------------------------------------------------------
    assign Aligned_C = extended_C >> shift_amt;

endmodule