module Stage2_Adder (

    input  [111:0] partial_products_sum,
    input  [111:0] partial_products_carry,

    input          PD_mode,
    input          PD2_mode,
    input          PD4_mode,

    output [106:0] product0,
    output [106:0] product1,
    output [106:0] product2,
    output [106:0] product3

);

    // ------------------------------------------------------------
    // Local 56-bit 3:2 CSA row compressor.
    // sum + carry is equivalent to x + y + z.
    // ------------------------------------------------------------
    function [111:0] csa3_56;
        input [55:0] x;
        input [55:0] y;
        input [55:0] z;
        reg   [55:0] s;
        reg   [55:0] c;
        begin
            s = x ^ y ^ z;
            c = ((x & y) | (x & z) | (y & z)) << 1;
            csa3_56 = {s, c};
        end
    endfunction

    // Stage1 already generated carry-save rows with a 4:2 compressor.
    // Keep both rows visible in Stage2 instead of collapsing early.
    wire [111:0] cs_sum   = partial_products_sum;
    wire [111:0] cs_carry = partial_products_carry;

    // DP is a single wide product path, so keep the full-width collapse.
    wire [111:0] pp_cpa_dp = cs_sum + cs_carry;

    // PD2 path: combine Stage1 4:2 rows with a Stage2 3:2 per 56-bit lane.
    wire [111:0] pd2_lo_rows = csa3_56(cs_sum[55:0],   cs_carry[55:0],   56'd0);
    wire [111:0] pd2_hi_rows = csa3_56(cs_sum[111:56], cs_carry[111:56], 56'd0);

    // Final lane-local collapse (no carry propagation across lane boundaries).
    wire [55:0] pd2_lo_mag = pd2_lo_rows[111:56] + pd2_lo_rows[55:0];
    wire [55:0] pd2_hi_mag = pd2_hi_rows[111:56] + pd2_hi_rows[55:0];

    wire [27:0] pd4_lane0_mag = cs_sum[27:0]    + cs_carry[27:0];
    wire [27:0] pd4_lane1_mag = cs_sum[55:28]   + cs_carry[55:28];
    wire [27:0] pd4_lane2_mag = cs_sum[83:56]   + cs_carry[83:56];
    wire [27:0] pd4_lane3_mag = cs_sum[111:84]  + cs_carry[111:84];

    // Unpack the Stage-1 product bus into mode-dependent magnitudes.
    reg [107:0] mag0;
    reg [107:0] mag1;
    reg [107:0] mag2;
    reg [107:0] mag3;

    always @(*) begin
        mag0 = 108'd0;
        mag1 = 108'd0;
        mag2 = 108'd0;
        mag3 = 108'd0;

        if (PD_mode) begin
            // DP: bypass Stage2 product compression.
            mag0 = pp_cpa_dp[107:0];
        end
        else if (PD2_mode) begin
            // PD2 (SP/TF32): Stage1 4:2 rows + Stage2 3:2 finalize two 56-bit products.
            // Place at HIGH side of 108-bit magnitude so alignment keeps MSB near bit 163.
            mag0 = {pd2_lo_mag,  52'd0};
            mag1 = {pd2_hi_mag, 52'd0};
        end
        else begin  // PD4_mode (HP/BF16)
            // PD4: use only Stage1 4:2 rows, then finalize each 28-bit lane independently.
            mag0 = {pd4_lane0_mag, 80'd0};
            mag1 = {pd4_lane1_mag, 80'd0};
            mag2 = {pd4_lane2_mag, 80'd0};
            mag3 = {pd4_lane3_mag, 80'd0};
        end
    end

    // Output unsigned magnitudes (sign will be applied AFTER alignment)
    assign product0 = mag0[106:0];
    assign product1 = mag1[106:0];
    assign product2 = mag2[106:0];
    assign product3 = mag3[106:0];

endmodule