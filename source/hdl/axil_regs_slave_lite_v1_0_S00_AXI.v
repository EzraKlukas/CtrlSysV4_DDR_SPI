`timescale 1 ns / 1 ps

module axil_regs_slave_lite_v1_0_S00_AXI #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6
)
(
    // FPGA-side outputs from CPU-written registers
    output wire        enable,
    output wire        soft_reset,
    output wire [31:0] sample_period,
    output wire        useAXI,

    // FPGA-side command pulses
    output reg         clear_error,
    output reg         reset_sample_counter,
    output reg         cpu_clear_irq,
    

    // FPGA-side status inputs
    input  wire        busy,
    input  wire        error,
    input  wire        read_in_progress,
    input  wire        packet_done,
    input  wire [31:0] sample_count,
    input  wire [31:0] error_code,
    input  wire [3:0]  state,

    // FPGA-side packet/data inputs
    input  wire [31:0] data_word0,
    input  wire [31:0] data_word1,
    input  wire [31:0] data_word2,
    input  wire [31:0] data_word3,
    input  wire [31:0] data_word4,
    input  wire [31:0] data_word5,
    input  wire [31:0] data_word6,
    input  wire [31:0] data_word7,

    // AXI4-Lite slave interface
    input  wire                                      S_AXI_ACLK,
    input  wire                                      S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0]           S_AXI_AWADDR,
    input  wire [2 : 0]                              S_AXI_AWPROT,
    input  wire                                      S_AXI_AWVALID,
    output wire                                      S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1 : 0]           S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0]       S_AXI_WSTRB,
    input  wire                                      S_AXI_WVALID,
    output wire                                      S_AXI_WREADY,
    output wire [1 : 0]                              S_AXI_BRESP,
    output wire                                      S_AXI_BVALID,
    input  wire                                      S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1 : 0]           S_AXI_ARADDR,
    input  wire [2 : 0]                              S_AXI_ARPROT,
    input  wire                                      S_AXI_ARVALID,
    output wire                                      S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0]           S_AXI_RDATA,
    output wire [1 : 0]                              S_AXI_RRESP,
    output wire                                      S_AXI_RVALID,
    input  wire                                      S_AXI_RREADY
);

localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1; // 2 for 32-bit AXI data
localparam integer OPT_MEM_ADDR_BITS = 3;                  // address bits [5:2] => 16 registers

// CPU-writable registers
reg [31:0] slv_reg0 = 32'h00000001; // 0x00 control
reg [31:0] slv_reg1 = 32'd5000; // 0x04 sample_period

// AXI write channel state
reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
reg [C_S_AXI_DATA_WIDTH-1:0] axi_wdata;
reg [(C_S_AXI_DATA_WIDTH/8)-1:0] axi_wstrb;
reg axi_aw_seen;
reg axi_w_seen;
reg axi_awready;
reg axi_wready;
reg axi_bvalid;
reg [1:0] axi_bresp;

// AXI read channel state
reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
reg axi_arready;
reg axi_rvalid;
reg [1:0] axi_rresp;

integer byte_index;

assign S_AXI_AWREADY = axi_awready;
assign S_AXI_WREADY  = axi_wready;
assign S_AXI_BVALID  = axi_bvalid;
assign S_AXI_BRESP   = axi_bresp;
assign S_AXI_ARREADY = axi_arready;
assign S_AXI_RVALID  = axi_rvalid;
assign S_AXI_RRESP   = axi_rresp;

assign enable             = slv_reg0[0];
assign soft_reset         = slv_reg0[1];
assign useAXI             = slv_reg0[2];
assign sample_period      = slv_reg1;

wire [3:0] wr_addr_index = axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB];
wire [3:0] rd_addr_index = axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB];

wire write_ready_to_commit = axi_aw_seen && axi_w_seen && !axi_bvalid;

// Write address/data handshake and register writes.
// This accepts AW and W independently, so it works even if the PS/interconnect
// sends address and data on different cycles.
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        axi_awaddr <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        axi_wdata  <= {C_S_AXI_DATA_WIDTH{1'b0}};
        axi_wstrb  <= {(C_S_AXI_DATA_WIDTH/8){1'b0}};

        axi_aw_seen  <= 1'b0;
        axi_w_seen   <= 1'b0;
        axi_awready  <= 1'b0;
        axi_wready   <= 1'b0;
        axi_bvalid   <= 1'b0;
        axi_bresp    <= 2'b00;

        slv_reg0 <= 32'h00000001;
        slv_reg1 <= 32'd5000;

        clear_error          <= 1'b0;
        reset_sample_counter <= 1'b0;
        cpu_clear_irq        <= 1'b0;
    end else begin
        // Command outputs are one-clock pulses.
        clear_error          <= 1'b0;
        reset_sample_counter <= 1'b0;
        cpu_clear_irq        <= 1'b0;

        // Ready for one address and one data beat while no response is pending.
        axi_awready <= (!axi_aw_seen && !axi_bvalid);
        axi_wready  <= (!axi_w_seen  && !axi_bvalid);

        if (S_AXI_AWVALID && axi_awready) begin
            axi_awaddr  <= S_AXI_AWADDR;
            axi_aw_seen <= 1'b1;
            axi_awready <= 1'b0;
        end

        if (S_AXI_WVALID && axi_wready) begin
            axi_wdata  <= S_AXI_WDATA;
            axi_wstrb  <= S_AXI_WSTRB;
            axi_w_seen <= 1'b1;
            axi_wready <= 1'b0;
        end

        if (write_ready_to_commit) begin
            case (wr_addr_index)
                4'h0: begin // 0x00 control
                    for (byte_index = 0; byte_index < (C_S_AXI_DATA_WIDTH/8); byte_index = byte_index + 1) begin
                        if (axi_wstrb[byte_index]) begin
                            slv_reg0[(byte_index*8) +: 8] <= axi_wdata[(byte_index*8) +: 8];
                        end
                    end
                end

                4'h1: begin // 0x04 sample_period
                    for (byte_index = 0; byte_index < (C_S_AXI_DATA_WIDTH/8); byte_index = byte_index + 1) begin
                        if (axi_wstrb[byte_index]) begin
                            slv_reg1[(byte_index*8) +: 8] <= axi_wdata[(byte_index*8) +: 8];
                        end
                    end
                end

                4'h3: begin // 0x0C command register, write-only pulse bits
                    if (axi_wstrb[0]) begin
                        clear_error          <= axi_wdata[0];
                        reset_sample_counter <= axi_wdata[1];
                        cpu_clear_irq        <= axi_wdata[2];
                    end
                end

                default: begin
                    // Status/data registers are read-only from the CPU side.
                end
            endcase

            axi_aw_seen <= 1'b0;
            axi_w_seen  <= 1'b0;
            axi_bvalid  <= 1'b1;
            axi_bresp   <= 2'b00; // OKAY
        end else if (axi_bvalid && S_AXI_BREADY) begin
            axi_bvalid <= 1'b0;
        end
    end
end

// Read address/data handshake.
always @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN) begin
        axi_araddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        axi_arready <= 1'b0;
        axi_rvalid  <= 1'b0;
        axi_rresp   <= 2'b00;
    end else begin
        axi_arready <= !axi_rvalid;

        if (S_AXI_ARVALID && axi_arready) begin
            axi_araddr <= S_AXI_ARADDR;
            axi_rvalid <= 1'b1;
            axi_rresp  <= 2'b00; // OKAY
            axi_arready <= 1'b0;
        end else if (axi_rvalid && S_AXI_RREADY) begin
            axi_rvalid <= 1'b0;
        end
    end
end

wire [31:0] status_reg;
assign status_reg = {
    24'b0,
    state,
    packet_done,
    read_in_progress,
    error,
    busy
};

assign S_AXI_RDATA =
    (rd_addr_index == 4'h0) ? slv_reg0 :              // 0x00 control
    (rd_addr_index == 4'h1) ? slv_reg1 :              // 0x04 sample_period
    (rd_addr_index == 4'h2) ? 32'h00000000 :          // 0x08 reserved
    (rd_addr_index == 4'h3) ? 32'h00000000 :          // 0x0C command, write-only
    (rd_addr_index == 4'h4) ? status_reg :            // 0x10 status
    (rd_addr_index == 4'h5) ? sample_count :          // 0x14 sample_count
    (rd_addr_index == 4'h6) ? 32'h00000000 :          // 0x18 reserved
    (rd_addr_index == 4'h7) ? error_code :            // 0x1C error_code
    (rd_addr_index == 4'h8) ? data_word0 :            // 0x20 data_word0
    (rd_addr_index == 4'h9) ? data_word1 :            // 0x24 data_word1
    (rd_addr_index == 4'hA) ? data_word2 :            // 0x28 data_word2
    (rd_addr_index == 4'hB) ? data_word3 :            // 0x2C data_word3
    (rd_addr_index == 4'hC) ? data_word4 :            // 0x30 data_word4
    (rd_addr_index == 4'hD) ? data_word5 :            // 0x34 data_word5
    (rd_addr_index == 4'hE) ? data_word6 :            // 0x38 data_word6
    (rd_addr_index == 4'hF) ? data_word7 :            // 0x3C data_word7
    32'h00000000;

endmodule
