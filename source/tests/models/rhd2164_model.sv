/*
 * Lightweight, simulation-only model of one Intan RHD2164.
 *
 * Modeled behavior:
 *   - receives one 16-bit MOSI command, MSB first;
 *   - returns the RHD2164's interleaved A/B DDR MISO streams;
 *   - includes the real two-command response pipeline;
 *   - implements deterministic CONVERT data and basic READ/WRITE behavior;
 *   - exposes the most recently captured command to a testbench.
 *
 * Deliberate simplifications:
 *   - no analog behavior, noise, filters, saturation, or calibration time;
 *   - writable registers start at zero rather than an indeterminate value;
 *   - non-amplifier ADC channels return deterministic placeholder values;
 *   - register reads are deterministic on both streams even where the
 *     datasheet says that one stream is not meaningful;
 *   - invalid-command and calibration responses are zero.
 *
 * This is behavioral testbench code.  Do not add it to synthesis sources.
 */

module rhd2164_model #(
    parameter int SENSOR_ID = 0,
    parameter logic [15:0] SAMPLE_BASE = 16'h1000,

    // The datasheet permits up to 12 ns from the relevant sensor edge until
    // MISO is valid.  Use 0 ns for simple functional tests, then 12 ns for a
    // timing-margin test.
    parameter time T_MISO = 0ns,

    parameter bit CHECK_TIMING = 1'b1,
    parameter realtime T_SCLK_HIGH_MIN = 20.8ns,
    parameter realtime T_SCLK_LOW_MIN = 20.8ns,
    parameter realtime T_CS_TO_SCLK_MIN = 20.8ns,
    parameter realtime T_SCLK_TO_CS_MIN = 20.8ns,
    parameter realtime T_CS_HIGH_MIN = 154ns,

    // Register 4 controls real-chip behavior while CS is high.  High impedance
    // is the more useful default for catching accidental bus contention.
    parameter bit HIGH_Z_WHEN_DESELECTED = 1'b1
) (
    input  logic cs_n,
    input  logic sclk,
    input  logic mosi,
    output wire  miso,

    output logic [15:0] captured_command,
    output logic command_valid
);
    timeunit 1ns; timeprecision 1ps;

    localparam logic [15:0] SENSOR_OFFSET = SENSOR_ID * 16'h0100;

    logic [7:0] register_a[0:63];
    logic [7:0] register_b[0:63];

    logic [15:0] command_shift;
    logic [15:0] response_pipe_a_0;
    logic [15:0] response_pipe_a_1;
    logic [15:0] response_pipe_b_0;
    logic [15:0] response_pipe_b_1;
    logic [15:0] response_tx_a;
    logic [15:0] response_tx_b;

    integer rising_edge_count;
    integer falling_edge_count;
    integer register_index;

    realtime last_cs_fall;
    realtime last_cs_rise;
    realtime last_sclk_rise;
    realtime last_sclk_fall;
    bit have_seen_cs_fall;
    bit have_seen_cs_rise;

    function automatic logic [15:0] sample_for_channel(input logic [5:0] channel);
        sample_for_channel = SAMPLE_BASE + SENSOR_OFFSET + {10'b0, channel};
    endfunction

    function automatic logic [15:0] response_for_a(input logic [15:0] command);
        logic [5:0] address;
        begin
            address = command[13:8];

            unique case (command[15:14])
                2'b00: begin
                    // CONVERT(C): module A represents channels 0-31.
                    response_for_a = sample_for_channel(address);
                end

                2'b10: begin
                    // WRITE(R,D): the chip echoes D below an all-ones byte.
                    response_for_a = {8'hff, command[7:0]};
                end

                2'b11: begin
                    // READ(R): registers 18-21 are meaningful on MISO B only.
                    if ((address >= 6'd18) && (address <= 6'd21)) response_for_a = 16'h0000;
                    else response_for_a = {8'h00, register_a[address]};
                end

                default: response_for_a = 16'h0000;
            endcase
        end
    endfunction

    function automatic logic [15:0] response_for_b(input logic [15:0] command);
        logic [5:0] address;
        logic [5:0] channel_b;
        begin
            address   = command[13:8];
            channel_b = address + 6'd32;

            unique case (command[15:14])
                2'b00: begin
                    // CONVERT(C): module B simultaneously converts C + 32.
                    response_for_b = sample_for_channel(channel_b);
                end

                2'b10: begin
                    response_for_b = {8'hff, command[7:0]};
                end

                2'b11: begin
                    response_for_b = {8'h00, register_b[address]};
                end

                default: response_for_b = 16'h0000;
            endcase
        end
    endfunction

    initial begin
        command_shift = '0;
        captured_command = '0;
        command_valid = 1'b0;

        response_pipe_a_0 = '0;
        response_pipe_a_1 = '0;
        response_pipe_b_0 = '0;
        response_pipe_b_1 = '0;
        response_tx_a = '0;
        response_tx_b = '0;

        rising_edge_count = 0;
        falling_edge_count = 0;
        last_cs_fall = 0.0;
        last_cs_rise = 0.0;
        last_sclk_rise = 0.0;
        last_sclk_fall = 0.0;
        have_seen_cs_fall = 1'b0;
        have_seen_cs_rise = 1'b0;

        for (register_index = 0; register_index < 64; register_index = register_index + 1) begin
            register_a[register_index] = 8'h00;
            register_b[register_index] = 8'h00;
        end

        // Read-only identity registers.
        register_a[40] = "I";
        register_a[41] = "N";
        register_a[42] = "T";
        register_a[43] = "A";
        register_a[44] = "N";
        register_b[40] = "I";
        register_b[41] = "N";
        register_b[42] = "T";
        register_b[43] = "A";
        register_b[44] = "N";

        // RHD2164-specific identity values.
        register_a[59] = 8'd53;  // MISO A marker.
        register_b[59] = 8'd58;  // MISO B marker.
        register_a[60] = 8'd1;
        register_b[60] = 8'd1;
        register_a[61] = 8'd1;  // Unipolar amplifiers.
        register_b[61] = 8'd1;
        register_a[62] = 8'd64;  // Number of amplifiers.
        register_b[62] = 8'd64;
        register_a[63] = 8'd4;  // RHD2164 chip ID.
        register_b[63] = 8'd4;
    end

    // Beginning a chip-select cycle selects the response produced by the
    // command from two transactions ago.
    always @(negedge cs_n) begin
        if (CHECK_TIMING && have_seen_cs_rise && (($realtime - last_cs_rise) < T_CS_HIGH_MIN))
            $error(
                "rhd2164_model[%0d]: CS high time %0t is below %0t",
                SENSOR_ID,
                $realtime - last_cs_rise,
                T_CS_HIGH_MIN
            );

        last_cs_fall = $realtime;
        have_seen_cs_fall = 1'b1;
        command_shift = '0;
        rising_edge_count = 0;
        falling_edge_count = 0;
        response_tx_a = response_pipe_a_1;
        response_tx_b = response_pipe_b_1;
    end

    // The RHD2164 samples MOSI on each rising SCLK edge.
    always @(posedge sclk) begin
        if (!cs_n) begin
            if (CHECK_TIMING && (rising_edge_count == 0)
                && have_seen_cs_fall
                && (($realtime - last_cs_fall) < T_CS_TO_SCLK_MIN))
                $error(
                    "rhd2164_model[%0d]: CS-to-first-SCLK time %0t is below %0t",
                    SENSOR_ID,
                    $realtime - last_cs_fall,
                    T_CS_TO_SCLK_MIN
                );

            if (CHECK_TIMING && (falling_edge_count > 0)
                && (($realtime - last_sclk_fall) < T_SCLK_LOW_MIN))
                $error(
                    "rhd2164_model[%0d]: SCLK low time %0t is below %0t",
                    SENSOR_ID,
                    $realtime - last_sclk_fall,
                    T_SCLK_LOW_MIN
                );

            last_sclk_rise = $realtime;
            command_shift = {command_shift[14:0], mosi};
            rising_edge_count = rising_edge_count + 1;

            if (rising_edge_count > 16)
                $error("rhd2164_model[%0d]: more than 16 SCLK rising edges", SENSOR_ID);
        end
    end

    always @(negedge sclk) begin
        if (!cs_n) begin
            if (CHECK_TIMING && (($realtime - last_sclk_rise) < T_SCLK_HIGH_MIN))
                $error(
                    "rhd2164_model[%0d]: SCLK high time %0t is below %0t",
                    SENSOR_ID,
                    $realtime - last_sclk_rise,
                    T_SCLK_HIGH_MIN
                );

            last_sclk_fall = $realtime;
            falling_edge_count = falling_edge_count + 1;

            if (falling_edge_count > 16)
                $error("rhd2164_model[%0d]: more than 16 SCLK falling edges", SENSOR_ID);
        end
    end

    // Finish command capture, update the two-command pipeline, and perform
    // simple register writes when CS rises.
    always @(posedge cs_n) begin
        last_cs_rise = $realtime;
        have_seen_cs_rise = 1'b1;

        if ((rising_edge_count != 0) || (falling_edge_count != 0)) begin
            if (CHECK_TIMING && (($realtime - last_sclk_fall) < T_SCLK_TO_CS_MIN))
                $error(
                    "rhd2164_model[%0d]: final-SCLK-to-CS time %0t is below %0t",
                    SENSOR_ID,
                    $realtime - last_sclk_fall,
                    T_SCLK_TO_CS_MIN
                );

            if ((rising_edge_count != 16) || (falling_edge_count != 16))
                $error(
                    "rhd2164_model[%0d]: transaction had %0d rising and %0d falling SCLK edges",
                    SENSOR_ID,
                    rising_edge_count,
                    falling_edge_count
                );

            captured_command = command_shift;
            command_valid = 1'b1;

            response_pipe_a_1 = response_pipe_a_0;
            response_pipe_b_1 = response_pipe_b_0;
            response_pipe_a_0 = response_for_a(command_shift);
            response_pipe_b_0 = response_for_b(command_shift);

            if (command_shift[15:14] == 2'b10) begin
                // Registers 0-21 are writable on the RHD2164.
                if (command_shift[13:8] <= 6'd21) begin
                    register_a[command_shift[13:8]] = command_shift[7:0];
                    register_b[command_shift[13:8]] = command_shift[7:0];
                end
            end

            // A short event-like pulse makes command monitoring convenient
            // from either a SystemVerilog testbench or cocotb.
            #1ps command_valid = 1'b0;
        end
    end

    logic miso_data;

    always_comb begin
        // Keep the internal data path free of high-impedance values.
        miso_data = 1'b0;

        if (!cs_n && sclk) begin
            if (falling_edge_count <= 15) miso_data = response_tx_a[15-falling_edge_count];

        end else if (!cs_n) begin
            if ((rising_edge_count >= 1) && (rising_edge_count <= 16))
                miso_data = response_tx_b[16-rising_edge_count];
        end
    end

    // Apply high impedance only at the actual output net.
    assign #(T_MISO) miso = (cs_n && HIGH_Z_WHEN_DESELECTED) ? 1'bz : miso_data;

endmodule
