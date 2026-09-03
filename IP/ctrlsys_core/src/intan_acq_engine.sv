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
    input logic diagnostic_clear,
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
    output logic err,

    // Registered initialization diagnostics.  The published mismatch fields
    // describe the first completed failed attempt after reset/clear.
    output logic [15:0] diagnostic_attempt_count,
    output logic diagnostic_snapshot_valid,
    output logic [7:0] diagnostic_a_mismatch_count,
    output logic [7:0] diagnostic_b_mismatch_count,
    output logic [MAX_COMMANDS-1:0] diagnostic_a_mismatch_bitmap,
    output logic [MAX_COMMANDS-1:0] diagnostic_b_mismatch_bitmap,
    output logic diagnostic_first_a_valid,
    output logic [6:0] diagnostic_first_a_command_index,
    output logic [2:0] diagnostic_first_a_sensor_index,
    output logic [BITS_PER_WORD-1:0] diagnostic_first_a_command,
    output logic [BITS_PER_WORD-1:0] diagnostic_first_a_actual,
    output logic [BITS_PER_WORD-1:0] diagnostic_first_a_expected,
    output logic diagnostic_first_b_valid,
    output logic [6:0] diagnostic_first_b_command_index,
    output logic [2:0] diagnostic_first_b_sensor_index,
    output logic [BITS_PER_WORD-1:0] diagnostic_first_b_command,
    output logic [BITS_PER_WORD-1:0] diagnostic_first_b_actual,
    output logic [BITS_PER_WORD-1:0] diagnostic_first_b_expected,
    output logic [3:0] diagnostic_state,
    output logic [6:0] diagnostic_verify_command_index,
    output logic [2:0] diagnostic_verify_sensor_index
);
    typedef enum logic [3:0] {
        ST_PRE_INIT       = 4'd0,
        ST_INITING        = 4'd1,
        ST_VERIFY_FETCH   = 4'd2,
        ST_VERIFY_COMPARE = 4'd3,
        ST_VERIFY_DONE    = 4'd4,
        ST_FAULT          = 4'd5,
        ST_READ_READY     = 4'd6,
        ST_READING        = 4'd7,
        ST_DONE           = 4'd8
    } intan_frame_state_t;

    intan_frame_state_t intan_state;
    localparam int CHANNEL_B_OFFSET = config_pkg::INTAN_CHANNELS / 2;
    localparam int VERIFY_COMMAND_INDEX_WIDTH = (MAX_COMMANDS > 1) ? $clog2(MAX_COMMANDS + 1) : 1;
    localparam int VERIFY_COMMAND_ADDRESS_WIDTH = (MAX_COMMANDS > 1) ? $clog2(MAX_COMMANDS) : 1;
    localparam int VERIFY_SENSOR_INDEX_WIDTH = (NUM_INTAN > 1) ? $clog2(NUM_INTAN + 1) : 1;
    localparam int VERIFY_SENSOR_ADDRESS_WIDTH = (NUM_INTAN > 1) ? $clog2(NUM_INTAN) : 1;
    localparam logic [NUM_INTAN-1:0] INTAN_MASK =
        config_pkg::INTAN_MASK[NUM_INTAN-1:0];

    logic [VERIFY_COMMAND_INDEX_WIDTH-1:0] verify_command_index;
    logic [VERIFY_SENSOR_INDEX_WIDTH-1:0] verify_sensor_index;
    logic [BITS_PER_WORD-1:0] verify_actual_a;
    logic [BITS_PER_WORD-1:0] verify_actual_b;
    logic [BITS_PER_WORD-1:0] verify_expected_a;
    logic [BITS_PER_WORD-1:0] verify_expected_b;
    logic verify_mismatch;

    logic [7:0] attempt_a_mismatch_count;
    logic [7:0] attempt_b_mismatch_count;
    logic [MAX_COMMANDS-1:0] attempt_a_mismatch_bitmap;
    logic [MAX_COMMANDS-1:0] attempt_b_mismatch_bitmap;
    logic attempt_first_a_valid;
    logic [6:0] attempt_first_a_command_index;
    logic [2:0] attempt_first_a_sensor_index;
    logic [BITS_PER_WORD-1:0] attempt_first_a_command;
    logic [BITS_PER_WORD-1:0] attempt_first_a_actual;
    logic [BITS_PER_WORD-1:0] attempt_first_a_expected;
    logic attempt_first_b_valid;
    logic [6:0] attempt_first_b_command_index;
    logic [2:0] attempt_first_b_sensor_index;
    logic [BITS_PER_WORD-1:0] attempt_first_b_command;
    logic [BITS_PER_WORD-1:0] attempt_first_b_actual;
    logic [BITS_PER_WORD-1:0] attempt_first_b_expected;

    assign diagnostic_state = intan_state;
    assign diagnostic_verify_command_index = 7'(verify_command_index);
    assign diagnostic_verify_sensor_index = 3'(verify_sensor_index);

    initial begin
        if (NUM_CHAN > CHANNEL_B_OFFSET)
            $error("intan_acq_engine NUM_CHAN exceeds one RHD2164 ADC bank");
        if (BITS_PER_WORD != config_pkg::INTAN_BITS_PER_WORD)
            $error("intan_acq_engine word width must match Intan_frame_t");
        if (MAX_COMMANDS > 128)
            $error("intan_acq_engine diagnostics support at most 128 commands");
        if (NUM_INTAN > 8)
            $error("intan_acq_engine diagnostics support at most eight sensors");
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
            verify_command_index <= '0;
            verify_sensor_index <= '0;
            verify_actual_a <= '0;
            verify_actual_b <= '0;
            verify_expected_a <= '0;
            verify_expected_b <= '0;
            verify_mismatch <= 1'b0;
            attempt_a_mismatch_count <= '0;
            attempt_b_mismatch_count <= '0;
            attempt_a_mismatch_bitmap <= '0;
            attempt_b_mismatch_bitmap <= '0;
            attempt_first_a_valid <= 1'b0;
            attempt_first_a_command_index <= '0;
            attempt_first_a_sensor_index <= '0;
            attempt_first_a_command <= '0;
            attempt_first_a_actual <= '0;
            attempt_first_a_expected <= '0;
            attempt_first_b_valid <= 1'b0;
            attempt_first_b_command_index <= '0;
            attempt_first_b_sensor_index <= '0;
            attempt_first_b_command <= '0;
            attempt_first_b_actual <= '0;
            attempt_first_b_expected <= '0;
            diagnostic_attempt_count <= '0;
            diagnostic_snapshot_valid <= 1'b0;
            diagnostic_a_mismatch_count <= '0;
            diagnostic_b_mismatch_count <= '0;
            diagnostic_a_mismatch_bitmap <= '0;
            diagnostic_b_mismatch_bitmap <= '0;
            diagnostic_first_a_valid <= 1'b0;
            diagnostic_first_a_command_index <= '0;
            diagnostic_first_a_sensor_index <= '0;
            diagnostic_first_a_command <= '0;
            diagnostic_first_a_actual <= '0;
            diagnostic_first_a_expected <= '0;
            diagnostic_first_b_valid <= 1'b0;
            diagnostic_first_b_command_index <= '0;
            diagnostic_first_b_sensor_index <= '0;
            diagnostic_first_b_command <= '0;
            diagnostic_first_b_actual <= '0;
            diagnostic_first_b_expected <= '0;
            Intan_frame.init_read_ts <= 64'b0;
            Intan_frame.done_read_ts <= 64'b0;
            for (sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1) begin
                Intan_frame.Intan_data[sensor_idx].sensor_id <= sensor_idx[7:0];
                Intan_frame.Intan_data[sensor_idx].data <= '0;
            end
        end else begin
            init_done_pulse  <= 1'b0;
            frame_done_pulse <= 1'b0;
            start_seq_pulse  <= 1'b0;

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
                        verify_mismatch <= 1'b0;
                        attempt_a_mismatch_count <= '0;
                        attempt_b_mismatch_count <= '0;
                        attempt_a_mismatch_bitmap <= '0;
                        attempt_b_mismatch_bitmap <= '0;
                        attempt_first_a_valid <= 1'b0;
                        attempt_first_a_command_index <= '0;
                        attempt_first_a_sensor_index <= '0;
                        attempt_first_a_command <= '0;
                        attempt_first_a_actual <= '0;
                        attempt_first_a_expected <= '0;
                        attempt_first_b_valid <= 1'b0;
                        attempt_first_b_command_index <= '0;
                        attempt_first_b_sensor_index <= '0;
                        attempt_first_b_command <= '0;
                        attempt_first_b_actual <= '0;
                        attempt_first_b_expected <= '0;
                        if (diagnostic_attempt_count != 16'hffff)
                            diagnostic_attempt_count <= diagnostic_attempt_count + 1'b1;
                    end
                end
                ST_INITING: begin
                    busy <= 1'b1;

                    if (done_seq_pulse) begin
                        verify_command_index <= '0;
                        verify_sensor_index <= '0;
                        verify_mismatch <= 1'b0;
                        intan_state <= ST_VERIFY_FETCH;
                    end
                end
                ST_VERIFY_FETCH: begin
                    busy <= 1'b1;

                    if (verify_command_index >= VERIFY_COMMAND_INDEX_WIDTH'(MAX_COMMANDS) ||
                        7'(verify_command_index) >= init_list_len) begin
                        intan_state <= ST_VERIFY_DONE;
                    end else if (verify_sensor_index >= VERIFY_SENSOR_INDEX_WIDTH'(NUM_INTAN)) begin
                        verify_command_index <= verify_command_index + 1'b1;
                        verify_sensor_index  <= '0;
                    end else if (!INTAN_MASK[
                                     verify_sensor_index[VERIFY_SENSOR_ADDRESS_WIDTH-1:0]
                                 ]) begin
                        verify_sensor_index <= verify_sensor_index + 1'b1;
                    end else begin
                        verify_actual_a <=
                            rx_ans_list_a[
                                verify_command_index[VERIFY_COMMAND_ADDRESS_WIDTH-1:0]
                            ][verify_sensor_index[VERIFY_SENSOR_ADDRESS_WIDTH-1:0]];
                        verify_actual_b <=
                            rx_ans_list_b[
                                verify_command_index[VERIFY_COMMAND_ADDRESS_WIDTH-1:0]
                            ][verify_sensor_index[VERIFY_SENSOR_ADDRESS_WIDTH-1:0]];
                        verify_expected_a <=
                            expect_rx_ans_list_a[
                                verify_command_index[VERIFY_COMMAND_ADDRESS_WIDTH-1:0]
                            ][verify_sensor_index[VERIFY_SENSOR_ADDRESS_WIDTH-1:0]];
                        verify_expected_b <=
                            expect_rx_ans_list_b[
                                verify_command_index[VERIFY_COMMAND_ADDRESS_WIDTH-1:0]
                            ][verify_sensor_index[VERIFY_SENSOR_ADDRESS_WIDTH-1:0]];
                        intan_state <= ST_VERIFY_COMPARE;
                    end
                end
                ST_VERIFY_COMPARE: begin
                    busy <= 1'b1;
                    verify_mismatch <= verify_mismatch ||
                        verify_actual_a != verify_expected_a ||
                        verify_actual_b != verify_expected_b;

                    if (verify_actual_a != verify_expected_a) begin
                        if (attempt_a_mismatch_count != 8'hff)
                            attempt_a_mismatch_count <= attempt_a_mismatch_count + 1'b1;
                        attempt_a_mismatch_bitmap[
                            verify_command_index[VERIFY_COMMAND_ADDRESS_WIDTH-1:0]
                        ] <= 1'b1;
                        if (!attempt_first_a_valid) begin
                            attempt_first_a_valid <= 1'b1;
                            attempt_first_a_command_index <= 7'(verify_command_index);
                            attempt_first_a_sensor_index <= 3'(verify_sensor_index);
                            attempt_first_a_command <= tx_cmd_list[
                                verify_command_index[VERIFY_COMMAND_ADDRESS_WIDTH-1:0]
                            ];
                            attempt_first_a_actual <= verify_actual_a;
                            attempt_first_a_expected <= verify_expected_a;
                        end
                    end

                    if (verify_actual_b != verify_expected_b) begin
                        if (attempt_b_mismatch_count != 8'hff)
                            attempt_b_mismatch_count <= attempt_b_mismatch_count + 1'b1;
                        attempt_b_mismatch_bitmap[
                            verify_command_index[VERIFY_COMMAND_ADDRESS_WIDTH-1:0]
                        ] <= 1'b1;
                        if (!attempt_first_b_valid) begin
                            attempt_first_b_valid <= 1'b1;
                            attempt_first_b_command_index <= 7'(verify_command_index);
                            attempt_first_b_sensor_index <= 3'(verify_sensor_index);
                            attempt_first_b_command <= tx_cmd_list[
                                verify_command_index[VERIFY_COMMAND_ADDRESS_WIDTH-1:0]
                            ];
                            attempt_first_b_actual <= verify_actual_b;
                            attempt_first_b_expected <= verify_expected_b;
                        end
                    end

                    verify_sensor_index <= verify_sensor_index + 1'b1;
                    intan_state <= ST_VERIFY_FETCH;
                end
                ST_VERIFY_DONE: begin
                    if (verify_mismatch) begin
                        intan_state <= ST_FAULT;
                        err <= 1'b1;
                        initialized <= 1'b0;
                        if (!diagnostic_snapshot_valid) begin
                            diagnostic_snapshot_valid <= 1'b1;
                            diagnostic_a_mismatch_count <= attempt_a_mismatch_count;
                            diagnostic_b_mismatch_count <= attempt_b_mismatch_count;
                            diagnostic_a_mismatch_bitmap <= attempt_a_mismatch_bitmap;
                            diagnostic_b_mismatch_bitmap <= attempt_b_mismatch_bitmap;
                            diagnostic_first_a_valid <= attempt_first_a_valid;
                            diagnostic_first_a_command_index <=
                                attempt_first_a_command_index;
                            diagnostic_first_a_sensor_index <= attempt_first_a_sensor_index;
                            diagnostic_first_a_command <= attempt_first_a_command;
                            diagnostic_first_a_actual <= attempt_first_a_actual;
                            diagnostic_first_a_expected <= attempt_first_a_expected;
                            diagnostic_first_b_valid <= attempt_first_b_valid;
                            diagnostic_first_b_command_index <=
                                attempt_first_b_command_index;
                            diagnostic_first_b_sensor_index <= attempt_first_b_sensor_index;
                            diagnostic_first_b_command <= attempt_first_b_command;
                            diagnostic_first_b_actual <= attempt_first_b_actual;
                            diagnostic_first_b_expected <= attempt_first_b_expected;
                        end
                    end else begin
                        intan_state <= ST_READ_READY;
                        init_done_pulse <= 1'b1;
                        initialized <= 1'b1;
                    end
                    busy <= 1'b0;
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
                        verify_mismatch <= 1'b0;
                        attempt_a_mismatch_count <= '0;
                        attempt_b_mismatch_count <= '0;
                        attempt_a_mismatch_bitmap <= '0;
                        attempt_b_mismatch_bitmap <= '0;
                        attempt_first_a_valid <= 1'b0;
                        attempt_first_a_command_index <= '0;
                        attempt_first_a_sensor_index <= '0;
                        attempt_first_a_command <= '0;
                        attempt_first_a_actual <= '0;
                        attempt_first_a_expected <= '0;
                        attempt_first_b_valid <= 1'b0;
                        attempt_first_b_command_index <= '0;
                        attempt_first_b_sensor_index <= '0;
                        attempt_first_b_command <= '0;
                        attempt_first_b_actual <= '0;
                        attempt_first_b_expected <= '0;
                        if (diagnostic_attempt_count != 16'hffff)
                            diagnostic_attempt_count <= diagnostic_attempt_count + 1'b1;
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

                    if (done_seq_pulse) begin  // this might be too much?
                        intan_state <= ST_DONE;
                        Intan_frame.done_read_ts <= timestamp;

                        // pack result into frame
                        for (
                            sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1
                        ) begin
                            // sensor_id already filled out in previous state.
                            if (INTAN_MASK[sensor_idx]) begin
                                for (
                                    chan_idx = 0; chan_idx < NUM_CHAN; chan_idx = chan_idx + 1
                                ) begin
                                    Intan_frame.Intan_data[sensor_idx].data[
                                        BITS_PER_WORD*chan_idx+:BITS_PER_WORD
                                    ] <= rx_ans_list_a[chan_idx][sensor_idx];
                                    Intan_frame.Intan_data[sensor_idx].data[
                                        BITS_PER_WORD*(chan_idx+CHANNEL_B_OFFSET)+:BITS_PER_WORD
                                    ] <= rx_ans_list_b[chan_idx][sensor_idx];
                                end
                            end else begin
                                Intan_frame.Intan_data[sensor_idx].data <= '0;
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
                        verify_mismatch <= 1'b0;
                        attempt_a_mismatch_count <= '0;
                        attempt_b_mismatch_count <= '0;
                        attempt_a_mismatch_bitmap <= '0;
                        attempt_b_mismatch_bitmap <= '0;
                        attempt_first_a_valid <= 1'b0;
                        attempt_first_a_command_index <= '0;
                        attempt_first_a_sensor_index <= '0;
                        attempt_first_a_command <= '0;
                        attempt_first_a_actual <= '0;
                        attempt_first_a_expected <= '0;
                        attempt_first_b_valid <= 1'b0;
                        attempt_first_b_command_index <= '0;
                        attempt_first_b_sensor_index <= '0;
                        attempt_first_b_command <= '0;
                        attempt_first_b_actual <= '0;
                        attempt_first_b_expected <= '0;
                        if (diagnostic_attempt_count != 16'hffff)
                            diagnostic_attempt_count <= diagnostic_attempt_count + 1'b1;
                    end
                end
                default: begin
                end
            endcase

            // Clear wins over an attempt-count increment or snapshot publish
            // on the same clock, without stalling the acquisition state machine.
            if (diagnostic_clear) begin
                diagnostic_attempt_count <= '0;
                diagnostic_snapshot_valid <= 1'b0;
                diagnostic_a_mismatch_count <= '0;
                diagnostic_b_mismatch_count <= '0;
                diagnostic_a_mismatch_bitmap <= '0;
                diagnostic_b_mismatch_bitmap <= '0;
                diagnostic_first_a_valid <= 1'b0;
                diagnostic_first_a_command_index <= '0;
                diagnostic_first_a_sensor_index <= '0;
                diagnostic_first_a_command <= '0;
                diagnostic_first_a_actual <= '0;
                diagnostic_first_a_expected <= '0;
                diagnostic_first_b_valid <= 1'b0;
                diagnostic_first_b_command_index <= '0;
                diagnostic_first_b_sensor_index <= '0;
                diagnostic_first_b_command <= '0;
                diagnostic_first_b_actual <= '0;
                diagnostic_first_b_expected <= '0;
            end
        end
    end
endmodule
