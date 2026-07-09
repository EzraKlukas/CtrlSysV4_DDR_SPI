/*
Name: Ezra Klukas
File: Intan_reader.sv
Description: Synthetic Intan frame source for datapath testing.
*/

import config_pkg::*;

module Intan_reader #(
    parameter int ST_DONE_DELAY_CYCLES = 1,
    parameter integer SCLK_HALF_PERIOD = 63,
    parameter int NUM_INTAN = config_pkg::NUM_INTAN,
    parameter int INTAN_DATA_BYTES = config_pkg::INTAN_DATA_BYTES,
    parameter int BITS_PER_WORD = 16,
    parameter integer T_CS_1 = config_pkg::INTAN_T_CS_1,
    parameter integer T_CS_2 = config_pkg::INTAN_T_CS_2,
    parameter integer T_MOSI = config_pkg::INTAN_T_MOSI,
    parameter integer T_CS_OFF = config_pkg::INTAN_T_CS_OFF
) (
    input logic        clk,
    input logic        rst,
    input logic        start,
    input logic [63:0] timestamp,

    output Intan_frame_t Intan_frame,

    output logic busy,
    output logic done,

    // SPI lines
    output logic sclk,
    output logic mosi,
    input logic [NUM_INTAN-1:0] miso,
    output logic cs_n
);

    // sequential copies of spi lines
    logic cs_n_q;
    logic mosi_q;

    // FSM
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_CS_ASSERT_SETUP,  // wait t_{CS1}: CS low before first SCLK high
        ST_TRANSFER,  // 16 SCLK cycles: drive MOSI, capture DDR MISO
        ST_CS_DEASSERT_SETUP,  // wait t_{CS2}: final SCLK low before CS high
        ST_CS_HIGH_GAP,  // wait t_{CSOFF} before another transaction
        ST_DONE
    } intan_spi_state_t;

    intan_spi_state_t state;
    intan_spi_state_t next_state;

    logic [15:0] state_cycles_q;

    // data
    logic [15:0] tx_word;
    logic [BITS_PER_WORD * NUM_INTAN - 1:0] rx_word_a;
    logic [BITS_PER_WORD * NUM_INTAN - 1:0] rx_word_b;

    logic [15:0] next_tx_word;
    logic [BITS_PER_WORD * NUM_INTAN - 1:0] next_rx_word_a;
    logic [BITS_PER_WORD * NUM_INTAN - 1:0] next_rx_word_b;

    logic [5:0] channel_mod_32;

    logic [7:0] num_data_bytes;  // number of bytes in a given exchange (20 for ICM, 64 likely for 64-channel Intan? Or 128 actually since 64 channels * 2 bytes each?)

    // SPI timing related
    localparam int SCLK_DIV_CNT_W = (SCLK_HALF_PERIOD > 1) ? $clog2( // might have to change for DDR
        SCLK_HALF_PERIOD
    ) : 1;

    logic [SCLK_DIV_CNT_W-1:0] sclk_div_cnt;
    logic sclk_q;
    logic sclk_en;
    logic sclk_rise_stb;  // serial clock rising strobes (pulses on sclk transition)
    logic sclk_fall_stb;
    logic [3:0] sclk_cnt = 4'b0;  // probably increase, number of bits / SPI cycle (in SDR).

    initial begin
        if (SCLK_HALF_PERIOD < 1) $error("Intan_reader requires SCLK_HALF_PERIOD_CYCLES >= 1");
        if (NUM_INTAN != config_pkg::NUM_INTAN)
            $error("Intan_reader NUM_INTAN must match config_pkg::Intan_frame_t");
        if (INTAN_DATA_BYTES != config_pkg::INTAN_DATA_BYTES)
            $error("Intan_reader INTAN_DATA_BYTES must match config_pkg::Intan_measurement_t");
    end

    assign cs_n = cs_n_q;  // _n means active low
    assign mosi = mosi_q;
    assign sclk = sclk_q;
    assign busy = state != ST_IDLE;

    // SCLK generator
    always_ff @(posedge clk) begin
        if (rst) begin
            sclk_div_cnt <= '0;
            sclk_q <= 1'b0;
            sclk_rise_stb <= 1'b0;
            sclk_fall_stb <= 1'b0;
        end else begin
            sclk_rise_stb <= 1'b0;
            sclk_fall_stb <= 1'b0;
            if (sclk_en) begin
                if (sclk_div_cnt == SCLK_HALF_PERIOD - 1) begin
                    sclk_div_cnt <= '0;
                    sclk_q <= ~sclk_q;

                    if (sclk_q == 1'b0) begin
                        sclk_rise_stb <= 1'b1;
                    end else begin
                        sclk_fall_stb <= 1'b1;
                        sclk_cnt <= sclk_cnt - 1;
                    end
                end else begin
                    sclk_div_cnt <= sclk_div_cnt + 1'b1;
                end
            end else begin
                sclk_div_cnt <= '0;
                sclk_q <= 1'b0;  // Intan SCLK idle/base value is zero.
            end
        end
    end

    integer sensor_idx;
    // SPI sequential block -> clock driven
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            sclk_cnt <= 4'b0;
            tx_word <= 16'b0;
            rx_word_a <= '0;
            rx_word_b <= '0;
            sclk_en <= 1'b0;
        end else begin
            state <= next_state;
            tx_word <= next_tx_word;
            rx_word_a <= next_rx_word_a;
            rx_word_b <= next_rx_word_b;

            if (state != next_state) begin
                state_cycles_q <= 16'b0;
            end else begin
                state_cycles_q <= state_cycles_q + 16'b1;
            end
        end
    end

    // SPI combinational block -> state / input driven.
    always_comb begin
        next_state = state;
        next_tx_word = tx_word;
        next_rx_word_a = rx_word_a;
        next_rx_word_b = rx_word_b;

        case (state)
            ST_IDLE: begin
                // Drive SPI driven values to default inactive levels.
                cs_n_q = 1'b1;
                mosi_q = 1'b0;
                sclk_en = 1'b0;  // disabled sclk (so shouldn't drive sclk_q?)

                // Resetting rx_words as well.
                next_rx_word_a = '0;
                next_rx_word_b = '0;

                // Only next possible state is ST_CS_ASSERT_SETUP.
                if (start) begin
                    state = ST_CS_ASSERT_SETUP;
                end
            end

            ST_CS_ASSERT_SETUP: begin
                cs_n_q  = 1'b0;  // pull CS low
                mosi_q  = tx_word[0];  // drive MOSI right away.
                sclk_en = 1'b0;
                if (state_cycles_q == T_CS_1 - SCLK_HALF_PERIOD) begin
                    sclk_en = 1'b1;
                    state   = ST_TRANSFER;
                end
            end

            ST_TRANSFER: begin
                if (sclk_fall_stb) begin
                    mosi_q = tx_word[sclk_cnt-1];  // underflow is not a problem:)

                    for (sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1) begin
                        next_rx_word_a[sensor_idx*BITS_PER_WORD+sclk_cnt] = miso[sensor_idx];
                    end

                    // sclk_cnt == 0 corresponds with last SCLK fall.
                    if (sclk_cnt == 0) begin
                        state   = ST_CS_DEASSERT_SETUP;
                        sclk_en = 1'b0;
                    end
                end
                if (sclk_rise_stb) begin
                    for (sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1) begin
                        next_rx_word_b[sensor_idx*BITS_PER_WORD+sclk_cnt] = miso[sensor_idx];
                    end
                end
            end

            ST_CS_DEASSERT_SETUP: begin
                // take care of B0
                if (state_cycles_q == SCLK_HALF_PERIOD) begin
                    for (sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1) begin
                        next_rx_word_b[sensor_idx*BITS_PER_WORD+sclk_cnt] = miso[sensor_idx];
                    end
                end

                if (state_cycles_q == T_CS_2) begin
                    state = ST_CS_HIGH_GAP;
                end
            end

            ST_CS_HIGH_GAP: begin
                cs_n_q = 1'b1;
                if (state_cycles_q == T_CS_OFF) begin
                    state = ST_DONE;
                end
                // higher level condition needed to transition to ST_DONE.
            end

            ST_DONE: begin
            end
        endcase
    end
endmodule
