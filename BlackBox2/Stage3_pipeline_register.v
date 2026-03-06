module Stage3_Pipeline_Register (

    input clk,
    input rst_n,

    //------------------------------------
    // Inputs from Stage 3 logic
    //------------------------------------

    input  [162:0] Add_Rslt_in,
    input          Result_sign_in,
    input  [7:0]   LZA_CNT_in,

    input  [2:0]   Prec_in,
    input  [3:0]   Valid_in,

    //------------------------------------
    // Outputs to Stage 4
    //------------------------------------

    output reg [162:0] Add_Rslt_out,
    output reg         Result_sign_out,
    output reg [7:0]   LZA_CNT_out,

    output reg [2:0]   Prec_out,
    output reg [3:0]   Valid_out

);

always @(posedge clk or negedge rst_n) begin

    if(!rst_n) begin

        Add_Rslt_out <= 0;
        Result_sign_out <= 0;
        LZA_CNT_out <= 0;

        Prec_out <= 0;
        Valid_out <= 0;

    end
    else begin

        Add_Rslt_out <= Add_Rslt_in;
        Result_sign_out <= Result_sign_in;
        LZA_CNT_out <= LZA_CNT_in;

        Prec_out <= Prec_in;
        Valid_out <= Valid_in;

    end

end

endmodule