`timescale 1ns / 1ps

module component_formatter (

    input  [63:0] A_in,
    input  [63:0] B_in,
    input  [63:0] C_in,
    input  [2:0]  Prec,
    input [3:0]  Valid,

    // Extracted sign outputs
    output  [3:0]      A_sign,
    output  [3:0]      B_sign,
    output  [3:0]      C_sign,

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
    parameter DP    = 3'b100;
    parameter SP    = 3'b011;
    parameter TF32  = 3'b010;
    parameter HP    = 3'b000;
    parameter BF16  = 3'b001;
    //----------------------------------
    // Valid PD_mode mapping
    //----------------------------------
    parameter PD4_mode = 4'b1111; // All lanes valid for BF16/HP
    parameter PD2_mode = 4'b0101; // Only lower 2 lanes valid for SP/TF32
    parameter PD_mode = 4'b0001; // Only lowest lane valid for DP

    wire en_seg3 = Valid[3]; // Controls bits 55:42 (MS segment)
    wire en_seg2 = Valid[2]; // Controls bits 41:28
    wire en_seg1 = Valid[1]; // Controls bits 27:14
    wire en_seg0 = Valid[0]; // Controls bits 13:0  (LS segment)

    wire en_top28 = en_seg3 | en_seg2;
    wire en_bot28 = en_seg1 | en_seg0;
    wire en_dp56  = en_seg3 | en_seg2 | en_seg1 | en_seg0;

    assign A_sign = {A_in[63] & en_seg3, A_in[47] & en_seg2, A_in[31] & en_seg1, A_in[15] & en_seg0};
    assign B_sign = {B_in[63] & en_seg3, B_in[47] & en_seg2, B_in[31] & en_seg1, B_in[15] & en_seg0};
    assign C_sign = {C_in[63] & en_seg3, C_in[47] & en_seg2, C_in[31] & en_seg1, C_in[15] & en_seg0};

    //----------------------------------------------------------
    // Mantissa Extension Logic
    //----------------------------------------------------------
    reg [55:0] A_mant_ext;
    reg [55:0] B_mant_ext;
    reg [55:0] C_mant_ext;

    always @(*) begin
        A_mant_ext = 56'd0;
        B_mant_ext = 56'd0;
        C_mant_ext = 56'd0;

        case (Prec)

            DP: begin
                if (en_dp56) begin
                    // 56-bit segment: 3 pad bits + (hidden 1 + 52-bit fraction)
                    A_mant_ext = {3'b000, (|A_in[62:52]), A_in[51:0]};
                    B_mant_ext = {3'b000, (|B_in[62:52]), B_in[51:0]};
                    C_mant_ext = {3'b000, (|C_in[62:52]), C_in[51:0]};
                end
            end

            SP: begin
                if (en_top28 || en_bot28) begin
                    // Two 28-bit segments: each is 4 pad bits + (hidden 1 + 23-bit fraction)
                    A_mant_ext = { (en_top28 ? {4'b0000, (|A_in[62:55]), A_in[54:32]} : 28'd0),
                                   (en_bot28 ? {4'b0000, (|A_in[30:23]), A_in[22:0]}  : 28'd0) };
                    B_mant_ext = { (en_top28 ? {4'b0000, (|B_in[62:55]), B_in[54:32]} : 28'd0),
                                   (en_bot28 ? {4'b0000, (|B_in[30:23]), B_in[22:0]}  : 28'd0) };
                    C_mant_ext = { (en_top28 ? {4'b0000, (|C_in[62:55]), C_in[54:32]} : 28'd0),
                                   (en_bot28 ? 
                                   {4'b0000, (|C_in[30:23]), C_in[22:0]}  : 28'd0) };
                end
            end

            TF32: begin
                if (en_top28 || en_bot28) begin
                    // Two 28-bit segments: each is 17 pad bits + (hidden 1 + lower 10 fraction bits)
                    A_mant_ext = { (en_top28 ? {17'b0, (|A_in[62:55]), A_in[41:32]} : 28'd0),
                                   (en_bot28 ? {17'b0, (|A_in[30:23]), A_in[9:0]}   : 28'd0) };
                    B_mant_ext = { (en_top28 ? {17'b0, (|B_in[62:55]), B_in[41:32]} : 28'd0),
                                   (en_bot28 ? {17'b0, (|B_in[30:23]), B_in[9:0]}   : 28'd0) };
                    C_mant_ext = { (en_top28 ? {17'b0, (|C_in[62:55]), C_in[41:32]} : 28'd0),
                                   (en_bot28 ? {17'b0, (|C_in[30:23]), C_in[9:0]}   : 28'd0) };
                end
            end

            HP: begin
                if (en_seg3 || en_seg2 || en_seg1 || en_seg0) begin
                    // Four 14-bit segments: each is 3 pad bits + (hidden 1 + 10-bit fraction)
                    A_mant_ext = { (en_seg3 ? {3'b000, (|A_in[62:58]), A_in[57:48]} : 14'd0),
                                   (en_seg2 ? {3'b000, (|A_in[46:42]), A_in[41:32]} : 14'd0),
                                   (en_seg1 ? {3'b000, (|A_in[30:26]), A_in[25:16]} : 14'd0),
                                   (en_seg0 ? {3'b000, (|A_in[14:10]), A_in[9:0]}   : 14'd0) };
                    B_mant_ext = { (en_seg3 ? {3'b000, (|B_in[62:58]), B_in[57:48]} : 14'd0),
                                   (en_seg2 ? {3'b000, (|B_in[46:42]), B_in[41:32]} : 14'd0),
                                   (en_seg1 ? {3'b000, (|B_in[30:26]), B_in[25:16]} : 14'd0),
                                   (en_seg0 ? {3'b000, (|B_in[14:10]), B_in[9:0]}   : 14'd0) };
                    C_mant_ext = { (en_seg3 ? {3'b000, (|C_in[62:58]), C_in[57:48]} : 14'd0),
                                   (en_seg2 ? {3'b000, (|C_in[46:42]), C_in[41:32]} : 14'd0),
                                   (en_seg1 ? {3'b000, (|C_in[30:26]), C_in[25:16]} : 14'd0),
                                   (en_seg0 ? {3'b000, (|C_in[14:10]), C_in[9:0]}   : 14'd0) };
                end
            end

            BF16: begin
                if (en_seg3 || en_seg2 || en_seg1 || en_seg0) begin
                    // Four 14-bit segments: each is 6 pad bits + (hidden 1 + 7-bit fraction)
                    A_mant_ext = { (en_seg3 ? {6'b000000, (|A_in[62:55]), A_in[54:48]} : 14'd0),
                                   (en_seg2 ? {6'b000000, (|A_in[46:39]), A_in[38:32]} : 14'd0),
                                   (en_seg1 ? {6'b000000, (|A_in[30:23]), A_in[22:16]} : 14'd0),
                                   (en_seg0 ? {6'b000000, (|A_in[14:7]), A_in[6:0]}   : 14'd0) };
                    B_mant_ext = { (en_seg3 ? {6'b000000, (|B_in[62:55]), B_in[54:48]} : 14'd0),
                                   (en_seg2 ? {6'b000000, (|B_in[46:39]), B_in[38:32]} : 14'd0),
                                   (en_seg1 ? {6'b000000, (|B_in[30:23]), B_in[22:16]} : 14'd0),
                                   (en_seg0 ? {6'b000000, (|B_in[14:7]), B_in[6:0]}   : 14'd0) };
                    C_mant_ext = { (en_seg3 ? {6'b000000, (|C_in[62:55]), C_in[54:48]} : 14'd0),
                                   (en_seg2 ? {6'b000000, (|C_in[46:39]), C_in[38:32]} : 14'd0),
                                   (en_seg1 ? {6'b000000, (|C_in[30:23]), C_in[22:16]} : 14'd0),
                                   (en_seg0 ? {6'b000000, (|C_in[14:7]), C_in[6:0]}   : 14'd0) };
                end
            end

            default: ;
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
        A_exp_ext = 32'd0;
        B_exp_ext = 32'd0;
        C_exp_ext = 32'd0;

        case (Prec)

            DP: begin
                if (en_dp56) begin
                    A_exp_ext = {21'd0, A_in[62:52]};
                    B_exp_ext = {21'd0, B_in[62:52]};
                    C_exp_ext = {21'd0, C_in[62:52]};
                end
            end

            SP: begin
                A_exp_ext = { (en_top28 ? A_in[62:55] : 8'd0), 8'd0,
                              (en_bot28 ? A_in[30:23] : 8'd0), 8'd0 };
                B_exp_ext = { (en_top28 ? B_in[62:55] : 8'd0), 8'd0,
                              (en_bot28 ? B_in[30:23] : 8'd0), 8'd0 };
                C_exp_ext = { (en_top28 ? C_in[62:55] : 8'd0), 8'd0,
                              (en_bot28 ? C_in[30:23] : 8'd0), 8'd0 };
            end

            TF32: begin
                A_exp_ext = { (en_top28 ? A_in[62:55] : 8'd0), 8'd0,
                              (en_bot28 ? A_in[30:23] : 8'd0), 8'd0 };
                B_exp_ext = { (en_top28 ? B_in[62:55] : 8'd0), 8'd0,
                              (en_bot28 ? B_in[30:23] : 8'd0), 8'd0 };
                C_exp_ext = { (en_top28 ? C_in[62:55] : 8'd0), 8'd0,
                              (en_bot28 ? C_in[30:23] : 8'd0), 8'd0 };
            end

            HP: begin
                A_exp_ext = { (en_seg3 ? {3'b000, A_in[62:58]} : 8'd0),
                              (en_seg2 ? {3'b000, A_in[46:42]} : 8'd0),
                              (en_seg1 ? {3'b000, A_in[30:26]} : 8'd0),
                              (en_seg0 ? {3'b000, A_in[14:10]} : 8'd0) };
                B_exp_ext = { (en_seg3 ? {3'b000, B_in[62:58]} : 8'd0),
                              (en_seg2 ? {3'b000, B_in[46:42]} : 8'd0),
                              (en_seg1 ? {3'b000, B_in[30:26]} : 8'd0),
                              (en_seg0 ? {3'b000, B_in[14:10]} : 8'd0) };
                C_exp_ext = { (en_seg3 ? {3'b000, C_in[62:58]} : 8'd0),
                              (en_seg2 ? {3'b000, C_in[46:42]} : 8'd0),
                              (en_seg1 ? {3'b000, C_in[30:26]} : 8'd0),
                              (en_seg0 ? {3'b000, C_in[14:10]} : 8'd0) };
            end

            BF16: begin
                A_exp_ext = { (en_seg3 ? A_in[62:55] : 8'd0),
                              (en_seg2 ? A_in[46:39] : 8'd0),
                              (en_seg1 ? A_in[30:23] : 8'd0),
                              (en_seg0 ? A_in[14:7]  : 8'd0) };
                B_exp_ext = { (en_seg3 ? B_in[62:55] : 8'd0),
                              (en_seg2 ? B_in[46:39] : 8'd0),
                              (en_seg1 ? B_in[30:23] : 8'd0),
                              (en_seg0 ? B_in[14:7]  : 8'd0) };
                C_exp_ext = { (en_seg3 ? C_in[62:55] : 8'd0),
                              (en_seg2 ? C_in[46:39] : 8'd0),
                              (en_seg1 ? C_in[30:23] : 8'd0),
                              (en_seg0 ? C_in[14:7]  : 8'd0) };
            end

            default: ;
        endcase
    end

    assign A_exponent_ext = A_exp_ext;
    assign B_exponent_ext = B_exp_ext;
    assign C_exponent_ext = C_exp_ext;

endmodule