module intan_cmd_sequencer #(
    parameter int MAX_COMMANDS = 64,
    parameter int NUM_INTAN = config_pkg::NUM_INTAN,
    parameter int BITS_PER_WORD = 16
) (
    // input: command list
    // output: outputs
    input logic clk,
    input logic rst,

    output logic run_cyclic,
    // should monitor error? or busy?
    input logic done_pulse,  // from word engine
    input logic start_seq_pulse,  // from above
    output logic done_seq_pulse,

    output logic [15:0] tx_word,
    input logic [NUM_INTAN-1:0][BITS_PER_WORD-1:0] rx_ans_a,
    input logic [NUM_INTAN-1:0][BITS_PER_WORD-1:0] rx_ans_b,

    input logic [6:0] cmd_list_len,
    input logic [MAX_COMMANDS-1:0][BITS_PER_WORD-1:0] tx_cmd_list,
    output logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] rx_ans_list_a,
    output logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] rx_ans_list_b
);

    logic [6:0] cmd_cnt;
    logic running_sequence;
    integer sensor_idx;

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_ans_list_a <= '0;
            rx_ans_list_b <= '0;
            cmd_cnt <= '0;
            tx_word <= '0;
            run_cyclic <= 1'b0;
            done_seq_pulse <= 1'b0;
        end else if (start_seq_pulse) begin
            done_seq_pulse   <= 1'b0;
            running_sequence <= 1'b1;
            // all things associated with resetting in some sense?
        end else if (running_sequence) begin
            // each time the word engine is done, initiate.
            if (done_pulse) begin  // only runs once?
                cmd_cnt <= cmd_cnt + 1;

                if (cmd_cnt + 1 < cmd_list_len) begin
                    if (cmd_cnt >= 2) begin
                        // read from rx, check endianness
                        for (
                            sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1
                        ) begin
                            rx_ans_list_a[cmd_cnt-2][sensor_idx] <= rx_ans_a[sensor_idx];
                            rx_ans_list_b[cmd_cnt-2][sensor_idx] <= rx_ans_b[sensor_idx];
                        end
                    end
                    tx_word <= tx_cmd_list[cmd_cnt];
                end else begin  // means we've transmitted every word.
                    if (cmd_cnt + 1 == cmd_list_len + 2) begin
                        run_cyclic <= 1'b0;
                        done_seq_pulse <= 1'b1;
                        running_sequence <= 1'b0;
                    end
                end
            end else if (cmd_cnt == '0) begin
                tx_word <= tx_cmd_list[0];
                run_cyclic <= 1'b1;  // ignites SPI word engine.
            end
        end
    end

endmodule
