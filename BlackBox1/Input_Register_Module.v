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
    input  [3:0]       Valid,
    input              Para,
    input              Cvt,

    //----------------------------------------------------------
    // Outputs AFTER Pipeline Stage 1 Register
    //----------------------------------------------------------

    // Multiplier partial products
    output reg [111:0] partial_products,

    // Exponent comparison results
    output reg [31:0]  ExpDiff,
    output reg [31:0]  MaxExp,

    // Aligned C output
    output reg [162:0] Aligned_C,

    // Product sign
    output reg [3:0]   Sign_AB,

    //input pass
    output reg         Para_reg,
    output reg         Cvt_reg,

    // Mode signals
    output             PD_mode,
    output             PD2_mode,
    output             PD4_mode

);

    //----------------------------------------------------------
    // Precision Encoding
    //----------------------------------------------------------
    parameter HP    = 3'b000;
    parameter BF16  = 3'b001;
    parameter TF32  = 3'b010;
    parameter SP    = 3'b011;
    parameter DP    = 3'b100;

    //----------------------------------------------------------
    // Mode Decode
    //----------------------------------------------------------
    assign PD_mode  = (Prec == DP);
    assign PD2_mode = (Prec == SP)  || (Prec == TF32);
    assign PD4_mode = (Prec == HP)  || (Prec == BF16);

    //----------------------------------------------------------
    // Stage 0 : Input Register
    //----------------------------------------------------------
    reg [63:0] A_reg, B_reg, C_reg;
    reg [2:0]  Prec_reg;
    reg [3:0]  Valid_reg;
    reg [31:0] Cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A_reg     <= 64'd0;
            B_reg     <= 64'd0;
            C_reg     <= 64'd0;
            Prec_reg  <= 3'd0;
            Valid_reg <= 4'd0;
            Cnt       <= 32'd0;
            Para_reg  <= 1'b0;
            Cvt_reg   <= 1'b0;
        end
        else begin
            A_reg     <= A_in;
            B_reg     <= B_in;
            C_reg     <= C_in;
            Prec_reg  <= Prec;
            Valid_reg <= Valid;
            Cnt       <= Cnt + 32'd1;
            Para_reg  <= Para;
            Cvt_reg   <= Cvt;
        end
    end

    //----------------------------------------------------------
    // Extraction + Formatting Block
    //----------------------------------------------------------
    wire [55:0] A_mant_ext;
    wire [55:0] B_mant_ext;
    wire [55:0] C_mant_ext;

    wire [31:0] A_exp_ext;
    wire [31:0] B_exp_ext;
    wire [31:0] C_exp_ext;

    wire [3:0]  A_sign_raw;
    wire [3:0]  B_sign_raw;
    wire [3:0]  C_sign_raw;

    component_formatter u_component_formatter (

        .A_in(A_reg),
        .B_in(B_reg),
        .C_in(C_reg),
        .Prec(Prec_reg),

        .A_sign(A_sign_raw),
        .B_sign(B_sign_raw),
        .C_sign(C_sign_raw),

        .A_exponent_ext(A_exp_ext),
        .B_exponent_ext(B_exp_ext),
        .C_exponent_ext(C_exp_ext),

        .A_mantissa_ext(A_mant_ext),
        .B_mantissa_ext(B_mant_ext),
        .C_mantissa_ext(C_mant_ext)
    );

    //----------------------------------------------------------
    // Stage 1 Arithmetic Blocks (Combinational)
    //----------------------------------------------------------

    // Multiplier Output
    wire [111:0] partial_products_w;

    low_cost_multiplier_array u_multiplier (
        .clk(clk),
        .rst_n(rst_n),
        .A_mantissa(A_mant_ext),
        .B_mantissa(B_mant_ext),
        .Prec(Prec_reg),
        .Valid(Valid_reg),
        .PD_mode(PD_mode),
        .PD2_mode(PD2_mode),
        .PD4_mode(PD4_mode),
        .Cnt0(Cnt[0]),
        .partial_products(partial_products_w)
    );

    // Exponent Comparison
    wire [31:0] ExpDiff_w;
    wire [31:0] MaxExp_w;

    exponent_comparison u_exp_compare (
        .A_exp(A_exp_ext),
        .B_exp(B_exp_ext),
        .C_exp(C_exp_ext),
        .Prec(Prec_reg),
        .Valid(Valid_reg),
        .Para(Para_reg),
        .Cvt(Cvt_reg),
        .ExpDiff(ExpDiff_w),
        .MaxExp(MaxExp_w)
    );

    // Addend Alignment Shifter
    wire [162:0] Aligned_C_w;

    addend_alignment_shifter u_align (
        .C_mantissa(C_mant_ext),
        .ExpDiff(ExpDiff_w),
        .Prec(Prec_reg),
        .Aligned_C(Aligned_C_w)
    );

    // Sign Logic
    wire [3:0] Sign_AB_w;

    sign_logic u_sign_logic (
        .A_sign(A_sign_raw),
        .B_sign(B_sign_raw),
        .Valid(Valid_reg),
        .Sign_AB(Sign_AB_w)
    );

    //----------------------------------------------------------
    // Stage 1 Pipeline Register
    //----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            partial_products <= 112'd0;
            ExpDiff          <= 32'd0;
            MaxExp           <= 32'd0;
            Aligned_C        <= 163'd0;
            Sign_AB          <= 4'd0;
        end
        else begin
            partial_products <= partial_products_w;
            ExpDiff          <= ExpDiff_w;
            MaxExp           <= MaxExp_w;
            Aligned_C        <= Aligned_C_w;
            Sign_AB          <= Sign_AB_w;
        end
    end

endmodule