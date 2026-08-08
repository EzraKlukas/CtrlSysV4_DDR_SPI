`timescale 1ns / 1ps

module integrate_intan_packet_path_layout_tb;
    timeunit 1ns; timeprecision 1ps;

    localparam time CLK_PERIOD = 8ns;

    localparam int MAX_COMMANDS = 34;
    localparam int NUM_CHAN_PER_ADC = INTAN_CHANNELS / 2;
    localparam int BITS_PER_WORD = INTAN_BITS_PER_WORD;

    localparam int SCLK_HALF_PERIOD_CYCLES = 3;
    localparam int T_CS_1_CYCLES = 6;
    localparam int T_CS_2_CYCLES = 6;
    localparam int T_CS_OFF_CYCLES = 20;
    localparam time T_MISO_MAX = 12ns;

    logic clk = 1'b0;
    logic rst = 1'b1;

    always #(CLK_PERIOD / 2) clk = ~clk;

    logic start_init = 1'b0;
    logic start_read = 1'b0;
    logic [63:0] timestamp = '0;
    logic read_mode;

    always @(posedge clk) begin
        if (rst) timestamp <= '0;
        else timestamp <= timestamp + 1'b1;
    end

    logic [6:0] init_list_len = 7'(MAX_COMMANDS);
    logic [MAX_COMMANDS-1:0][BITS_PER_WORD-1:0] init_cmd_list;
    logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] rx_init_list_expect_a;
    logic [MAX_COMMANDS-1:0][NUM_INTAN-1:0][BITS_PER_WORD-1:0] rx_init_list_expect_b;

    logic [6:0] acq_list_len = 7'(NUM_CHAN_PER_ADC);
    logic [MAX_COMMANDS-1:0][BITS_PER_WORD-1:0] acq_cmd_list;

    config_pkg::Intan_frame_t reader_intan_frame;
    config_pkg::Intan_frame_t reader_snapshots[0:1];
    config_pkg::ICM_frame_t icm_frame;

    logic reader_done_pulse;
    logic reader_error;
    logic intan_sclk;
    logic intan_mosi;
    logic intan_cs_n;
    wire [NUM_INTAN-1:0] intan_miso;

    logic [NUM_INTAN-1:0] intan_fault_bit = '0;
    logic [NUM_INTAN-1:0] intan_init_bit = '1;

    // logic read_in_flight = 1'b0;
    logic reader_intan_frame_done;
    int init_done_count = 0;
    int read_completion_count = 0;
    int forwarded_frame_count = 0;

    logic icm_done = 1'b0;
    logic packet_ready;
    logic writer_ready;
    logic writer_word_valid;
    logic writer_word_ready;
    logic [AXIS_DATA_WIDTH-1:0] writer_word_data;
    logic writer_packet_done;

    logic fifo_rd_en;
    logic [AXIS_DATA_WIDTH-1:0] fifo_rd_data;
    logic fifo_full;
    logic fifo_packet_space;
    logic fifo_packet_available;
    logic fifo_overflow;
    logic fifo_underflow;

    logic axis_valid;
    logic axis_ready = 1'b1;
    logic [AXIS_DATA_WIDTH-1:0] axis_data;
    logic [AXIS_DATA_WIDTH/8-1:0] axis_keep;
    logic axis_last;

    byte unsigned packet_bytes[0:PACKET_BYTES-1];
    int byte_count = 0;
    int beat_count = 0;
    int packet_done_count = 0;
    int axis_last_count = 0;

    assign packet_ready = fifo_packet_space;
    assign writer_word_ready = !fifo_full;
    assign reader_intan_frame_done = reader_done_pulse && read_mode;

    intan_reader #(
        .MAX_COMMANDS(MAX_COMMANDS),
        .NUM_INTAN(NUM_INTAN),
        .NUM_CHANNELS_PER_ADC(NUM_CHAN_PER_ADC),
        .BITS_PER_WORD(BITS_PER_WORD),
        .SCLK_HALF_PERIOD_CYCLES(SCLK_HALF_PERIOD_CYCLES),
        .CS_TO_SCLK_CYCLES(T_CS_1_CYCLES),
        .SCLK_TO_CS_CYCLES(T_CS_2_CYCLES),
        .CS_HIGH_CYCLES(T_CS_OFF_CYCLES)
    ) u_reader (
        .clk(clk),
        .rst(rst),
        .start_init(start_init),
        .start_read(start_read),
        .timestamp(timestamp),
        .read_mode(read_mode),
        .init_list_len(init_list_len),
        .init_cmd_list(init_cmd_list),
        .expect_rx_ans_list_a(rx_init_list_expect_a),
        .expect_rx_ans_list_b(rx_init_list_expect_b),
        .acq_list_len(acq_list_len),
        .acq_cmd_list(acq_cmd_list),
        .intan_frame(reader_intan_frame),
        .done_pulse(reader_done_pulse),
        .error(reader_error),
        .intan_sclk(intan_sclk),
        .intan_mosi(intan_mosi),
        .intan_cs_n(intan_cs_n),
        .intan_miso(intan_miso)
    );

    genvar sensor_gen;
    generate
        for (
            sensor_gen = 0; sensor_gen < NUM_INTAN; sensor_gen = sensor_gen + 1
        ) begin : intan_model_gen
            logic [15:0] captured_command;
            logic command_valid;

            rhd2164_model #(
                .SENSOR_ID(sensor_gen),
                .T_MISO(T_MISO_MAX),
                .CHECK_TIMING(1'b1)
            ) sensor (
                .cs_n(intan_cs_n),
                .sclk(intan_sclk),
                .mosi(intan_mosi),
                .miso(intan_miso[sensor_gen]),
                .fault_bit(intan_fault_bit[sensor_gen]),
                .init_bit(intan_init_bit[sensor_gen]),
                .captured_command(captured_command),
                .command_valid(command_valid)
            );
        end
    endgenerate

    packet_writer u_writer (
        .clk(clk),
        .rst(rst),
        .ICM_frame_done(icm_done),
        .Intan_frame_done(reader_intan_frame_done),
        .ICM_frame_in(icm_frame),
        .Intan_frame_in(reader_intan_frame),
        .packet_ready(packet_ready),
        .ready(writer_ready),
        .word_valid(writer_word_valid),
        .word_ready(writer_word_ready),
        .word_data(writer_word_data),
        .packet_done(writer_packet_done)
    );

    packet_buffer #(
        .DATA_WIDTH  (AXIS_DATA_WIDTH),
        .DEPTH_WORDS (PACKET_BUFFER_WORDS),
        .PACKET_WORDS(PACKET_AXIS_WORDS)
    ) u_buffer (
        .clk(clk),
        .rst(rst),
        .wr_en(writer_word_valid && !fifo_full),
        .wr_data(writer_word_data),
        .rd_en(fifo_rd_en),
        .rd_data(fifo_rd_data),
        .empty(),
        .full(fifo_full),
        .packet_space(fifo_packet_space),
        .packet_available(fifo_packet_available),
        .overflow(fifo_overflow),
        .underflow(fifo_underflow)
    );

    packet_to_axis u_axis (
        .clk(clk),
        .rst(rst),
        .fifo_rd_en(fifo_rd_en),
        .fifo_rd_data(fifo_rd_data),
        .fifo_packet_available(fifo_packet_available),
        .m_axis_tvalid(axis_valid),
        .m_axis_tready(axis_ready),
        .m_axis_tdata(axis_data),
        .m_axis_tkeep(axis_keep),
        .m_axis_tlast(axis_last)
    );

    task automatic fail(input string message);
        $fatal(1, "%0t: %s", $realtime, message);
    endtask

    task automatic set_init_vector(input int command_idx, input logic [15:0] command,
                                   input logic [15:0] response);
        begin
            init_cmd_list[command_idx] = command;
            for (int sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1) begin
                rx_init_list_expect_a[command_idx][sensor_idx] = response;
                rx_init_list_expect_b[command_idx][sensor_idx] = response;
            end
        end
    endtask

    task automatic reset_dut();
        begin
            rst <= 1'b1;
            start_init <= 1'b0;
            start_read <= 1'b0;
            icm_done <= 1'b0;
            intan_fault_bit <= '0;
            intan_init_bit <= '1;
            repeat (10) @(posedge clk);
            rst <= 1'b0;
            repeat (5) @(posedge clk);
        end
    endtask

    task automatic pulse_start_init();
        begin
            @(posedge clk);
            start_init <= 1'b1;
            @(posedge clk);
            start_init <= 1'b0;
        end
    endtask

    task automatic pulse_start_read();
        begin
            @(posedge clk);
            start_read <= 1'b1;
            @(posedge clk);
            start_read <= 1'b0;
        end
    endtask

    task automatic wait_for_init_count(input int target, input int timeout_cycles);
        int waited;
        begin
            waited = 0;
            while (init_done_count < target && waited < timeout_cycles) begin
                @(posedge clk);
                waited = waited + 1;
            end

            if (init_done_count < target)
                fail($sformatf(
                     "timed out waiting for initialization count %0d, got %0d",
                     target,
                     init_done_count
                     ));
        end
    endtask

    task automatic wait_for_read_count(input int target, input int timeout_cycles);
        int waited;
        begin
            waited = 0;
            while (read_completion_count < target && waited < timeout_cycles) begin
                @(posedge clk);
                waited = waited + 1;
            end

            if (read_completion_count < target)
                fail($sformatf(
                     "timed out waiting for read completion count %0d, got %0d",
                     target,
                     read_completion_count
                     ));
        end
    endtask

    task automatic wait_for_beat_count(input int target, input int timeout_cycles);
        int waited;
        begin
            waited = 0;
            while (beat_count < target && waited < timeout_cycles) begin
                @(posedge clk);
                waited = waited + 1;
            end

            if (beat_count < target)
                fail($sformatf(
                     "timed out waiting for AXI beat count %0d, got %0d", target, beat_count));
        end
    endtask

    task automatic fill_icm;
        begin
            icm_frame.init_read_ts = 64'h3000_0000_0000_0000;
            icm_frame.done_read_ts = 64'h4000_0000_0000_0000;
            for (int sensor = 0; sensor < NUM_ICM; sensor = sensor + 1) begin
                icm_frame.ICM_data[sensor].sensor_id = sensor[7:0];
                for (int byte_idx = 0; byte_idx < ICM_DATA_BYTES; byte_idx = byte_idx + 1)
                icm_frame.ICM_data[sensor].data[8*byte_idx+:8] =
                        byte'(int'(8'h80) + sensor + byte_idx);
            end
        end
    endtask

    task automatic pulse_icm_done();
        begin
            fill_icm();
            @(posedge clk);
            icm_done <= 1'b1;
            @(posedge clk);
            icm_done <= 1'b0;
        end
    endtask

    function automatic logic [15:0] expected_sample(input int sensor_idx, input int channel_idx);
        int unsigned sample;
        begin
            sample = 32'h1000 + sensor_idx * 32'h0100 + channel_idx;
            expected_sample = sample[15:0];
        end
    endfunction

    function automatic logic [7:0] intan_frame_byte(input config_pkg::Intan_frame_t frame,
                                                    input int byte_index);
        int unsigned msb;
        begin
            msb = INTAN_FRAME_BITS - 1 - 8 * byte_index;
            intan_frame_byte = frame[msb-:8];
        end
    endfunction

    function automatic logic [7:0] icm_frame_byte(input config_pkg::ICM_frame_t frame,
                                                  input int byte_index);
        int unsigned msb;
        begin
            msb = ICM_FRAME_BITS - 1 - 8 * byte_index;
            icm_frame_byte = frame[msb-:8];
        end
    endfunction

    function automatic int unsigned be32(input int offset);
        be32 = {
            packet_bytes[offset],
            packet_bytes[offset+1],
            packet_bytes[offset+2],
            packet_bytes[offset+3]
        };
    endfunction

    function automatic logic [AXIS_BYTES-1:0] expected_keep(input int beat_idx);
        begin
            expected_keep = '1;
            if (beat_idx == PACKET_AXIS_WORDS - 1 && PACKET_LAST_BYTES != AXIS_BYTES) begin
                expected_keep = '0;
                expected_keep[PACKET_LAST_BYTES-1:0] = '1;
            end
        end
    endfunction

    task automatic check_intan_frame(input config_pkg::Intan_frame_t frame, input int frame_idx);
        logic [15:0] got_sample;
        logic [15:0] want_sample;
        begin
            if (frame.init_read_ts == 64'b0)
                fail($sformatf("frame %0d init timestamp was zero", frame_idx));
            if (frame.done_read_ts == 64'b0)
                fail($sformatf("frame %0d done timestamp was zero", frame_idx));
            if (frame.done_read_ts <= frame.init_read_ts)
                fail($sformatf(
                     "frame %0d timestamps not increasing: init=%0d done=%0d",
                     frame_idx,
                     frame.init_read_ts,
                     frame.done_read_ts
                     ));

            for (int sensor_idx = 0; sensor_idx < NUM_INTAN; sensor_idx = sensor_idx + 1) begin
                if (frame.Intan_data[sensor_idx].sensor_id !== sensor_idx[7:0])
                    fail($sformatf(
                         "frame %0d sensor %0d id mismatch: got 0x%02h",
                         frame_idx,
                         sensor_idx,
                         frame.Intan_data[sensor_idx].sensor_id
                         ));

                for (
                    int channel_idx = 0; channel_idx < INTAN_CHANNELS; channel_idx = channel_idx + 1
                ) begin
                    got_sample = frame.Intan_data[sensor_idx].data[
                        BITS_PER_WORD*channel_idx+:BITS_PER_WORD
                    ];
                    want_sample = expected_sample(sensor_idx, channel_idx);
                    if (got_sample !== want_sample)
                        fail($sformatf(
                             "frame %0d sensor %0d channel %0d mismatch: got 0x%04h expected 0x%04h",
                             frame_idx,
                             sensor_idx,
                             channel_idx,
                             got_sample,
                             want_sample
                             ));
                end
            end
        end
    endtask

    task automatic check_frame_bytes(input int packet_offset, input config_pkg::Intan_frame_t frame,
                                     input string name);
        logic [7:0] want;
        begin
            for (int byte_idx = 0; byte_idx < INTAN_FRAME_BYTES; byte_idx = byte_idx + 1) begin
                want = intan_frame_byte(frame, byte_idx);
                if (packet_bytes[packet_offset+byte_idx] !== want)
                    fail($sformatf(
                         "%s byte %0d mismatch at packet offset %0d: got 0x%02h expected 0x%02h",
                         name,
                         byte_idx,
                         packet_offset + byte_idx,
                         packet_bytes[packet_offset+byte_idx],
                         want
                         ));
            end
        end
    endtask

    task automatic check_icm_bytes(input int packet_offset);
        logic [7:0] want;
        begin
            for (int byte_idx = 0; byte_idx < ICM_FRAME_BYTES; byte_idx = byte_idx + 1) begin
                want = icm_frame_byte(icm_frame, byte_idx);
                if (packet_bytes[packet_offset+byte_idx] !== want)
                    fail($sformatf(
                         "ICM byte %0d mismatch at packet offset %0d: got 0x%02h expected 0x%02h",
                         byte_idx,
                         packet_offset + byte_idx,
                         packet_bytes[packet_offset+byte_idx],
                         want
                         ));
            end
        end
    endtask

    task automatic check_packet();
        int expected_icm_offset;
        int expected_valid_bytes;
        int expected_trailer_offset;
        begin
            expected_icm_offset = 2 * INTAN_FRAME_BYTES;
            expected_valid_bytes = expected_icm_offset + ICM_FRAME_BYTES;
            expected_trailer_offset = PACKET_TRAILER_OFFSET_BYTES;

            if (packet_done_count != 1)
                fail($sformatf("expected one packet_done, got %0d", packet_done_count));
            if (beat_count != PACKET_AXIS_WORDS)
                fail($sformatf("expected %0d AXIS beats, got %0d", PACKET_AXIS_WORDS, beat_count));
            if (byte_count != PACKET_BYTES)
                fail($sformatf("expected %0d AXIS bytes, got %0d", PACKET_BYTES, byte_count));
            if (axis_last_count != 1)
                fail($sformatf("expected one tlast, got %0d", axis_last_count));

            check_frame_bytes(0, reader_snapshots[0], "Intan frame 0");
            check_frame_bytes(INTAN_FRAME_BYTES, reader_snapshots[1], "Intan frame 1");
            check_icm_bytes(expected_icm_offset);

            for (
                int byte_idx = expected_valid_bytes;
                byte_idx < expected_trailer_offset;
                byte_idx = byte_idx + 1
            ) begin
                if (packet_bytes[byte_idx] !== 8'h00)
                    fail($sformatf(
                         "non-zero padding byte at offset %0d: 0x%02h",
                         byte_idx,
                         packet_bytes[byte_idx]
                         ));
            end

            for (int byte_idx = 0; byte_idx < 8; byte_idx = byte_idx + 1) begin
                if (packet_bytes[PACKET_TRAILER_OFFSET_BYTES+byte_idx] !== 8'hff)
                    fail($sformatf(
                         "bad trailer magic byte %0d: 0x%02h",
                         byte_idx,
                         packet_bytes[PACKET_TRAILER_OFFSET_BYTES+byte_idx]
                         ));
            end

            if (be32(PACKET_TRAILER_OFFSET_BYTES + 12) != PACKET_TRAILER_BYTES)
                fail($sformatf("bad trailer_bytes: %0d", be32(PACKET_TRAILER_OFFSET_BYTES + 12)));
            if (be32(PACKET_TRAILER_OFFSET_BYTES + 16) != PACKET_BYTES)
                fail($sformatf("bad packet_bytes: %0d", be32(PACKET_TRAILER_OFFSET_BYTES + 16)));
            if (be32(PACKET_TRAILER_OFFSET_BYTES + 20) != expected_valid_bytes)
                fail($sformatf(
                     "bad valid_data_bytes: %0d expected %0d",
                     be32(
                         PACKET_TRAILER_OFFSET_BYTES + 20
                     ),
                     expected_valid_bytes
                     ));
            if (be32(PACKET_TRAILER_OFFSET_BYTES + 24) != 2)
                fail($sformatf("bad intan_frame_count: %0d", be32(PACKET_TRAILER_OFFSET_BYTES + 24)
                     ));
            if (be32(PACKET_TRAILER_OFFSET_BYTES + 36) != expected_icm_offset)
                fail($sformatf(
                     "bad icm_frame_start_index: %0d expected %0d",
                     be32(
                         PACKET_TRAILER_OFFSET_BYTES + 36
                     ),
                     expected_icm_offset
                     ));
            if (be32(PACKET_TRAILER_OFFSET_BYTES + 40) != PACKET_TRAILER_OFFSET_BYTES)
                fail($sformatf(
                     "bad trailer_start_index: %0d", be32(PACKET_TRAILER_OFFSET_BYTES + 40)));

            if (be32(PACKET_TRAILER_OFFSET_BYTES + 56) != 0)
                fail($sformatf(
                     "bad Intan frame 0 offset: %0d", be32(PACKET_TRAILER_OFFSET_BYTES + 56)));
            if (be32(PACKET_TRAILER_OFFSET_BYTES + 60) != INTAN_FRAME_BYTES)
                fail($sformatf(
                     "bad Intan frame 1 offset: %0d expected %0d",
                     be32(
                         PACKET_TRAILER_OFFSET_BYTES + 60
                     ),
                     INTAN_FRAME_BYTES
                     ));

            for (
                int offset_idx = 2;
                offset_idx < PACKET_TRAILER_INTAN_OFFSET_COUNT;
                offset_idx = offset_idx + 1
            ) begin
                if (be32(PACKET_TRAILER_OFFSET_BYTES + 56 + 4 * offset_idx) != 0)
                    fail($sformatf(
                         "unused Intan offset %0d was non-zero: %0d",
                         offset_idx,
                         be32(
                             PACKET_TRAILER_OFFSET_BYTES + 56 + 4 * offset_idx
                         )
                         ));
            end
        end
    endtask

    initial begin
        init_cmd_list = '0;
        rx_init_list_expect_a = '0;
        rx_init_list_expect_b = '0;
        acq_cmd_list = '0;
        icm_frame = '0;

        set_init_vector(0, 16'hFF00, 16'h0004);
        set_init_vector(1, 16'hFF00, 16'h0004);
        set_init_vector(2, 16'hFF00, 16'h0004);
        set_init_vector(3, 16'hFF00, 16'h0004);
        set_init_vector(4, 16'hFF00, 16'h0004);
        set_init_vector(5, 16'hFF00, 16'h0004);
        set_init_vector(6, 16'hFF00, 16'h0004);
        set_init_vector(7, 16'hFF00, 16'h0004);
        set_init_vector(8, 16'hFF00, 16'h0004);
        set_init_vector(9, 16'h5500, 16'h0000);
        set_init_vector(10, 16'h95FF, 16'hFFFF);
        set_init_vector(11, 16'h94FF, 16'hFFFF);
        set_init_vector(12, 16'h93FF, 16'hFFFF);
        set_init_vector(13, 16'h92FF, 16'hFFFF);
        set_init_vector(14, 16'h91FF, 16'hFFFF);
        set_init_vector(15, 16'h90FF, 16'hFFFF);
        set_init_vector(16, 16'h8FFF, 16'hFFFF);
        set_init_vector(17, 16'h8EFF, 16'hFFFF);
        set_init_vector(18, 16'h8D86, 16'hFF86);
        set_init_vector(19, 16'h8C2C, 16'hFF2C);
        set_init_vector(20, 16'h8B80, 16'hFF80);
        set_init_vector(21, 16'h8A17, 16'hFF17);
        set_init_vector(22, 16'h8980, 16'hFF80);
        set_init_vector(23, 16'h8816, 16'hFF16);
        set_init_vector(24, 16'h8700, 16'hFF00);
        set_init_vector(25, 16'h8680, 16'hFF80);
        set_init_vector(26, 16'h8540, 16'hFF40);
        set_init_vector(27, 16'h8480, 16'hFF80);
        set_init_vector(28, 16'h8300, 16'hFF00);
        set_init_vector(29, 16'h8204, 16'hFF04);
        set_init_vector(30, 16'h8142, 16'hFF42);
        set_init_vector(31, 16'h80DE, 16'hFFDE);
        set_init_vector(32, 16'hFF00, 16'h0004);
        set_init_vector(33, 16'hFF00, 16'h0004);

        for (int channel_idx = 0; channel_idx < NUM_CHAN_PER_ADC; channel_idx = channel_idx + 1)
        acq_cmd_list[channel_idx] = {2'b0, 6'(channel_idx), 8'b0};
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            // read_in_flight <= 1'b0;
            init_done_count <= 0;
            read_completion_count <= 0;
            forwarded_frame_count <= 0;
        end else begin
            if (reader_error !== 1'b0) fail("intan_reader error asserted");

            // if (start_read) read_in_flight <= 1'b1;

            if (reader_intan_frame_done) forwarded_frame_count <= forwarded_frame_count + 1;

            if (reader_done_pulse) begin
                if (read_mode) begin
                    if (read_completion_count >= 2)
                        fail("more than two Intan read completions observed");

                    reader_snapshots[read_completion_count] <= reader_intan_frame;
                    read_completion_count <= read_completion_count + 1;
                    // read_in_flight <= 1'b0;
                end else begin
                    init_done_count <= init_done_count + 1;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            byte_count <= 0;
            beat_count <= 0;
            packet_done_count <= 0;
            axis_last_count <= 0;
        end else begin
            if (writer_packet_done) packet_done_count <= packet_done_count + 1;

            if (fifo_underflow) fail("packet FIFO underflowed");
            if (fifo_overflow) fail("packet FIFO overflowed");

            if (axis_valid && axis_ready) begin
                if (beat_count >= PACKET_AXIS_WORDS)
                    fail($sformatf("extra AXI beat %0d", beat_count));

                if (axis_keep !== expected_keep(beat_count))
                    fail($sformatf(
                         "bad tkeep on beat %0d: got 0x%032h expected 0x%032h",
                         beat_count,
                         axis_keep,
                         expected_keep(
                             beat_count
                         )
                         ));
                if (axis_last !== (beat_count == PACKET_AXIS_WORDS - 1))
                    fail($sformatf("bad tlast on beat %0d", beat_count));

                for (int lane = 0; lane < AXIS_BYTES; lane = lane + 1) begin
                    if (axis_keep[lane]) begin
                        if (byte_count + lane < PACKET_BYTES)
                            packet_bytes[byte_count+lane] <= axis_data[8*lane+:8];
                    end
                end

                if (axis_last) axis_last_count <= axis_last_count + 1;

                byte_count <= byte_count + AXIS_BYTES;
                beat_count <= beat_count + 1;
            end
        end
    end

    initial begin : test_reader_to_packet_path
        reset_dut();

        if (reader_error !== 1'b0) fail("error was not clear after reset");

        pulse_start_init();
        wait_for_init_count(1, 20000);
        if (reader_error !== 1'b0) fail("initialization completed with error");
        if (forwarded_frame_count != 0)
            fail($sformatf("initialization forwarded %0d Intan frames", forwarded_frame_count));

        pulse_start_read();
        wait_for_read_count(1, 20000);
        pulse_start_read();
        wait_for_read_count(2, 20000);

        repeat (4) @(posedge clk);
        if (forwarded_frame_count != 2)
            fail($sformatf("expected 2 forwarded Intan frames, got %0d", forwarded_frame_count));
        if (init_done_count != 1)
            fail($sformatf("expected one initialization done pulse, got %0d", init_done_count));

        check_intan_frame(reader_snapshots[0], 0);
        check_intan_frame(reader_snapshots[1], 1);
        if (reader_snapshots[0].init_read_ts == reader_snapshots[1].init_read_ts ||
            reader_snapshots[0].done_read_ts == reader_snapshots[1].done_read_ts)
            fail("the two Intan frame timestamps were not distinct");

        repeat (3000) @(posedge clk);
        pulse_icm_done();

        wait_for_beat_count(PACKET_AXIS_WORDS, 50000);
        repeat (4) @(posedge clk);

        check_packet();

        $display("PASS integrate_intan_packet_path_layout_tb");
        $finish;
    end

    initial begin : timeout
        #5ms;
        $fatal(1, "integrate_intan_packet_path_layout_tb timed out");
    end
endmodule
