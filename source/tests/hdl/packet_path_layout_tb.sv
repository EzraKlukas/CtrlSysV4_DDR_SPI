`timescale 1ns / 1ps

import config_pkg::*;

module packet_path_layout_tb;
    localparam int INTAN_SENSOR_DATA_BYTES = INTAN_BITS_PER_WORD * INTAN_CHANNELS / 8;

    logic clk = 1'b0;
    logic rst = 1'b1;

    ICM_frame_t icm_frame;
    Intan_frame_t intan_frame;

    logic icm_done = 1'b0;
    logic intan_done = 1'b0;
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
    int ready_counter = 0;
    logic stalled = 1'b0;
    logic [AXIS_DATA_WIDTH-1:0] stalled_data;
    logic [AXIS_BYTES-1:0] stalled_keep;
    logic stalled_last;

    always #5 clk <= ~clk;

    assign packet_ready = fifo_packet_space;
    assign writer_word_ready = !fifo_full;

    packet_writer u_writer (
        .clk(clk),
        .rst(rst),
        .ICM_frame_done(icm_done),
        .Intan_frame_done(intan_done),
        .ICM_frame_in(icm_frame),
        .Intan_frame_in(intan_frame),
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

    task automatic fill_intan(input int frame_id);
        int sensor;
        int byte_idx;
        begin
            intan_frame.init_read_ts = 64'h1000_0000_0000_0000 + frame_id;
            intan_frame.done_read_ts = 64'h2000_0000_0000_0000 + frame_id;
            for (sensor = 0; sensor < NUM_INTAN; sensor = sensor + 1) begin
                intan_frame.Intan_data[sensor].sensor_id = sensor[7:0];
                for (byte_idx = 0; byte_idx < INTAN_SENSOR_DATA_BYTES; byte_idx = byte_idx + 1)
                intan_frame.Intan_data[sensor].data[8*byte_idx +: 8] =
                        byte'(8'h40 + frame_id + sensor + byte_idx);
            end
        end
    endtask

    task automatic fill_icm;
        int sensor;
        int byte_idx;
        begin
            icm_frame.init_read_ts = 64'h3000_0000_0000_0000;
            icm_frame.done_read_ts = 64'h4000_0000_0000_0000;
            for (sensor = 0; sensor < NUM_ICM; sensor = sensor + 1) begin
                icm_frame.ICM_data[sensor].sensor_id = sensor[7:0];
                for (byte_idx = 0; byte_idx < ICM_DATA_BYTES; byte_idx = byte_idx + 1)
                icm_frame.ICM_data[sensor].data[8*byte_idx+:8] = byte'(8'h80 + sensor + byte_idx);
            end
        end
    endtask

    task automatic pulse_intan(input int frame_id);
        begin
            fill_intan(frame_id);
            @(negedge clk);
            intan_done = 1'b1;
            @(posedge clk);
            #1;
            if (!u_writer.accept_intan_frame)
                $fatal(1, "Intan admission was not registered");
            if (u_writer.intan_chunks_remaining != 0)
                $fatal(1, "Intan shift register loaded before registered admission");
            @(negedge clk);
            intan_done = 1'b0;
            @(posedge clk);
            #1;
            if (u_writer.accept_intan_frame)
                $fatal(1, "Intan admission event lasted more than one cycle");
            if (u_writer.intan_chunks_remaining != u_writer.INTAN_FRAME_CHUNKS)
                $fatal(1, "Intan frame was not captured on the delayed cycle");
            if (u_writer.intan_shift[7:0] !== intan_frame[INTAN_FRAME_BITS-1-:8])
                $fatal(1, "Intan frame changed or was captured with the wrong byte order");
        end
    endtask

    task automatic pulse_icm;
        begin
            fill_icm();
            @(posedge clk);
            icm_done = 1'b1;
            @(posedge clk);
            icm_done = 1'b0;
        end
    endtask

    task automatic pulse_intan_and_icm(input int frame_id);
        begin
            fill_intan(frame_id);
            fill_icm();
            @(negedge clk);
            intan_done = 1'b1;
            icm_done   = 1'b1;
            @(posedge clk);
            #1;
            if (!u_writer.accept_intan_frame)
                $fatal(1, "simultaneous Intan/ICM admission was not registered");
            if (!u_writer.pending_icm_valid || !u_writer.packet_closing)
                $fatal(1, "simultaneous ICM completion was not retained for packet close");
            @(negedge clk);
            intan_done = 1'b0;
            icm_done   = 1'b0;
            @(posedge clk);
            #1;
            if (u_writer.intan_chunks_remaining != u_writer.INTAN_FRAME_CHUNKS)
                $fatal(1, "simultaneous Intan frame was not captured after admission");
        end
    endtask

    function automatic int unsigned be32(input int offset);
        be32 = {
            packet_bytes[offset],
            packet_bytes[offset+1],
            packet_bytes[offset+2],
            packet_bytes[offset+3]
        };
    endfunction

    always_ff @(posedge clk) begin
        if (rst) begin
            byte_count <= 0;
            beat_count <= 0;
            packet_done_count <= 0;
            axis_last_count <= 0;
            ready_counter <= 0;
            axis_ready <= 1'b1;
            stalled <= 1'b0;
        end else begin
            ready_counter <= ready_counter + 1;
            axis_ready <= ready_counter[3:0] != 4'h7;

            if (stalled) begin
                if (!axis_valid || axis_data !== stalled_data ||
                    axis_keep !== stalled_keep || axis_last !== stalled_last)
                    $fatal(1, "AXI output changed while backpressured");
                if (axis_ready) stalled <= 1'b0;
            end else if (axis_valid && !axis_ready) begin
                stalled <= 1'b1;
                stalled_data <= axis_data;
                stalled_keep <= axis_keep;
                stalled_last <= axis_last;
            end

            if (writer_packet_done) packet_done_count <= packet_done_count + 1;

            if (axis_valid && axis_ready) begin
                if (axis_keep !== '1)
                    $fatal(1, "beat %0d did not assert all tkeep bits", beat_count);
                if (axis_last !== (beat_count == PACKET_AXIS_WORDS - 1))
                    $fatal(1, "tlast mismatch on beat %0d", beat_count);
                for (int lane = 0; lane < AXIS_BYTES; lane = lane + 1) begin
                    if (byte_count + lane < PACKET_BYTES)
                        packet_bytes[byte_count+lane] <= axis_data[8*lane+:8];
                end
                if (axis_last) axis_last_count <= axis_last_count + 1;
                byte_count <= byte_count + AXIS_BYTES;
                beat_count <= beat_count + 1;
            end
        end
    end

    initial begin
        if (INTAN_SENSOR_DATA_BYTES != 128) $fatal(1, "production Intan data must be 128 bytes");
        if ($bits(Intan_measurement_t'(0)) / 8 != 129)
            $fatal(1, "production Intan measurement must be 129 bytes");
        if (INTAN_FRAME_BYTES != 1048 || ICM_FRAME_BYTES != 100)
            $fatal(1, "production frame sizes are incorrect");
        if (PACKET_BYTES != 24576 || PACKET_TRAILER_OFFSET_BYTES != 24320)
            $fatal(1, "production packet/trailer layout is incorrect");
        if (MAX_INTAN_FRAMES_PER_PACKET != 23)
            $fatal(1, "production packet capacity must be 23 Intan frames");
        if (AXIS_DATA_WIDTH != 64 || AXIS_BYTES != 8 || PACKET_AXIS_WORDS != 3072)
            $fatal(1, "production AXI packet geometry is incorrect");

        repeat (10) @(posedge clk);
        rst <= 1'b0;
        repeat (5) @(posedge clk);

        pulse_intan(1);
        wait (u_writer.intan_chunks_remaining == 0 && !u_writer.accept_intan_frame);
        repeat (2) @(posedge clk);
        pulse_intan_and_icm(2);

        wait (axis_valid && axis_ready && axis_last);
        repeat (4) @(posedge clk);

        if (packet_done_count != 1)
            $fatal(1, "expected one packet_done, got %0d", packet_done_count);
        if (beat_count != PACKET_AXIS_WORDS)
            $fatal(1, "expected %0d AXIS beats, got %0d", PACKET_AXIS_WORDS, beat_count);
        if (byte_count != PACKET_BYTES)
            $fatal(1, "expected %0d bytes, got %0d", PACKET_BYTES, byte_count);
        if (axis_last_count != 1) $fatal(1, "expected one tlast, got %0d", axis_last_count);
        if (fifo_underflow) $fatal(1, "packet FIFO underflowed");
        if (fifo_overflow) $fatal(1, "packet FIFO overflowed");

        for (int i = 0; i < 8; i = i + 1) begin
            if (packet_bytes[PACKET_TRAILER_OFFSET_BYTES+i] !== 8'hff)
                $fatal(
                    1,
                    "bad trailer magic byte %0d: 0x%02h",
                    i,
                    packet_bytes[PACKET_TRAILER_OFFSET_BYTES+i]
                );
        end
        if (be32(PACKET_TRAILER_OFFSET_BYTES + 12) != PACKET_TRAILER_BYTES)
            $fatal(1, "bad trailer_bytes: %0d", be32(PACKET_TRAILER_OFFSET_BYTES + 12));
        if (be32(PACKET_TRAILER_OFFSET_BYTES + 16) != PACKET_BYTES)
            $fatal(1, "bad packet_bytes: %0d", be32(PACKET_TRAILER_OFFSET_BYTES + 16));
        if (be32(PACKET_TRAILER_OFFSET_BYTES + 20) != 2196)
            $fatal(1, "bad valid_data_bytes: %0d", be32(PACKET_TRAILER_OFFSET_BYTES + 20));
        if (be32(PACKET_TRAILER_OFFSET_BYTES + 24) != 2)
            $fatal(1, "bad Intan frame count: %0d", be32(PACKET_TRAILER_OFFSET_BYTES + 24));
        if (be32(PACKET_TRAILER_OFFSET_BYTES + 28) != MAX_INTAN_FRAMES_PER_PACKET)
            $fatal(1, "bad maximum Intan frame count");
        if (be32(PACKET_TRAILER_OFFSET_BYTES + 32) != 1) $fatal(1, "bad ICM frame count");
        if (be32(PACKET_TRAILER_OFFSET_BYTES + 36) != 2096)
            $fatal(1, "bad ICM frame start: %0d", be32(PACKET_TRAILER_OFFSET_BYTES + 36));
        if (be32(PACKET_TRAILER_OFFSET_BYTES + 40) != PACKET_TRAILER_OFFSET_BYTES)
            $fatal(1, "bad trailer_start_index: %0d", be32(PACKET_TRAILER_OFFSET_BYTES + 40));
        if (be32(
                PACKET_TRAILER_OFFSET_BYTES + 44
            ) != 0 || be32(
                PACKET_TRAILER_OFFSET_BYTES + 48
            ) != 0 || be32(
                PACKET_TRAILER_OFFSET_BYTES + 52
            ) != 0)
            $fatal(1, "packet unexpectedly reported dropped frames");
        if (be32(
                PACKET_TRAILER_OFFSET_BYTES + 56
            ) != 0 || be32(
                PACKET_TRAILER_OFFSET_BYTES + 60
            ) != INTAN_FRAME_BYTES)
            $fatal(1, "bad Intan frame offsets");

        $display("PASS packet_path_layout_tb");
        $finish;
    end

    initial begin : timeout
        #1ms;
        $fatal(1, "packet_path_layout_tb timed out");
    end
endmodule
