`timescale 1ns / 1ps

module ctrlsys_core_tb;
    timeunit 1ns; timeprecision 1ps;

    localparam time CLK_PERIOD = 8ns;
    localparam logic [31:0] STATUS_ERROR = 32'h0000_0002;
    localparam logic [31:0] STATUS_PACKET_DONE = 32'h0000_0008;
    localparam logic [31:0] STATUS_INTAN_INITIALIZED = 32'h0000_0100;
    localparam logic [31:0] STATUS_INTAN_INIT_ERROR = 32'h0000_0400;
    localparam logic [31:0] ERROR_INTAN_INIT = 32'h0000_0004;
    localparam logic [31:0] CONTROL_ENABLE = 32'h0000_0001;
    localparam logic [31:0] CONTROL_DIAGNOSTIC_PAGE = 32'h0000_0008;
    localparam logic [31:0] COMMAND_CLEAR_ERROR = 32'h0000_0001;
    localparam logic [31:0] COMMAND_CLEAR_PACKET_IRQ = 32'h0000_0004;
    localparam logic [31:0] COMMAND_CLEAR_INTAN_DIAGNOSTICS = 32'h0000_0008;
    localparam logic [31:0] DIAGNOSTIC_FROZEN_STATUS_MASK = 32'h00f0_0007;
    localparam logic [31:0] DIAGNOSTIC_FROZEN_STATUS_VALUE = 32'h00f0_0007;

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
    int total_beat_count = 0;
    int ready_counter = 0;
    logic [31:0] sample_count_at_packet[0:1];
    logic stalled = 1'b0;
    logic [config_pkg::AXIS_DATA_WIDTH-1:0] stalled_data;
    logic [config_pkg::AXIS_BYTES-1:0] stalled_keep;
    logic stalled_last;
    logic [31:0] frozen_diagnostic[0:7];
    logic [31:0] legacy_data_words[0:7];

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
            axi_awaddr  = address;
            axi_awvalid = 1'b1;
            axi_wdata   = data;
            axi_wstrb   = 4'hf;
            axi_wvalid  = 1'b1;
            @(posedge clk);
            @(negedge clk);
            axi_awvalid = 1'b0;
            axi_wvalid  = 1'b0;
            axi_bready  = 1'b1;
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
            axi_araddr  = address;
            axi_arvalid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            axi_arvalid = 1'b0;
            axi_rready  = 1'b1;
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
                fail($sformatf(
                     "status timeout: got 0x%08h mask 0x%08h value 0x%08h", status, mask, value));
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
            total_beat_count <= 0;
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
                packet_bytes[packet_count][packet_byte_count+lane] <= axis_data[8*lane+:8];

                if (axis_last) begin
                    sample_count_at_packet[packet_count] <= dut.sample_count;
                    packet_count <= packet_count + 1;
                    packet_byte_count <= 0;
                    packet_beat_count <= 0;
                end else begin
                    packet_byte_count <= packet_byte_count + config_pkg::AXIS_BYTES;
                    packet_beat_count <= packet_beat_count + 1;
                end
                total_beat_count <= total_beat_count + 1;
            end
        end
    end

    initial begin : test
        logic [31:0] value;
        logic [31:0] retry_value;
        int waited;
        int trailer;

        intan_fault[0] = 1'b1;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        wait_status(STATUS_INTAN_INIT_ERROR | STATUS_ERROR, STATUS_INTAN_INIT_ERROR | STATUS_ERROR,
                    20000);
        $display("Observed expected initialization failure at %0t", $realtime);
        axil_read(6'h1c, value);
        if ((value & ERROR_INTAN_INIT) == 0)
            fail("initialization error was absent from error_code bitmask");
        if (packet_count != 0 || axis_valid) fail("failed initialization produced AXI stream data");

        // Page zero retains the legacy debug window until control bit 3 is set.
        for (int word_index = 0; word_index < 8; word_index++) begin
            axil_read(6'(6'h20 + 4 * word_index), value);
            if (value != 0) fail("legacy data window changed before the first packet");
        end

        axil_write(6'h00, CONTROL_DIAGNOSTIC_PAGE);
        axil_read(6'h00, value);
        if (value != CONTROL_DIAGNOSTIC_PAGE)
            fail("diagnostic page-select control bit was not persistent");
        if (dut.axil_enable || dut.axil_soft_reset || dut.axil_use_axi)
            fail("diagnostic page selection changed an existing control bit");

        for (int word_index = 0; word_index < 8; word_index++)
            axil_read(6'(6'h20 + 4 * word_index), frozen_diagnostic[word_index]);

        if ((frozen_diagnostic[0] & DIAGNOSTIC_FROZEN_STATUS_MASK) !=
            DIAGNOSTIC_FROZEN_STATUS_VALUE || frozen_diagnostic[0][31:24] != 0)
            fail("forced initialization failure was absent from diagnostic status");
        if (frozen_diagnostic[1][15:0] == 0 || frozen_diagnostic[1][23:16] != 8'd34 ||
            frozen_diagnostic[1][31:24] != 8'd34)
            fail("diagnostic attempt or mismatch counts were wrong");
        if (frozen_diagnostic[2] != 32'h8000_ff00 ||
            frozen_diagnostic[3] != 32'h0004_0000 ||
            frozen_diagnostic[4] != 32'h8000_ff00 ||
            frozen_diagnostic[5] != 32'h0004_0000)
            fail("first A/B mismatch metadata or response words were wrong");
        if (frozen_diagnostic[6] != 32'hffff_ffff ||
            frozen_diagnostic[7] != 32'hffff_ffff)
            fail("low 32 initialization mismatch bitmap bits were wrong");

        // Keep the model faulted through multiple automatic retries.  Only the
        // live attempt count may change; every frozen failure field must stay coherent.
        retry_value = frozen_diagnostic[1];
        waited = 0;
        while (retry_value[15:0] < 3 && waited < 100000) begin
            axil_read(6'h24, retry_value);
            waited++;
        end
        if (retry_value[15:0] < 3)
            fail("automatic initialization retries did not increment the attempt count");
        if (retry_value[31:16] != frozen_diagnostic[1][31:16])
            fail("automatic retry changed frozen mismatch counts");
        for (int word_index = 2; word_index < 8; word_index++) begin
            axil_read(6'(6'h20 + 4 * word_index), value);
            if (value != frozen_diagnostic[word_index])
                fail("automatic retry tore or overwrote the frozen diagnostic snapshot");
        end

        intan_fault[0] = 1'b0;
        wait_status(STATUS_INTAN_INITIALIZED, STATUS_INTAN_INITIALIZED, 40000);
        $display("Observed successful initialization retry at %0t", $realtime);

        axil_read(6'h20, value);
        if ((value & 32'h0000_0001) == 0)
            fail("successful retry overwrote the frozen failure snapshot");

        // Diagnostic clear is independent of all three legacy command pulses.
        axil_write(6'h0c, COMMAND_CLEAR_INTAN_DIAGNOSTICS);
        axil_read(6'h1c, value);
        if ((value & ERROR_INTAN_INIT) == 0)
            fail("diagnostic clear aliased the legacy clear-error command");
        axil_read(6'h14, value);
        if (value != 0) fail("diagnostic clear aliased reset-sample-count");
        axil_read(6'h10, value);
        if ((value & STATUS_PACKET_DONE) != 0)
            fail("packet-done IRQ unexpectedly set before acquisition");
        axil_read(6'h24, value);
        if (value != 0) fail("diagnostic clear did not clear counts");
        axil_read(6'h20, value);
        if (value[2:0] != 0 || !value[4])
            fail("diagnostic clear did not clear the snapshot or disturbed initialization");

        axil_write(6'h0c, COMMAND_CLEAR_ERROR);
        wait_status(STATUS_ERROR | STATUS_INTAN_INIT_ERROR, 32'b0, 100);
        axil_read(6'h1c, value);
        if (value != 0) fail("clear_error did not clear the error bitmask");

        repeat (200) @(posedge clk);
        if (packet_count != 0 || axis_valid)
            fail("initialization while disabled produced a packet");

        axil_write(6'h04, config_pkg::ICM_SAMPLE_PERIOD_TICKS_DEFAULT);
        axil_write(6'h00, CONTROL_ENABLE);

        waited = 0;
        while (packet_count < 2 && waited < 400000) begin
            @(posedge clk);
            waited++;
        end
        if (packet_count != 2) fail("timed out waiting for two complete AXI packets");
        #1ps;

        if (total_beat_count != 2 * config_pkg::PACKET_AXIS_WORDS)
            fail("two packets did not contain exactly 6,144 accepted AXI beats");
        if (sample_count_at_packet[0] != 1 || sample_count_at_packet[1] != 2)
            fail("sample counter was not monotonic across consecutive packets");

        trailer = config_pkg::PACKET_TRAILER_OFFSET_BYTES;
        if (packet_be32(0, trailer + 8) != 0 || packet_be32(1, trailer + 8) != 1)
            fail("packet counter was not monotonic across consecutive packets");
        if (packet_be32(
                1, trailer + 20
            ) != 2 * config_pkg::INTAN_FRAME_BYTES + config_pkg::ICM_FRAME_BYTES)
            fail("second packet valid_data_bytes mismatch");
        if (packet_be32(1, trailer + 24) != 2)
            fail("second packet did not contain the nominal two Intan frames");
        if (packet_be32(1, trailer + 28) != config_pkg::MAX_INTAN_FRAMES_PER_PACKET)
            fail("packet capacity field mismatch");
        if (packet_be32(1, trailer + 32) != 1) fail("ICM frame count mismatch");
        if (packet_be32(1, trailer + 36) != 2 * config_pkg::INTAN_FRAME_BYTES)
            fail("ICM frame offset mismatch");
        if (packet_be32(1, trailer + 40) != trailer) fail("trailer offset mismatch");
        if (packet_be32(1, trailer + 48) != 0 || packet_be32(1, trailer + 52) != 0)
            fail("packet reported dropped frames");
        if (packet_be32(
                1, trailer + 56
            ) != 0 || packet_be32(
                1, trailer + 60
            ) != config_pkg::INTAN_FRAME_BYTES)
            fail("Intan frame offsets mismatch");

        if (packet_bytes[1][16] != 8'd7)
            fail("serialized sensor order did not begin with sensor 7");
        if ({packet_bytes[1][17], packet_bytes[1][18]} != (config_pkg::INTAN_MASK[7] ? 16'h173f : 16'h0))
            fail("sensor 7 channel 63 byte order mismatch");
        if ({packet_bytes[1][143], packet_bytes[1][144]} != (config_pkg::INTAN_MASK[7] ? 16'h1700 : 16'h0))
            fail("sensor 7 channel 0 byte order mismatch");

        axil_read(6'h08, value);
        if (value != 0) fail("unexpected missed Intan read count");
        axil_read(6'h18, value);
        if (value != 0) fail("unexpected missed ICM read count");
        axil_read(6'h14, value);
        if (value != 2) fail("AXI-Lite sample counter did not report two packets");
        axil_read(6'h10, value);
        if ((value & STATUS_ERROR) != 0)
            fail("core reported an error during nominal acquisition");
        if ((value & STATUS_PACKET_DONE) == 0)
            fail("packet completion was not visible through AXI-Lite");

        for (int word_index = 0; word_index < 8; word_index++)
            axil_read(6'(6'h20 + 4 * word_index), legacy_data_words[word_index]);
        if (legacy_data_words[0] != 1 ||
            legacy_data_words[1] != config_pkg::PACKET_AXIS_WORDS ||
            legacy_data_words[2] != config_pkg::PACKET_BUFFER_WORDS ||
            legacy_data_words[7] != config_pkg::PACKET_BYTES)
            fail("legacy data-word values or addresses changed");

        // Switch banks while acquisition remains enabled.  This must change
        // only the read view and must not assert reset or route the ICM pins.
        axil_write(6'h00, CONTROL_ENABLE | CONTROL_DIAGNOSTIC_PAGE);
        if (!dut.axil_enable || dut.axil_soft_reset || dut.axil_use_axi)
            fail("diagnostic page selection disturbed active control bits");
        for (int word_index = 1; word_index < 8; word_index++) begin
            axil_read(6'(6'h20 + 4 * word_index), value);
            if (value != 0) fail("cleared diagnostic page contained stale snapshot data");
        end

        // With a nonzero sample count and asserted packet IRQ, command bit 3
        // proves it does not alias either legacy clear pulse.
        axil_write(6'h0c, COMMAND_CLEAR_INTAN_DIAGNOSTICS);
        axil_read(6'h14, value);
        if (value != 2) fail("diagnostic clear reset the sample count");
        axil_read(6'h10, value);
        if ((value & STATUS_PACKET_DONE) == 0)
            fail("diagnostic clear cleared the packet-done IRQ");

        axil_write(6'h00, CONTROL_ENABLE);
        for (int word_index = 0; word_index < 8; word_index++) begin
            axil_read(6'(6'h20 + 4 * word_index), value);
            if (value != legacy_data_words[word_index])
                fail("returning to page zero did not restore the legacy data-word view");
        end

        axil_write(6'h0c, COMMAND_CLEAR_PACKET_IRQ);
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
