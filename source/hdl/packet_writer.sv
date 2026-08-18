/*
Name: Gordon Zhao
File: packet_writer.sv
Description: Packs fixed-size DMA packets with a metadata trailer.
*/

import config_pkg::*;

module packet_writer #(
    parameter int DATA_WIDTH = config_pkg::AXIS_DATA_WIDTH,
    parameter int PACKET_BYTES = config_pkg::PACKET_BYTES,
    parameter int PACKET_WORDS = config_pkg::PACKET_AXIS_WORDS,
    parameter int INTAN_FRAME_BITS = config_pkg::INTAN_FRAME_BITS,
    parameter int ICM_FRAME_BITS = config_pkg::ICM_FRAME_BITS,
    parameter int PACKET_TRAILER_BITS = config_pkg::PACKET_TRAILER_BITS,
    parameter int INTAN_FIFO_DEPTH = config_pkg::MAX_INTAN_FRAMES_PER_PACKET,
    parameter int ICM_FIFO_DEPTH = config_pkg::BUFFER_SIZE
)(
    input  logic clk,
    input  logic rst,

    input  logic ICM_frame_done,
    input  logic Intan_frame_done,
    input  config_pkg::ICM_frame_t ICM_frame_in,
    input  config_pkg::Intan_frame_t Intan_frame_in,

    input  logic packet_ready,
    output logic ready,

    output logic word_valid,
    input  logic word_ready,
    output logic [DATA_WIDTH-1:0] word_data,
    output logic packet_done
);

localparam int CHUNK_BITS = 32;
localparam int AXIS_BYTES = DATA_WIDTH / 8;
localparam int CHUNKS_PER_WORD = DATA_WIDTH / CHUNK_BITS;
localparam int INTAN_FRAME_BYTES = INTAN_FRAME_BITS / 8;
localparam int ICM_FRAME_BYTES = ICM_FRAME_BITS / 8;
localparam int INTAN_FRAME_CHUNKS = INTAN_FRAME_BITS / CHUNK_BITS;
localparam int ICM_FRAME_CHUNKS = ICM_FRAME_BITS / CHUNK_BITS;
localparam int PACKET_TRAILER_BYTES = PACKET_TRAILER_BITS / 8;
localparam int PACKET_TRAILER_OFFSET_BYTES = PACKET_BYTES - PACKET_TRAILER_BYTES;
localparam int PACKET_DATA_WORDS = PACKET_TRAILER_OFFSET_BYTES / AXIS_BYTES;
localparam int PACKET_TRAILER_WORDS = PACKET_TRAILER_BITS / DATA_WIDTH;
localparam int MAX_INTAN_FRAMES = config_pkg::MAX_INTAN_FRAMES_PER_PACKET;

localparam int CHUNK_COUNT_WIDTH =
    (CHUNKS_PER_WORD > 1) ? $clog2(CHUNKS_PER_WORD) : 1;
localparam int INTAN_CHUNK_COUNT_WIDTH =
    (INTAN_FRAME_CHUNKS > 1) ? $clog2(INTAN_FRAME_CHUNKS + 1) : 1;
localparam int ICM_CHUNK_COUNT_WIDTH =
    (ICM_FRAME_CHUNKS > 1) ? $clog2(ICM_FRAME_CHUNKS + 1) : 1;
localparam int INTAN_COUNT_WIDTH =
    (MAX_INTAN_FRAMES > 1) ? $clog2(MAX_INTAN_FRAMES + 1) : 1;
localparam int PACKET_WORD_INDEX_WIDTH =
    (PACKET_WORDS > 1) ? $clog2(PACKET_WORDS + 1) : 1;
localparam int TRAILER_WORD_COUNT_WIDTH =
    (PACKET_TRAILER_WORDS > 1) ? $clog2(PACKET_TRAILER_WORDS + 1) : 1;

typedef enum logic [2:0] {
    WAIT_INPUT,
    STREAM_INTAN,
    STREAM_ICM,
    PAD_PACKET,
    STREAM_TRAILER,
    WAIT_LAST_ACCEPT
} state_t;

state_t state;

logic packet_active;
logic packet_closing;
logic pending_intan_valid;
logic pending_icm_valid;
logic accept_intan_frame;

