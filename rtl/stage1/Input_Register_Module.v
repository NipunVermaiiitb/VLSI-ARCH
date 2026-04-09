`timescale 1ns / 1ps

module Stage1_Module (

    input              clk,
    input              rst_n,

    // 64-bit operands
    input  [63:0]      A_in,
    input  [63:0]      B_in,
    input  [63:0]      C_in,

    // Control signals
    input  [2:0]       Prec,
    input              Para,
    input              Cvt,

    //----------------------------------------------------------
    // Outputs AFTER Pipeline Stage 1 Register
    //----------------------------------------------------------

    // Multiplier carry-save outputs
    output reg [111:0] partial_products_sum,
    output reg [111:0] partial_products_carry,

    // Exponent comparison results
    output reg [31:0]  ExpDiff,
    output reg [31:0]  MaxExp,
    output reg [63:0]  ProdASC,    // Product alignment shift counts for Stage 2

    // Aligned C outputs
    output reg [162:0] Aligned_C,
    output reg [1:0]   Sticky_C,   // ADDED: Sticky bits for IEEE rounding in Stage 3

    // Signs
    output reg [3:0]   Sign_AB,
    output reg [3:0]   Sign_C,

    // Control Pass-through
    output reg         Para_reg,
    output reg         Cvt_reg,

    // Pipeline valid signal (deterministic latency)
    output reg         valid_out,

    // Mode signals (Combinational decoded)
    output             PD_mode,
    output             PD2_mode,
    output             PD4_mode

);

    //----------------------------------------------------------
    // Precision Encoding
    //----------------------------------------------------------
    parameter HP   = 3'b000;
    parameter BF16 = 3'b001;
    parameter TF32 = 3'b010;
    parameter SP   = 3'b011;
    parameter DP   = 3'b100;

    //----------------------------------------------------------
    // Mode Decode
    //----------------------------------------------------------
    assign PD_mode  = (Prec == DP);
    assign PD2_mode = (Prec == SP)  || (Prec == TF32);
    assign PD4_mode = (Prec == HP)  || (Prec == BF16);

    //----------------------------------------------------------
    // Global Cycle Counter (for DP iteration)
    //----------------------------------------------------------
    reg cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt <= 1'b0;
        else
            cnt <= ~cnt;
    end

    //----------------------------------------------------------
    // Stage 0 : Input Register with DP Hold Logic
    //----------------------------------------------------------
    reg [63:0] A_reg, B_reg, C_reg;
    reg [2:0]  Prec_reg;
    reg        Para_reg_int, Cvt_reg_int;

    wire [3:0] Valid_reg = (Prec_reg == TF32) ? 4'b0101 : 4'b1111;
    wire accept_inputs = (Prec == DP) ? (cnt == 1'b0) : 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A_reg        <= 64'd0;
            B_reg        <= 64'd0;
            C_reg        <= 64'd0;
            Prec_reg     <= 3'd0;
            Para_reg_int <= 1'b0;
            Cvt_reg_int  <= 1'b0;
        end
        else if (accept_inputs) begin
            A_reg        <= A_in;
            B_reg        <= B_in;
            C_reg        <= C_in;
            Prec_reg     <= Prec;
            Para_reg_int <= Para;
            Cvt_reg_int  <= Cvt;
        end
    end

    //----------------------------------------------------------
    // Extraction + Formatting Block
    //----------------------------------------------------------
    wire [55:0] A_mant_ext, B_mant_ext, C_mant_ext;
    wire [31:0] A_exp_ext, B_exp_ext, C_exp_ext;
    wire [3:0]  A_sign_raw, B_sign_raw, C_sign_raw;

    component_formatter u_component_formatter (
        .A_in(A_reg), .B_in(B_reg), .C_in(C_reg),
        .Prec(Prec_reg), .Valid(Valid_reg), .Para(Para_reg_int),
        .A_sign(A_sign_raw), .B_sign(B_sign_raw), .C_sign(C_sign_raw),
        .A_exponent_ext(A_exp_ext), .B_exponent_ext(B_exp_ext), .C_exponent_ext(C_exp_ext),
        .A_mantissa_ext(A_mant_ext), .B_mantissa_ext(B_mant_ext), .C_mantissa_ext(C_mant_ext)
    );

    //----------------------------------------------------------
    // Stage 1 Arithmetic Blocks (Combinational)
    //----------------------------------------------------------

    // 1. Multiplier Array
    wire [111:0] partial_products_sum_w;
    wire [111:0] partial_products_carry_w;

    low_cost_multiplier_array u_multiplier (
        .clk(clk), .rst_n(rst_n),
        .A_mantissa(A_mant_ext), .B_mantissa(B_mant_ext),
        .Prec(Prec_reg), .Valid(Valid_reg),
        .PD_mode(PD_mode), .PD2_mode(PD2_mode), .PD4_mode(PD4_mode),
        .Cnt0(cnt),
        .partial_sum(partial_products_sum_w),
        .partial_carry(partial_products_carry_w)
    );

    // 2. Exponent Comparison
    wire [31:0] ExpDiff_w, MaxExp_w;
    wire [63:0] ProdASC_w;

    exponent_comparison u_exp_compare (
        .A_exp(A_exp_ext), .B_exp(B_exp_ext), .C_exp(C_exp_ext),
        .Prec(Prec_reg), .Valid(Valid_reg), .Para(Para_reg_int), .Cvt(Cvt_reg_int),
        .ExpDiff(ExpDiff_w), .MaxExp(MaxExp_w), .ProdASC(ProdASC_w)
    );

    // 3. Sign Logic
    wire [3:0] Sign_AB_w;

    sign_logic u_sign_logic (
        .A_sign(A_sign_raw), .B_sign(B_sign_raw),
        .Valid(Valid_reg),
        .Sign_AB(Sign_AB_w)
    );

    // 4. Inversion Logic for Addend C (Two's Complement Prep)
    wire [1:0] Sign_Inv_C;
    assign Sign_Inv_C[1] = (Prec_reg == 3'b100) ? C_sign_raw[0] : C_sign_raw[3]; // DP: match lower lane
    assign Sign_Inv_C[0] = C_sign_raw[0]; // Lower lane (C0)

    // 5. Addend Alignment Shifter
    wire [162:0] Aligned_C_w;
    wire [1:0]   Sticky_C_w; // 2-bit per-lane sticky from the shifter

    addend_alignment_shifter u_align (
        .C_mantissa(C_mant_ext),
        .ExpDiff(ExpDiff_w),
        .Prec(Prec_reg),
        .Para(Para_reg_int),
        .Sign_Inv(Sign_Inv_C),     // Triggers inversion if subtracting
        .Aligned_C(Aligned_C_w),
        .Sticky_Bits(Sticky_C_w)
    );

    //----------------------------------------------------------
    // Stage 1 Pipeline Register
    //----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            partial_products_sum   <= 112'd0;
            partial_products_carry <= 112'd0;
            ExpDiff                <= 32'd0;
            MaxExp                 <= 32'd0;
            ProdASC                <= 64'd0;
            Aligned_C              <= 163'd0;
            Sticky_C               <= 2'd0;
            Sign_AB                <= 4'd0;
            Sign_C                 <= 4'd0;
            Para_reg               <= 1'b0;
            Cvt_reg                <= 1'b0;
            valid_out              <= 1'b0;
        end
        else begin
            partial_products_sum   <= partial_products_sum_w;
            partial_products_carry <= partial_products_carry_w;
            ExpDiff                <= ExpDiff_w;
            MaxExp                 <= MaxExp_w;
            ProdASC                <= ProdASC_w;
            Aligned_C              <= Aligned_C_w;

            Sticky_C               <= Sticky_C_w;

            Sign_AB                <= Sign_AB_w;
            Sign_C                 <= C_sign_raw;
            Para_reg               <= Para_reg_int;
            Cvt_reg                <= Cvt_reg_int;

            // Deterministic valid output
            valid_out              <= (Prec_reg == DP) ? cnt : 1'b1;
        end
    end

endmodule
