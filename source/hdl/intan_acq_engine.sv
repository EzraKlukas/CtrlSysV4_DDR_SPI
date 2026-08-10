module intan_acq_engine #(
    parameter int MAX_COMMANDS = 64,
    parameter int NUM_INTAN = config_pkg::NUM_INTAN,
    parameter int NUM_CHAN = 32,
    parameter int BITS_PER_WORD = 16
) (
    input logic clk,
    input logic rst,
    input logic start_init,
    input logic start_read,
    input logic [63:0] timestamp,  // live timestamp!

    output logic initialized,
    output config_pkg::Intan_frame_t Intan_frame,

    // init specific
    input logic [6:0] init_list_len,
    input logic [MAX_COMMANDS-1:0][BITS_PER_WORD-1:0] init_cmd_list,
    input logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] expect_rx_ans_list_a,
    input logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] expect_rx_ans_list_b,

    // reading specific
    input logic [6:0] acq_list_len,
    input logic [MAX_COMMANDS-1:0][BITS_PER_WORD-1:0] acq_cmd_list,

    // direction of intan_cmd_sequencer (general)
    output logic [6:0] cmd_list_len,
    output logic [MAX_COMMANDS-1:0][BITS_PER_WORD-1:0] tx_cmd_list,
    output logic start_seq_pulse,

    // from intan_cmd_sequencer
    input logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] rx_ans_list_a,
    input logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] rx_ans_list_b,
    input logic done_seq_pulse,

    output logic init_done_pulse,
    output logic frame_done_pulse,
    output logic busy,
    output logic err
);
    typedef enum logic [2:0] {
        ST_PRE_INIT,
        ST_INITING,
        ST_FAULT,
        ST_READ_READY,
        ST_READING,
        ST_DONE
    } intan_frame_state_t;

    intan_frame_state_t intan_state;
    localparam int CHANNEL_B_OFFSET = config_pkg::INTAN_CHANNELS / 2;

    initial begin
        if (NUM_CHAN > CHANNEL_B_OFFSET)
            $error("intan_acq_engine NUM_CHAN exceeds one RHD2164 ADC bank");
        if (BITS_PER_WORD != config_pkg::INTAN_BITS_PER_WORD)
            $error("intan_acq_engine word width must match Intan_frame_t");
    end

    integer sensor_idx;
    integer chan_idx;
    always_ff @(posedge clk) begin
        if (rst) begin
            initialized <= 1'b0;
            intan_state <= ST_PRE_INIT;
            busy <= 1'b0;
            init_done_pulse <= 1'b0;
            frame_done_pulse <= 1'b0;
            err <= 1'b0;
            cmd_list_len <= '0;
            tx_cmd_list <= '0;
            start_seq_pulse <= 1'b0;
            Intan_frame.init_read_ts <= 64'b0;
            Intan_frame.done_read_ts <= 64'b0;
            for (sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1) begin
                Intan_frame.Intan_data[sensor_idx].sensor_id <= sensor_idx[7:0];
                Intan_frame.Intan_data[sensor_idx].data <= '0;
            end
        end else begin
            init_done_pulse <= 1'b0;
            frame_done_pulse <= 1'b0;
            start_seq_pulse <= 1'b0;

            case (intan_state)
                ST_PRE_INIT: begin
                    initialized <= 1'b0;
                    busy <= 1'b0;

                    if (start_init) begin
                        intan_state <= ST_INITING;
                        busy <= 1'b1;
                        cmd_list_len <= init_list_len;
                        tx_cmd_list <= init_cmd_list;
                        start_seq_pulse <= 1'b1;
                        err <= 1'b0;
                        initialized <= 1'b0;
                    end
                end
                ST_INITING: begin
                    busy <= 1'b1;

                    if (done_seq_pulse) begin
                        if (rx_ans_list_a == expect_rx_ans_list_a && rx_ans_list_b == expect_rx_ans_list_b) begin
                            intan_state <= ST_READ_READY;
                            init_done_pulse <= 1'b1;
                            initialized <= 1'b1;
                            busy <= 1'b0;
                        end else begin
                            intan_state <= ST_FAULT;
                            err <= 1'b1;
                            initialized <= 1'b0;
                            busy <= 1'b0;
                        end
                    end
                end
                ST_READ_READY: begin
                    initialized <= 1'b1;
                    busy <= 1'b0;

                    if (start_init) begin
                        intan_state <= ST_INITING;
                        busy <= 1'b1;
                        cmd_list_len <= init_list_len;
                        tx_cmd_list <= init_cmd_list;
                        start_seq_pulse <= 1'b1;
                        err <= 1'b0;
                        initialized <= 1'b0;
                    end else if (start_read) begin
                        intan_state <= ST_READING;
                        busy <= 1'b1;
                        cmd_list_len <= acq_list_len;
                        tx_cmd_list <= acq_cmd_list;
                        Intan_frame.init_read_ts <= timestamp;
                        Intan_frame.done_read_ts <= 64'b0;
                        for (
                            sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1
                        ) begin
                            Intan_frame.Intan_data[sensor_idx].sensor_id <= sensor_idx[7:0];
                            Intan_frame.Intan_data[sensor_idx].data <= '0;
                        end

                        start_seq_pulse <= 1'b1;
                    end
                end
                ST_READING: begin
                    busy <= 1'b1;

                    if (done_seq_pulse) begin
                        intan_state <= ST_DONE;
                        Intan_frame.done_read_ts <= timestamp;

                        // pack result into frame
                        for (
                            sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1
                        ) begin
                            // sensor_id already filled out in previous state.
                            for (chan_idx = 0; chan_idx < NUM_CHAN; chan_idx = chan_idx + 1) begin
                                Intan_frame.Intan_data[sensor_idx].data[BITS_PER_WORD*chan_idx+:BITS_PER_WORD] <= rx_ans_list_a[chan_idx][sensor_idx];
                                Intan_frame.Intan_data[sensor_idx].data[BITS_PER_WORD*(chan_idx+CHANNEL_B_OFFSET)+:BITS_PER_WORD] <= rx_ans_list_b[chan_idx][sensor_idx];
                            end
                        end
                    end
                end
                ST_DONE: begin
                    frame_done_pulse <= 1'b1;
                    busy <= 1'b0;
                    initialized <= 1'b1;
                    intan_state <= ST_READ_READY;
                end
                ST_FAULT: begin
                    busy <= 1'b0;
                    initialized <= 1'b0;
                    if (start_init) begin
                        intan_state <= ST_INITING;
                        busy <= 1'b1;
                        cmd_list_len <= init_list_len;
                        tx_cmd_list <= init_cmd_list;
                        start_seq_pulse <= 1'b1;
                        err <= 1'b0;
                    end
                end
                default: begin
                end
            endcase
        end
    end
endmodule
