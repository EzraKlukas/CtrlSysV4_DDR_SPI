`timescale 1ns/1ps

module SPI_path_tb;

localparam integer NUM_SENSORS = 2;
localparam integer DATA_BYTES = 2;
localparam logic [15:0] SENSOR0_DATA = 16'hA55A;
localparam logic [15:0] SENSOR1_DATA = 16'h3CC3;

logic clk = 1'b0;
logic rst = 1'b1;
logic start = 1'b0;
logic [63:0] timestamp = 64'b0;
wire [15:0] data_out [NUM_SENSORS-1:0];
logic [63:0] start_timestamp;
logic [63:0] done_timestamp;
logic busy;
logic done;
logic reader_sclk;
logic reader_mosi;
logic [NUM_SENSORS-1:0] reader_miso = '0;
logic reader_cs_n;

logic axi_enable;
logic axi_sclk;
logic axi_mosi;
logic axi_cs_n;
logic axi_miso;
logic [NUM_SENSORS-1:0] mux_reader_miso;
logic mux_sclk;
logic mux_mosi;
logic mux_cs_n;
logic [NUM_SENSORS-1:0] mux_miso;

logic [7:0] captured_command = 8'b0;
integer command_edges = 0;
integer response_bit = 15;

always #5 clk = ~clk;
always @(posedge clk)
    timestamp <= timestamp + 1'b1;

always @(posedge reader_sclk) begin
    if (!reader_cs_n && command_edges < 8) begin
        captured_command = {captured_command[6:0], reader_mosi};
        command_edges = command_edges + 1;
    end
end

always @(negedge reader_sclk) begin
    if (!reader_cs_n && command_edges >= 8 && response_bit >= 0) begin
        reader_miso[0] <= SENSOR0_DATA[response_bit];
        reader_miso[1] <= SENSOR1_DATA[response_bit];
        response_bit = response_bit - 1;
    end
end

SPI_reader #(
    .REG_ADDR(7'd45),
    .DATA_BYTES(DATA_BYTES),
    .NUM_SENSORS(NUM_SENSORS)
) u_reader (
    .clk(clk),
    .rst(rst),
    .start(start),
    .timestamp(timestamp),
    .data_out(data_out),
    .startRead_timestamp(start_timestamp),
    .doneRead_timestamp(done_timestamp),
    .busy(busy),
    .done(done),
    .sclk(reader_sclk),
    .mosi(reader_mosi),
    .miso(reader_miso),
    .cs_n(reader_cs_n)
);

SPI_mux #(
    .NUM_SENSORS(NUM_SENSORS)
) u_mux (
    .axi_enable(axi_enable),
    .reader_sclk(1'b1),
    .reader_mosi(1'b0),
    .reader_cs_n(1'b0),
    .reader_miso(mux_reader_miso),
    .axi_sclk(axi_sclk),
    .axi_mosi(axi_mosi),
    .axi_cs_n(axi_cs_n),
    .axi_miso(axi_miso),
    .spi_sclk(mux_sclk),
    .spi_mosi(mux_mosi),
    .spi_cs_n(mux_cs_n),
    .spi_miso(mux_miso)
);

initial begin
    axi_enable = 1'b0;
    axi_sclk = 1'b0;
    axi_mosi = 1'b1;
    axi_cs_n = 1'b0;
    mux_miso = 2'b10;

    #1;
    if (mux_cs_n !== 1'b0 || mux_sclk !== 1'b1 || mux_mosi !== 1'b0)
        $fatal(1, "Reader-mode SPI mux routing failed");
    if (mux_reader_miso !== mux_miso)
        $fatal(1, "Reader MISO routing failed");

    axi_enable = 1'b1;
    #1;
    if (mux_cs_n !== axi_cs_n || mux_sclk !== axi_sclk || mux_mosi !== axi_mosi)
        $fatal(1, "AXI-mode SPI mux routing failed");
    if (axi_miso !== mux_miso[0])
        $fatal(1, "AXI MISO must come from sensor 0");

    repeat (3) @(posedge clk);
    rst <= 1'b0;
    @(posedge clk);
    start <= 1'b1;
    @(posedge clk);
    start <= 1'b0;

    wait (done);
    #1;
    if (captured_command !== 8'hAD)
        $fatal(1, "SPI command mismatch: got %h", captured_command);
    if (data_out[0] !== SENSOR0_DATA || data_out[1] !== SENSOR1_DATA)
        $fatal(1, "SPI data mismatch: got %h %h", data_out[0], data_out[1]);
    if (done_timestamp <= start_timestamp)
        $fatal(1, "Reader timestamps are invalid");

    $display("SPI path test passed");
    $finish;
end

initial begin
    #10000;
    $fatal(1, "SPI path test timed out");
end

endmodule
