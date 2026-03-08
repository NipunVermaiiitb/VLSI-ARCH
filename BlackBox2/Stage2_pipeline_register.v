module Stage2_Pipeline_Register (

    input clk,
    input rst_n,

    //------------------------------------------------
    // Inputs from Stage 2
    //------------------------------------------------

    input [162:0] Sum_in,
    input [162:0] Carry_in,

    input [162:0] Aligned_C_dual_in,
    input [162:0] Aligned_C_high_in,

    input [3:0]   Sign_AB_in,

    input [2:0]   Prec_in,
    input [3:0]   Valid_in,

    input         PD_mode_in,

    //------------------------------------------------
    // Outputs to Stage 3
    //------------------------------------------------

    output reg [162:0] Sum_out,
    output reg [162:0] Carry_out,

    output reg [162:0] Aligned_C_dual_out,
    output reg [162:0] Aligned_C_high_out,

    output reg [3:0]   Sign_AB_out,

    output reg [2:0]   Prec_out,
    output reg [3:0]   Valid_out,

    output reg         PD_mode_out
);

always @(posedge clk or negedge rst_n) begin

    if(!rst_n) begin

        Sum_out <= 0;
        Carry_out <= 0;

        Aligned_C_dual_out <= 0;
        Aligned_C_high_out <= 0;

        Sign_AB_out <= 0;

        Prec_out <= 0;
        Valid_out <= 0;

        PD_mode_out <= 0;

    end else begin
        // Unconditional capture (no pipeline stalls)
        // Valid signal flows as metadata; Stage 3 decides to use data based on Valid_out
        Sum_out <= Sum_in;
        Carry_out <= Carry_in;

        Aligned_C_dual_out <= Aligned_C_dual_in;
        Aligned_C_high_out <= Aligned_C_high_in;

        Sign_AB_out <= Sign_AB_in;

        Prec_out <= Prec_in;
        Valid_out <= Valid_in;

        PD_mode_out <= PD_mode_in;

    end

end

endmodule