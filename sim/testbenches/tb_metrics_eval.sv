`timescale 1ns/1ps

`ifndef DATA_WIDTH
    `define DATA_WIDTH 64
`endif
`ifndef NUM_PARALLEL_MAC
    `define NUM_PARALLEL_MAC 2
`endif
`ifndef FORMAT_STR
    `define FORMAT_STR "DP"
`endif
`ifndef FUNC_STR
    `define FUNC_STR "FMA"
`endif

module tb_metrics_final;

    // ====================================================
    // PARAMETERS (MACRO OVERRIDDEN BY PYTHON)
    // ====================================================
    parameter int DATA_WIDTH = `DATA_WIDTH;     // 64=DP, 32=SP, 16=HP/BF16
    parameter int PIPELINE_DEPTH = (DATA_WIDTH == 64) ? 6 : 5;
    parameter int NUM_PARALLEL_MAC = `NUM_PARALLEL_MAC;
    parameter real CLK_PERIOD_NS = 25.6;        // From synthesis
    parameter int NUM_TRANSACTIONS = 1000;

    // ====================================================
    // SIGNALS
    // ====================================================
    logic clk, rst_n;

    logic valid_in, ready_in;
    logic [DATA_WIDTH-1:0] operand_a, operand_b, operand_c;

    logic valid_out;
    logic [DATA_WIDTH-1:0] result;

    // ====================================================
    // 🔴 REPLACE WITH YOUR DUT
    // ====================================================
    // Determine precision mode and padding based on DATA_WIDTH
    logic [2:0] prec_mode;
    always_comb begin
        if (DATA_WIDTH == 64)      prec_mode = 3'b100; // DP
        else if (DATA_WIDTH == 32) prec_mode = 3'b011; // SP
        else                       prec_mode = 3'b001; // BF16
    end

    wire [63:0] op_a_64 = { {64-DATA_WIDTH{1'b0}}, operand_a };
    wire [63:0] op_b_64 = { {64-DATA_WIDTH{1'b0}}, operand_b };
    wire [63:0] op_c_64 = { {64-DATA_WIDTH{1'b0}}, operand_c };

    wire [3:0] dut_valid_out;
    wire [63:0] dut_result_out;

    DPDAC_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .A_in(op_a_64),
        .B_in(op_b_64),
        .C_in(op_c_64),
        .Prec(prec_mode),
        .Para(1'b0), // 0 for most standard formatting unless parallel
        .Cvt(1'b0),
        .Result_out(dut_result_out),
        .Valid_out(dut_valid_out),
        .Result_sign_out()
    );

    // Since DPDAC_top's Valid_out is just tied to Prec format intrinsically without data-gating, 
    // and we send data 100% of the time seamlessly, we'll sync our testbench valid tracking.
    // DPDAC has fixed latencies: DP=6, SP=5 etc. 
    // For testbench simplicity, we map Valid_out to the pipeline's internal valid tracking OR just check the output sequence natively!
    // Since DPDAC doesn't drop pulses, valid_out goes high when the first latency cycle ends!
    
    // Track valid pipeline delay accurately aligned to tb expectations
    logic pipeline_val [PIPELINE_DEPTH-1:0];
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < PIPELINE_DEPTH; i++) pipeline_val[i] <= 1'b0;
        end else if (ready_in) begin
            pipeline_val[0] <= valid_in;
            for (int i = 1; i < PIPELINE_DEPTH; i++) pipeline_val[i] <= pipeline_val[i-1];
        end
    end
    assign valid_out = pipeline_val[PIPELINE_DEPTH-1] & (|dut_valid_out);
    assign result = dut_result_out[DATA_WIDTH-1:0];

    // ====================================================
    // CLOCK
    // ====================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD_NS/2.0) clk = ~clk;
    end

    // ====================================================
    // TRACKING
    // ====================================================
    int cycle = 0;
    int active_cycles = 0;

    int input_q[$];
    int total_in = 0, total_out = 0;

    int max_latency = 0;
    longint total_latency = 0;

    // ====================================================
    // CYCLE COUNTER
    // ====================================================
    always_ff @(posedge clk) begin
        if (rst_n) begin
            cycle++;
            if (valid_out) active_cycles++;
        end
    end

    // ====================================================
    // INPUT DRIVER
    // ====================================================
    task send_inputs();
        valid_in = 0;

        @(posedge clk);

        while (total_in < NUM_TRANSACTIONS) begin
            if (ready_in) begin
                valid_in = 1;

                operand_a = $urandom();
                operand_b = $urandom();
                operand_c = $urandom();

                input_q.push_back(cycle);
                total_in++;
            end else begin
                valid_in = 0;
            end

            @(posedge clk);
        end

        valid_in = 0;
    endtask

    // ====================================================
    // OUTPUT MONITOR
    // ====================================================
    task monitor_output();
        int in_cycle, lat;

        while (total_out < NUM_TRANSACTIONS) begin
            @(posedge clk);

            if (valid_out) begin
                if (input_q.size() == 0) begin
                    $error("Output without input!");
                end else begin
                    in_cycle = input_q.pop_front();
                    lat = cycle - in_cycle;

                    total_latency += lat;
                    if (lat > max_latency) max_latency = lat;

                    total_out++;
                end
            end
        end
    endtask

    // ====================================================
    // METRIC COMPUTATION + TABLE PRINT
    // ====================================================
    task print_table_row(string format, string function_name);

        real avg_latency;
        real throughput;
        real freq_mhz;
        real bandwidth;
        real byte_per_op;
        real width_bytes;
        real effective_cycles;

        avg_latency = real'(total_latency) / total_out;

        effective_cycles = cycle - PIPELINE_DEPTH;
        throughput = total_out / effective_cycles;

        freq_mhz = (1.0 / CLK_PERIOD_NS) * 1000.0;

        width_bytes = 24;

        bandwidth = width_bytes * (freq_mhz / 1000.0);

        byte_per_op = width_bytes / NUM_PARALLEL_MAC;

        $display("----------------------------------------------------------------");
        $display("Format  Function        Delay  Freq   Lat  OP   TF   Width  GB/s  B/OP");
        $display("----------------------------------------------------------------");

        $display("%-6s %-15s %5.2f  %5.0f   %2.0f   %2d  %4.2f  %5.0f  %5.1f  %4.1f",
            format,
            function_name,
            CLK_PERIOD_NS,
            freq_mhz,
            avg_latency,
            NUM_PARALLEL_MAC,
            throughput,
            width_bytes,
            bandwidth,
            byte_per_op
        );

        $display("----------------------------------------------------------------");
    endtask

    // ====================================================
    // MAIN
    // ====================================================
    initial begin
        ready_in = 1;

        // RESET
        rst_n = 0;
        #(CLK_PERIOD_NS * 5);
        rst_n = 1;

        // RUN
        fork
            send_inputs();
            monitor_output();
        join

        // Flush pipeline
        #(CLK_PERIOD_NS * PIPELINE_DEPTH * 2);

        // PRINT TABLE ROW
        print_table_row(`FORMAT_STR, `FUNC_STR);

        $finish;
    end

endmodule