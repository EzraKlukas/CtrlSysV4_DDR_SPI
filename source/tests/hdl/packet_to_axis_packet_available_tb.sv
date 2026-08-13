`timescale 1ns/1ps

module packet_to_axis_packet_available_tb;
    localparam int DATA_WIDTH = 32;
    localparam int DEPTH_WORDS = 8;
    localparam int PACKET_WORDS = 4;
    localparam int PACKET_LAST_BYTES = DATA_WIDTH / 8;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic wr_en = 1'b0;
    logic [DATA_WIDTH-1:0] wr_data = '0;
    logic rd_en;
    logic [DATA_WIDTH-1:0] rd_data;
    logic empty;
    logic full;
    logic packet_space;
    logic packet_available;
    logic overflow;
    logic underflow;
    logic tvalid;
    logic tready = 1'b1;
    logic [DATA_WIDTH-1:0] tdata;
    logic [DATA_WIDTH/8-1:0] tkeep;
    logic tlast;
    logic [DATA_WIDTH-1:0] stalled_data;
    logic [DATA_WIDTH/8-1:0] stalled_keep;
    logic stalled_last;
    int index;
    int seen;

    always #5 clk = ~clk;

    packet_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH_WORDS(DEPTH_WORDS),
        .PACKET_WORDS(PACKET_WORDS)
    ) u_buffer (
        .clk(clk),
        .rst(rst),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .empty(empty),
        .full(full),
        .packet_space(packet_space),
        .packet_available(packet_available),
        .overflow(overflow),
        .underflow(underflow)
    );

    packet_to_axis #(
        .DATA_WIDTH(DATA_WIDTH),
        .PACKET_WORDS(PACKET_WORDS),
        .PACKET_LAST_BYTES(PACKET_LAST_BYTES)
    ) u_axis (
        .clk(clk),
        .rst(rst),
        .fifo_rd_en(rd_en),
        .fifo_rd_data(rd_data),
        .fifo_packet_available(packet_available),
        .m_axis_tvalid(tvalid),
        .m_axis_tready(tready),
        .m_axis_tdata(tdata),
        .m_axis_tkeep(tkeep),
        .m_axis_tlast(tlast)
    );

    task automatic write_word(input int value);
        begin
            wr_data <= value[DATA_WIDTH-1:0];
            wr_en <= 1'b1;
            @(posedge clk);
            wr_en <= 1'b0;
            wr_data <= '0;
            @(posedge clk);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst <= 1'b0;
        repeat (2) @(posedge clk);

        for (index = 0; index < PACKET_WORDS - 1; index = index + 1)
            write_word(32'hA500_0000 | index[31:0]);

        repeat (10) begin
            @(posedge clk);
            if (tvalid || rd_en)
                $fatal(1, "stream started before a complete packet was available");
        end

        tready = 1'b0;
        write_word(32'hA500_0000 | (PACKET_WORDS - 1));

        wait (tvalid);
        @(negedge clk);
        stalled_data = tdata;
        stalled_keep = tkeep;
        stalled_last = tlast;
        repeat (3) begin
            @(negedge clk);
            if (!tvalid || tdata !== stalled_data || tkeep !== stalled_keep ||
                tlast !== stalled_last)
                $fatal(1, "AXI output changed while backpressured");
        end
        tready = 1'b1;

        while (seen < PACKET_WORDS) begin
            @(posedge clk);
            if (tvalid && tready) begin
                if (tdata !== (32'hA500_0000 | seen[31:0]))
                    $fatal(1, "beat %0d data mismatch: 0x%08h", seen, tdata);
                if (tkeep !== '1)
                    $fatal(1, "beat %0d did not assert all tkeep bits", seen);
                if (tlast !== (seen == PACKET_WORDS - 1))
                    $fatal(1, "beat %0d tlast mismatch: %0b", seen, tlast);
                seen = seen + 1;
            end
        end

        for (index = 0; index < PACKET_WORDS; index = index + 1)
            write_word(32'hA600_0000 | index[31:0]);

        while (seen < 2 * PACKET_WORDS) begin
            @(posedge clk);
            if (tvalid && tready) begin
                if (tdata !== (32'hA600_0000 | (seen - PACKET_WORDS)))
                    $fatal(1, "second packet beat %0d data mismatch: 0x%08h",
                           seen - PACKET_WORDS, tdata);
                if (tkeep !== '1)
                    $fatal(1, "second packet beat %0d had partial tkeep",
                           seen - PACKET_WORDS);
                if (tlast !== (seen == 2 * PACKET_WORDS - 1))
                    $fatal(1, "second packet beat %0d tlast mismatch",
                           seen - PACKET_WORDS);
                seen = seen + 1;
            end
        end

        repeat (4) @(posedge clk);
        if (underflow)
            $fatal(1, "packet reader underflowed");
        if (overflow)
            $fatal(1, "packet buffer overflowed");

        $display("PASS packet_to_axis_packet_available_tb");
        $finish;
    end
endmodule
