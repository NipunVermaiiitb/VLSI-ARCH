module Stage2_Pipeline_Register (

    input clk,
    input rst_n,
    input enable,            // Capture enable (tied to Stage1 valid_out)

    //------------------------------------------------
    // Inputs from Stage 2
    //------------------------------------------------

    input [162:0] Sum_in,
    input [162:0] Carry_in,

    input [162:0] Aligned_C_in,    // UPDATED: Single unified 163-bit bus

    input [3:0]   Sign_AB_in,
    input [3:0]   Sign_C_in,       // ADDED: Forwarded from Stage 1
    input [1:0]   Sticky_C_in,     // ADDED: Sticky bits for Stage 3 rounding

    input [2:0]   Prec_in,
    input [3:0]   Valid_in,
    input         PD_mode_in,

    //------------------------------------------------
    // Outputs to Stage 3
    //------------------------------------------------

    output reg [162:0] Sum_out,
    output reg [162:0] Carry_out,

    output reg [162:0] Aligned_C_out,

    output reg [3:0]   Sign_AB_out,
    output reg [3:0]   Sign_C_out,
    output reg [1:0]   Sticky_C_out,

    output reg [2:0]   Prec_out,
    output reg [3:0]   Valid_out,
    output reg         PD_mode_out
);

always @(posedge clk or negedge rst_n) begin

    if(!rst_n) begin

        Sum_out       <= 163'd0;
        Carry_out     <= 163'd0;

        Aligned_C_out <= 163'd0;

        Sign_AB_out   <= 4'd0;
        Sign_C_out    <= 4'd0;
        Sticky_C_out  <= 2'd0;

        Prec_out      <= 3'd0;
        Valid_out     <= 4'd0;

        PD_mode_out   <= 1'b0;

    end else if (enable) begin
        // Enabled capture: only capture when valid data is present
        // For DP: enable = valid_out from Stage1 (high only on cnt=1)
        // For non-DP: enable = always 1
        Sum_out       <= Sum_in;
        Carry_out     <= Carry_in;

        Aligned_C_out <= Aligned_C_in;

        Sign_AB_out   <= Sign_AB_in;
        Sign_C_out    <= Sign_C_in;
        Sticky_C_out  <= Sticky_C_in;

        Prec_out      <= Prec_in;
        Valid_out     <= Valid_in;

        PD_mode_out   <= PD_mode_in;

    end

end

endmodule
