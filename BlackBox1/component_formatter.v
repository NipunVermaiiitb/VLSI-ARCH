`timescale 1ns / 1ps

module component_formatter (

    input  [63:0] A_in,
    input  [63:0] B_in,
    input  [63:0] C_in,
    input  [2:0]  Prec,

    // Extracted sign outputs
    output        A_sign,
    output        B_sign,
    output        C_sign,

    // Extended exponent outputs (32-bit unified)
    output [31:0] A_exponent_ext,
    output [31:0] B_exponent_ext,
    output [31:0] C_exponent_ext,

    // Extended mantissa outputs (56-bit unified)
    output [55:0] A_mantissa_ext,
    output [55:0] B_mantissa_ext,
    output [55:0] C_mantissa_ext
);

    //----------------------------------------------------------
    // Precision encoding
    //----------------------------------------------------------
    parameter DP    = 3'b000;
    parameter SP    = 3'b001;
    parameter TF32  = 3'b010;
    parameter HP    = 3'b011;
    parameter BF16  = 3'b100;

    //----------------------------------------------------------
    // IEEE Field Extraction
    //----------------------------------------------------------
    wire [10:0] A_exponent;
    wire [10:0] B_exponent;
    wire [10:0] C_exponent;

    wire [51:0] A_mantissa;
    wire [51:0] B_mantissa;
    wire [51:0] C_mantissa;

    assign A_sign     = A_in[63];
    assign A_exponent = A_in[62:52];
    assign A_mantissa = A_in[51:0];

    assign B_sign     = B_in[63];
    assign B_exponent = B_in[62:52];
    assign B_mantissa = B_in[51:0];

    assign C_sign     = C_in[63];
    assign C_exponent = C_in[62:52];
    assign C_mantissa = C_in[51:0];

    //----------------------------------------------------------
    // Mantissa Extension Logic
    //----------------------------------------------------------
    reg [55:0] A_mant_ext;
    reg [55:0] B_mant_ext;
    reg [55:0] C_mant_ext;

    always @(*) begin
        case (Prec)

            DP: begin
                A_mant_ext = {1'b1, A_mantissa, 3'b000};
                B_mant_ext = {1'b1, B_mantissa, 3'b000};
                C_mant_ext = {1'b1, C_mantissa, 3'b000};
            end

            SP: begin
                A_mant_ext = {1'b1, A_mantissa[22:0], 31'b0};
                B_mant_ext = {1'b1, B_mantissa[22:0], 31'b0};
                C_mant_ext = {1'b1, C_mantissa[22:0], 31'b0};
            end

            TF32: begin
                A_mant_ext = {1'b1, A_mantissa[9:0], 42'b0};
                B_mant_ext = {1'b1, B_mantissa[9:0], 42'b0};
                C_mant_ext = {1'b1, C_mantissa[9:0], 42'b0};
            end

            HP: begin
                A_mant_ext = {1'b1, A_mantissa[9:0], 42'b0};
                B_mant_ext = {1'b1, B_mantissa[9:0], 42'b0};
                C_mant_ext = {1'b1, C_mantissa[9:0], 42'b0};
            end

            BF16: begin
                A_mant_ext = {1'b1, A_mantissa[6:0], 45'b0};
                B_mant_ext = {1'b1, B_mantissa[6:0], 45'b0};
                C_mant_ext = {1'b1, C_mantissa[6:0], 45'b0};
            end

            default: begin
                A_mant_ext = 56'd0;
                B_mant_ext = 56'd0;
                C_mant_ext = 56'd0;
            end
        endcase
    end

    assign A_mantissa_ext = A_mant_ext;
    assign B_mantissa_ext = B_mant_ext;
    assign C_mantissa_ext = C_mant_ext;

    //----------------------------------------------------------
    // Exponent Extension Logic
    //----------------------------------------------------------
    reg [31:0] A_exp_ext;
    reg [31:0] B_exp_ext;
    reg [31:0] C_exp_ext;

    always @(*) begin
        case (Prec)

            DP: begin
                A_exp_ext = {21'd0, A_exponent};
                B_exp_ext = {21'd0, B_exponent};
                C_exp_ext = {21'd0, C_exponent};
            end

            SP: begin
                A_exp_ext = {24'd0, A_exponent[7:0]};
                B_exp_ext = {24'd0, B_exponent[7:0]};
                C_exp_ext = {24'd0, C_exponent[7:0]};
            end

            TF32: begin
                A_exp_ext = {24'd0, A_exponent[7:0]};
                B_exp_ext = {24'd0, B_exponent[7:0]};
                C_exp_ext = {24'd0, C_exponent[7:0]};
            end

            HP: begin
                A_exp_ext = {27'd0, A_exponent[4:0]};
                B_exp_ext = {27'd0, B_exponent[4:0]};
                C_exp_ext = {27'd0, C_exponent[4:0]};
            end

            BF16: begin
                A_exp_ext = {24'd0, A_exponent[7:0]};
                B_exp_ext = {24'd0, B_exponent[7:0]};
                C_exp_ext = {24'd0, C_exponent[7:0]};
            end

            default: begin
                A_exp_ext = 32'd0;
                B_exp_ext = 32'd0;
                C_exp_ext = 32'd0;
            end
        endcase
    end

    assign A_exponent_ext = A_exp_ext;
    assign B_exponent_ext = B_exp_ext;
    assign C_exponent_ext = C_exp_ext;

endmodule