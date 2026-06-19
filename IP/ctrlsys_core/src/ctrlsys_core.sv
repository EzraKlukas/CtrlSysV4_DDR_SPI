`timescale 1ns/1ps

import config_pkg::*;

module ctrlsys_core #(
    parameter integer NUM_SENSORS = 3,
    parameter integer BUFFER_SIZE = 5
)(
    input  logic                         clk,
    input  logic                         rst_n,

    output logic                         spi_sclk,
    output logic                         spi_mosi,
    output logic                         spi_cs_n,
    input  logic [NUM_SENSORS-1:0]       spi_miso,

    output logic                         axi_spi_io0_i,
    input  logic                         axi_spi_io0_o,
    input  logic                         axi_spi_io0_t,
    output logic                         axi_spi_io1_i,
    input  logic                         axi_spi_io1_o,
    input  logic                         axi_spi_io1_t,
    output logic                         axi_spi_sck_i,
    input  logic                         axi_spi_sck_o,
    input  logic                         axi_spi_sck_t,
    output logic                         axi_spi_ss_i,
    input  logic                         axi_spi_ss_o,
    input  logic                         axi_spi_ss_t,

    output logic                         m_axis_tvalid,
    input  logic                         m_axis_tready,
    output logic [31:0]                  m_axis_tdata,
    output logic [3:0]                   m_axis_tkeep,
    output logic                         m_axis_tlast,

    input  logic                         s00_axi_aclk,
    input  logic                         s00_axi_aresetn,
    input  logic [5:0]                   s00_axi_awaddr,
    input  logic [2:0]                   s00_axi_awprot,
    input  logic                         s00_axi_awvalid,
    output logic                         s00_axi_awready,
    input  logic [31:0]                  s00_axi_wdata,
    input  logic [3:0]                   s00_axi_wstrb,
    input  logic                         s00_axi_wvalid,
    output logic                         s00_axi_wready,
    output logic [1:0]                   s00_axi_bresp,
    output logic                         s00_axi_bvalid,
    input  logic                         s00_axi_bready,
    input  logic [5:0]                   s00_axi_araddr,
    input  logic [2:0]                   s00_axi_arprot,
    input  logic                         s00_axi_arvalid,
    output logic                         s00_axi_arready,
    output logic [31:0]                  s00_axi_rdata,
    output logic [1:0]                   s00_axi_rresp,
    output logic                         s00_axi_rvalid,
    input  logic                         s00_axi_rready
);

localparam logic [6:0] SPI_REG_ADDR = 7'd45;
localparam integer SPI_DATA_BYTES = SENSOR_DATA_BYTES;

initial begin
    if (NUM_SENSORS < 1 || NUM_SENSORS > 32)
        $error("ctrlsys_core requires 1 <= NUM_SENSORS <= 32");
    if (BUFFER_SIZE < 1)
        $error("ctrlsys_core requires BUFFER_SIZE >= 1");
end

logic [63:0] timestamp;
logic start_read;
logic spi_start;
logic core_rst;

raw_packet_t sensor_frame [NUM_SENSORS];
raw_packet_t fifo_frame [NUM_SENSORS];
raw_packet_t status_frame;

logic [8*SPI_DATA_BYTES-1:0] spi_data [NUM_SENSORS-1:0];
logic [63:0] spi_start_timestamp;
logic [63:0] spi_done_timestamp;
logic spi_reader_sclk;
logic spi_reader_mosi;
logic spi_reader_cs_n;
logic [NUM_SENSORS-1:0] spi_reader_miso;
logic spi_busy;
logic spi_done;
logic axi_spi_miso;

logic frame_wr_en;
logic frame_rd_en;
logic frame_empty;
logic frame_full;

logic axil_enable;
logic axil_soft_reset;
logic [31:0] axil_sample_period;
logic axil_use_axi;
logic axil_clear_error;
logic axil_reset_sample_counter;
logic axil_cpu_clear_irq;
logic packet_done_irq;
logic error_latched;
logic [31:0] sample_count;
logic [31:0] error_code;
logic [31:0] data_word0;
logic [31:0] data_word1;
logic [31:0] data_word2;
logic [31:0] data_word3;
logic [31:0] data_word4;
logic [31:0] data_word5;
logic [31:0] data_word6;
logic [31:0] data_word7;

integer frame_sensor_index;

logic rst_meta;
logic rst_sync;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rst_meta <= 1'b1;
        rst_sync <= 1'b1;
    end else begin
        rst_meta <= 1'b0;
        rst_sync <= rst_meta;
    end
end

assign core_rst = rst_sync || axil_soft_reset;
assign spi_start = start_read && !axil_use_axi && !frame_full && !spi_busy;
assign status_frame = sensor_frame[0];
assign axi_spi_io0_i = axi_spi_io0_o;
assign axi_spi_io1_i = axi_spi_miso;
assign axi_spi_sck_i = axi_spi_sck_o;
assign axi_spi_ss_i = axi_spi_ss_o;

axil_regs u_axil_regs (
    .enable(axil_enable),
    .soft_reset(axil_soft_reset),
    .sample_period(axil_sample_period),
    .useAXI(axil_use_axi),
    .clear_error(axil_clear_error),
    .reset_sample_counter(axil_reset_sample_counter),
    .cpu_clear_irq(axil_cpu_clear_irq),
    .busy(spi_busy || frame_full),
    .error(error_latched),
    .read_in_progress(spi_busy),
    .packet_done(packet_done_irq),
    .sample_count(sample_count),
    .error_code(error_code),
    .state({2'b0, spi_busy, axil_use_axi}),
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
    .enable(axil_enable),
    .timestamp(timestamp),
    .sample_period({32'b0, axil_sample_period}),
    .startRead(start_read)
);

SPI_reader #(
    .REG_ADDR(SPI_REG_ADDR),
    .DATA_BYTES(SPI_DATA_BYTES),
    .NUM_SENSORS(NUM_SENSORS)
) u_spi_reader (
    .clk(clk),
    .rst(core_rst),
    .start(spi_start),
    .timestamp(timestamp),
    .data_out(spi_data),
    .startRead_timestamp(spi_start_timestamp),
    .doneRead_timestamp(spi_done_timestamp),
    .busy(spi_busy),
    .done(spi_done),
    .sclk(spi_reader_sclk),
    .mosi(spi_reader_mosi),
    .miso(spi_reader_miso),
    .cs_n(spi_reader_cs_n)
);

SPI_mux #(
    .NUM_SENSORS(NUM_SENSORS)
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
        frame_wr_en <= 1'b0;
        for (frame_sensor_index = 0;
             frame_sensor_index < NUM_SENSORS;
             frame_sensor_index = frame_sensor_index + 1)
            sensor_frame[frame_sensor_index] <= '0;
    end else begin
        frame_wr_en <= 1'b0;

        if (spi_done && !frame_full) begin
            frame_wr_en <= 1'b1;
            for (frame_sensor_index = 0;
                 frame_sensor_index < NUM_SENSORS;
                 frame_sensor_index = frame_sensor_index + 1) begin
                sensor_frame[frame_sensor_index] <= {
                    spi_start_timestamp,
                    spi_done_timestamp,
                    spi_data[frame_sensor_index]
                };
            end
        end
    end
end

always_ff @(posedge clk) begin
    if (core_rst) begin
        sample_count    <= 32'b0;
        error_latched   <= 1'b0;
        error_code      <= 32'b0;
        packet_done_irq <= 1'b0;
        data_word0      <= 32'b0;
        data_word1      <= 32'b0;
        data_word2      <= 32'b0;
        data_word3      <= 32'b0;
        data_word4      <= 32'b0;
        data_word5      <= 32'b0;
        data_word6      <= 32'b0;
        data_word7      <= 32'b0;
    end else begin
        if (axil_clear_error) begin
            error_latched <= 1'b0;
            error_code    <= 32'b0;
        end

        if (axil_cpu_clear_irq)
            packet_done_irq <= 1'b0;
        else if (frame_wr_en)
            packet_done_irq <= 1'b1;

        if (axil_reset_sample_counter)
            sample_count <= 32'b0;
        else if (frame_wr_en)
            sample_count <= sample_count + 1'b1;

        if (frame_wr_en) begin
            data_word0 <= status_frame.init_read_ts[31:0];
            data_word1 <= status_frame.init_read_ts[63:32];
            data_word2 <= 32'b0;
            data_word3 <= status_frame.sensor_data[159:128];
            data_word4 <= status_frame.sensor_data[127:96];
            data_word5 <= status_frame.sensor_data[95:64];
            data_word6 <= status_frame.sensor_data[63:32];
            data_word7 <= status_frame.sensor_data[31:0];
        end
    end
end

data_buff #(
    .NUM_SENSORS(NUM_SENSORS),
    .BUFFER_SIZE(BUFFER_SIZE)
) u_data_buff (
    .clk(clk),
    .rst(core_rst),
    .wr_en(frame_wr_en),
    .rd_en(frame_rd_en),
    .in_frame(sensor_frame),
    .out_frame(fifo_frame),
    .empty(frame_empty),
    .full(frame_full)
);

frame_to_axis #(
    .NUM_SENSORS(NUM_SENSORS),
    .data_width(32)
) u_frame_to_axis (
    .clk(clk),
    .rst(core_rst),
    .rd_en(frame_rd_en),
    .empty(frame_empty),
    .frame(fifo_frame),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tlast(m_axis_tlast)
);

endmodule
