/*
 * Synthesizable integration wrapper for the RHD2164 acquisition path.
 *
 * This module intentionally contains no state machine.  Its job is to expose
 * the subsystem boundary and connect:
 *
 *   acquisition controller -> command sequencer -> SPI word engine
 *
 * Port directions are relative to this module.  For example, clk and rst are
 * inputs because the parent module (or a testbench) drives them.  The shared
 * SPI signals are outputs because this subsystem drives the physical sensors,
 * while each sensor has its own MISO input.
 */

module intan_reader #(
    parameter int MAX_COMMANDS = 64,
    parameter int NUM_INTAN = config_pkg::NUM_INTAN,
    parameter int NUM_CHANNELS_PER_ADC = config_pkg::INTAN_CHANNELS / 2,
    parameter int BITS_PER_WORD = config_pkg::INTAN_BITS_PER_WORD,

    // All timing parameters below are measured in clk cycles.
    parameter int SCLK_HALF_PERIOD_CYCLES = 63,
    parameter int CS_TO_SCLK_CYCLES = config_pkg::INTAN_T_CS_1,
    parameter int SCLK_TO_CS_CYCLES = config_pkg::INTAN_T_CS_2,
    parameter int CS_HIGH_CYCLES = config_pkg::INTAN_T_CS_OFF
) (
    input logic clk,
    input logic rst,

    // High-level requests from the parent.
    input logic start_init,
    input logic start_read,
    input logic [63:0] timestamp,

    // Initialization sequence and expected pipelined responses.
    input logic [6:0] init_list_len,
    input logic [MAX_COMMANDS*BITS_PER_WORD-1:0] init_cmd_list,
    input logic [MAX_COMMANDS*NUM_INTAN*BITS_PER_WORD-1:0] expect_rx_ans_list_a,
    input logic [MAX_COMMANDS*NUM_INTAN*BITS_PER_WORD-1:0] expect_rx_ans_list_b,

    // Acquisition sequence.
    input logic [6:0] acq_list_len,
    input logic [MAX_COMMANDS*BITS_PER_WORD-1:0] acq_cmd_list,

    // Completed frame and status.
    output config_pkg::Intan_frame_t intan_frame,
    output logic done_pulse,
    output logic error,

    // Physical RHD2164 bus.  SCLK, MOSI, and CS are shared; each chip has a
    // separate MISO return line.
    output logic intan_sclk,
    output logic intan_mosi,
    output logic intan_cs_n,
    input logic [NUM_INTAN-1:0] intan_miso
);

    localparam int COMMAND_LIST_BITS = MAX_COMMANDS * BITS_PER_WORD;
    localparam int RESPONSE_LIST_BITS = MAX_COMMANDS * NUM_INTAN * BITS_PER_WORD;
    localparam int RESPONSE_WORD_BITS = NUM_INTAN * BITS_PER_WORD;

    // Acquisition engine <-> command sequencer.
    logic [6:0] command_list_len;
    logic [COMMAND_LIST_BITS-1:0] command_list;
    logic start_sequence_pulse;
    logic sequence_done_pulse;
    logic [RESPONSE_LIST_BITS-1:0] response_list_a;
    logic [RESPONSE_LIST_BITS-1:0] response_list_b;

    // Command sequencer <-> SPI word engine.
    logic run_words;
    logic word_done_pulse;
    logic [BITS_PER_WORD-1:0] tx_word;
    logic [RESPONSE_WORD_BITS-1:0] rx_word_a;
    logic [RESPONSE_WORD_BITS-1:0] rx_word_b;

    intan_acq_engine #(
        .MAX_COMMANDS(MAX_COMMANDS),
        .NUM_INTAN(NUM_INTAN),
        .NUM_CHAN(NUM_CHANNELS_PER_ADC),
        .BITS_PER_WORD(BITS_PER_WORD)
    ) u_acq_engine (
        .clk(clk),
        .rst(rst),
        .start_init(start_init),
        .start_read(start_read),
        .timestamp(timestamp),
        .Intan_frame(intan_frame),

        .init_list_len(init_list_len),
        .init_cmd_list(init_cmd_list),
        .expect_rx_ans_list_a(expect_rx_ans_list_a),
        .expect_rx_ans_list_b(expect_rx_ans_list_b),

        .acq_list_len(acq_list_len),
        .acq_cmd_list(acq_cmd_list),

        .cmd_list_len(command_list_len),
        .tx_cmd_list(command_list),
        .start_seq_pulse(start_sequence_pulse),

        .rx_ans_list_a (response_list_a),
        .rx_ans_list_b (response_list_b),
        .done_seq_pulse(sequence_done_pulse),

        .done(done_pulse),
        .err (error)
    );

    intan_cmd_sequencer #(
        .MAX_COMMANDS(MAX_COMMANDS),
        .NUM_INTAN(NUM_INTAN),
        .BITS_PER_WORD(BITS_PER_WORD)
    ) u_cmd_sequencer (
        .clk(clk),
        .rst(rst),

        .run_cyclic(run_words),
        .done_pulse(word_done_pulse),
        .start_seq_pulse(start_sequence_pulse),
        .done_seq_pulse(sequence_done_pulse),

        .tx_word (tx_word),
        .rx_ans_a(rx_word_a),
        .rx_ans_b(rx_word_b),

        .cmd_list_len (command_list_len),
        .tx_cmd_list  (command_list),
        .rx_ans_list_a(response_list_a),
        .rx_ans_list_b(response_list_b)
    );

    intan_spi_word_engine #(
        .SCLK_HALF_PERIOD_CYCLES(SCLK_HALF_PERIOD_CYCLES),
        .NUM_INTAN(NUM_INTAN),
        .T_CS_1(CS_TO_SCLK_CYCLES),
        .T_CS_2(SCLK_TO_CS_CYCLES),
        .T_CS_OFF(CS_HIGH_CYCLES),
        .BITS_PER_WORD(BITS_PER_WORD)
    ) u_spi_word_engine (
        .clk(clk),
        .rst(rst),

        .run_cyclic(run_words),
        .done_pulse(word_done_pulse),
        .tx_word(tx_word),
        .rx_word_a(rx_word_a),
        .rx_word_b(rx_word_b),

        .sclk(intan_sclk),
        .mosi(intan_mosi),
        .miso(intan_miso),
        .cs_n(intan_cs_n)
    );

endmodule
