module addend_alignment_shifter (

    input  [55:0]  C_mantissa,
    input  [31:0]  ExpDiff,
    input  [2:0]   Prec,
    input          Para,

    output [162:0] Aligned_C

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

    //----------------------------------------------------------
    // Unified C placement (Stage1): ManC is pre-placed left of
    // product domain, then two parallel shifters align C1/C0.
    //----------------------------------------------------------
    wire [162:0] man_c_unified;
    wire [81:0]  man_c_hi;
    wire [80:0]  man_c_lo;
    wire [81:0]  data_pad;

    // Keep C on the high side so right-shift aligns down into product region.
    assign man_c_unified = {C_mantissa, 107'd0};
    
    // Para mode: C_mantissa = {C1[27:0], C0[27:0]} - split for independent alignment
    // Normal mode: single C value in upper path
    assign man_c_hi = (Para && Prec == DP) ? {C_mantissa[55:28], 54'd0} : man_c_unified[162:81];
    assign man_c_lo = (Para && Prec == DP) ? {C_mantissa[27:0], 53'd0}  : man_c_unified[80:0];

    // From paper flow: DP path can reuse high part as datapad for C0 path (only when Para=0 AND regular DP)
    // Note: DP Para mode uses independent paths, so no datapad reuse
    assign data_pad = (Prec == DP && !Para) ? man_c_hi : 82'd0;

    //----------------------------------------------------------
    // Dual alignment shifters controlled by ASC_C1 / ASC_C0
    //----------------------------------------------------------
    wire [162:0] sht_rc1;
    wire [162:0] sht_rc0;

    // Place man_c_hi on the upper side before right-shift so [162:81] slice
    // retains aligned payload for small/medium ASC values.
    assign sht_rc1 = ({man_c_hi, 81'd0}) >> asc_c1;
    assign sht_rc0 = ({data_pad, man_c_lo}) >> asc_c0;

    //----------------------------------------------------------
    // Merge two aligned paths into one 163-bit addend vector
    //----------------------------------------------------------
    assign Aligned_C = {sht_rc1[162:81], sht_rc0[80:0]};

    // Note: sticky generation from shifted-out bits can be added later
    // by exposing dropped-bit ORs from each shifter level/path.

endmodule