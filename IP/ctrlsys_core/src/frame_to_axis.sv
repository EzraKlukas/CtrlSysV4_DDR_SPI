`timescale 1ns/1ps

/* 
Name: Gordon Zhao
File: frame_to_axis.sv
Description: an AXI-Stream producer. takes sensor frames from the FIFO and streams to DMA
*/

import config_pkg::*;

module frame_to_axis #(
    parameter int NUM_SENSORS = 3,
    parameter int data_width = 32
)(
    input logic         clk,
    input logic         rst,

    // To/from Buffer
    output logic        rd_en,
    input logic         empty,
    input raw_packet_t  frame [NUM_SENSORS],

    // AXI
    output logic                    m_axis_tvalid,
    input logic                     m_axis_tready,
    output logic [data_width-1:0]   m_axis_tdata,
    output logic [data_width/8-1:0] m_axis_tkeep,
    output logic                    m_axis_tlast
);

localparam int WORDS_PER_PACKET = 9;
localparam int SENSOR_INDEX_WIDTH = (NUM_SENSORS > 1) ? $clog2(NUM_SENSORS) : 1;
localparam int WORD_INDEX_WIDTH   = (WORDS_PER_PACKET > 1) ? $clog2(WORDS_PER_PACKET) : 1;

typedef enum logic [1:0] {
    IDLE,
    WAIT_FOR_FRAME,
    LOAD_FRAME,
    SEND_FRAME
} state_t;

state_t state;
raw_packet_t active_frame [NUM_SENSORS];

logic [SENSOR_INDEX_WIDTH-1:0] sensor_index;
logic [WORD_INDEX_WIDTH-1:0] word_index;
int sensor_loop_index;

// 32-bit word order per sensor:
// 0 init_read_ts[31:0], 1 init_read_ts[63:32],
// 2 done_read_ts[31:0], 3 done_read_ts[63:32],
// 4-8 sensor_data.
function automatic logic [data_width-1:0] packet_word(
    input raw_packet_t packet,
    input int unsigned index
);
    logic [31:0] word32;
begin
    case (index)
        0: word32 = packet.init_read_ts[31:0];
        1: word32 = packet.init_read_ts[63:32];
        2: word32 = packet.done_read_ts[31:0];
        3: word32 = packet.done_read_ts[63:32];
        4: word32 = packet.sensor_data[31:0];
        5: word32 = packet.sensor_data[63:32];
        6: word32 = packet.sensor_data[95:64];
        7: word32 = packet.sensor_data[127:96];
        8: word32 = packet.sensor_data[159:128];
        default: word32 = 32'b0;
    endcase

    packet_word = word32;
end
endfunction

function automatic logic is_last_word(
    input int unsigned sensor,
    input int unsigned word
);
begin
    is_last_word = (sensor == NUM_SENSORS - 1) && (word == WORDS_PER_PACKET - 1);
end
endfunction

always_ff @(posedge clk) begin
    if (rst) begin
        state         <= IDLE;
        rd_en        <= 1'b0;
        m_axis_tvalid <= 1'b0;
        m_axis_tdata <= '0;
        m_axis_tkeep <= '0;
        m_axis_tlast <= 1'b0;
        sensor_index <= '0;
        word_index   <= '0;
        for (sensor_loop_index = 0; sensor_loop_index < NUM_SENSORS; sensor_loop_index++) begin
            active_frame[sensor_loop_index] <= '0;
        end
    end else begin
        rd_en <= 1'b0;

        case (state)
            IDLE: begin
                m_axis_tvalid <= 1'b0;
                m_axis_tkeep  <= '0;
                m_axis_tlast  <= 1'b0;

                if (!empty) begin
                    rd_en <= 1'b1;
                    state <= WAIT_FOR_FRAME;
                end
            end

            WAIT_FOR_FRAME: begin
                state <= LOAD_FRAME;
            end

            LOAD_FRAME: begin
                for (sensor_loop_index = 0; sensor_loop_index < NUM_SENSORS; sensor_loop_index++) begin
                    active_frame[sensor_loop_index] <= frame[sensor_loop_index];
                end
                sensor_index  <= '0;
                word_index    <= '0;
                m_axis_tdata  <= packet_word(frame[0], 0);
                m_axis_tvalid <= 1'b1;
                m_axis_tkeep  <= '1;
                m_axis_tlast  <= is_last_word(0, 0);
                state         <= SEND_FRAME;
            end

            SEND_FRAME: begin
                if (m_axis_tready) begin
                    if (is_last_word(sensor_index, word_index)) begin
                        m_axis_tvalid <= 1'b0;
                        m_axis_tkeep  <= '0;
                        m_axis_tlast  <= 1'b0;
                        sensor_index  <= '0;
                        word_index    <= '0;
                        state         <= IDLE;
                    end else if (word_index == WORDS_PER_PACKET - 1) begin
                        sensor_index  <= sensor_index + 1'b1;
                        word_index    <= '0;
                        m_axis_tdata  <= packet_word(active_frame[sensor_index + 1'b1], 0);
                        m_axis_tlast  <= is_last_word(sensor_index + 1'b1, 0);
                    end else begin
                        word_index    <= word_index + 1'b1;
                        m_axis_tdata  <= packet_word(active_frame[sensor_index], word_index + 1'b1);
                        m_axis_tlast  <= is_last_word(sensor_index, word_index + 1'b1);
                    end
                end
            end

            default: begin
                state         <= IDLE;
                rd_en         <= 1'b0;
                m_axis_tvalid <= 1'b0;
                m_axis_tkeep  <= '0;
                m_axis_tlast  <= 1'b0;
                sensor_index  <= '0;
                word_index    <= '0;
            end
        endcase
    end
end

endmodule
