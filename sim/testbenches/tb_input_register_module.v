`timescale 1ns / 1ps

module tb_input_register_module;

    //-----------------------------------------
    // Clock / Reset
    //-----------------------------------------
    reg clk;
    reg rst_n;

    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz clock

    //-----------------------------------------
    // DUT Inputs
    //-----------------------------------------
    reg [63:0] A_in;
    reg [63:0] B_in;
    reg [63:0] C_in;

    reg [2:0]  Prec;
    reg [3:0]  Valid;
    reg        Para;
    reg        Cvt;

    //-----------------------------------------
    // DUT Outputs
    //-----------------------------------------
    wire [111:0] partial_products;
    wire [31:0]  ExpDiff;
    wire [31:0]  MaxExp;
    wire [162:0] Aligned_C;
    wire [3:0]   Sign_AB;

    wire PD_mode;
    wire PD2_mode;
    wire PD4_mode;

    //-----------------------------------------
    // Instantiate DUT
    //-----------------------------------------
    Input_Register_Module dut(

        .clk(clk),
        .rst_n(rst_n),

        .A_in(A_in),
        .B_in(B_in),
        .C_in(C_in),

        .Prec(Prec),
        .Valid(Valid),
        .Para(Para),
        .Cvt(Cvt),

        .partial_products(partial_products),
        .ExpDiff(ExpDiff),
        .MaxExp(MaxExp),
        .Aligned_C(Aligned_C),
        .Sign_AB(Sign_AB),

        .PD_mode(PD_mode),
        .PD2_mode(PD2_mode),
        .PD4_mode(PD4_mode)
    );

    //-----------------------------------------
    // Error tracking
    //-----------------------------------------
    integer error_count;
    integer test_count;

    //-----------------------------------------
    // Reference model variables
    //-----------------------------------------
    reg [55:0] A_ext;
    reg [55:0] B_ext;
    reg [55:0] C_ext;

    reg [111:0] exp_product;
    reg [31:0]  exp_maxexp;
    reg [31:0]  exp_expdiff;
    reg [162:0] exp_alignC;
    reg [3:0]   exp_sign;

    reg [10:0] A_exp;
    reg [10:0] B_exp;
    reg [10:0] C_exp;

    reg [31:0] product_exp;

    //-----------------------------------------
    // Waveform dump
    //-----------------------------------------
    initial begin
        $dumpfile("stage1_debug.vcd");
        $dumpvars(0,tb_input_register_module);
    end

    //-----------------------------------------
    // Debug task
    //-----------------------------------------
    task print_debug;
    begin
        $display("\n----- DEBUG INFO -----");
        $display("A = %h",A_in);
        $display("B = %h",B_in);
        $display("C = %h",C_in);

        $display("Expected Product = %h",exp_product);
        $display("RTL Product      = %h",partial_products);

        $display("Expected MaxExp  = %d",exp_maxexp);
        $display("RTL MaxExp       = %d",MaxExp);

        $display("Expected ExpDiff = %d",exp_expdiff);
        $display("RTL ExpDiff      = %d",ExpDiff);

        $display("Expected Sign    = %b",exp_sign);
        $display("RTL Sign         = %b",Sign_AB);

        $display("----------------------\n");
    end
    endtask

    //-----------------------------------------
    // Reference model calculation
    //-----------------------------------------
    task compute_reference;
    begin

        //-------------------------------------
        // Mantissa extension (DP mode)
        //-------------------------------------
        A_ext = {1'b1, A_in[51:0],3'b000};
        B_ext = {1'b1, B_in[51:0],3'b000};
        C_ext = {1'b1, C_in[51:0],3'b000};

        //-------------------------------------
        // Multiplier reference
        //-------------------------------------
        exp_product = A_ext * B_ext;

        //-------------------------------------
        // Exponent extraction
        //-------------------------------------
        A_exp = A_in[62:52];
        B_exp = B_in[62:52];
        C_exp = C_in[62:52];

        //-------------------------------------
        // Exponent comparison
        //-------------------------------------
        product_exp = A_exp + B_exp;

        if(product_exp > C_exp)
            exp_maxexp = product_exp;
        else
            exp_maxexp = C_exp;

        exp_expdiff = exp_maxexp - C_exp;

        //-------------------------------------
        // Alignment
        //-------------------------------------
        exp_alignC = ({C_ext,107'b0}) >> exp_expdiff;

        //-------------------------------------
        // Sign logic
        //-------------------------------------
        exp_sign = {4{A_in[63]^B_in[63]}} & Valid;

    end
    endtask

    //-----------------------------------------
    // Output checker
    //-----------------------------------------
    task check_results;
    begin
        if(partial_products !== exp_product) begin
            $display("ERROR: MULTIPLIER mismatch");
            print_debug();
            error_count = error_count + 1;
        end

        if(MaxExp !== exp_maxexp) begin
            $display("ERROR: MAXEXP mismatch");
            print_debug();
            error_count = error_count + 1;
        end

        if(ExpDiff !== exp_expdiff) begin
            $display("ERROR: EXPDIFF mismatch");
            print_debug();
            error_count = error_count + 1;
        end

        if(Sign_AB !== exp_sign) begin
            $display("ERROR: SIGN mismatch");
            print_debug();
            error_count = error_count + 1;
        end
    end
    endtask

    //-----------------------------------------
    // Test stimulus
    //-----------------------------------------
    initial begin

        error_count = 0;
        test_count  = 0;

        //-------------------------------------
        // Reset
        //-------------------------------------
        rst_n = 0;

        A_in = 0;
        B_in = 0;
        C_in = 0;

        Prec = 3'b100; // DP mode
        Valid = 4'b1111;

        Para = 0;
        Cvt = 0;

        #20;
        rst_n = 1;

        //-------------------------------------
        // Directed tests
        //-------------------------------------
        repeat(10) begin

            @(posedge clk);

            A_in = {$random,$random};
            B_in = {$random,$random};
            C_in = {$random,$random};

            Valid = 4'b1111;

            compute_reference();

            @(posedge clk);

            check_results();

            test_count = test_count + 1;

        end

        //-------------------------------------
        // Random stress test
        //-------------------------------------
        repeat(100) begin

            @(posedge clk);

            A_in = {$random,$random};
            B_in = {$random,$random};
            C_in = {$random,$random};

            Valid = $random;

            compute_reference();

            @(posedge clk);

            check_results();

            test_count = test_count + 1;

        end

        //-------------------------------------
        // Summary
        //-------------------------------------
        $display("\n==================================");
        $display("Total Tests  = %d",test_count);
        $display("Total Errors = %d",error_count);

        if(error_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");

        $display("==================================\n");

        $finish;

    end

endmodule