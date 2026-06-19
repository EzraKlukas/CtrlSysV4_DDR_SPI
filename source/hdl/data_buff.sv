`timescale 1ns/1ps

/* 
Name: Gordon Zhao
File: data_buff.sv
Description: synchronous FIFO for storing sensor data frames (multiple sensor packets)
*/

import config_pkg::*;

module data_buff #(
    parameter integer NUM_SENSORS = 3,
    parameter integer BUFFER_SIZE = 5
)(
    input logic         clk,
    input logic         rst,
    input logic         wr_en,
    input logic         rd_en,
    input raw_packet_t  in_frame [NUM_SENSORS],
    output raw_packet_t out_frame [NUM_SENSORS],
    output logic        empty,
    output logic        full
);

localparam int PTR_WIDTH = (BUFFER_SIZE > 1) ? $clog2(BUFFER_SIZE) : 1;
localparam int COUNT_WIDTH = $clog2(BUFFER_SIZE + 1);

logic [PTR_WIDTH-1:0] wptr;
logic [PTR_WIDTH-1:0] rptr;
logic [COUNT_WIDTH-1:0] count;
raw_packet_t fifo [BUFFER_SIZE-1:0][NUM_SENSORS-1:0];
int sensor_loop_index;

wire do_read;
wire do_write;

assign do_read  = rd_en && !empty;
assign do_write = wr_en && (!full || do_read);

always_ff @(posedge clk) begin
    if (rst) begin
        wptr  <= '0;
        rptr  <= '0;
        count <= '0;
        for (sensor_loop_index = 0; sensor_loop_index < NUM_SENSORS; sensor_loop_index++) begin
            out_frame[sensor_loop_index] <= '0;
        end
    end else begin
        if (do_write) begin
            for (sensor_loop_index = 0; sensor_loop_index < NUM_SENSORS; sensor_loop_index++) begin
                fifo[wptr][sensor_loop_index] <= in_frame[sensor_loop_index];
            end

            if (wptr == BUFFER_SIZE - 1)
                wptr <= '0;
            else
                wptr <= wptr + 1'b1;
        end

        if (do_read) begin
            for (sensor_loop_index = 0; sensor_loop_index < NUM_SENSORS; sensor_loop_index++) begin
                out_frame[sensor_loop_index] <= fifo[rptr][sensor_loop_index];
            end

            if (rptr == BUFFER_SIZE - 1)
                rptr <= '0;
            else
                rptr <= rptr + 1'b1;
        end

        case ({do_write, do_read})
            2'b10: count <= count + 1'b1;
            2'b01: count <= count - 1'b1;
            default: count <= count;
        endcase
    end
end

assign full  = count == BUFFER_SIZE;
assign empty = count == 0;

endmodule
