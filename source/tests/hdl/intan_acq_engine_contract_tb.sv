`timescale 1ns / 1ps

module intan_acq_engine_contract_tb;
    localparam int MAX_COMMANDS = 4;
    localparam int NUM_INTAN = 2;
    localparam int NUM_CHAN = 1;
    localparam int BITS_PER_WORD = 16;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic start_init = 1'b0;
    logic start_read = 1'b0;
    logic [63:0] timestamp = '0;
    logic initialized;
    config_pkg::Intan_frame_t frame;
    logic [6:0] init_list_len = 7'd1;
    logic [MAX_COMMANDS-1:0][BITS_PER_WORD-1:0] init_cmd_list = '0;
    logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] expect_a = '0;
    logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] expect_b = '0;
    logic [6:0] acq_list_len = 7'd1;
    logic [MAX_COMMANDS-1:0][BITS_PER_WORD-1:0] acq_cmd_list = '0;
    logic [6:0] cmd_list_len;
    logic [MAX_COMMANDS-1:0][BITS_PER_WORD-1:0] tx_cmd_list;
    logic start_seq_pulse;
    logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] rx_a = '0;
    logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] rx_b = '0;
    logic done_seq_pulse = 1'b0;
    logic init_done_pulse;
    logic frame_done_pulse;
    logic busy;
    logic err;

    always #5 clk = ~clk;
    always_ff @(posedge clk) begin
        if (rst) timestamp <= '0;
        else timestamp <= timestamp + 1'b1;
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
        .initialized(initialized),
        .Intan_frame(frame),
        .init_list_len(init_list_len),
        .init_cmd_list(init_cmd_list),
        .expect_rx_ans_list_a(expect_a),
        .expect_rx_ans_list_b(expect_b),
        .acq_list_len(acq_list_len),
        .acq_cmd_list(acq_cmd_list),
        .cmd_list_len(cmd_list_len),
        .tx_cmd_list(tx_cmd_list),
        .start_seq_pulse(start_seq_pulse),
        .rx_ans_list_a(rx_a),
        .rx_ans_list_b(rx_b),
        .done_seq_pulse(done_seq_pulse),
        .init_done_pulse(init_done_pulse),
        .frame_done_pulse(frame_done_pulse),
        .busy(busy),
        .err(err)
    );

    task automatic fail(input string message);
        $fatal(1, "%0t: %s", $time, message);
    endtask

    task automatic step();
        @(posedge clk);
        #1;
    endtask

    task automatic pulse_done();
        begin
            done_seq_pulse = 1'b1;
            step();
            done_seq_pulse = 1'b0;
        end
    endtask

    task automatic start_init_attempt();
        begin
            start_init = 1'b1;
            step();
            start_init = 1'b0;
            if (!start_seq_pulse || !busy || err || initialized)
                fail("initialization attempt did not start cleanly");
        end
    endtask

    task automatic finish_init_attempt(input bit expect_success, input string name);
        int waited;
        begin
            pulse_done();
            if (!busy || init_done_pulse || err)
                fail({name, ": verification completed on the sequence-done cycle"});

            waited = 0;
            while (!init_done_pulse && !err && waited < 4 * MAX_COMMANDS * NUM_INTAN + 16) begin
                if (!busy) fail({name, ": busy cleared before verification completed"});
                step();
                waited = waited + 1;
            end

            if (expect_success) begin
                if (!init_done_pulse || !initialized || err || busy)
                    fail({name, ": expected successful multi-cycle verification"});
            end else begin
                if (!err || initialized || init_done_pulse || busy)
                    fail({name, ": expected failed multi-cycle verification"});
            end
        end
    endtask

    initial begin
        for (int command_index = 0; command_index < MAX_COMMANDS; command_index++) begin
            init_cmd_list[command_index] = 16'hFF00 + command_index;
            expect_a[command_index][0] = 16'h1100 + command_index;
            expect_a[command_index][1] = 16'h2200 + command_index;
            expect_b[command_index][0] = 16'h3300 + command_index;
            expect_b[command_index][1] = 16'h4400 + command_index;
        end
        init_list_len = MAX_COMMANDS;
        acq_cmd_list[0]  = 16'h0000;

        repeat (3) step();
        rst = 1'b0;
        step();
        if (initialized || busy || err || init_done_pulse || frame_done_pulse)
            fail("reset state was not deterministic");

        start_read = 1'b1;
        step();
        start_read = 1'b0;
        if (start_seq_pulse || frame_done_pulse) fail("read before init started a sequence");

        rx_a = expect_a;
        rx_b = expect_b;
        rx_a[0][0] ^= 16'h0001;
        start_init_attempt();
        finish_init_attempt(1'b0, "first active response mismatch");

        rx_a = expect_a;
        rx_b = expect_b;
        rx_b[MAX_COMMANDS-1][0] ^= 16'h0001;
        start_init_attempt();
        finish_init_attempt(1'b0, "final active response mismatch");

        // Disabled sensors are neither verified nor exposed as acquired data.
        if (config_pkg::INTAN_MASK[1] !== 1'b0)
            fail("contract test requires sensor one to be inactive");
        rx_a = expect_a;
        rx_b = expect_b;
        for (int command_index = 0; command_index < MAX_COMMANDS; command_index++) begin
            rx_a[command_index][1] ^= 16'h00ff;
            rx_b[command_index][1] ^= 16'hff00;
        end
        start_init_attempt();
        finish_init_attempt(1'b1, "inactive responses ignored on retry");
        step();
        if (init_done_pulse) fail("init_done_pulse lasted more than one clock");

        start_read = 1'b1;
        step();
        start_read = 1'b1;
        step();
        start_read = 1'b0;
        if (!busy) fail("read did not make engine busy");

        rx_a = '0;
        rx_b = '0;
        rx_a[0][0] = 16'h1000;
        rx_a[0][1] = 16'h1100;
        rx_b[0][0] = 16'h1020;
        rx_b[0][1] = 16'h1120;
        pulse_done();
        if (frame_done_pulse) fail("frame pulse asserted before stable-frame cycle");
        step();
        if (!frame_done_pulse || !initialized || err) fail("read did not produce frame pulse");
        if (frame.Intan_data[0].data[15:0] !== 16'h1000 ||
            frame.Intan_data[0].data[16*32+:16] !== 16'h1020)
            fail("active A/B response channels were not packed");
        if (frame.Intan_data[1].data !== '0)
            fail("inactive sensor acquisition data was not held at zero");
        step();
        if (frame_done_pulse) fail("frame_done_pulse lasted more than one clock");

        $display("PASS intan_acq_engine_contract_tb");
        $finish;
    end
endmodule
