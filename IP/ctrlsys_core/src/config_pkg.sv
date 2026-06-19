`timescale 1ns/1ps

package config_pkg;

	localparam int NUM_SENSORS = 3;
	localparam int BUFFER_SIZE = 5;
	localparam int SENSOR_DATA_BYTES = 20;

	typedef struct packed{
	    logic [63:0]    init_read_ts; // timestamp that read was initiated
	    logic [63:0]    done_read_ts; // timestamp that read finished
	    logic [8*SENSOR_DATA_BYTES-1:0] sensor_data;
	} raw_packet_t;
endpackage
