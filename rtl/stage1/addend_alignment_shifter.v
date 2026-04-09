`timescale 1ns / 1ps

module addend_alignment_shifter (
    input  [55:0]  C_mantissa, // Raw bits {C1, C0} or {DP_Man}
    input  [31:0]  ExpDiff,    // {ASC_C1[15:0], ASC_C0[15:0]} — includes format constant
    input  [2:0]   Prec,
    input          Para,
    input  [1:0]   Sign_Inv,   // Per-lane sign inversion flags

    output [162:0] Aligned_C,
    output [1:0]   Sticky_Bits
);

    parameter DP = 3'b100;

    wire [7:0] asc1 = ExpDiff[23:16];
    wire [7:0] asc0 = ExpDiff[7:0];

    // Initial Placement
    reg [162:0] c_initial;
    always @(*) begin
        c_initial = 163'd0;
        if (Prec == DP && !Para) begin
            c_initial[162:110] = C_mantissa[52:0];
        end else begin
            c_initial[162:135] = C_mantissa[55:28]; // C1 upper window (starts at 162)
            c_initial[108:81]  = C_mantissa[27:0];  // C0 lower window (starts at 108)
        end
    end

    // Right-shift logic (DP Unified vs SIMD Split)
    wire [162:0] shifted_result;
    
    // Unified shift for DP (163-bit)
    wire [162:0] dp_shifted = c_initial >> (asc0[7] ? 8'd128 : asc0[6:0]);

    // Split shift for SIMD: Separation at bit 109
    wire [53:0]  c_hi_window = c_initial[162:109];
    wire [108:0] c_lo_window = c_initial[108:0];
    wire [53:0]  simd_hi_shifted = c_hi_window >> asc1[5:0];
    wire [108:0] simd_lo_shifted = c_lo_window >> asc0[6:0];
    wire [162:0] simd_shifted = {simd_hi_shifted, simd_lo_shifted};

    assign shifted_result = (Prec == DP) ? dp_shifted : simd_shifted;

    // Sticky Bits (approximate for now)
    assign Sticky_Bits[0] = (asc0 > 8'd0);
    assign Sticky_Bits[1] = (asc1 > 8'd0);

    // One's Complement Inversion: Separate by lane
    wire [162:0] inverted;
    assign inverted[162:109] = Sign_Inv[1] ? ~shifted_result[162:109] : shifted_result[162:109];
    assign inverted[108:0]   = Sign_Inv[0] ? ~shifted_result[108:0]   : shifted_result[108:0];

    assign Aligned_C = inverted;

endmodule
