module intan_init #(
    parameter int MAX_COMMANDS = 64,
    parameter int NUM_INTAN = config_pkg::NUM_INTAN,
    parameter int BITS_PER_WORD = 16
) (
    input logic rst,
    input logic clk,
    input logic start_init,

    // direction of intan_cmd_sequence
    output logic [6:0] cmd_list_len,
    input logic [MAX_COMMANDS * BITS_PER_WORD-1:0] init_cmd_list,  // received from axi
    output logic [MAX_COMMANDS * BITS_PER_WORD-1:0] tx_cmd_list,
    output logic start_init_pulse,
    input logic [MAX_COMMANDS * NUM_INTAN * BITS_PER_WORD-1:0] expect_rx_ans_list_a,
    input logic [MAX_COMMANDS * NUM_INTAN * BITS_PER_WORD-1:0] expect_rx_ans_list_b,

    input logic [MAX_COMMANDS * NUM_INTAN * BITS_PER_WORD-1:0] rx_ans_list_a,
    input logic [MAX_COMMANDS * NUM_INTAN * BITS_PER_WORD-1:0] rx_ans_list_b,
    input logic done_seq_pulse,

    output logic done_init
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_INITING,
        ST_DONE,
        ST_FAULT
    } intan_init_t;

    intan_init_t init_state;

    always_ff @(posedge clk) begin
        if (rst) begin
            done_init   <= 1'b0;
            tx_cmd_list <= '0;
        end else begin
            case (init_state)
                ST_IDLE: begin
                    if (start_init) begin
                        init_state <= ST_INITING;
                        tx_cmd_list <= init_cmd_list;
                        start_init_pulse <= 1'b1;
                    end
                end
                ST_INITING: begin
                    start_init_pulse <= 1'b0;
                    if (done_seq_pulse) begin
                        if (rx_ans_list_a == expect_rx_ans_list_a && rx_ans_list_b == expect_rx_ans_list_b) begin
                            init_state <= ST_DONE;
                            done_init  <= 1'b1;
                        end else begin
                            init_state <= ST_FAULT;
                        end
                    end
                end
                ST_DONE: begin

                end
                ST_FAULT: begin
                end
            endcase
        end
    end

endmodule
