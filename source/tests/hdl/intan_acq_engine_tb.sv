`timescale 1ns / 1ps

module intan_acq_engine_tb;
    timeunit 1ns; timeprecision 1ps;

    localparam time CLK_PERIOD = 8ns;

    localparam int MAX_COMMANDS = 34;
    localparam int NUM_INTAN = 8;
    localparam int NUM_CHAN = 32;
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

    // DUT (intan_acq_engine)
    logic rst = 1'b1;
    logic start_init = 1'b0;
    logic start_read = 1'b0;
    logic [63:0] timestamp;

    initial timestamp = '0;
    always #(CLK_PERIOD) timestamp = timestamp + 1;

    Intan_frame_t Intan_frame;

    logic [6:0] init_list_len = 7'(MAX_COMMANDS);
    // Declaration as a 2D packed array
    logic [MAX_COMMANDS-1:0][BITS_PER_WORD-1:0] init_cmd_list;
    // Clean, readable assignment assuming BITS_PER_WORD = 16
    assign init_cmd_list = '{
            16'hFF00,
            16'hFF00,
            16'hFF00,
            16'hFF00,  // Padding / Idle
            16'hFF00,
            16'hFF00,
            16'hFF00,
            16'hFF00,
            16'hFF00,
            16'h5500,
            16'h95FF,
            16'h94FF,
            16'h93FF,
            16'h92FF,
            16'h91FF,
            16'h90FF,
            16'h8FFF,
            16'h8EFF,
            16'h8D86,
            16'h8C2C,
            16'h8B80,
            16'h8A17,
            16'h8980,
            16'h8816,
            16'h8700,
            16'h8680,
            16'h8540,
            16'h8480,
            16'h8300,
            16'h8204,
            16'h8142,
            16'h80DE,
            16'hFF00,
            16'hFF00
        };

    logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] rx_init_list_expect_a;

    assign rx_init_list_expect_a = '{
            16'h0004,
            16'h0004,
            16'h0004,
            16'h0004,
            16'h0004,
            16'h0004,
            16'h0004,
            16'h0004,
            16'h0004,
            16'hFFFF,
            16'hFFFF,
            16'hFFFF,
            16'hFFFF,
            16'hFFFF,
            16'hFFFF,
            16'hFFFF,
            16'hFFFF,
            16'hFFFF,
            16'hFF86,
            16'hFF2C,
            16'hFF80,
            16'hFF17,
            16'hFF80,
            16'hFF16,
            16'hFF00,
            16'hFF80,
            16'hFF40,
            16'hFF80,
            16'hFF00,
            16'hFF04,
            16'hFF42,
            16'hFFDE,
            16'h0004,
            16'h0004
        };

    logic [MAX_COMMANDS * NUM_INTAN * BITS_PER_WORD-1:0] rx_init_list_expect_b = rx_init_list_expect_a;

    logic [MAX_COMMANDS * NUM_INTAN * BITS_PER_WORD-1:0] rx_acq_list_expect_a;  // testing purposes.
    logic [MAX_COMMANDS * NUM_INTAN * BITS_PER_WORD-1:0] rx_acq_list_expect_b;  // for testing.

    logic [6:0] acq_list_len = 7'b0100000;
    logic [MAX_COMMANDS * BITS_PER_WORD-1:0] acq_cmd_list;

    logic [6:0] cmd_list_len = 0;
    logic [MAX_COMMANDS * BITS_PER_WORD-1:0] tx_cmd_list;
    logic start_seq_pulse = 1'b0;

    logic [MAX_COMMANDS * NUM_INTAN * BITS_PER_WORD-1:0] rx_ans_list_a;
    logic [MAX_COMMANDS * NUM_INTAN * BITS_PER_WORD-1:0] rx_ans_list_b;
    logic done_seq_pulse;

    logic done;
    logic err;

    // intan_cmd_sequencer
    logic run_cyclic = 1'b0;
    logic done_pulse;
    logic [15:0] tx_word;

    // spi_word_engine
    logic [NUM_INTAN*BITS_PER_WORD-1:0] rx_word_a;
    logic [NUM_INTAN*BITS_PER_WORD-1:0] rx_word_b;
    logic sclk;
    logic mosi;
    wire [NUM_INTAN-1:0] miso;
    logic cs_n = 1'b1;

    // preparing / initializing set command lists for initialization and
    // acquisition.

    // generating acquisition and initialization command lists, and expected
    // responses.
    initial begin
        automatic logic [15:0] SAMPLE_BASE = 16'h1000;

        for (int cmd_idx = 1; cmd_idx <= MAX_COMMANDS; cmd_idx = cmd_idx + 1) begin
            automatic logic [15:0] convert_channel_cmd_idx = {2'b0, 6'(cmd_idx - 1), 8'b0};
            automatic logic [15:0] rx_expect = SAMPLE_BASE + {10'b0, 6'(cmd_idx - 1)};

            acq_cmd_list[cmd_idx*BITS_PER_WORD-1-:BITS_PER_WORD] = convert_channel_cmd_idx;

            for (int intan_idx = 0; intan_idx < NUM_INTAN; intan_idx = intan_idx + 1) begin
                automatic logic [15:0] sensor_offset = intan_idx * 16'h0100;
                rx_acq_list_expect_a[((cmd_idx-1) * NUM_INTAN + intan_idx + 1) * BITS_PER_WORD - 1 -: BITS_PER_WORD] = sensor_offset + rx_expect;
                rx_acq_list_expect_b[((cmd_idx-1) * NUM_INTAN + intan_idx + 1) * BITS_PER_WORD - 1 -: BITS_PER_WORD] = sensor_offset + rx_expect + 16'h0020;
            end
        end

        acq_list_len = 7'(MAX_COMMANDS);
    end

    intan_acq_engine #(
        .MAX_COMMANDS(MAX_COMMANDS),
        .NUM_INTAN(NUM_INTAN),
        .NUM_CHAN(NUM_CHAN),
        .BITS_PER_WORD(BITS_PER_WORD)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start_init(start_init),
        .start_read(start_read),
        .timestamp(timestamp),
        .Intan_frame(Intan_frame),
        .init_list_len(init_list_len),
        .init_cmd_list(init_cmd_list),
        .rx_init_list_expect_a(rx_init_list_expect_a),
        .rx_init_list_expect_b(rx_init_list_expect_b),
        .acq_list_len(acq_list_len),
        .acq_cmd_list(acq_cmd_list),
        .cmd_list_len(cmd_list_len),
        .tx_cmd_list(tx_cmd_list),
        .start_seq_pulse(start_seq_pulse),
        .rx_ans_list_a(rx_ans_list_a),
        .rx_ans_list_b(rx_ans_list_b),
        .done_seq_pulse(done_seq_pulse),
        .done(done),
        .err(err)
    );

    intan_cmd_sequencer #(
        .MAX_COMMANDS(MAX_COMMANDS),
        .NUM_INTAN(NUM_INTAN),
        .BITS_PER_WORD(BITS_PER_WORD)
    ) sequencer (
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

    genvar i;

    logic [NUM_INTAN-1:0] intan_fault_bit = '0;
    logic [NUM_INTAN-1:0] intan_init_bit = '1;

    generate
        for (i = 0; i < NUM_INTAN; i = i + 1) begin : intan_gen
            logic [15:0] captured_command;
            logic command_valid;
            rhd2164_model #(
                .SENSOR_ID(i),
                .T_MISO(T_MISO_MAX),
                .CHECK_TIMING(1'b1)
            ) sensor (
                .cs_n(cs_n),
                .sclk(sclk),
                .mosi(mosi),
                .miso(miso[i]),
                .fault_bit(intan_fault_bit[i]),
                .init_bit(intan_init_bit[i]),
                .captured_command(captured_command),
                .command_valid(command_valid)
            );
        end
    endgenerate

    task automatic fail(input string message);
        $fatal(1, "%0t: %s", $realtime, message);
    endtask

    task automatic assert_init_lists();
        assert (rx_ans_list_a == rx_init_list_expect_a)
        else
            $error(
                "rx_ans_list_a mismatch: got %h, expected %h", rx_ans_list_a, rx_init_list_expect_a
            );
        assert (rx_ans_list_b == rx_init_list_expect_b)
        else
            $error(
                "rx_ans_list_b mismatch: got %h, expected %h", rx_ans_list_b, rx_init_list_expect_b
            );
    endtask

    task automatic assert_acq_lists();
        assert (rx_ans_list_a == rx_acq_list_expect_a)
        else
            $error(
                "rx_ans_list_a mismatch: got %h, expected %h", rx_ans_list_a, rx_acq_list_expect_a
            );
        assert (rx_ans_list_b == rx_acq_list_expect_b)
        else
            $error(
                "rx_ans_list_b mismatch: got %h, expected %h", rx_ans_list_b, rx_acq_list_expect_b
            );
    endtask

    task automatic reset_dut();
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
    endtask

    // this task initializes all the sensors, fault_bits -> 0, init_bits -> 1.
    task automatic initialize_sensors();
        for (int intan_idx = 0; intan_idx < NUM_INTAN; intan_idx = intan_idx + 1) begin
            intan_fault_bit[intan_idx] = 1'b0;
            intan_init_bit[intan_idx]  = 1'b1;
        end
        run_command_list_test(MAX_COMMANDS, 1'b1);
    endtask

    task automatic generate_fault();
        for (int intan_idx = 0; intan_idx < NUM_INTAN; intan_idx = intan_idx + 1) begin
            intan_fault_bit[intan_idx] = 1'b1;
            intan_init_bit[intan_idx]  = 1'b0;
        end
    endtask

    task automatic pulse_start_init();
        repeat (1) @(posedge clk);
        start_init = 1'b1;
        repeat (1) @(posedge clk);
        start_init = 1'b0;
    endtask

    task automatic pulse_start_read();
        repeat (2) @(posedge clk);
        start_read = 1'b1;
        repeat (2) @(posedge clk);
        start_read = 1'b0;
    endtask

    // ST_PRE_INIT -> ST_INITING -> ST_READ_READY -> ST_READING -> ST_DONE.
    task automatic baseline_progression();
        reset_dut();
        pulse_start_init();
        $display("Initing!");
        @(posedge done_seq_pulse);
        assert_init_lists();
        $display("Ready to read!");
        @(posedge clk);
        pulse_start_read();
        $display("Reading!");
        @(posedge done_seq_pulse);
        assert_acq_lists();
        repeat (1) @(posedge clk);
    endtask

    task automatic reading_fault_recover();
        reset_dut();
        pulse_start_init();
        $display("Initing!");
        @(posedge done_seq_pulse);
        $display("Ready to read!");
        pulse_start_read();
        $display("Reading!");
        repeat (50) @(posedge clk);
        generate_fault();
        $display("Faulted!");
        pulse_start_init();
        $display("Should be initing again!");
        @(posedge done_seq_pulse);
        assert_init_lists();
        $display("Ready to read!");
        @(posedge clk);
        pulse_start_read();
        $display("Reading!");
        @(posedge done_seq_pulse);
        assert_acq_lists();
        repeat (1) @(posedge clk);
    endtask

    // runs arbitrary command list. If it's an initialization sequence.
    task automatic run_command_list_test(input int command_count, input bit initializing);
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

            if (initializing) begin
                rx_init_list_expect_a = rx_list_expect_a;
                rx_init_list_expect_b = rx_list_expect_b;
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
        $dumpfile("intan_acq_engine.fst");
        $dumpvars(0, intan_spi_word_engine_tb);
    end

    initial begin : test_acq_engine
        reading_fault_recover();
        $finish;
    end

    initial begin : timeout
        #2ms;
        $fatal(1, "intan_spi_word_engine_tb timed out");
    end
endmodule
