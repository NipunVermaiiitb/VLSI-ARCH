`timescale 1ns / 1ps

// Stage 4 Pipeline Output Register
// Captures the final result at the output boundary of Stage 4.

module Stage4_Pipeline_Register (

    input clk,
    input rst_n,

    //--------------------------------------------------
    // Inputs from Stage 4 logic
    //--------------------------------------------------

    input  [63:0] Result_in,
    input  [3:0]  Valid_in,
    input         Result_sign_in,

    //--------------------------------------------------
    // Registered outputs
    //--------------------------------------------------

    output reg [63:0] Result_out,
    output reg [3:0]  Valid_out,
    output reg        Result_sign_out

);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            Result_out      <= 64'd0;
            Valid_out       <= 4'd0;
            Result_sign_out <= 1'b0;
        end else begin
            Result_out      <= Result_in;
            Valid_out       <= Valid_in;
            Result_sign_out <= Result_sign_in;
        end
    end

endmodule
