`timescale 1ns/1ps

module packet_buffer_space_tb;
    localparam int DATA_WIDTH = 32;
    localparam int DEPTH_WORDS = 8;
    localparam int PACKET_WORDS = 4;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic wr_en = 1'b0;
    logic [DATA_WIDTH-1:0] wr_data = '0;
    logic rd_en = 1'b0;
    logic [DATA_WIDTH-1:0] rd_data;
    logic empty;
    logic full;
    logic packet_space;
    logic packet_available;
    logic overflow;
    logic underflow;

    always #5 clk = ~clk;

    packet_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH_WORDS(DEPTH_WORDS),
        .PACKET_WORDS(PACKET_WORDS)
    ) dut (
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

    task automatic step();
        @(posedge clk);
        #1;
    endtask

    task automatic write_word(input logic [DATA_WIDTH-1:0] value);
        begin
            @(negedge clk);
            wr_data = value;
            wr_en = 1'b1;
            step();
            @(negedge clk);
            wr_en = 1'b0;
        end
    endtask

    initial begin
        repeat (3) step();
        @(negedge clk);
        rst = 1'b0;
        step();
        if (!packet_space) $fatal(1, "empty FIFO did not advertise packet space");

        for (int index = 0; index < PACKET_WORDS; index++)
            write_word(32'hA500_0000 | index);
        if (!packet_space)
            $fatal(1, "packet_space deasserted at the exact free-packet threshold");

        write_word(32'hA500_0004);
        if (packet_space)
            $fatal(1, "packet_space did not deassert below the free-packet threshold");

        @(negedge clk);
        rd_en = 1'b1;
        step();
        @(negedge clk);
        rd_en = 1'b0;
        if (!packet_space)
            $fatal(1, "packet_space did not reassert on the threshold-restoring read");
        if (overflow || underflow) $fatal(1, "FIFO status fault during threshold test");

        $display("PASS packet_buffer_space_tb");
        $finish;
    end
endmodule
