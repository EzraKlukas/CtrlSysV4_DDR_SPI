`timescale 1ns / 1ps

module ctrlsys_core (
    input logic clk,
    input logic rst_n,

    output logic                           spi_sclk,
    output logic                           spi_mosi,
    output logic                           spi_cs_n,
    input  logic [config_pkg::NUM_ICM-1:0] spi_miso,

    output logic intan_sclk,
    output logic intan_mosi,
    output logic intan_cs_n,
    input logic [config_pkg::NUM_INTAN-1:0] intan_miso,

    output logic axi_spi_io0_i,
    input  logic axi_spi_io0_o,
    input  logic axi_spi_io0_t,
    output logic axi_spi_io1_i,
    input  logic axi_spi_io1_o,
    input  logic axi_spi_io1_t,
    output logic axi_spi_sck_i,
    input  logic axi_spi_sck_o,
    input  logic axi_spi_sck_t,
    output logic axi_spi_ss_i,
    input  logic axi_spi_ss_o,
    input  logic axi_spi_ss_t,

    output logic                         m_axis_tvalid,
    input  logic                         m_axis_tready,
    output logic [  AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output logic [AXIS_DATA_WIDTH/8-1:0] m_axis_tkeep,
    output logic                         m_axis_tlast,

    input  logic        s00_axi_aclk,
    input  logic        s00_axi_aresetn,
    input  logic [ 5:0] s00_axi_awaddr,
    input  logic [ 2:0] s00_axi_awprot,
    input  logic        s00_axi_awvalid,
    output logic        s00_axi_awready,
    input  logic [31:0] s00_axi_wdata,
    input  logic [ 3:0] s00_axi_wstrb,
    input  logic        s00_axi_wvalid,
    output logic        s00_axi_wready,
    output logic [ 1:0] s00_axi_bresp,
    output logic        s00_axi_bvalid,
    input  logic        s00_axi_bready,
    input  logic [ 5:0] s00_axi_araddr,
    input  logic [ 2:0] s00_axi_arprot,
    input  logic        s00_axi_arvalid,
    output logic        s00_axi_arready,
    output logic [31:0] s00_axi_rdata,
    output logic [ 1:0] s00_axi_rresp,
    output logic        s00_axi_rvalid,
    input  logic        s00_axi_rready
);

    localparam logic [6:0] SPI_REG_ADDR = 7'd45;
    localparam int MAX_COMMANDS = 64;
    localparam logic [31:0] ERR_FIFO_OVERFLOW = 32'h0000_0001;
    localparam logic [31:0] ERR_FIFO_UNDERFLOW = 32'h0000_0002;
    localparam logic [31:0] ERR_INTAN_INIT = 32'h0000_0004;
    localparam logic [31:0] ERR_MISSED_INTAN = 32'h0000_0008;
    localparam logic [31:0] ERR_MISSED_ICM = 32'h0000_0010;

    initial begin
        if (BUFFER_SIZE < 1) $error("ctrlsys_core requires BUFFER_SIZE >= 1");
        if (AXIS_DATA_WIDTH < 8 || (AXIS_DATA_WIDTH % 8) != 0)
            $error("ctrlsys_core AXIS_DATA_WIDTH must be a positive byte multiple");
        if (PACKET_BYTES % (AXIS_DATA_WIDTH / 8) != 0)
            $error("ctrlsys_core PACKET_BYTES must align to AXI stream word width");
        if (MAX_INTAN_FRAMES_PER_PACKET < EXPECTED_INTAN_FRAMES_PER_PACKET)
            $error("ctrlsys_core packet cannot hold the nominal Intan frames per ICM period");
        if (INTAN_FRAME_BYTES != 1048)
            $error("ctrlsys_core production Intan frame must be 1048 bytes");
        if (ICM_FRAME_BYTES != 100) $error("ctrlsys_core production ICM frame must be 100 bytes");
        if (PACKET_TRAILER_OFFSET_BYTES < ICM_FRAME_BYTES + INTAN_FRAME_BYTES)
            $error("ctrlsys_core packet data region cannot hold one Intan and one ICM frame");
    end

    logic [63:0] timestamp;
    logic start_read_icm;
    logic start_init_intan;
    logic start_read_intan;
    logic intan_initialized;
    logic init_done_pulse_intan;
    logic frame_done_pulse_intan;

    logic spi_start;
    logic core_rst;
    logic packet_path_rst;

    logic [6:0] init_list_len;
    logic [MAX_COMMANDS-1:0][INTAN_BITS_PER_WORD-1:0] init_cmd_list;
    logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][INTAN_BITS_PER_WORD-1:0] expect_rx_ans_list_a;
    logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][INTAN_BITS_PER_WORD-1:0] expect_rx_ans_list_b;

    logic [6:0] acq_list_len;
    logic [MAX_COMMANDS-1:0][INTAN_BITS_PER_WORD-1:0] acq_cmd_list;

    logic error_intan;
    logic intan_busy;

    config_pkg::ICM_frame_t icm_frame;
    config_pkg::ICM_frame_t debug_icm_frame;
    config_pkg::Intan_frame_t intan_frame;

    logic spi_reader_sclk;
    logic spi_reader_mosi;
    logic spi_reader_cs_n;
    logic [NUM_ICM-1:0] spi_reader_miso;
    logic spi_busy;
    logic spi_done;
    logic axi_spi_miso;

    logic packet_fifo_full;
    logic packet_fifo_overflow;
    logic packet_fifo_underflow;
    logic packet_fifo_rd_en;
    logic packet_fifo_wr_en;
    logic packet_fifo_packet_space;
    logic packet_fifo_packet_available;
    logic [AXIS_DATA_WIDTH-1:0] packet_fifo_wr_data;
    logic [AXIS_DATA_WIDTH-1:0] packet_fifo_rd_data;
    logic packet_writer_ready;
    logic packet_writer_word_valid;
    logic packet_writer_packet_done;

    logic axil_enable;
    logic axil_soft_reset;
    logic [31:0] axil_sample_period;
    logic [63:0] icm_sample_period;
    logic [63:0] intan_sample_period;
    logic axil_use_axi;
    logic axil_clear_error;
    logic axil_reset_sample_counter;
    logic axil_cpu_clear_irq;
    logic packet_done_irq;
    logic error_latched;
    logic [31:0] sample_count;
    logic [31:0] error_code;
    logic [31:0] ext_status;
    logic [31:0] missed_icm_count;
    logic [31:0] missed_intan_count;
    logic [31:0] missed_icm_count_d;
    logic [31:0] missed_intan_count_d;
    logic [31:0] error_events;
    logic [31:0] data_word0;
    logic [31:0] data_word1;
    logic [31:0] data_word2;
    logic [31:0] data_word3;
    logic [31:0] data_word4;
    logic [31:0] data_word5;
    logic [31:0] data_word6;
    logic [31:0] data_word7;

    (* ASYNC_REG = "TRUE" *) logic rst_meta;
    (* ASYNC_REG = "TRUE" *) logic rst_sync;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rst_meta <= 1'b1;
            rst_sync <= 1'b1;
        end else begin
            rst_meta <= 1'b0;
            rst_sync <= rst_meta;
        end
    end

    assign core_rst = rst_sync || axil_soft_reset;
    assign packet_path_rst = core_rst || !axil_enable;
    assign spi_start = start_read_icm && !axil_use_axi && !spi_busy;
    assign axi_spi_io0_i = axi_spi_io0_o;
    assign axi_spi_io1_i = axi_spi_miso;
    assign axi_spi_sck_i = axi_spi_sck_o;
    assign axi_spi_ss_i = axi_spi_ss_o;
    assign icm_sample_period = {32'b0, axil_sample_period};
    assign intan_sample_period = {32'b0, axil_sample_period} / 64'(INTAN_SAMPLING_RATIO);
    assign packet_fifo_wr_en = packet_writer_word_valid && !packet_fifo_full;
    assign ext_status = {
        16'b0,
        missed_icm_count != 0,
        missed_intan_count != 0,
        error_code[1],
        error_code[0],
        axil_enable && intan_initialized,
        error_code[2],
        intan_busy,
        intan_initialized,
        8'b0
    };
    assign error_events =
        (packet_fifo_overflow ? ERR_FIFO_OVERFLOW : 32'b0) |
        (packet_fifo_underflow ? ERR_FIFO_UNDERFLOW : 32'b0) |
        (error_intan ? ERR_INTAN_INIT : 32'b0) |
        ((missed_intan_count != missed_intan_count_d) ? ERR_MISSED_INTAN : 32'b0) |
        ((missed_icm_count != missed_icm_count_d) ? ERR_MISSED_ICM : 32'b0);

    axil_regs u_axil_regs (
        .enable(axil_enable),
        .soft_reset(axil_soft_reset),
        .sample_period(axil_sample_period),
        .useAXI(axil_use_axi),
        .clear_error(axil_clear_error),
        .reset_sample_counter(axil_reset_sample_counter),
        .cpu_clear_irq(axil_cpu_clear_irq),
        .busy(spi_busy || intan_busy),
        .error(error_latched),
        .read_in_progress(spi_busy || intan_busy),
        .packet_done(packet_done_irq),
        .sample_count(sample_count),
        .error_code(error_code),
        .state({2'b0, spi_busy, axil_use_axi}),
        .ext_status(ext_status),
        .missed_intan_count(missed_intan_count),
        .missed_icm_count(missed_icm_count),
        .data_word0(data_word0),
        .data_word1(data_word1),
        .data_word2(data_word2),
        .data_word3(data_word3),
        .data_word4(data_word4),
        .data_word5(data_word5),
        .data_word6(data_word6),
        .data_word7(data_word7),
        .s00_axi_aclk(s00_axi_aclk),
        .s00_axi_aresetn(s00_axi_aresetn),
        .s00_axi_awaddr(s00_axi_awaddr),
        .s00_axi_awprot(s00_axi_awprot),
        .s00_axi_awvalid(s00_axi_awvalid),
        .s00_axi_awready(s00_axi_awready),
        .s00_axi_wdata(s00_axi_wdata),
        .s00_axi_wstrb(s00_axi_wstrb),
        .s00_axi_wvalid(s00_axi_wvalid),
        .s00_axi_wready(s00_axi_wready),
        .s00_axi_bresp(s00_axi_bresp),
        .s00_axi_bvalid(s00_axi_bvalid),
        .s00_axi_bready(s00_axi_bready),
        .s00_axi_araddr(s00_axi_araddr),
        .s00_axi_arprot(s00_axi_arprot),
        .s00_axi_arvalid(s00_axi_arvalid),
        .s00_axi_arready(s00_axi_arready),
        .s00_axi_rdata(s00_axi_rdata),
        .s00_axi_rresp(s00_axi_rresp),
        .s00_axi_rvalid(s00_axi_rvalid),
        .s00_axi_rready(s00_axi_rready)
    );

    stopwatch_64 u_stopwatch_64 (
        .clk(clk),
        .rst(core_rst),
        .timestamp_counter(timestamp)
    );

    acquisition_controller u_acquisition_controller (
        .clk(clk),
        .rst(core_rst),
        .intan_initialized(intan_initialized),
        .intan_busy(intan_busy),
        .icm_busy(spi_busy),
        .enable(axil_enable),
        .timestamp(timestamp),
        .sample_period_ICM(icm_sample_period),
        .sample_period_Intan(intan_sample_period),
        .startInit_Intan(start_init_intan),
        .startRead_ICM(start_read_icm),
        .startRead_Intan(start_read_intan),
        .missedRead_ICM_count(missed_icm_count),
        .missedRead_Intan_count(missed_intan_count)
    );

    ICM_reader #(
        .REG_ADDR(SPI_REG_ADDR)
    ) u_icm_reader (
        .clk(clk),
        .rst(core_rst),
        .start(spi_start),
        .timestamp(timestamp),
        .ICM_frame(icm_frame),
        .busy(spi_busy),
        .done(spi_done),
        .sclk(spi_reader_sclk),
        .mosi(spi_reader_mosi),
        .miso(spi_reader_miso),
        .cs_n(spi_reader_cs_n)
    );

    intan_program #(
        .MAX_COMMANDS(MAX_COMMANDS),
        .NUM_INTAN(NUM_INTAN),
        .BITS_PER_WORD(INTAN_BITS_PER_WORD)
    ) u_intan_program (
        .init_list_len(init_list_len),
        .init_cmd_list(init_cmd_list),
        .expect_rx_ans_list_a(expect_rx_ans_list_a),
        .expect_rx_ans_list_b(expect_rx_ans_list_b),
        .acq_list_len(acq_list_len),
        .acq_cmd_list(acq_cmd_list)
    );

    intan_reader #(
        .MAX_COMMANDS(MAX_COMMANDS),
        .NUM_INTAN(NUM_INTAN),
        .NUM_CHANNELS_PER_ADC(INTAN_CHANNELS / 2),
        .BITS_PER_WORD(INTAN_BITS_PER_WORD),
        .SCLK_HALF_PERIOD_CYCLES(INTAN_T_SCLK),
        .CS_TO_SCLK_CYCLES(INTAN_T_CS_1),
        .SCLK_TO_CS_CYCLES(INTAN_T_CS_2),
        .CS_HIGH_CYCLES(INTAN_T_CS_OFF)
    ) u_intan_reader (
        .clk(clk),
        .rst(core_rst),
        .start_init(start_init_intan),
        .start_read(start_read_intan),
        .timestamp(timestamp),
        .initialized(intan_initialized),
        .init_list_len(init_list_len),
        .init_cmd_list(init_cmd_list),
        .expect_rx_ans_list_a(expect_rx_ans_list_a),
        .expect_rx_ans_list_b(expect_rx_ans_list_b),
        .acq_list_len(acq_list_len),
        .acq_cmd_list(acq_cmd_list),
        .intan_frame(intan_frame),
        .init_done_pulse(init_done_pulse_intan),
        .frame_done_pulse(frame_done_pulse_intan),
        .busy(intan_busy),
        .error(error_intan),
        .intan_sclk(intan_sclk),
        .intan_mosi(intan_mosi),
        .intan_cs_n(intan_cs_n),
        .intan_miso(intan_miso)
    );

    packet_writer u_packet_writer (
        .clk(clk),
        .rst(packet_path_rst),
        .ICM_frame_done(spi_done),
        .Intan_frame_done(frame_done_pulse_intan),
        .ICM_frame_in(icm_frame),
        .Intan_frame_in(intan_frame),
        .packet_ready(packet_fifo_packet_space),
        .ready(packet_writer_ready),
        .word_valid(packet_writer_word_valid),
        .word_ready(!packet_fifo_full),
        .word_data(packet_fifo_wr_data),
        .packet_done(packet_writer_packet_done)
    );

    SPI_mux #(
        .NUM_SENSORS(NUM_ICM)
    ) u_spi_mux (
        .axi_enable(axil_use_axi && !spi_busy),
        .reader_sclk(spi_reader_sclk),
        .reader_mosi(spi_reader_mosi),
        .reader_cs_n(spi_reader_cs_n),
        .reader_miso(spi_reader_miso),
        .axi_sclk(axi_spi_sck_t ? 1'b0 : axi_spi_sck_o),
        .axi_mosi(axi_spi_io0_t ? 1'b0 : axi_spi_io0_o),
        .axi_cs_n(axi_spi_ss_t ? 1'b1 : axi_spi_ss_o),
        .axi_miso(axi_spi_miso),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_cs_n(spi_cs_n),
        .spi_miso(spi_miso)
    );

    always_ff @(posedge clk) begin
        if (core_rst) begin
            sample_count         <= 32'b0;
            error_latched        <= 1'b0;
            error_code           <= 32'b0;
            missed_icm_count_d   <= 32'b0;
            missed_intan_count_d <= 32'b0;
            packet_done_irq      <= 1'b0;
            debug_icm_frame      <= '0;
            data_word0           <= 32'b0;
            data_word1           <= 32'b0;
            data_word2           <= 32'b0;
            data_word3           <= 32'b0;
            data_word4           <= 32'b0;
            data_word5           <= 32'b0;
            data_word6           <= 32'b0;
            data_word7           <= 32'b0;
        end else begin
            if (axil_clear_error) begin
                error_latched <= error_events != 0;
                error_code    <= error_events;
            end else if (error_events != 0) begin
                error_latched <= 1'b1;
                error_code <= error_code | error_events;
            end

            if (axil_cpu_clear_irq) packet_done_irq <= 1'b0;
            else if (packet_writer_packet_done) packet_done_irq <= 1'b1;

            if (axil_reset_sample_counter) sample_count <= 32'b0;
            else if (packet_writer_packet_done) sample_count <= sample_count + 1'b1;

            missed_intan_count_d <= missed_intan_count;
            missed_icm_count_d   <= missed_icm_count;

            if (spi_done) debug_icm_frame <= icm_frame;

            if (packet_writer_packet_done) begin
                data_word0 <= sample_count;
                data_word1 <= PACKET_AXIS_WORDS;
                data_word2 <= PACKET_BUFFER_WORDS;
                data_word3 <= debug_icm_frame.init_read_ts[31:0];
                data_word4 <= debug_icm_frame.init_read_ts[63:32];
                data_word5 <= debug_icm_frame.done_read_ts[31:0];
                data_word6 <= debug_icm_frame.done_read_ts[63:32];
                data_word7 <= PACKET_BYTES;
            end
        end
    end

    packet_buffer #(
        .DATA_WIDTH  (AXIS_DATA_WIDTH),
        .DEPTH_WORDS (PACKET_BUFFER_WORDS),
        .PACKET_WORDS(PACKET_AXIS_WORDS)
    ) u_packet_buffer (
        .clk(clk),
        .rst(packet_path_rst),
        .wr_en(packet_fifo_wr_en),
        .wr_data(packet_fifo_wr_data),
        .rd_en(packet_fifo_rd_en),
        .rd_data(packet_fifo_rd_data),
        .empty(),
        .full(packet_fifo_full),
        .packet_space(packet_fifo_packet_space),
        .packet_available(packet_fifo_packet_available),
        .overflow(packet_fifo_overflow),
        .underflow(packet_fifo_underflow)
    );

    packet_to_axis u_packet_to_axis (
        .clk(clk),
        .rst(packet_path_rst),
        .fifo_rd_en(packet_fifo_rd_en),
        .fifo_rd_data(packet_fifo_rd_data),
        .fifo_packet_available(packet_fifo_packet_available),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tlast(m_axis_tlast)
    );

endmodule
