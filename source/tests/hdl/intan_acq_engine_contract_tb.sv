`timescale 1ns / 1ps

module intan_acq_engine_contract_tb;
    localparam int MAX_COMMANDS = 34;
    localparam int NUM_INTAN = 2;
    localparam int NUM_CHAN = 1;
    localparam int BITS_PER_WORD = 16;
    localparam logic [3:0] ST_VERIFY_DONE = 4'd4;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic start_init = 1'b0;
    logic start_read = 1'b0;
    logic diagnostic_clear = 1'b0;
    logic [63:0] timestamp = '0;
    logic initialized;
    config_pkg::Intan_frame_t frame;
    logic [6:0] init_list_len = 7'(MAX_COMMANDS);
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
    logic [15:0] diagnostic_attempt_count;
    logic diagnostic_snapshot_valid;
    logic [7:0] diagnostic_a_mismatch_count;
    logic [7:0] diagnostic_b_mismatch_count;
    logic [MAX_COMMANDS-1:0] diagnostic_a_mismatch_bitmap;
    logic [MAX_COMMANDS-1:0] diagnostic_b_mismatch_bitmap;
    logic diagnostic_first_a_valid;
    logic [6:0] diagnostic_first_a_command_index;
    logic [2:0] diagnostic_first_a_sensor_index;
    logic [BITS_PER_WORD-1:0] diagnostic_first_a_command;
    logic [BITS_PER_WORD-1:0] diagnostic_first_a_actual;
    logic [BITS_PER_WORD-1:0] diagnostic_first_a_expected;
    logic diagnostic_first_b_valid;
    logic [6:0] diagnostic_first_b_command_index;
    logic [2:0] diagnostic_first_b_sensor_index;
    logic [BITS_PER_WORD-1:0] diagnostic_first_b_command;
    logic [BITS_PER_WORD-1:0] diagnostic_first_b_actual;
    logic [BITS_PER_WORD-1:0] diagnostic_first_b_expected;
    logic [3:0] diagnostic_state;
    logic [6:0] diagnostic_verify_command_index;
    logic [2:0] diagnostic_verify_sensor_index;

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
        .diagnostic_clear(diagnostic_clear),
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
        .err(err),
        .diagnostic_attempt_count(diagnostic_attempt_count),
        .diagnostic_snapshot_valid(diagnostic_snapshot_valid),
        .diagnostic_a_mismatch_count(diagnostic_a_mismatch_count),
        .diagnostic_b_mismatch_count(diagnostic_b_mismatch_count),
        .diagnostic_a_mismatch_bitmap(diagnostic_a_mismatch_bitmap),
        .diagnostic_b_mismatch_bitmap(diagnostic_b_mismatch_bitmap),
        .diagnostic_first_a_valid(diagnostic_first_a_valid),
        .diagnostic_first_a_command_index(diagnostic_first_a_command_index),
        .diagnostic_first_a_sensor_index(diagnostic_first_a_sensor_index),
        .diagnostic_first_a_command(diagnostic_first_a_command),
        .diagnostic_first_a_actual(diagnostic_first_a_actual),
        .diagnostic_first_a_expected(diagnostic_first_a_expected),
        .diagnostic_first_b_valid(diagnostic_first_b_valid),
        .diagnostic_first_b_command_index(diagnostic_first_b_command_index),
        .diagnostic_first_b_sensor_index(diagnostic_first_b_sensor_index),
        .diagnostic_first_b_command(diagnostic_first_b_command),
        .diagnostic_first_b_actual(diagnostic_first_b_actual),
        .diagnostic_first_b_expected(diagnostic_first_b_expected),
        .diagnostic_state(diagnostic_state),
        .diagnostic_verify_command_index(diagnostic_verify_command_index),
        .diagnostic_verify_sensor_index(diagnostic_verify_sensor_index)
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

    task automatic pulse_diagnostic_clear();
        begin
            diagnostic_clear = 1'b1;
            step();
            diagnostic_clear = 1'b0;
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

    task automatic wait_init_attempt(input bit expect_success, input string name);
        int waited;
        begin
            waited = 0;
            while (!init_done_pulse && !err && waited < 4 * MAX_COMMANDS * NUM_INTAN + 16) begin
                if (!busy) fail({name, ": busy cleared before verification completed"});
                if (init_done_pulse) fail({name, ": init_done_pulse asserted prematurely"});
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

    task automatic finish_init_attempt(input bit expect_success, input string name);
        begin
            pulse_done();
            if (!busy || init_done_pulse || err)
                fail({name, ": verification completed on the sequence-done cycle"});
            if (diagnostic_state != 4'd2 || diagnostic_verify_command_index != 0 ||
                diagnostic_verify_sensor_index != 0)
                fail({name, ": live verification state or indexes were wrong"});
            wait_init_attempt(expect_success, name);
        end
    endtask

    task automatic expect_no_snapshot(input string name);
        begin
            if (diagnostic_snapshot_valid || diagnostic_first_a_valid ||
                diagnostic_first_b_valid || diagnostic_a_mismatch_count != 0 ||
                diagnostic_b_mismatch_count != 0 || diagnostic_a_mismatch_bitmap != '0 ||
                diagnostic_b_mismatch_bitmap != '0)
                fail({name, ": unexpected published diagnostic snapshot"});
        end
    endtask

    task automatic check_first_a(
        input logic valid,
        input logic [6:0] command_index,
        input logic [2:0] sensor_index,
        input logic [15:0] command,
        input logic [15:0] actual,
        input logic [15:0] expected,
        input string name
    );
        begin
            if (diagnostic_first_a_valid !== valid)
                fail({name, ": wrong first-A valid flag"});
            if (valid && (diagnostic_first_a_command_index !== command_index ||
                          diagnostic_first_a_sensor_index !== sensor_index ||
                          diagnostic_first_a_command !== command ||
                          diagnostic_first_a_actual !== actual ||
                          diagnostic_first_a_expected !== expected))
                fail({name, ": wrong first-A snapshot"});
        end
    endtask

    task automatic check_first_b(
        input logic valid,
        input logic [6:0] command_index,
        input logic [2:0] sensor_index,
        input logic [15:0] command,
        input logic [15:0] actual,
        input logic [15:0] expected,
        input string name
    );
        begin
            if (diagnostic_first_b_valid !== valid)
                fail({name, ": wrong first-B valid flag"});
            if (valid && (diagnostic_first_b_command_index !== command_index ||
                          diagnostic_first_b_sensor_index !== sensor_index ||
                          diagnostic_first_b_command !== command ||
                          diagnostic_first_b_actual !== actual ||
                          diagnostic_first_b_expected !== expected))
                fail({name, ": wrong first-B snapshot"});
        end
    endtask

    initial begin
        logic [MAX_COMMANDS-1:0] expected_a_bitmap;
        logic [MAX_COMMANDS-1:0] expected_b_bitmap;

        for (int command_index = 0; command_index < MAX_COMMANDS; command_index++) begin
            init_cmd_list[command_index] = 16'(16'hFF00 + command_index);
            expect_a[command_index][0] = 16'(16'h1100 + command_index);
            expect_a[command_index][1] = 16'(16'h2200 + command_index);
            expect_b[command_index][0] = 16'(16'h3300 + command_index);
            expect_b[command_index][1] = 16'(16'h4400 + command_index);
        end
        acq_cmd_list[0] = 16'h0000;

        repeat (3) step();
        rst = 1'b0;
        step();
        if (initialized || busy || err || init_done_pulse || frame_done_pulse ||
            diagnostic_attempt_count != 0 || diagnostic_state != 4'd0)
            fail("reset state was not deterministic");
        expect_no_snapshot("reset");

        start_read = 1'b1;
        step();
        start_read = 1'b0;
        if (start_seq_pulse || frame_done_pulse) fail("read before init started a sequence");

        // A-only failure: exact first-hit metadata, words, count, and bitmap.
        rx_a = expect_a;
        rx_b = expect_b;
        rx_a[2][0] = 16'ha2a2;
        start_init_attempt();
        if (diagnostic_attempt_count != 1) fail("first attempt was not counted");
        finish_init_attempt(1'b0, "A-only mismatch");
        if (!diagnostic_snapshot_valid || diagnostic_a_mismatch_count != 1 ||
            diagnostic_b_mismatch_count != 0 || diagnostic_a_mismatch_bitmap != (34'b1 << 2) ||
            diagnostic_b_mismatch_bitmap != '0)
            fail("A-only snapshot counters or bitmaps were wrong");
        check_first_a(1'b1, 7'd2, 3'd0, 16'hff02, 16'ha2a2, 16'h1102,
                      "A-only mismatch");
        check_first_b(1'b0, '0, '0, '0, '0, '0, "A-only mismatch");

        // A later failed retry increments the attempt count but cannot replace
        // the first completed failure snapshot.
        rx_a = expect_a;
        rx_b = expect_b;
        rx_b[3][0] = 16'hb3b3;
        rx_b[33][0] = 16'hb333;
        start_init_attempt();
        finish_init_attempt(1'b0, "frozen snapshot retry");
        if (diagnostic_attempt_count != 2 || diagnostic_a_mismatch_count != 1 ||
            diagnostic_b_mismatch_count != 0 || diagnostic_a_mismatch_bitmap != (34'b1 << 2) ||
            diagnostic_b_mismatch_bitmap != '0)
            fail("failed retry overwrote the frozen first-failure snapshot");
        check_first_a(1'b1, 7'd2, 3'd0, 16'hff02, 16'ha2a2, 16'h1102,
                      "frozen snapshot retry");
        check_first_b(1'b0, '0, '0, '0, '0, '0, "frozen snapshot retry");

        pulse_diagnostic_clear();
        if (diagnostic_attempt_count != 0) fail("diagnostic clear did not clear attempt count");
        expect_no_snapshot("diagnostic clear");

        // B-only failure after clear publishes a new independent snapshot.
        rx_a = expect_a;
        rx_b = expect_b;
        rx_b[0][0] = 16'hb0b0;
        start_init_attempt();
        finish_init_attempt(1'b0, "B-only mismatch");
        if (!diagnostic_snapshot_valid || diagnostic_a_mismatch_count != 0 ||
            diagnostic_b_mismatch_count != 1 || diagnostic_a_mismatch_bitmap != '0 ||
            diagnostic_b_mismatch_bitmap != 34'b1)
            fail("B-only snapshot counters or bitmaps were wrong");
        check_first_a(1'b0, '0, '0, '0, '0, '0, "B-only mismatch");
        check_first_b(1'b1, 7'd0, 3'd0, 16'hff00, 16'hb0b0, 16'h3300,
                      "B-only mismatch");

        pulse_diagnostic_clear();

        // Both streams may first fail at different commands.  Disabled sensor
        // one is corrupted at every command and must not affect diagnostics.
        rx_a = expect_a;
        rx_b = expect_b;
        for (int command_index = 0; command_index < MAX_COMMANDS; command_index++) begin
            rx_a[command_index][1] ^= 16'h00ff;
            rx_b[command_index][1] ^= 16'hff00;
        end
        rx_a[5][0] = 16'ha5a5;
        rx_a[32][0] = 16'ha032;
        rx_b[7][0] = 16'hb707;
        rx_b[33][0] = 16'hb033;
        expected_a_bitmap = (34'b1 << 5) | (34'b1 << 32);
        expected_b_bitmap = (34'b1 << 7) | (34'b1 << 33);
        start_init_attempt();
        finish_init_attempt(1'b0, "split A/B and final mismatch");
        if (diagnostic_a_mismatch_count != 2 || diagnostic_b_mismatch_count != 2 ||
            diagnostic_a_mismatch_bitmap != expected_a_bitmap ||
            diagnostic_b_mismatch_bitmap != expected_b_bitmap)
            fail("split/final mismatch counts or 34-bit bitmaps were wrong");
        check_first_a(1'b1, 7'd5, 3'd0, 16'hff05, 16'ha5a5, 16'h1105,
                      "split A/B mismatch");
        check_first_b(1'b1, 7'd7, 3'd0, 16'hff07, 16'hb707, 16'h3307,
                      "split A/B mismatch");

        // Clear during verification invalidates the old snapshot without
        // pausing the state machine, and this active attempt can publish anew.
        rx_a = expect_a;
        rx_b = expect_b;
        rx_b[1][0] = 16'hb1b1;
        start_init_attempt();
        pulse_done();
        if (!busy || init_done_pulse || err)
            fail("active-clear attempt completed on the sequence-done cycle");
        pulse_diagnostic_clear();
        expect_no_snapshot("clear during active attempt");
        wait_init_attempt(1'b0, "clear during active attempt");
        if (!diagnostic_snapshot_valid || diagnostic_attempt_count != 0 ||
            diagnostic_a_mismatch_count != 0 || diagnostic_b_mismatch_count != 1 ||
            diagnostic_b_mismatch_bitmap != (34'b1 << 1))
            fail("active attempt did not publish after diagnostic clear");
        check_first_b(1'b1, 7'd1, 3'd0, 16'hff01, 16'hb1b1, 16'h3301,
                      "clear during active attempt");

        // Clear on the publication clock wins.  The next failed retry may then
        // publish, demonstrating that simultaneous clear does not leave a torn snapshot.
        rx_a = expect_a;
        rx_b = expect_b;
        rx_a[9][0] = 16'ha9a9;
        start_init_attempt();
        pulse_done();
        while (diagnostic_state != ST_VERIFY_DONE) step();
        diagnostic_clear = 1'b1;
        step();
        diagnostic_clear = 1'b0;
        if (!err || busy || diagnostic_snapshot_valid || diagnostic_attempt_count != 0)
            fail("diagnostic clear did not win over simultaneous snapshot publication");

        rx_a = expect_a;
        rx_b = expect_b;
        rx_a[10][0] = 16'haaaa;
        start_init_attempt();
        finish_init_attempt(1'b0, "post-clear failed retry");
        if (!diagnostic_snapshot_valid || diagnostic_attempt_count != 1 ||
            diagnostic_a_mismatch_count != 1 ||
            diagnostic_a_mismatch_bitmap != (34'b1 << 10))
            fail("failed retry did not publish after publication-cycle clear");
        check_first_a(1'b1, 7'd10, 3'd0, 16'hff0a, 16'haaaa, 16'h110a,
                      "post-clear failed retry");

        // A clean active sensor succeeds even with every inactive response bad.
        pulse_diagnostic_clear();
        rx_a = expect_a;
        rx_b = expect_b;
        for (int command_index = 0; command_index < MAX_COMMANDS; command_index++) begin
            rx_a[command_index][1] ^= 16'hffff;
            rx_b[command_index][1] ^= 16'hffff;
        end
        start_init_attempt();
        finish_init_attempt(1'b1, "inactive responses ignored on successful retry");
        if (diagnostic_attempt_count != 1)
            fail("successful initialization attempt was not counted");
        expect_no_snapshot("successful initialization");
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
