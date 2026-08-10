`timescale 1ns / 1ps

module ctrlsys_core_tb;
    timeunit 1ns;
    timeprecision 1ps;

    localparam time CLK_PERIOD = 8ns;
    localparam logic [31:0] STATUS_ERROR = 32'h0000_0002;
    localparam logic [31:0] STATUS_PACKET_DONE = 32'h0000_0008;
    localparam logic [31:0] STATUS_INTAN_INITIALIZED = 32'h0000_0100;
    localparam logic [31:0] STATUS_INTAN_INIT_ERROR = 32'h0000_0400;
    localparam logic [31:0] ERROR_INTAN_INIT = 32'h0000_0004;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    logic spi_sclk;
    logic spi_mosi;
    logic spi_cs_n;
    logic [config_pkg::NUM_ICM-1:0] spi_miso = '0;

    logic intan_sclk;
    logic intan_mosi;
    logic intan_cs_n;
    wire [config_pkg::NUM_INTAN-1:0] intan_miso;
    logic [config_pkg::NUM_INTAN-1:0] intan_fault = '0;
    logic [config_pkg::NUM_INTAN-1:0] intan_present = '1;

    logic axi_spi_io0_i;
    logic axi_spi_io1_i;
    logic axi_spi_sck_i;
    logic axi_spi_ss_i;

    logic axis_valid;
    logic axis_ready = 1'b1;
    logic [config_pkg::AXIS_DATA_WIDTH-1:0] axis_data;
    logic [config_pkg::AXIS_BYTES-1:0] axis_keep;
    logic axis_last;

    logic [5:0] axi_awaddr = '0;
    logic [2:0] axi_awprot = '0;
    logic axi_awvalid = 1'b0;
    logic axi_awready;
    logic [31:0] axi_wdata = '0;
    logic [3:0] axi_wstrb = '0;
    logic axi_wvalid = 1'b0;
    logic axi_wready;
    logic [1:0] axi_bresp;
    logic axi_bvalid;
    logic axi_bready = 1'b0;
    logic [5:0] axi_araddr = '0;
    logic [2:0] axi_arprot = '0;
    logic axi_arvalid = 1'b0;
    logic axi_arready;
    logic [31:0] axi_rdata;
    logic [1:0] axi_rresp;
    logic axi_rvalid;
    logic axi_rready = 1'b0;

    byte unsigned packet_bytes[0:1][0:config_pkg::PACKET_BYTES-1];
    int packet_count = 0;
    int packet_byte_count = 0;
    int packet_beat_count = 0;
    int ready_counter = 0;
    logic stalled = 1'b0;
    logic [config_pkg::AXIS_DATA_WIDTH-1:0] stalled_data;
    logic [config_pkg::AXIS_BYTES-1:0] stalled_keep;
    logic stalled_last;

    ctrlsys_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_cs_n(spi_cs_n),
        .spi_miso(spi_miso),
        .intan_sclk(intan_sclk),
        .intan_mosi(intan_mosi),
        .intan_cs_n(intan_cs_n),
        .intan_miso(intan_miso),
        .axi_spi_io0_i(axi_spi_io0_i),
        .axi_spi_io0_o(1'b0),
        .axi_spi_io0_t(1'b1),
        .axi_spi_io1_i(axi_spi_io1_i),
        .axi_spi_io1_o(1'b0),
        .axi_spi_io1_t(1'b1),
        .axi_spi_sck_i(axi_spi_sck_i),
        .axi_spi_sck_o(1'b0),
        .axi_spi_sck_t(1'b1),
        .axi_spi_ss_i(axi_spi_ss_i),
        .axi_spi_ss_o(1'b1),
        .axi_spi_ss_t(1'b1),
        .m_axis_tvalid(axis_valid),
        .m_axis_tready(axis_ready),
        .m_axis_tdata(axis_data),
        .m_axis_tkeep(axis_keep),
        .m_axis_tlast(axis_last),
        .s00_axi_aclk(clk),
        .s00_axi_aresetn(rst_n),
        .s00_axi_awaddr(axi_awaddr),
        .s00_axi_awprot(axi_awprot),
        .s00_axi_awvalid(axi_awvalid),
        .s00_axi_awready(axi_awready),
        .s00_axi_wdata(axi_wdata),
        .s00_axi_wstrb(axi_wstrb),
        .s00_axi_wvalid(axi_wvalid),
        .s00_axi_wready(axi_wready),
        .s00_axi_bresp(axi_bresp),
        .s00_axi_bvalid(axi_bvalid),
        .s00_axi_bready(axi_bready),
        .s00_axi_araddr(axi_araddr),
        .s00_axi_arprot(axi_arprot),
        .s00_axi_arvalid(axi_arvalid),
        .s00_axi_arready(axi_arready),
        .s00_axi_rdata(axi_rdata),
        .s00_axi_rresp(axi_rresp),
        .s00_axi_rvalid(axi_rvalid),
        .s00_axi_rready(axi_rready)
    );

    genvar sensor_gen;
    generate
        for (sensor_gen = 0; sensor_gen < config_pkg::NUM_INTAN; sensor_gen++) begin : sensors
            rhd2164_model #(
                .SENSOR_ID(sensor_gen),
                .SAMPLE_BASE(16'h1000),
                .T_MISO(12ns)
            ) model (
                .cs_n(intan_cs_n),
                .sclk(intan_sclk),
                .mosi(intan_mosi),
                .miso(intan_miso[sensor_gen]),
                .fault_bit(intan_fault[sensor_gen]),
                .init_bit(intan_present[sensor_gen]),
                .captured_command(),
                .command_valid()
            );
        end
    endgenerate

    task automatic fail(input string message);
        $fatal(1, "%0t: %s", $realtime, message);
    endtask

    task automatic axil_write(input logic [5:0] address, input logic [31:0] data);
        begin
            @(negedge clk);
            while (!axi_awready || !axi_wready) @(negedge clk);
            axi_awaddr = address;
            axi_awvalid = 1'b1;
            axi_wdata = data;
            axi_wstrb = 4'hf;
            axi_wvalid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            axi_awvalid = 1'b0;
            axi_wvalid = 1'b0;
            axi_bready = 1'b1;
            while (!axi_bvalid) @(negedge clk);
            if (axi_bresp != 2'b00) fail("AXI-Lite write returned non-OKAY response");
            @(negedge clk);
            axi_bready = 1'b0;
        end
    endtask

    task automatic axil_read(input logic [5:0] address, output logic [31:0] data);
        begin
            @(negedge clk);
            while (!axi_arready) @(negedge clk);
            axi_araddr = address;
            axi_arvalid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            axi_arvalid = 1'b0;
            axi_rready = 1'b1;
            while (!axi_rvalid) @(negedge clk);
            if (axi_rresp != 2'b00) fail("AXI-Lite read returned non-OKAY response");
            data = axi_rdata;
            @(negedge clk);
            axi_rready = 1'b0;
        end
    endtask

    task automatic wait_status(input logic [31:0] mask, input logic [31:0] value,
                               input int max_reads);
        logic [31:0] status;
        int reads;
        begin
            status = value ^ mask;
            for (reads = 0; reads < max_reads && (status & mask) != value; reads++)
                axil_read(6'h10, status);
            if ((status & mask) != value)
                fail($sformatf("status timeout: got 0x%08h mask 0x%08h value 0x%08h",
                               status, mask, value));
        end
    endtask

    function automatic int unsigned packet_be32(input int packet_index, input int offset);
        packet_be32 = {
            packet_bytes[packet_index][offset],
            packet_bytes[packet_index][offset+1],
            packet_bytes[packet_index][offset+2],
            packet_bytes[packet_index][offset+3]
        };
    endfunction

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            packet_count <= 0;
            packet_byte_count <= 0;
            packet_beat_count <= 0;
            ready_counter <= 0;
            axis_ready <= 1'b1;
            stalled <= 1'b0;
        end else begin
            ready_counter <= ready_counter + 1;
            axis_ready <= ready_counter[3:0] != 4'h7;

            if (stalled) begin
                if (!axis_valid || axis_data !== stalled_data || axis_keep !== stalled_keep ||
                    axis_last !== stalled_last)
                    fail("AXI stream changed while tready was low");
                if (axis_ready) stalled <= 1'b0;
            end else if (axis_valid && !axis_ready) begin
                stalled <= 1'b1;
                stalled_data <= axis_data;
                stalled_keep <= axis_keep;
                stalled_last <= axis_last;
            end

            if (axis_valid && axis_ready) begin
                if (packet_count >= 2) fail("unexpected third AXI packet");
                if (axis_keep !== '1) fail("aligned packet produced partial tkeep");
                if (axis_last !== (packet_beat_count == config_pkg::PACKET_AXIS_WORDS - 1))
                    fail("AXI tlast was not on the final packet word");

                for (int lane = 0; lane < config_pkg::AXIS_BYTES; lane++)
                    packet_bytes[packet_count][packet_byte_count+lane] <=
                        axis_data[8*lane+:8];

                if (axis_last) begin
                    packet_count <= packet_count + 1;
                    packet_byte_count <= 0;
                    packet_beat_count <= 0;
                end else begin
                    packet_byte_count <= packet_byte_count + config_pkg::AXIS_BYTES;
                    packet_beat_count <= packet_beat_count + 1;
                end
            end
        end
    end

    initial begin : test
        logic [31:0] value;
        int waited;
        int trailer;

        intan_fault[0] = 1'b1;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        wait_status(STATUS_INTAN_INIT_ERROR | STATUS_ERROR,
                    STATUS_INTAN_INIT_ERROR | STATUS_ERROR, 20000);
        $display("Observed expected initialization failure at %0t", $realtime);
        axil_read(6'h1c, value);
        if ((value & ERROR_INTAN_INIT) == 0)
            fail("initialization error was absent from error_code bitmask");
        if (packet_count != 0 || axis_valid)
            fail("failed initialization produced AXI stream data");

        intan_fault[0] = 1'b0;
        wait_status(STATUS_INTAN_INITIALIZED, STATUS_INTAN_INITIALIZED, 40000);
        $display("Observed successful initialization retry at %0t", $realtime);
        axil_write(6'h0c, 32'h0000_0001);
        wait_status(STATUS_ERROR | STATUS_INTAN_INIT_ERROR, 32'b0, 100);
        axil_read(6'h1c, value);
        if (value != 0) fail("clear_error did not clear the error bitmask");

        repeat (200) @(posedge clk);
        if (packet_count != 0 || axis_valid)
            fail("initialization while disabled produced a packet");

        axil_write(6'h04, config_pkg::ICM_SAMPLE_PERIOD_TICKS_DEFAULT);
        axil_write(6'h00, 32'h0000_0001);

        waited = 0;
        while (packet_count < 2 && waited < 400000) begin
            @(posedge clk);
            waited++;
        end
        if (packet_count != 2) fail("timed out waiting for two complete AXI packets");
        #1ps;

        trailer = config_pkg::PACKET_TRAILER_OFFSET_BYTES;
        if (packet_be32(1, trailer + 20) !=
            2 * config_pkg::INTAN_FRAME_BYTES + config_pkg::ICM_FRAME_BYTES)
            fail("second packet valid_data_bytes mismatch");
        if (packet_be32(1, trailer + 24) != 2)
            fail("second packet did not contain the nominal two Intan frames");
        if (packet_be32(1, trailer + 28) != config_pkg::MAX_INTAN_FRAMES_PER_PACKET)
            fail("packet capacity field mismatch");
        if (packet_be32(1, trailer + 32) != 1)
            fail("ICM frame count mismatch");
        if (packet_be32(1, trailer + 36) != 2 * config_pkg::INTAN_FRAME_BYTES)
            fail("ICM frame offset mismatch");
        if (packet_be32(1, trailer + 40) != trailer)
            fail("trailer offset mismatch");
        if (packet_be32(1, trailer + 48) != 0 || packet_be32(1, trailer + 52) != 0)
            fail("packet reported dropped frames");
        if (packet_be32(1, trailer + 56) != 0 ||
            packet_be32(1, trailer + 60) != config_pkg::INTAN_FRAME_BYTES)
            fail("Intan frame offsets mismatch");

        if (packet_bytes[1][16] != 8'd7)
            fail("serialized sensor order did not begin with sensor 7");
        if ({packet_bytes[1][17], packet_bytes[1][18]} != 16'h173f)
            fail("sensor 7 channel 63 byte order mismatch");
        if ({packet_bytes[1][143], packet_bytes[1][144]} != 16'h1700)
            fail("sensor 7 channel 0 byte order mismatch");

        axil_read(6'h08, value);
        if (value != 0) fail("unexpected missed Intan read count");
        axil_read(6'h18, value);
        if (value != 0) fail("unexpected missed ICM read count");
        axil_read(6'h10, value);
        if ((value & STATUS_PACKET_DONE) == 0)
            fail("packet completion was not visible through AXI-Lite");
        axil_write(6'h0c, 32'h0000_0004);
        wait_status(STATUS_PACKET_DONE, 32'b0, 100);

        axil_write(6'h00, 32'b0);
        $display("PASS ctrlsys_core_tb");
        $finish;
    end

    initial begin : timeout
        #10ms;
        $fatal(1, "ctrlsys_core_tb timed out");
    end
endmodule
