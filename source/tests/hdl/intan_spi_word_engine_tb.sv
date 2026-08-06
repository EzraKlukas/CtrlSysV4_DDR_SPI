`timescale 1ns / 1ps

/*
 * Self-checking testbench for intan_spi_word_engine.
 *
 * The main DUT is connected to two rhd2164_model instances.  Both models use
 * the datasheet's maximum 12 ns MISO output delay, so the ordinary functional
 * tests also exercise the worst permitted output timing.
 *
 * A second word-engine instance is used only for the reset-abort test.  The
 * sensor model quite reasonably reports a short SPI word as a protocol error,
 * whereas resetting the controller in the middle of a word intentionally
 * creates such a short word at the pins.  Keeping that test separate lets us
 * verify the controller's reset behavior without teaching the sensor model
 * about the controller's reset signal.
 */

module intan_spi_word_engine_tb;
    timeunit 1ns; timeprecision 1ps;

    localparam time CLK_PERIOD = 8ns;  // 125 MHz fabric clock.

    localparam int NUM_INTAN = 2;
    localparam int BITS_PER_WORD = 16;

    /*
     * Three 125 MHz fabric clocks per half-period gives a 20.833 MHz SCLK:
     * below the 24 MHz maximum, with 24 ns high and low times.
     */
    localparam int SCLK_HALF_PERIOD_CYCLES = 3;
    localparam int T_CS_1_CYCLES = 6;
    localparam int T_CS_2_CYCLES = 6;
    localparam int T_CS_OFF_CYCLES = 20;

    localparam realtime T_SCLK_HIGH_MIN = 20.8ns;
    localparam realtime T_SCLK_LOW_MIN = 20.8ns;
    localparam realtime T_CS_TO_SCLK_MIN = 20.8ns;
    localparam realtime T_SCLK_TO_CS_MIN = 20.8ns;
    localparam time T_CS_HIGH_MIN = 154ns;
    localparam time T_MISO_MAX = 12ns;

    localparam logic [15:0] ONE_SHOT_COMMAND = 16'hCAFE;
    localparam logic [15:0] CONVERT_CHANNEL_5 = 16'h0500;

    localparam logic [15:0] SENSOR_0_EXPECT_A = 16'h1005;
    localparam logic [15:0] SENSOR_0_EXPECT_B = 16'h1025;
    localparam logic [15:0] SENSOR_1_EXPECT_A = 16'h1105;
    localparam logic [15:0] SENSOR_1_EXPECT_B = 16'h1125;

    logic clk;

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Main DUT and its two sensor models.
    logic rst = 1'b1;
    logic run_cyclic = 1'b0;
    logic done_pulse;
    logic [15:0] tx_word = '0;
    logic [NUM_INTAN-1:0][BITS_PER_WORD-1:0] rx_word_a;
    logic [NUM_INTAN-1:0][BITS_PER_WORD-1:0] rx_word_b;
    logic sclk;
    logic mosi;
    wire [NUM_INTAN-1:0] miso;
    logic cs_n = 1'b1;

    logic [15:0] captured_command_0;
    logic [15:0] captured_command_1;
    logic command_valid_0;
    logic command_valid_1;

    // Separate DUT used to test reset in the middle of a transfer.
    logic abort_rst = 1'b1;
    logic abort_run_cyclic = 1'b0;
    logic abort_done_pulse;
    logic [15:0] abort_tx_word = 16'h5AA5;
    logic [NUM_INTAN-1:0][BITS_PER_WORD-1:0] abort_rx_word_a;
    logic [NUM_INTAN-1:0][BITS_PER_WORD-1:0] abort_rx_word_b;
    logic abort_sclk;
    logic abort_mosi;
    logic abort_cs_n;

    int transaction_count;
    initial transaction_count = 0;
    int done_count;
    initial done_count = 0;
    int command_count_0;
    initial command_count_0 = 0;
    int command_count_1;
    initial command_count_1 = 0;
    logic [15:0] expected_model_command = '0;

    bit transaction_active;
    initial transaction_active = 1'b0;
    int transaction_rise_count;
    initial transaction_rise_count = 0;
    int transaction_fall_count;
    initial transaction_fall_count = 0;
    logic [15:0] observed_mosi_word;
    initial observed_mosi_word = '0;

    realtime transaction_cs_fall_time;
    realtime previous_cs_rise_time;
    realtime previous_sclk_rise_time;
    realtime previous_sclk_fall_time;
    bit have_previous_transaction;

    initial transaction_cs_fall_time = 0.0;
    initial previous_cs_rise_time = 0.0;
    initial previous_sclk_rise_time = 0.0;
    initial previous_sclk_fall_time = 0.0;
    initial have_previous_transaction = 1'b0;

    realtime done_rise_time;
    bit done_is_high;

    initial done_rise_time = 0.0;
    initial done_is_high = 1'b0;

    intan_spi_word_engine #(
        .SCLK_HALF_PERIOD_CYCLES(SCLK_HALF_PERIOD_CYCLES),
        .NUM_INTAN(NUM_INTAN),
        .T_CS_1(T_CS_1_CYCLES),
        .T_CS_2(T_CS_2_CYCLES),
        .T_CS_OFF(T_CS_OFF_CYCLES),
        .BITS_PER_WORD(BITS_PER_WORD)
    ) dut (
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
        .fault_bit(0),
        .init_bit(1),
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
        .fault_bit(0),
        .init_bit(1),
        .captured_command(captured_command_1),
        .command_valid(command_valid_1)
    );

    intan_spi_word_engine #(
        .SCLK_HALF_PERIOD_CYCLES(SCLK_HALF_PERIOD_CYCLES),
        .NUM_INTAN(NUM_INTAN),
        .T_CS_1(T_CS_1_CYCLES),
        .T_CS_2(T_CS_2_CYCLES),
        .T_CS_OFF(T_CS_OFF_CYCLES),
        .BITS_PER_WORD(BITS_PER_WORD)
    ) abort_dut (
        .clk(clk),
        .rst(abort_rst),
        .run_cyclic(abort_run_cyclic),
        .done_pulse(abort_done_pulse),
        .tx_word(abort_tx_word),
        .rx_word_a(abort_rx_word_a),
        .rx_word_b(abort_rx_word_b),
        .sclk(abort_sclk),
        .mosi(abort_mosi),
        .miso({NUM_INTAN{1'b0}}),
        .cs_n(abort_cs_n)
    );

    task automatic fail(input string message);
        $fatal(1, "%0t: %s", $realtime, message);
    endtask

    task automatic check_main_idle(input string check_name);
        begin
            if (cs_n !== 1'b1) fail($sformatf("%s: expected CS high, got %b", check_name, cs_n));
            if (sclk !== 1'b0) fail($sformatf("%s: expected SCLK low, got %b", check_name, sclk));
            if (done_pulse !== 1'b0) fail($sformatf("%s: done_pulse should be low", check_name));
        end
    endtask

    task automatic wait_for_main_idle;
        begin
            wait (cs_n === 1'b1 && sclk === 1'b0);
            repeat (2) @(posedge clk);
        end
    endtask

    /*
     * Start exactly one word.  run_cyclic only needs to be present long
     * enough for the IDLE state to accept it; taking it low afterward must not
     * truncate the word already in progress.
     */
    task automatic run_one_transaction(input logic [15:0] command);
        int count_before;
        begin
            count_before = transaction_count;
            expected_model_command = command;
            tx_word = command;

            @(negedge clk);
            run_cyclic = 1'b1;
            @(negedge clk);
            run_cyclic = 1'b0;

            wait (transaction_count == count_before + 1);
            wait_for_main_idle;

            // repeat (T_CS_OFF_CYCLES) @(posedge clk);
            if (transaction_count != count_before + 1)
                fail("a one-shot request created more than one transaction");
        end
    endtask

    /*
     * Keep run_cyclic high for exactly transaction_total completions, then
     * remove it while the final transaction is still completing.
     */
    task automatic run_consecutive_transactions(input logic [15:0] command,
                                                input int transaction_total);
        int count_before;
        int done_before;
        begin
            count_before = transaction_count;
            done_before = done_count;
            expected_model_command = command;
            tx_word = command;

            @(negedge clk);
            run_cyclic = 1'b1;
            wait (done_count == done_before + transaction_total);
            @(negedge clk);
            run_cyclic = 1'b0;

            wait (transaction_count == count_before + transaction_total);
            wait_for_main_idle;

            repeat (T_CS_OFF_CYCLES + 4) @(posedge clk);
            if (transaction_count != count_before + transaction_total)
                fail("run_cyclic low did not stop after the current transaction");
        end
    endtask

    // Pin-level transaction and timing scoreboard.
    always @(negedge cs_n) begin
        if (!rst) begin
            if (transaction_active) fail("CS fell while another transaction was active");

            if (have_previous_transaction && (($realtime - previous_cs_rise_time) < T_CS_HIGH_MIN))
                fail($sformatf(
                     "CS high gap was %0t; minimum is %0t",
                     $realtime - previous_cs_rise_time,
                     T_CS_HIGH_MIN
                     ));

            transaction_active = 1'b1;
            transaction_rise_count = 0;
            transaction_fall_count = 0;
            observed_mosi_word = '0;
            transaction_cs_fall_time = $realtime;
        end
    end

    always @(posedge sclk) begin
        if (!rst && !cs_n) begin
            if (!transaction_active) fail("SCLK rose without an active transaction");

            if ((transaction_rise_count == 0)
                && (($realtime - transaction_cs_fall_time) < T_CS_TO_SCLK_MIN))
                fail($sformatf(
                     "CS setup time was %0t; minimum is %0t",
                     $realtime - transaction_cs_fall_time,
                     T_CS_TO_SCLK_MIN
                     ));

            if ((transaction_fall_count > 0)
                && (($realtime - previous_sclk_fall_time) < T_SCLK_LOW_MIN))
                fail($sformatf(
                     "SCLK low time was %0t; minimum is %0t",
                     $realtime - previous_sclk_fall_time,
                     T_SCLK_LOW_MIN
                     ));

            observed_mosi_word = {observed_mosi_word[14:0], mosi};
            transaction_rise_count = transaction_rise_count + 1;
            previous_sclk_rise_time = $realtime;
        end
    end

    always @(negedge sclk) begin
        if (!rst && !cs_n) begin
            if (!transaction_active) fail("SCLK fell without an active transaction");

            if (($realtime - previous_sclk_rise_time) < T_SCLK_HIGH_MIN)
                fail($sformatf(
                     "SCLK high time was %0t; minimum is %0t",
                     $realtime - previous_sclk_rise_time,
                     T_SCLK_HIGH_MIN
                     ));

            transaction_fall_count  = transaction_fall_count + 1;
            previous_sclk_fall_time = $realtime;
        end
    end

    always @(posedge cs_n) begin
        if (!rst && transaction_active) begin
            if (transaction_rise_count != BITS_PER_WORD)
                fail($sformatf(
                     "transaction had %0d rising SCLK edges; expected %0d",
                     transaction_rise_count,
                     BITS_PER_WORD
                     ));
            if (transaction_fall_count != BITS_PER_WORD)
                fail($sformatf(
                     "transaction had %0d falling SCLK edges; expected %0d",
                     transaction_fall_count,
                     BITS_PER_WORD
                     ));
            if (observed_mosi_word !== expected_model_command)
                fail($sformatf(
                     "MOSI word was 0x%04h; expected 0x%04h",
                     observed_mosi_word,
                     expected_model_command
                     ));
            if (($realtime - previous_sclk_fall_time) < T_SCLK_TO_CS_MIN)
                fail($sformatf(
                     "CS hold time was %0t; minimum is %0t",
                     $realtime - previous_sclk_fall_time,
                     T_SCLK_TO_CS_MIN
                     ));

            transaction_count = transaction_count + 1;
            transaction_active = 1'b0;
            previous_cs_rise_time = $realtime;
            have_previous_transaction = 1'b1;
        end
    end

    // Both sensor models must receive the same complete command.
    always @(posedge command_valid_0) begin
        if (captured_command_0 !== expected_model_command)
            fail($sformatf(
                 "sensor 0 captured 0x%04h; expected 0x%04h",
                 captured_command_0,
                 expected_model_command
                 ));
        command_count_0 = command_count_0 + 1;
    end

    always @(posedge command_valid_1) begin
        if (captured_command_1 !== expected_model_command)
            fail($sformatf(
                 "sensor 1 captured 0x%04h; expected 0x%04h",
                 captured_command_1,
                 expected_model_command
                 ));
        command_count_1 = command_count_1 + 1;
    end

    // done_pulse must be exactly one fabric-clock period wide.
    always @(posedge done_pulse) begin
        if (done_is_high) fail("done_pulse rose while it was already high");
        done_is_high = 1'b1;
        done_rise_time = $realtime;
        done_count = done_count + 1;
    end

    always @(negedge done_pulse) begin
        if (!rst && done_is_high) begin
            if (($realtime - done_rise_time) != CLK_PERIOD)
                fail($sformatf(
                     "done_pulse width was %0t; expected one %0t fabric-clock period",
                     $realtime - done_rise_time,
                     CLK_PERIOD
                     ));
            done_is_high <= 1'b0;
        end
    end

    initial begin
        $dumpfile("intan_word_engine.fst");
        $dumpvars(0, intan_spi_word_engine_tb);
    end

    initial begin : test_sequence
        int transaction_count_before;
        int command_count_before_0;
        int command_count_before_1;

        // Reset and idle-level test.
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (20) @(posedge clk);  // respecting T_CS_OFF
        check_main_idle("after reset");

        // One request must be one 16-clock, MSB-first transaction.
        transaction_count_before = transaction_count;
        command_count_before_0   = command_count_0;
        command_count_before_1   = command_count_1;
        run_one_transaction(ONE_SHOT_COMMAND);

        if (transaction_count != transaction_count_before + 1)
            fail("one-shot transaction count mismatch");
        if (command_count_0 != command_count_before_0 + 1)
            fail("sensor 0 did not receive exactly one command");
        if (command_count_1 != command_count_before_1 + 1)
            fail("sensor 1 did not receive exactly one command");

        /*
         * The RHD2164 response to a command appears two transactions later.
         * Three identical CONVERT commands therefore make the final received
         * words deterministic regardless of the preceding one-shot command.
         * This also tests consecutive transactions and clean stopping.
         */
        transaction_count_before = transaction_count;
        command_count_before_0   = command_count_0;
        command_count_before_1   = command_count_1;
        run_consecutive_transactions(CONVERT_CHANNEL_5, 3);

        if (transaction_count != transaction_count_before + 3)
            fail("holding run_cyclic high did not create three transactions");
        if (command_count_0 != command_count_before_0 + 3)
            fail("sensor 0 did not receive all consecutive commands");
        if (command_count_1 != command_count_before_1 + 3)
            fail("sensor 1 did not receive all consecutive commands");

        if (rx_word_a[0] !== SENSOR_0_EXPECT_A)
            fail($sformatf(
                 "sensor 0 A response was 0x%04h; expected 0x%04h", rx_word_a[0], SENSOR_0_EXPECT_A
                 ));
        if (rx_word_b[0] !== SENSOR_0_EXPECT_B)
            fail($sformatf(
                 "sensor 0 B response was 0x%04h; expected 0x%04h", rx_word_b[0], SENSOR_0_EXPECT_B
                 ));
        if (rx_word_a[1] !== SENSOR_1_EXPECT_A)
            fail($sformatf(
                 "sensor 1 A response was 0x%04h; expected 0x%04h", rx_word_a[1], SENSOR_1_EXPECT_A
                 ));
        if (rx_word_b[1] !== SENSOR_1_EXPECT_B)
            fail($sformatf(
                 "sensor 1 B response was 0x%04h; expected 0x%04h", rx_word_b[1], SENSOR_1_EXPECT_B
                 ));

        if (rx_word_a[0] === rx_word_a[1])
            fail("sensor 0 and sensor 1 A responses were not distinct");
        if (rx_word_b[0] === rx_word_b[1])
            fail("sensor 0 and sensor 1 B responses were not distinct");

        check_main_idle("after run_cyclic was removed");

        // Reset during a transfer must synchronously restore idle pin levels.
        repeat (3) @(posedge clk);
        abort_rst = 1'b0;
        repeat (20) @(posedge clk);

        @(negedge clk);
        abort_run_cyclic = 1'b1;
        @(negedge clk);
        abort_run_cyclic = 1'b0;

        wait (abort_cs_n === 1'b0);
        repeat (3) @(posedge abort_sclk);
        @(negedge clk);
        abort_rst = 1'b1;
        @(posedge clk);
        #1ps;

        if (abort_cs_n !== 1'b1) fail("reset during transfer did not drive CS high");
        if (abort_sclk !== 1'b0) fail("reset during transfer did not drive SCLK low");
        if (abort_done_pulse !== 1'b0) fail("reset during transfer left done_pulse asserted");

        repeat (2) @(posedge clk);
        abort_rst = 1'b0;
        repeat (2) @(posedge clk);
        if (abort_cs_n !== 1'b1 || abort_sclk !== 1'b0)
            fail("reset-abort DUT did not remain idle after reset release");

        $display("PASS intan_spi_word_engine_tb: %0d transactions at T_MISO=%0t",
                 transaction_count, T_MISO_MAX);
        $finish;
    end

    initial begin : timeout
        #1ms;
        $fatal(1, "intan_spi_word_engine_tb timed out");
    end

endmodule
