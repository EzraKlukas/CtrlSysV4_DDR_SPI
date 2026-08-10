`timescale 1ns / 1ps

module acquisition_controller_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic intan_initialized = 1'b0;
    logic intan_busy = 1'b0;
    logic icm_busy = 1'b0;
    logic enable = 1'b0;
    logic [63:0] timestamp = '0;
    logic [63:0] timestamp_increment = 64'd1;
    logic [63:0] sample_period_ICM = 64'd8;
    logic [63:0] sample_period_Intan = 64'd4;
    logic startInit_Intan;
    logic startRead_ICM;
    logic startRead_Intan;
    logic [31:0] missedRead_ICM_count;
    logic [31:0] missedRead_Intan_count;

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (rst) timestamp <= '0;
        else timestamp <= timestamp + timestamp_increment;
    end

    acquisition_controller dut (
        .clk(clk),
        .rst(rst),
        .intan_initialized(intan_initialized),
        .intan_busy(intan_busy),
        .icm_busy(icm_busy),
        .enable(enable),
        .timestamp(timestamp),
        .sample_period_ICM(sample_period_ICM),
        .sample_period_Intan(sample_period_Intan),
        .startInit_Intan(startInit_Intan),
        .startRead_ICM(startRead_ICM),
        .startRead_Intan(startRead_Intan),
        .missedRead_ICM_count(missedRead_ICM_count),
        .missedRead_Intan_count(missedRead_Intan_count)
    );

    task automatic fail(input string message);
        $fatal(1, "%0t: %s", $time, message);
    endtask

    task automatic step();
        @(posedge clk);
        #1;
    endtask

    initial begin
        repeat (3) step();
        rst = 1'b0;
        step();

        if (!startInit_Intan) fail("uninitialized idle controller did not request init");
        if (startRead_ICM || startRead_Intan) fail("controller issued reads before init");

        step();
        if (startInit_Intan) fail("initialization request was held high for multiple clocks");

        intan_busy = 1'b1;
        step();
        if (startInit_Intan) fail("init request asserted while Intan reader busy");

        enable = 1'b1;
        step();
        if (startRead_ICM || startRead_Intan) fail("enable high caused reads before init");

        intan_busy = 1'b0;
        intan_initialized = 1'b1;
        step();
        if (!startRead_ICM || !startRead_Intan)
            fail("initialization completion while enable high did not start acquisition");

        begin : wait_for_intan_period
            int waited = 0;
            step();
            while (!startRead_Intan && waited < 8) begin
                if (startRead_ICM) fail("ICM fired at the Intan-only deadline");
                waited = waited + 1;
                step();
            end
            if (!startRead_Intan || startRead_ICM)
                fail("Intan period did not fire independently");
        end

        intan_busy = 1'b1;
        begin : wait_for_intan_miss
            logic [31:0] initial_misses;
            int waited = 0;
            initial_misses = missedRead_Intan_count;
            while (missedRead_Intan_count == initial_misses && waited < 8) begin
                step();
                if (startRead_Intan) fail("Intan read was issued while busy");
                waited = waited + 1;
            end
        end
        if (missedRead_Intan_count == 0) fail("busy Intan deadline miss was not counted");
        if (startRead_Intan) fail("Intan read was issued while busy");

        intan_busy = 1'b0;
        step();
        if (startRead_Intan) fail("controller burst a stale Intan read after busy cleared");

        icm_busy = 1'b1;
        begin : wait_for_icm_miss
            logic [31:0] initial_misses;
            int waited = 0;
            initial_misses = missedRead_ICM_count;
            while (missedRead_ICM_count == initial_misses && waited < 12) begin
                step();
                if (startRead_ICM) fail("ICM read was issued while busy");
                waited = waited + 1;
            end
        end
        if (missedRead_ICM_count == 0) fail("busy ICM deadline miss was not counted");
        if (startRead_ICM) fail("ICM read was issued while busy");

        icm_busy = 1'b0;
        enable = 1'b0;
        step();
        enable = 1'b1;
        step();
        if (!startRead_Intan || !startRead_ICM)
            fail("re-enable did not re-anchor and issue initial reads");
        timestamp_increment = 64'd20;
        step();
        timestamp_increment = 64'd1;
        begin : check_late_idle_deadline
            logic [31:0] initial_misses;
            initial_misses = missedRead_Intan_count;
            step();
            if (!startRead_Intan) fail("late idle deadline did not issue one current read");
            if (missedRead_Intan_count != initial_misses + 1'b1)
                fail("late idle deadline was not counted");
        end
        step();
        if (startRead_Intan) fail("late idle deadline caused a catch-up burst");

        enable = 1'b0;
        repeat (3) step();
        if (startRead_ICM || startRead_Intan) fail("reads continued while acquisition disabled");

        $display("PASS acquisition_controller_tb");
        $finish;
    end
endmodule
