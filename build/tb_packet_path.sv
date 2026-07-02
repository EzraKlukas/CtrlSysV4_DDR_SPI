`timescale 1ns/1ps

import config_pkg::*;

module tb_packet_path;
    logic clk = 1'b0;
    logic rst = 1'b1;

    ICM_frame_t icm_frame;
    Intan_frame_t intan_frame;

    logic icm_done;
    logic intan_done;
    logic packet_ready;
    logic writer_ready;
    logic writer_word_valid;
    logic writer_word_ready;
    logic [AXIS_DATA_WIDTH-1:0] writer_word_data;
    logic writer_packet_done;

    logic fifo_rd_en;
    logic [AXIS_DATA_WIDTH-1:0] fifo_rd_data;
    logic fifo_empty;
    logic fifo_full;
    logic fifo_packet_space;
    logic fifo_overflow;
    logic fifo_underflow;

    logic axis_valid;
    logic axis_ready = 1'b1;
    logic [AXIS_DATA_WIDTH-1:0] axis_data;
    logic [AXIS_DATA_WIDTH/8-1:0] axis_keep;
    logic axis_last;

    int beat_count;
    int packet_done_count;

    always #5 clk = ~clk;

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
        .DATA_WIDTH(AXIS_DATA_WIDTH),
        .DEPTH_WORDS(PACKET_BUFFER_WORDS),
        .PACKET_WORDS(PACKET_AXIS_WORDS)
    ) u_buffer (
        .clk(clk),
        .rst(rst),
        .wr_en(writer_word_valid && !fifo_full),
        .wr_data(writer_word_data),
        .rd_en(fifo_rd_en),
        .rd_data(fifo_rd_data),
        .empty(fifo_empty),
        .full(fifo_full),
        .packet_space(fifo_packet_space),
        .overflow(fifo_overflow),
        .underflow(fifo_underflow)
    );

    packet_to_axis u_axis (
        .clk(clk),
        .rst(rst),
        .fifo_rd_en(fifo_rd_en),
        .fifo_rd_data(fifo_rd_data),
        .fifo_empty(fifo_empty),
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
            intan_frame.init_read_ts = 64'h1000 + frame_id;
            intan_frame.done_read_ts = 64'h2000 + frame_id;
            for (sensor = 0; sensor < NUM_INTAN; sensor = sensor + 1) begin
                intan_frame.Intan_data[sensor].sensor_id = sensor[7:0];
                for (byte_idx = 0; byte_idx < INTAN_DATA_BYTES; byte_idx = byte_idx + 1) begin
                    intan_frame.Intan_data[sensor].data[8*byte_idx +: 8] =
                        byte'(frame_id + sensor + byte_idx);
                end
            end
        end
    endtask

    task automatic fill_icm;
        int sensor;
        int byte_idx;
        begin
            icm_frame.init_read_ts = 64'h3000;
            icm_frame.done_read_ts = 64'h4000;
            for (sensor = 0; sensor < NUM_ICM; sensor = sensor + 1) begin
                icm_frame.ICM_data[sensor].sensor_id = sensor[7:0];
                for (byte_idx = 0; byte_idx < ICM_DATA_BYTES; byte_idx = byte_idx + 1) begin
                    icm_frame.ICM_data[sensor].data[8*byte_idx +: 8] =
                        byte'(8'h80 + sensor + byte_idx);
                end
            end
        end
    endtask

    task automatic pulse_intan(input int frame_id);
        begin
            fill_intan(frame_id);
            @(posedge clk);
            intan_done <= 1'b1;
            @(posedge clk);
            intan_done <= 1'b0;
        end
    endtask

    task automatic pulse_icm;
        begin
            fill_icm();
            @(posedge clk);
            icm_done <= 1'b1;
            @(posedge clk);
            icm_done <= 1'b0;
        end
    endtask

    always_ff @(posedge clk) begin
        if (rst) begin
            beat_count <= 0;
            packet_done_count <= 0;
        end else begin
            if (writer_packet_done)
                packet_done_count <= packet_done_count + 1;

            if (axis_valid && axis_ready) begin
                if (beat_count == 0)
                    $display("beat0_low64=%016h", axis_data[63:0]);
                if (beat_count == 190)
                    $display("beat190_low64=%016h", axis_data[63:0]);
                if (axis_last)
                    $display("tlast beat=%0d packet_done_count=%0d", beat_count, packet_done_count);
                beat_count <= beat_count + 1;
            end
        end
    end

    initial begin
        icm_done = 1'b0;
        intan_done = 1'b0;
        icm_frame = '0;
        intan_frame = '0;

        repeat (10) @(posedge clk);
        rst <= 1'b0;
        repeat (5) @(posedge clk);

        pulse_intan(1);
        repeat (600) @(posedge clk);
        pulse_intan(2);
        repeat (600) @(posedge clk);
        pulse_icm();

        wait (axis_last && axis_valid && axis_ready);
        repeat (10) @(posedge clk);

        if (beat_count != PACKET_AXIS_WORDS)
            $fatal(1, "expected %0d beats, got %0d", PACKET_AXIS_WORDS, beat_count);
        if (packet_done_count != 1)
            $fatal(1, "expected one writer packet_done, got %0d", packet_done_count);

        $display("PASS packet path");
        $finish;
    end
endmodule