logic [INTAN_FRAME_BITS-1:0] intan_shift;
logic [INTAN_FRAME_BITS-1:0] pending_intan_frame;
logic [ICM_FRAME_BITS-1:0] icm_shift;
logic [ICM_FRAME_BITS-1:0] pending_icm_frame;
logic [PACKET_TRAILER_BITS-1:0] trailer_shift;
logic [DATA_WIDTH-1:0] word_assembly;

logic [INTAN_CHUNK_COUNT_WIDTH-1:0] intan_chunks_remaining;
logic [ICM_CHUNK_COUNT_WIDTH-1:0] icm_chunks_remaining;
logic [CHUNK_COUNT_WIDTH-1:0] chunk_count;
logic [INTAN_COUNT_WIDTH-1:0] packet_intan_frames;
logic [PACKET_WORD_INDEX_WIDTH-1:0] packet_word_index;
logic [TRAILER_WORD_COUNT_WIDTH-1:0] trailer_words_remaining;

logic [31:0] packet_counter;
logic [31:0] dropped_intan_frames;
logic [31:0] dropped_icm_frames;
logic word_last;

wire output_slot_available = !word_valid || word_ready;
wire finish_packet = word_valid && word_ready && word_last;

initial begin
    assert(DATA_WIDTH >= CHUNK_BITS && (DATA_WIDTH % CHUNK_BITS) == 0);
    assert((INTAN_FRAME_BITS % CHUNK_BITS) == 0);
    assert((ICM_FRAME_BITS % CHUNK_BITS) == 0);
    assert((PACKET_TRAILER_BITS % DATA_WIDTH) == 0);
    assert((PACKET_BYTES % AXIS_BYTES) == 0);
    assert((PACKET_TRAILER_OFFSET_BYTES % AXIS_BYTES) == 0);
    assert(PACKET_WORDS == PACKET_BYTES / AXIS_BYTES);
    assert(PACKET_DATA_WORDS == PACKET_TRAILER_OFFSET_BYTES / AXIS_BYTES);
    assert(PACKET_DATA_WORDS + PACKET_TRAILER_WORDS == PACKET_WORDS);
    assert(PACKET_TRAILER_BYTES == config_pkg::PACKET_TRAILER_BYTES);
    assert(MAX_INTAN_FRAMES * INTAN_FRAME_BYTES + ICM_FRAME_BYTES <=
           PACKET_TRAILER_OFFSET_BYTES);
    assert(INTAN_FIFO_DEPTH >= 1);
    assert(ICM_FIFO_DEPTH >= 1);
    assert($bits(config_pkg::packet_trailer_t'(0)) == PACKET_TRAILER_BITS);
end

function automatic logic [INTAN_FRAME_BITS-1:0] intan_to_stream_order(
    input config_pkg::Intan_frame_t frame
);
    logic [INTAN_FRAME_BITS-1:0] result;
begin
    result = '0;
    for (int byte_index = 0; byte_index < INTAN_FRAME_BYTES; byte_index++)
        result[8 * byte_index +: 8] =
            frame[INTAN_FRAME_BITS - 1 - 8 * byte_index -: 8];
    intan_to_stream_order = result;
end
endfunction

function automatic logic [ICM_FRAME_BITS-1:0] icm_to_stream_order(
    input config_pkg::ICM_frame_t frame
);
    logic [ICM_FRAME_BITS-1:0] result;
begin
    result = '0;
    for (int byte_index = 0; byte_index < ICM_FRAME_BYTES; byte_index++)
        result[8 * byte_index +: 8] =
            frame[ICM_FRAME_BITS - 1 - 8 * byte_index -: 8];
    icm_to_stream_order = result;
end
endfunction

function automatic logic [31:0] intan_bytes_for_frames(
    input logic [INTAN_COUNT_WIDTH-1:0] frame_count
);
    logic [31:0] result;
begin
    result = 32'b0;
    for (int bit_index = 0; bit_index < INTAN_COUNT_WIDTH; bit_index++) begin
        if (frame_count[bit_index])
            result = result + (INTAN_FRAME_BYTES << bit_index);
    end
    intan_bytes_for_frames = result;
end
endfunction

function automatic logic [PACKET_TRAILER_BITS-1:0] build_trailer_stream(
    input logic [31:0] packet_num,
    input logic [INTAN_COUNT_WIDTH-1:0] intan_count,
    input logic [31:0] dropped_intan,
    input logic [31:0] dropped_icm
);
    config_pkg::packet_trailer_t trailer;
    logic [PACKET_TRAILER_BITS-1:0] packed_trailer;
    logic [PACKET_TRAILER_BITS-1:0] result;
    logic [31:0] intan_bytes;
    logic [31:0] frame_offset;
begin
    trailer = '0;
    result = '0;
    intan_bytes = intan_bytes_for_frames(intan_count);

    trailer.magic_ones = 64'hffff_ffff_ffff_ffff;
    trailer.packet_num = packet_num;
    trailer.trailer_bytes = PACKET_TRAILER_BYTES;
    trailer.packet_bytes = PACKET_BYTES;
    trailer.valid_data_bytes = intan_bytes + ICM_FRAME_BYTES;
    trailer.intan_frame_count = 32'(intan_count);
    trailer.max_intan_frame_count = MAX_INTAN_FRAMES;
    trailer.icm_frame_count = 32'd1;
    trailer.icm_frame_start_index = intan_bytes;
    trailer.trailer_start_index = PACKET_TRAILER_OFFSET_BYTES;
    trailer.flags = {
        29'b0,
        intan_count == INTAN_COUNT_WIDTH'(MAX_INTAN_FRAMES),
        dropped_icm != 0,
        dropped_intan != 0
    };
    trailer.dropped_intan_frames = dropped_intan;
    trailer.dropped_icm_frames = dropped_icm;

    frame_offset = 32'b0;
    for (int frame_index = 0;
         frame_index < config_pkg::PACKET_TRAILER_INTAN_OFFSET_COUNT;
         frame_index++) begin
        if (frame_index < intan_count)
            trailer.intan_frame_start_indices[frame_index] = frame_offset;
        frame_offset = frame_offset + INTAN_FRAME_BYTES;
    end

    packed_trailer = trailer;
    for (int byte_index = 0; byte_index < PACKET_TRAILER_BYTES; byte_index++)
        result[8 * byte_index +: 8] =
            packed_trailer[PACKET_TRAILER_BITS - 1 - 8 * byte_index -: 8];

    build_trailer_stream = result;
end
endfunction

assign ready =
    !rst && !accept_intan_frame && !pending_intan_valid && !packet_closing &&
    packet_intan_frames < INTAN_COUNT_WIDTH'(MAX_INTAN_FRAMES) &&
    (packet_active || packet_ready);

always_ff @(posedge clk) begin
    logic [CHUNK_BITS-1:0] source_chunk;
    logic [DATA_WIDTH-1:0] completed_word;

    if (rst) begin
        state <= WAIT_INPUT;
        packet_active <= 1'b0;
        packet_closing <= 1'b0;
        pending_intan_valid <= 1'b0;
        pending_icm_valid <= 1'b0;
        accept_intan_frame <= 1'b0;
        intan_shift <= '0;
        pending_intan_frame <= '0;
        icm_shift <= '0;
        pending_icm_frame <= '0;
        trailer_shift <= '0;
        word_assembly <= '0;
        intan_chunks_remaining <= '0;
        icm_chunks_remaining <= '0;
        chunk_count <= '0;
        packet_intan_frames <= '0;
        packet_word_index <= '0;
        trailer_words_remaining <= '0;
        packet_counter <= 32'b0;
        dropped_intan_frames <= 32'b0;
        dropped_icm_frames <= 32'b0;
        word_valid <= 1'b0;
        word_last <= 1'b0;
        word_data <= '0;
        packet_done <= 1'b0;
    end else begin
        packet_done <= 1'b0;
        accept_intan_frame <= 1'b0;

        if (word_valid && word_ready) begin
            word_valid <= 1'b0;
            word_last <= 1'b0;
        end

        if (finish_packet) begin
            packet_done <= 1'b1;
            packet_counter <= packet_counter + 1'b1;
            packet_active <= 1'b0;
            packet_closing <= 1'b0;
            pending_intan_valid <= 1'b0;
            pending_icm_valid <= 1'b0;
            packet_intan_frames <= '0;
            packet_word_index <= '0;
            word_assembly <= '0;
            chunk_count <= '0;
            state <= WAIT_INPUT;

            // A completion pulse concurrent with the accepted final word cannot
            // be retained; account for it in the next packet's drop snapshot.
            if (Intan_frame_done)
                dropped_intan_frames <= dropped_intan_frames + 1'b1;
            if (ICM_frame_done)
                dropped_icm_frames <= dropped_icm_frames + 1'b1;
        end else begin
            case (state)
                WAIT_INPUT: begin
                    // Intan_frame_in is owned by the acquisition engine and
                    // remains stable until its next frame_done pulse.  Admission
                    // is registered first so only this event, never FIFO-space
                    // combinational logic, enables the wide shift-register load.
                    if (accept_intan_frame) begin
                        intan_shift <= intan_to_stream_order(Intan_frame_in);
                        intan_chunks_remaining <=
                            INTAN_CHUNK_COUNT_WIDTH'(INTAN_FRAME_CHUNKS);
                        state <= STREAM_INTAN;

                        // A second completion in this one-cycle capture window
                        // cannot replace the admitted frame.
                        if (Intan_frame_done)
                            dropped_intan_frames <= dropped_intan_frames + 1'b1;
                        if (ICM_frame_done) begin
                            if (!pending_icm_valid) begin
                                pending_icm_frame <= icm_to_stream_order(ICM_frame_in);
                                pending_icm_valid <= 1'b1;
                                packet_closing <= 1'b1;
                            end else begin
                                dropped_icm_frames <= dropped_icm_frames + 1'b1;
                            end
                        end
                    end else if (!packet_active) begin
                        if (Intan_frame_done && packet_ready) begin
                            accept_intan_frame <= 1'b1;
                            packet_active <= 1'b1;
                            packet_intan_frames <= INTAN_COUNT_WIDTH'(1);
                            packet_word_index <= '0;
                            chunk_count <= '0;
                            word_assembly <= '0;

                            // When both frame types complete together, retain
                            // the ICM frame during delayed Intan capture/streaming.
                            if (ICM_frame_done) begin
                                pending_icm_frame <= icm_to_stream_order(ICM_frame_in);
                                pending_icm_valid <= 1'b1;
                                packet_closing <= 1'b1;
                            end
                        end else if (ICM_frame_done && packet_ready) begin
                            packet_active <= 1'b1;
                            packet_closing <= 1'b1;
                            packet_intan_frames <= '0;
                            packet_word_index <= '0;
                            chunk_count <= '0;
                            word_assembly <= '0;
                            icm_shift <= icm_to_stream_order(ICM_frame_in);
                            icm_chunks_remaining <=
                                ICM_CHUNK_COUNT_WIDTH'(ICM_FRAME_CHUNKS);
                            trailer_shift <= build_trailer_stream(
                                packet_counter,
                                '0,
                                dropped_intan_frames,
                                dropped_icm_frames
                            );
                            dropped_intan_frames <= 32'b0;
                            dropped_icm_frames <= 32'b0;
                            state <= STREAM_ICM;
                        end else begin
                            if (Intan_frame_done)
                                dropped_intan_frames <= dropped_intan_frames + 1'b1;
                            if (ICM_frame_done)
                                dropped_icm_frames <= dropped_icm_frames + 1'b1;
                        end
                    end else begin
                        if (pending_intan_valid) begin
                            intan_shift <= pending_intan_frame;
                            intan_chunks_remaining <=
                                INTAN_CHUNK_COUNT_WIDTH'(INTAN_FRAME_CHUNKS);
                            pending_intan_valid <= 1'b0;

                            // Refill the slot that is consumed on this cycle.
                            if (Intan_frame_done) begin
                                if (!packet_closing &&
                                    packet_intan_frames <
                                        INTAN_COUNT_WIDTH'(MAX_INTAN_FRAMES)) begin
                                    pending_intan_frame <=
                                        intan_to_stream_order(Intan_frame_in);
                                    pending_intan_valid <= 1'b1;
                                    packet_intan_frames <= packet_intan_frames + 1'b1;
                                end else begin
                                    dropped_intan_frames <=
                                        dropped_intan_frames + 1'b1;
                                end
                            end

                            if (ICM_frame_done) begin
                                if (!pending_icm_valid) begin
                                    pending_icm_frame <=
                                        icm_to_stream_order(ICM_frame_in);
                                    pending_icm_valid <= 1'b1;
                                    packet_closing <= 1'b1;
                                end else begin
                                    dropped_icm_frames <=
                                        dropped_icm_frames + 1'b1;
                                end
                            end
                            state <= STREAM_INTAN;
                        end else if (Intan_frame_done && !packet_closing &&
                                     packet_intan_frames <
                                         INTAN_COUNT_WIDTH'(MAX_INTAN_FRAMES)) begin
                            accept_intan_frame <= 1'b1;
                            packet_intan_frames <= packet_intan_frames + 1'b1;

                            if (ICM_frame_done) begin
                                if (!pending_icm_valid) begin
                                    pending_icm_frame <=
                                        icm_to_stream_order(ICM_frame_in);
                                    pending_icm_valid <= 1'b1;
                                    packet_closing <= 1'b1;
                                end else begin
                                    dropped_icm_frames <=
                                        dropped_icm_frames + 1'b1;
                                end
                            end
                        end else if (pending_icm_valid) begin
                            icm_shift <= pending_icm_frame;
                            icm_chunks_remaining <=
                                ICM_CHUNK_COUNT_WIDTH'(ICM_FRAME_CHUNKS);
                            pending_icm_valid <= 1'b0;
                            trailer_shift <= build_trailer_stream(
                                packet_counter,
                                packet_intan_frames,
                                dropped_intan_frames +
                                    (Intan_frame_done ? 32'd1 : 32'd0),
                                dropped_icm_frames +
                                    (ICM_frame_done ? 32'd1 : 32'd0)
                            );
                            dropped_intan_frames <= 32'b0;
                            dropped_icm_frames <= 32'b0;
                            state <= STREAM_ICM;
                        end else if (ICM_frame_done) begin
                            packet_closing <= 1'b1;
                            icm_shift <= icm_to_stream_order(ICM_frame_in);
                            icm_chunks_remaining <=
                                ICM_CHUNK_COUNT_WIDTH'(ICM_FRAME_CHUNKS);
                            trailer_shift <= build_trailer_stream(
                                packet_counter,
                                packet_intan_frames,
                                dropped_intan_frames +
                                    (Intan_frame_done ? 32'd1 : 32'd0),
                                dropped_icm_frames
                            );
                            dropped_intan_frames <= 32'b0;
                            dropped_icm_frames <= 32'b0;
                            state <= STREAM_ICM;
                        end else if (Intan_frame_done) begin
                            dropped_intan_frames <= dropped_intan_frames + 1'b1;
                        end
                    end
                end

                STREAM_INTAN: begin
                    if (Intan_frame_done) begin
                        if (!packet_closing && !pending_intan_valid &&
                            packet_intan_frames <
                                INTAN_COUNT_WIDTH'(MAX_INTAN_FRAMES)) begin
                            pending_intan_frame <= intan_to_stream_order(Intan_frame_in);
                            pending_intan_valid <= 1'b1;
                            packet_intan_frames <= packet_intan_frames + 1'b1;
                        end else begin
                            dropped_intan_frames <= dropped_intan_frames + 1'b1;
                        end
                    end

                    if (ICM_frame_done) begin
                        if (!pending_icm_valid) begin
                            pending_icm_frame <= icm_to_stream_order(ICM_frame_in);
                            pending_icm_valid <= 1'b1;
                            packet_closing <= 1'b1;
                        end else begin
                            dropped_icm_frames <= dropped_icm_frames + 1'b1;
                        end
                    end

                    if (output_slot_available) begin
                        source_chunk = intan_shift[CHUNK_BITS-1:0];
                        completed_word = {
                            source_chunk,
                            word_assembly[DATA_WIDTH-1:CHUNK_BITS]
                        };
                        intan_shift <= intan_shift >> CHUNK_BITS;
                        intan_chunks_remaining <= intan_chunks_remaining - 1'b1;

                        if (chunk_count ==
                            CHUNK_COUNT_WIDTH'(CHUNKS_PER_WORD - 1)) begin
                            word_data <= completed_word;
                            word_valid <= 1'b1;
                            word_assembly <= '0;
                            chunk_count <= '0;
                            packet_word_index <= packet_word_index + 1'b1;
                        end else begin
                            word_assembly <= completed_word;
                            chunk_count <= chunk_count + 1'b1;
                        end

                        if (intan_chunks_remaining == 1)
                            state <= WAIT_INPUT;
                    end
                end

                STREAM_ICM: begin
                    if (Intan_frame_done)
                        dropped_intan_frames <= dropped_intan_frames + 1'b1;
                    if (ICM_frame_done)
                        dropped_icm_frames <= dropped_icm_frames + 1'b1;

                    if (output_slot_available) begin
                        source_chunk = icm_shift[CHUNK_BITS-1:0];
                        completed_word = {
                            source_chunk,
                            word_assembly[DATA_WIDTH-1:CHUNK_BITS]
                        };
                        icm_shift <= icm_shift >> CHUNK_BITS;
                        icm_chunks_remaining <= icm_chunks_remaining - 1'b1;

                        if (chunk_count ==
                            CHUNK_COUNT_WIDTH'(CHUNKS_PER_WORD - 1)) begin
                            word_data <= completed_word;
                            word_valid <= 1'b1;
                            word_assembly <= '0;
                            chunk_count <= '0;
                            packet_word_index <= packet_word_index + 1'b1;
                        end else begin
                            word_assembly <= completed_word;
                            chunk_count <= chunk_count + 1'b1;
                        end

                        if (icm_chunks_remaining == 1)
                            state <= PAD_PACKET;
                    end
                end

                PAD_PACKET: begin
                    if (Intan_frame_done)
                        dropped_intan_frames <= dropped_intan_frames + 1'b1;
                    if (ICM_frame_done)
                        dropped_icm_frames <= dropped_icm_frames + 1'b1;

                    if (output_slot_available) begin
                        if (chunk_count != 0) begin
                            completed_word = {
                                {CHUNK_BITS{1'b0}},
                                word_assembly[DATA_WIDTH-1:CHUNK_BITS]
                            };

                            if (chunk_count ==
                                CHUNK_COUNT_WIDTH'(CHUNKS_PER_WORD - 1)) begin
                                word_data <= completed_word;
                                word_valid <= 1'b1;
                                word_assembly <= '0;
                                chunk_count <= '0;
                                packet_word_index <= packet_word_index + 1'b1;
                            end else begin
                                word_assembly <= completed_word;
                                chunk_count <= chunk_count + 1'b1;
                            end
                        end else if (packet_word_index <
                                     PACKET_WORD_INDEX_WIDTH'(PACKET_DATA_WORDS)) begin
                            word_data <= '0;
                            word_valid <= 1'b1;
                            packet_word_index <= packet_word_index + 1'b1;
                        end else begin
                            trailer_words_remaining <=
                                TRAILER_WORD_COUNT_WIDTH'(PACKET_TRAILER_WORDS);
                            state <= STREAM_TRAILER;
                        end
                    end
                end

                STREAM_TRAILER: begin
                    if (Intan_frame_done)
                        dropped_intan_frames <= dropped_intan_frames + 1'b1;
                    if (ICM_frame_done)
                        dropped_icm_frames <= dropped_icm_frames + 1'b1;

                    if (output_slot_available) begin
                        word_data <= trailer_shift[DATA_WIDTH-1:0];
                        word_valid <= 1'b1;
                        word_last <= trailer_words_remaining == 1;
                        trailer_shift <= trailer_shift >> DATA_WIDTH;
                        trailer_words_remaining <= trailer_words_remaining - 1'b1;
                        packet_word_index <= packet_word_index + 1'b1;

                        if (trailer_words_remaining == 1)
                            state <= WAIT_LAST_ACCEPT;
                    end
                end

                WAIT_LAST_ACCEPT: begin
                    if (Intan_frame_done)
                        dropped_intan_frames <= dropped_intan_frames + 1'b1;
                    if (ICM_frame_done)
                        dropped_icm_frames <= dropped_icm_frames + 1'b1;
                end

                default: begin
                    state <= WAIT_INPUT;
                    packet_active <= 1'b0;
                    packet_closing <= 1'b0;
                    pending_intan_valid <= 1'b0;
                    pending_icm_valid <= 1'b0;
                    word_valid <= 1'b0;
                    word_last <= 1'b0;
                end
            endcase
        end
    end
end

endmodule
