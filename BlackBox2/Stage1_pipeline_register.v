module Stage1_Pipeline_Register (

    input clk,
    input rst_n,

    //------------------------------------------------
    // Inputs from Stage 1 modules
    //------------------------------------------------

    input  [111:0] partial_products_in,
    input  [31:0]  ExpDiff_in,
    input  [31:0]  MaxExp_in,

    input  [162:0] Aligned_C_in,

    input  [3:0]   Sign_AB_in,

    input  [2:0]   Prec_in,
    input  [3:0]   Valid_in,

    input          PD_mode_in,
    input          PD2_mode_in,
    input          PD4_mode_in,

    //------------------------------------------------
    // Outputs to Stage 2
    //------------------------------------------------

    output reg [111:0] partial_products_out,
    output reg [31:0]  ExpDiff_out,
    output reg [31:0]  MaxExp_out,

    output reg [162:0] Aligned_C_out,

    output reg [3:0]   Sign_AB_out,

    output reg [2:0]   Prec_out,
    output reg [3:0]   Valid_out,

    output reg         PD_mode_out,
    output reg         PD2_mode_out,
    output reg         PD4_mode_out

);

always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

        partial_products_out <= 112'd0;
        ExpDiff_out          <= 32'd0;
        MaxExp_out           <= 32'd0;

        Aligned_C_out        <= 163'd0;

        Sign_AB_out          <= 4'd0;

        Prec_out             <= 3'd0;
        Valid_out            <= 4'd0;

        PD_mode_out          <= 1'b0;
        PD2_mode_out         <= 1'b0;
        PD4_mode_out         <= 1'b0;

    end
    else begin

        partial_products_out <= partial_products_in;
        ExpDiff_out          <= ExpDiff_in;
        MaxExp_out           <= MaxExp_in;

        Aligned_C_out        <= Aligned_C_in;

        Sign_AB_out          <= Sign_AB_in;

        Prec_out             <= Prec_in;
        Valid_out            <= Valid_in;

        PD_mode_out          <= PD_mode_in;
        PD2_mode_out         <= PD2_mode_in;
        PD4_mode_out         <= PD4_mode_in;

    end

end

endmodule