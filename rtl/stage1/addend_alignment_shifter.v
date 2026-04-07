`timescale 1ns / 1ps

module addend_alignment_shifter (

    input  [55:0]  C_mantissa,
    input  [31:0]  ExpDiff,
    input  [2:0]   Prec,
    input          Para,

    // Two independent aligned C paths:
    //   Aligned_C_hi = sht_rc1: high-C or C1 (Para/DPDAC) or upper half (DP FMA)
    //   Aligned_C_lo = sht_rc0: low-C  or C0 (Para/DPDAC) or lower half (DP FMA)
    output [162:0] Aligned_C_hi,
    output [162:0] Aligned_C_lo

);

    //----------------------------------------------------------
    // Precision encoding
    //----------------------------------------------------------
    parameter HP    = 3'b000;
    parameter BF16  = 3'b001;
    parameter TF32  = 3'b010;
    parameter SP    = 3'b011;
    parameter DP    = 3'b100;

    //----------------------------------------------------------
    // ExpDiff packs two Stage1 ASCs: {ASC_C1, ASC_C0}
    //----------------------------------------------------------
    wire [15:0] asc_c1_raw = ExpDiff[31:16];
    wire [15:0] asc_c0_raw = ExpDiff[15:0];

    wire [7:0] asc_c1 = (asc_c1_raw > 16'd162) ? 8'd162 : asc_c1_raw[7:0];
    wire [7:0] asc_c0 = (asc_c0_raw > 16'd162) ? 8'd162 : asc_c0_raw[7:0];

    reg [162:0] man_c_hi_w;
    reg [162:0] man_c_lo_w;

    always @(*) begin
        // By default, zero everything
        man_c_hi_w = 163'd0;
        man_c_lo_w = 163'd0;
        case (Prec)
            DP: begin
                // Product MSB at 160. C implicit 1 at 52. Shift: 160 - 52 = 108.
                man_c_hi_w = {C_mantissa[54:0], 108'd0};
            end
            SP: begin
                // Product MSBs at 102. C implicit 1 at local 23. Shift: 102 - 23 = 79.
                man_c_hi_w = {56'd0, C_mantissa[55:28], 79'd0};
                man_c_lo_w = {56'd0, C_mantissa[27:0],  79'd0};
            end
            TF32: begin
                // Product MSBs at 76. C implicit 1 at local 10. Shift: 76 - 10 = 66.
                man_c_hi_w = {83'd0, C_mantissa[41:28], 66'd0};
                man_c_lo_w = {83'd0, C_mantissa[13:0],  66'd0};
            end
            HP: begin
                // Product MSB at 76. C implicit 1 at local 10. Shift: 76 - 10 = 66.
                // HP is a single vector dot product, uses single C (C_lo).
                man_c_lo_w = {83'd0, C_mantissa[13:0],  66'd0};
            end
            BF16: begin
                // Product MSB at 70. C implicit 1 at local 7. Shift: 70 - 7 = 63.
                man_c_lo_w = {86'd0, C_mantissa[13:0],  63'd0};
            end
            default: ;
        endcase
    end

    wire [162:0] man_c_hi = man_c_hi_w;
    wire [162:0] man_c_lo = man_c_lo_w;

    // DP FMA (single C, Para=0): reuse high path as data_pad so the full
    // 163-bit C value feeds both shifter stages correctly.
    // However, since man_c_hi is now a 163-bit vector representing the FULL C,
    // we don't need a data_pad concatenation.
    // man_c_hi handles the full width. DP FMA will just use sht_rc1.

    //----------------------------------------------------------
    // Dual alignment shifters (controlled by ASC_C1 / ASC_C0)
    //----------------------------------------------------------
    wire [162:0] sht_rc1;
    wire [162:0] sht_rc0;

    assign sht_rc1 = man_c_hi >> asc_c1;
    assign sht_rc0 = (Prec == DP && !Para) ? (man_c_hi >> asc_c0) : (man_c_lo >> asc_c0);

    //----------------------------------------------------------
    // Output both paths independently.
    // Stage2_Top decides how to combine them per mode:
    //   DP FMA (PD_mode, Para=0) : use merged {hi[162:81], lo[80:0]} as one C on one CSA input
    //   DPDAC  (Para=1 / PD2 / PD4): feed hi→CSA.in3, lo→CSA.in2 independently
    //----------------------------------------------------------
    assign Aligned_C_hi = sht_rc1;
    assign Aligned_C_lo = sht_rc0;

endmodule