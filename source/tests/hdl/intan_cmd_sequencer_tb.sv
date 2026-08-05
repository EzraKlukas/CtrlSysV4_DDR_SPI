`timescale 1ns / 1ps

module intan_cmd_sequencer_tb;
    timeunit 1ns; timeprecision 1ps;

    localparam time CLK_PERIOD = 8ns;

    localparam int MAX_COMMANDS = 64;
    localparam int NUM_INTAN = 2;
    localparam int BITS_PER_WORD = 16;

    localparam int SCLK_HALF_PERIOD_CYCLES = 3;
    localparam int T_CS_1_CYCLES = 6;
    localparam int T_CS_2_CYCLES = 6;
    localparam int T_CS_OFF_CYCLES = 20;
    localparam time T_MISO_MAX = 12ns;
    // no need to police timing of SPI word engine, other tb's job.
    // command lists, and expected responses from each sensor. Start with
    // simple one for first version of tb, just one response.

    localparam logic [15:0] CONVERT_CHANNEL_32 = 16'h1F00;

    localparam logic [15:0] SENSOR_0_EXPECT_A = 16'h101F;
    localparam logic [15:0] SENSOR_0_EXPECT_B = 16'h103F;

    localparam int CMD_LIST_WIDTH = MAX_COMMANDS * BITS_PER_WORD;

    logic clk;

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // DUT (intan_cmd_sequencer_tb)
    logic rst = 1'b1;
    logic run_cyclic = 1'b0;
    logic done_pulse;
    logic start_seq_pulse = 1'b0;
    logic done_seq_pulse;
    logic [15:0] tx_word;
    logic [6:0] cmd_list_len = 0;
    logic [MAX_COMMANDS * BITS_PER_WORD-1:0] tx_cmd_list;
    logic [MAX_COMMANDS * NUM_INTAN * BITS_PER_WORD-1:0] rx_ans_list_a;
    logic [MAX_COMMANDS * NUM_INTAN * BITS_PER_WORD-1:0] rx_ans_list_b;

    // spi_word_engine
    logic [NUM_INTAN*BITS_PER_WORD-1:0] rx_word_a;
    logic [NUM_INTAN*BITS_PER_WORD-1:0] rx_word_b;
    logic sclk;
    logic mosi;
    wire [NUM_INTAN-1:0] miso;
    logic cs_n = 1'b1;

    // two rhd2164 models
    logic [15:0] captured_command_0;
    logic [15:0] captured_command_1;
    logic command_valid_0;
    logic command_valid_1;

    // here to put useful variables for the sequencing of the testbench.

    // here to instantiate all relevant module
    intan_cmd_sequencer #(
        .MAX_COMMANDS(MAX_COMMANDS),
        .NUM_INTAN(NUM_INTAN),
        .BITS_PER_WORD(BITS_PER_WORD)
    ) dut (
        .clk(clk),
        .rst(rst),
        .run_cyclic(run_cyclic),
        .done_pulse(done_pulse),
        .start_seq_pulse(start_seq_pulse),
        .done_seq_pulse(done_seq_pulse),
        .tx_word(tx_word),
        .rx_ans_a(rx_word_a),
        .rx_ans_b(rx_word_b),
        .cmd_list_len(cmd_list_len),
        .tx_cmd_list(tx_cmd_list),
        .rx_ans_list_a(rx_ans_list_a),
        .rx_ans_list_b(rx_ans_list_b)
    );

    intan_spi_word_engine #(
        .SCLK_HALF_PERIOD_CYCLES(SCLK_HALF_PERIOD_CYCLES),
        .NUM_INTAN(NUM_INTAN),
        .T_CS_1(T_CS_1_CYCLES),
        .T_CS_2(T_CS_2_CYCLES),
        .T_CS_OFF(T_CS_OFF_CYCLES),
        .BITS_PER_WORD(BITS_PER_WORD)
    ) word_engine (
        .clk(clk),
        .rst(rst),
        .run_cyclic(run_cyclic),
        .done_pulse(done_pulse),
        .tx_word(tx_word),
        .rx_word_a(rx_word_a),
        .rx_word_b(rx_word_b),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .cs_n(cs_n)
    );

    rhd2164_model #(
        .SENSOR_ID(0),
        .T_MISO(T_MISO_MAX),
        .CHECK_TIMING(1'b1)
    ) sensor_0 (
        .cs_n(cs_n),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso[0]),
        .captured_command(captured_command_0),
        .command_valid(command_valid_0)
    );

    rhd2164_model #(
        .SENSOR_ID(1),
        .T_MISO(T_MISO_MAX),
        .CHECK_TIMING(1'b1)
    ) sensor_1 (
        .cs_n(cs_n),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso[1]),
        .captured_command(captured_command_1),
        .command_valid(command_valid_1)
    );

    // now on to behaviour / helper functions?

    task automatic fail(input string message);
        $fatal(1, "%0t: %s", $realtime, message);
    endtask

    task automatic reset_dut();
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
    endtask

    task automatic run_command_list_test(input int command_count);
        if (command_count <= MAX_COMMANDS) begin
            // construct tx_cmd_list as well as associated rx expected lists.
            logic [CMD_LIST_WIDTH-1:0] cmd_list = '0;
            logic [NUM_INTAN * CMD_LIST_WIDTH-1:0] rx_list_expect_a;
            logic [NUM_INTAN * CMD_LIST_WIDTH-1:0] rx_list_expect_b;

            for (int cmd_idx = 1; cmd_idx <= command_count; cmd_idx = cmd_idx + 1) begin
                cmd_list[cmd_idx*BITS_PER_WORD-1-:BITS_PER_WORD] = CONVERT_CHANNEL_32;
                for (int intan_idx = 0; intan_idx < NUM_INTAN; intan_idx = intan_idx + 1) begin
                    logic [15:0] sensor_offset = intan_idx * 16'h0100;
                    rx_list_expect_a[((cmd_idx-1) * NUM_INTAN + intan_idx + 1) * BITS_PER_WORD - 1 -: BITS_PER_WORD] = sensor_offset + SENSOR_0_EXPECT_A;
                    rx_list_expect_b[((cmd_idx-1) * NUM_INTAN + intan_idx + 1) * BITS_PER_WORD - 1 -: BITS_PER_WORD] = sensor_offset + SENSOR_0_EXPECT_B;
                end
            end

            // just need to provide command list, and start_seq_pulse
            cmd_list_len = 7'(command_count);
            tx_cmd_list  = cmd_list;

            $display("RUN: 0%d length command list test.", command_count);

            start_seq_pulse = 1'b1;
            repeat (1) @(posedge clk);
            start_seq_pulse = 1'b0;

            @(posedge done_seq_pulse);
            if (rx_ans_list_b != rx_list_expect_b) begin
                fail($sformatf(
                     "rx_ans_list_b = 0x%04h; expected 0x%04h", rx_ans_list_b, rx_list_expect_b));
            end
            if (rx_ans_list_a != rx_list_expect_a) begin
                fail($sformatf(
                     "rx_ans_list_a = 0x%04h; expected 0x%04h", rx_ans_list_a, rx_list_expect_a));
            end

            $display("PASS: 0%d length command list test.", command_count);
        end else begin
            fail("Command list length exceeds maximal command list length");
        end
    endtask

    initial begin
        $dumpfile("intan_cmd_sequencer.fst");
        $dumpvars(0, intan_spi_word_engine_tb);
    end

    initial begin : test_cmd_sequence

        reset_dut();

        run_command_list_test(1);

        reset_dut();

        run_command_list_test(2);

        reset_dut();

        run_command_list_test(3);

        reset_dut();

        run_command_list_test(4);

        reset_dut();

        run_command_list_test(MAX_COMMANDS);

        $finish;
    end

    initial begin : timeout
        #2ms;
        $fatal(1, "intan_spi_word_engine_tb timed out");
    end
endmodule
