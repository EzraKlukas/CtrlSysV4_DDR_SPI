module intan_acq_engine #(
    parameter int MAX_COMMANDS = 64,
    parameter int NUM_INTAN = config_pkg::NUM_INTAN,
    parameter int NUM_CHAN = 32,
    parameter int BITS_PER_WORD = 16
) (
    input logic clk,
    input logic rst,
    input logic start,
    input logic [63:0] timestamp,  // live timestamp!

    output Intan_frame_t Intan_frame,

    // direction of intan_cmd_sequence
    output logic [6:0] cmd_list_len,
    output logic [MAX_COMMANDS * BITS_PER_WORD-1:0] tx_cmd_list,
    output logic start_seq_pulse,

    input logic [MAX_COMMANDS * NUM_INTAN * BITS_PER_WORD-1:0] rx_ans_list_a,
    input logic [MAX_COMMANDS * NUM_INTAN * BITS_PER_WORD-1:0] rx_ans_list_b,
    input logic done_seq_pulse,

    output logic done
);
    // I should be forming the command list at this point!

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_READING,
        ST_DONE
    } intan_frame_state_t;

    intan_frame_state_t reader_state;

    integer sensor_idx;
    integer chan_idx;
    always_ff @(posedge clk) begin
        if (rst) begin
            done <= 1'b0;
            Intan_frame.init_read_ts <= 64'b0;
            Intan_frame.done_read_ts <= 64'b0;
            for (sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1) begin
                Intan_frame.Intan_data[sensor_idx].sensor_id <= sensor_idx[7:0];
                Intan_frame.Intan_data[sensor_idx].data <= '0;
            end
        end else begin
            case (reader_state)
                ST_IDLE: begin
                    // maintain defaults?
                    if (start_seq_pulse) begin
                        reader_state <= ST_READING;
                        Intan_frame.init_read_ts <= timestamp;
                        Intan_frame.done_read_ts <= 64'b0;
                        for (
                            sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1
                        ) begin
                            Intan_frame.Intan_data[sensor_idx].sensor_id <= sensor_idx[7:0];
                            Intan_frame.Intan_data[sensor_idx].data <= '0;
                        end

                        start_seq_pulse <= 1'b1;  // sets off intan_cmd_sequencer.sv
                    end
                end
                ST_READING: begin
                    start_seq_pulse <= 1'b0;

                    if (done_seq_pulse) begin
                        reader_state <= ST_DONE;
                        Intan_frame.done_read_ts <= timestamp;

                        // try framing now
                        for (
                            sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1
                        ) begin
                            // sensor_id already filled out in previous state.
                            for (chan_idx = 0; chan_idx < NUM_CHAN; chan_idx = chan_idx + 1) begin
                                Intan_frame.Intan_data[sensor_idx].data[BITS_PER_WORD*chan_idx+:BITS_PER_WORD] <= rx_ans_list_b[((NUM_CHAN-1)-chan_idx)*BITS_PER_WORD+:BITS_PER_WORD];
                                Intan_frame.Intan_data[sensor_idx].data[BITS_PER_WORD*(chan_idx+32)+:BITS_PER_WORD] <= rx_ans_list_a[((NUM_CHAN-1)-chan_idx)*BITS_PER_WORD+:BITS_PER_WORD];
                            end
                        end
                    end
                end
                ST_DONE: begin
                    done <= 1'b1;
                    reader_state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
