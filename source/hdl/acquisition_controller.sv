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
    input  logic        enable,               // Trigger reads while enable is high
    input  logic [63:0] timestamp,
    input  logic [63:0] sample_period_ICM,
    input  logic [63:0] sample_period_Intan,
    output logic        startInit_Intan,
    output logic        startRead_ICM,        // ICM read start pulse
    output logic        startRead_Intan,      // Intan RHD2164 read start pulse
    output logic [31:0] missedRead_ICM_count,
    output logic [31:0] missedRead_Intan_count
);

    logic [63:0] prev_sample_time_ICM;
    logic [63:0] prev_sample_time_Intan;
    logic prev_acquisition_active;
    logic init_request_pending;
    logic acquisition_active;
    logic icm_due;
    logic intan_due;
    logic icm_late;
    logic intan_late;

    assign acquisition_active = enable && intan_initialized;
    assign icm_due = sample_period_ICM != 0 && (timestamp - prev_sample_time_ICM) >= sample_period_ICM;
    assign intan_due =
        sample_period_Intan != 0 && (timestamp - prev_sample_time_Intan) >= sample_period_Intan;
    assign icm_late =
        sample_period_ICM != 0 && (timestamp - prev_sample_time_ICM) >= (sample_period_ICM << 1);
    assign intan_late =
        sample_period_Intan != 0 &&
        (timestamp - prev_sample_time_Intan) >= (sample_period_Intan << 1);

    always_ff @(posedge clk) begin
        if (rst) begin
            prev_sample_time_ICM  <= 0;
            prev_sample_time_Intan <= 0;
            startInit_Intan <= 0;
            startRead_ICM <= 0;
            startRead_Intan <= 0;
            missedRead_ICM_count <= 0;
            missedRead_Intan_count <= 0;
            prev_acquisition_active <= 0;
            init_request_pending <= 0;
        end else begin
            startInit_Intan <= 0;
            startRead_ICM <= 0;
            startRead_Intan <= 0;

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

            if (acquisition_active && !prev_acquisition_active) begin
                prev_sample_time_ICM <= timestamp;
                prev_sample_time_Intan <= timestamp;
                if (!icm_busy) startRead_ICM <= 1'b1;
                else missedRead_ICM_count <= missedRead_ICM_count + 1'b1;
                if (!intan_busy) startRead_Intan <= 1'b1;
                else missedRead_Intan_count <= missedRead_Intan_count + 1'b1;
            end else if (acquisition_active) begin
                if (icm_due) begin
                    if (!icm_busy) startRead_ICM <= 1'b1;
                    if (icm_busy || icm_late)
                        missedRead_ICM_count <= missedRead_ICM_count + 1'b1;

                    if (icm_late || icm_busy) prev_sample_time_ICM <= timestamp;
                    else prev_sample_time_ICM <= prev_sample_time_ICM + sample_period_ICM;
                end

                if (intan_due) begin
                    if (!intan_busy) startRead_Intan <= 1'b1;
                    if (intan_busy || intan_late)
                        missedRead_Intan_count <= missedRead_Intan_count + 1'b1;

                    if (intan_late || intan_busy) prev_sample_time_Intan <= timestamp;
                    else prev_sample_time_Intan <= prev_sample_time_Intan + sample_period_Intan;
                end
            end else begin
                if (prev_acquisition_active) begin
                    prev_sample_time_ICM <= timestamp;
                    prev_sample_time_Intan <= timestamp;
                end
            end

            prev_acquisition_active <= acquisition_active;
        end
    end

endmodule
