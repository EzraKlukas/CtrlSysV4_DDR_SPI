/* 
Name: Gordon Zhao
File: acquisition_controller.sv
Description: FPGA-side acquisition controller
*/

`timescale 1ns/1ps

module acquisition_controller ( 	
	input  logic        clk,
	input  logic        rst,
	input  logic        enable,         // Trigger reads while enable is high
	input  logic [63:0] timestamp,
	input  logic [63:0] sample_period,  
	output logic        startRead       // One-clock-cycle read start pulse
);

	logic [63:0] prev_sample_time;
	logic prev_enable;

	always_ff @(posedge clk) begin
		if (rst) begin
			prev_sample_time <= 0;
			startRead        <= 0;
			prev_enable		 <= 0;
		end else begin
			startRead <= 0;
			if (prev_enable == 0 && enable == 1) begin
				prev_sample_time <= timestamp;
				startRead <= 1;
			end

			else if (enable) begin
				if ((timestamp - prev_sample_time) >= sample_period) begin
					startRead <= 1;
					prev_sample_time <= prev_sample_time + sample_period;
				end
			end
			prev_enable <= enable;
		end
	end

endmodule
