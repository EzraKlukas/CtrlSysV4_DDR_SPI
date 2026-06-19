`timescale 1ns/1ps

/* 
Name: Gordon Zhao
File: stopwatch_64.sv
Description: a block for storing time
a 64 bit counter incrementing every 20ns (50MHz clock) would take > 10000 years to wrap
*/

module stopwatch_64 (
    input logic         clk,
    input logic         rst,
    output logic [63:0] timestamp_counter
);	

always_ff @(posedge clk) begin
    if (rst)
        timestamp_counter <= 64'd0;
    else
        timestamp_counter <= timestamp_counter + 1;
end

endmodule
