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
            running_sequence <= 1'b0;
        end else begin
            done_seq_pulse <= 1'b0;

            if (start_seq_pulse && !running_sequence) begin
                rx_ans_list_a <= '0;
                rx_ans_list_b <= '0;
                cmd_cnt <= '0;
                tx_word <= tx_cmd_list[0];
                run_cyclic <= 1'b1;
                running_sequence <= 1'b1;
            end else if (running_sequence && done_pulse) begin
                if (cmd_cnt >= 2 && cmd_cnt < cmd_list_len + 2) begin
                    for (sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1) begin
                        rx_ans_list_a[cmd_cnt-2][sensor_idx] <= rx_ans_a[sensor_idx];
                        rx_ans_list_b[cmd_cnt-2][sensor_idx] <= rx_ans_b[sensor_idx];
                    end
                end

                if (cmd_cnt == cmd_list_len + 1) begin
                    cmd_cnt <= '0;
                    tx_word <= '0;
                    run_cyclic <= 1'b0;
                    running_sequence <= 1'b0;
                    done_seq_pulse <= 1'b1;
                end else begin
                    cmd_cnt <= cmd_cnt + 1'b1;
                    if (cmd_cnt + 1 < cmd_list_len) tx_word <= tx_cmd_list[cmd_cnt+1];
                    else tx_word <= '0;
                end
            end
        end
    end

endmodule
