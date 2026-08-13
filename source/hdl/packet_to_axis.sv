`timescale 1ns/1ps

/*
Name: Gordon Zhao
File: packet_to_axis.sv
Description: Streams buffered packet words to AXI Stream.
*/

import config_pkg::*;

module packet_to_axis #(
    parameter int DATA_WIDTH = config_pkg::AXIS_DATA_WIDTH,
    parameter int PACKET_WORDS = config_pkg::PACKET_AXIS_WORDS,
    parameter int PACKET_LAST_BYTES = config_pkg::PACKET_LAST_BYTES
)(
    input  logic                    clk,
    input  logic                    rst,

    output logic                    fifo_rd_en,
    input  logic [DATA_WIDTH-1:0]   fifo_rd_data,
    input  logic                    fifo_packet_available,

    output logic                    m_axis_tvalid,
    input  logic                    m_axis_tready,
    output logic [DATA_WIDTH-1:0]   m_axis_tdata,
    output logic [DATA_WIDTH/8-1:0] m_axis_tkeep,
    output logic                    m_axis_tlast
);

localparam int WORD_COUNT_WIDTH = $clog2(PACKET_WORDS + 1);

typedef enum logic [1:0] {
    IDLE,
    WAIT_FOR_READ,
    CAPTURE_WORD,
    SEND_WORD
} state_t;

state_t state;
logic [WORD_COUNT_WIDTH-1:0] remaining_words;

initial begin
    if (DATA_WIDTH < 8 || (DATA_WIDTH % 8) != 0)
        $error("packet_to_axis requires DATA_WIDTH to be a positive byte multiple");
    if (PACKET_WORDS < 1)
        $error("packet_to_axis requires PACKET_WORDS >= 1");
    if (PACKET_LAST_BYTES != DATA_WIDTH / 8)
        $error("packet_to_axis currently expects full-width packet words");
    if (PACKET_LAST_BYTES < 1 || PACKET_LAST_BYTES > DATA_WIDTH / 8)
        $error("packet_to_axis requires 1 <= PACKET_LAST_BYTES <= DATA_WIDTH/8");
end

always_ff @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
        remaining_words <= '0;
        fifo_rd_en <= 1'b0;
        m_axis_tvalid <= 1'b0;
        m_axis_tdata <= '0;
        m_axis_tkeep <= '0;
        m_axis_tlast <= 1'b0;
    end else begin
        fifo_rd_en <= 1'b0;

        case (state)
            IDLE: begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
                m_axis_tkeep <= '0;

                if (fifo_packet_available) begin
                    remaining_words <= PACKET_WORDS;
                    fifo_rd_en <= 1'b1;
                    state <= WAIT_FOR_READ;
                end
            end

            WAIT_FOR_READ: begin
                state <= CAPTURE_WORD;
            end

            CAPTURE_WORD: begin
                m_axis_tdata <= fifo_rd_data;
                m_axis_tkeep <= '1;
                m_axis_tlast <= remaining_words == 1;
                m_axis_tvalid <= 1'b1;
                state <= SEND_WORD;
            end

            SEND_WORD: begin
                if (m_axis_tready) begin
                    m_axis_tvalid <= 1'b0;

                    if (remaining_words == 1) begin
                        remaining_words <= '0;
                        state <= IDLE;
                    end else begin
                        remaining_words <= remaining_words - 1'b1;
                        fifo_rd_en <= 1'b1;
                        state <= WAIT_FOR_READ;
                    end
                end
            end

            default: begin
                state <= IDLE;
                remaining_words <= '0;
                fifo_rd_en <= 1'b0;
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
                m_axis_tkeep <= '0;
            end
        endcase
    end
end

endmodule
