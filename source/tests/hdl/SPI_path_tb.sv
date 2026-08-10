`timescale 1ns / 1ps

module SPI_path_tb;
    localparam int NUM_SENSORS = config_pkg::NUM_ICM;
    localparam int DATA_BYTES = config_pkg::ICM_DATA_BYTES;
    localparam int RESPONSE_BITS = 8 * DATA_BYTES;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic start = 1'b0;
    logic [63:0] timestamp = '0;
    config_pkg::ICM_frame_t frame;
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

    logic [7:0] captured_command = '0;
    logic [NUM_SENSORS-1:0][RESPONSE_BITS-1:0] sensor_data = '0;
    integer command_edges = 0;
    integer response_bit = RESPONSE_BITS - 1;

    always #5 clk = ~clk;
    always @(posedge clk) timestamp <= timestamp + 1'b1;

    always @(posedge reader_sclk) begin
        if (!reader_cs_n && command_edges < 8) begin
            captured_command = {captured_command[6:0], reader_mosi};
            command_edges = command_edges + 1;
        end
    end

    always @(negedge reader_sclk) begin
        if (!reader_cs_n && command_edges >= 8 && response_bit >= 0) begin
            for (int sensor = 0; sensor < NUM_SENSORS; sensor++)
                reader_miso[sensor] <= sensor_data[sensor][response_bit];
            response_bit = response_bit - 1;
        end
    end

    ICM_reader #(
        .REG_ADDR(7'd45),
        .SCLK_HALF_PERIOD_CYCLES(2),
        .NUM_ICM(NUM_SENSORS),
        .ICM_DATA_BYTES(DATA_BYTES)
    ) u_reader (
        .clk(clk),
        .rst(rst),
        .start(start),
        .timestamp(timestamp),
        .ICM_frame(frame),
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
        for (int sensor = 0; sensor < NUM_SENSORS; sensor++) begin
            for (int byte_index = 0; byte_index < DATA_BYTES; byte_index++) begin
                sensor_data[sensor][8*byte_index+:8] =
                    8'(sensor * 32 + byte_index);
            end
        end

        axi_enable = 1'b0;
        axi_sclk = 1'b0;
        axi_mosi = 1'b1;
        axi_cs_n = 1'b0;
        mux_miso = 4'b1010;

        #1;
        if (mux_cs_n !== 1'b0 || mux_sclk !== 1'b1 || mux_mosi !== 1'b0)
            $fatal(1, "reader-mode SPI mux routing failed");
        if (mux_reader_miso !== mux_miso)
            $fatal(1, "reader MISO routing failed");

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
        if (captured_command !== 8'had)
            $fatal(1, "SPI command mismatch: got %h", captured_command);
        for (int sensor = 0; sensor < NUM_SENSORS; sensor++) begin
            if (frame.ICM_data[sensor].sensor_id !== sensor[7:0])
                $fatal(1, "ICM sensor ID mismatch at %0d", sensor);
            if (frame.ICM_data[sensor].data !== sensor_data[sensor])
                $fatal(1, "ICM data mismatch at sensor %0d", sensor);
        end
        if (frame.done_read_ts <= frame.init_read_ts)
            $fatal(1, "reader timestamps are invalid");
        if (busy) $fatal(1, "reader remained busy after done");

        $display("PASS SPI_path_tb");
        $finish;
    end

    initial begin
        #20us;
        $fatal(1, "SPI_path_tb timed out");
    end
endmodule
