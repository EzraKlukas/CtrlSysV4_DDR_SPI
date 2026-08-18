/* 
Name: Gordon Zhao / Ezra Klukas
File: acquisition_controller.sv
Description: FPGA-side acquisition controller, initializes Intan sensors.
*/

`timescale 1ns / 1ps

module acquisition_controller (
    input  logic        clk,
    input  logic        rst,
    input  logic        intan_initialized,
    input  logic        intan_busy,
    input  logic        icm_busy,
    input  logic        enable,                 // Trigger reads while enable is high
    input  logic [63:0] timestamp,
    input  logic [63:0] sample_period_ICM,
    input  logic [63:0] sample_period_Intan,
    output logic        startInit_Intan,
    output logic        startRead_ICM,          // ICM read start pulse
    output logic        startRead_Intan,        // Intan RHD2164 read start pulse
    output logic [31:0] missedRead_ICM_count,
    output logic [31:0] missedRead_Intan_count
);

    logic init_request_pending;
    logic acquisition_active;

    assign acquisition_active = enable && intan_initialized;

    acquisition_deadline_scheduler u_icm_scheduler (
        .clk(clk),
        .rst(rst),
        .active(acquisition_active),
        .busy(icm_busy),
        .timestamp(timestamp),
        .sample_period(sample_period_ICM),
        .start_read(startRead_ICM),
        .missed_read_count(missedRead_ICM_count)
    );

    acquisition_deadline_scheduler u_intan_scheduler (
        .clk(clk),
        .rst(rst),
        .active(acquisition_active),
        .busy(intan_busy),
        .timestamp(timestamp),
        .sample_period(sample_period_Intan),
        .start_read(startRead_Intan),
        .missed_read_count(missedRead_Intan_count)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            startInit_Intan <= 0;
            init_request_pending <= 0;
        end else begin
            startInit_Intan <= 0;

            if (intan_initialized) begin
                init_request_pending <= 1'b0;
            end else if (intan_busy) begin
                // The previous request was accepted.  Arm one retry for when
                // this initialization attempt completes unsuccessfully.
                init_request_pending <= 1'b0;
            end else if (!init_request_pending) begin
                startInit_Intan <= 1'b1;
                init_request_pending <= 1'b1;
            end
        end
    end

endmodule

module acquisition_deadline_scheduler (
    input  logic        clk,
    input  logic        rst,
    input  logic        active,
    input  logic        busy,
    input  logic [63:0] timestamp,
    input  logic [63:0] sample_period,
    output logic        start_read,
    output logic [31:0] missed_read_count
);

    logic active_q;
    logic [63:0] next_deadline;
    logic [63:0] late_deadline;
    logic        reanchor_pending;
    logic [63:0] reanchor_timestamp;
    logic [63:0] reanchor_period;
    logic due;
    logic late;

    // The live timestamp reaches only these registered-deadline comparators.
    // A reanchor decision captures its inputs before any deadline arithmetic,
    // so timestamp cannot feed a deadline-register D input in the same cycle.
    assign due = !reanchor_pending && sample_period != 0 && timestamp >= next_deadline;
    assign late = !reanchor_pending && sample_period != 0 && timestamp >= late_deadline;

    always_ff @(posedge clk) begin
        if (rst) begin
            active_q <= 1'b0;
            next_deadline <= '0;
            late_deadline <= '0;
            reanchor_pending <= 1'b0;
            reanchor_timestamp <= '0;
            reanchor_period <= '0;
            start_read <= 1'b0;
            missed_read_count <= '0;
        end else begin
            start_read <= 1'b0;

            if (!active) begin
                reanchor_pending <= 1'b0;
            end else if (reanchor_pending) begin
                // The event timestamp and period were captured on the cycle
                // that issued/counts the read, preserving the original anchor.
                next_deadline <= reanchor_timestamp + reanchor_period;
                late_deadline <= reanchor_timestamp + (reanchor_period << 1);
                reanchor_pending <= 1'b0;
            end else if (!active_q) begin
                if (busy)
                    missed_read_count <= missed_read_count + 1'b1;
                else
                    start_read <= 1'b1;

                reanchor_timestamp <= timestamp;
                reanchor_period <= sample_period;
                reanchor_pending <= 1'b1;
            end else if (due) begin
                if (!busy)
                    start_read <= 1'b1;
                if (busy || late)
                    missed_read_count <= missed_read_count + 1'b1;

                if (busy || late) begin
                    // A missed or late schedule is reanchored to avoid a burst
                    // of stale catch-up requests.
                    reanchor_timestamp <= timestamp;
                    reanchor_period <= sample_period;
                    reanchor_pending <= 1'b1;
                end else begin
                    // Advance from the scheduled deadline to avoid drift.
                    next_deadline <= next_deadline + sample_period;
                    late_deadline <= late_deadline + sample_period;
                end
            end

            active_q <= active;
        end
    end

endmodule
