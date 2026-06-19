`timescale 1 ns / 1 ps

module axil_regs #
(
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH = 6
)
(
    // FPGA-side outputs from CPU-written registers
    output wire        enable,
    output wire        soft_reset,
    output wire [31:0] sample_period,
    output wire        useAXI,

    // FPGA-side command pulses
    output wire        clear_error,
    output wire        reset_sample_counter,
    output wire        cpu_clear_irq,

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
    input  wire                                      s00_axi_aclk,
    input  wire                                      s00_axi_aresetn,
    input  wire [C_S00_AXI_ADDR_WIDTH-1 : 0]         s00_axi_awaddr,
    input  wire [2 : 0]                              s00_axi_awprot,
    input  wire                                      s00_axi_awvalid,
    output wire                                      s00_axi_awready,
    input  wire [C_S00_AXI_DATA_WIDTH-1 : 0]         s00_axi_wdata,
    input  wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0]     s00_axi_wstrb,
    input  wire                                      s00_axi_wvalid,
    output wire                                      s00_axi_wready,
    output wire [1 : 0]                              s00_axi_bresp,
    output wire                                      s00_axi_bvalid,
    input  wire                                      s00_axi_bready,
    input  wire [C_S00_AXI_ADDR_WIDTH-1 : 0]         s00_axi_araddr,
    input  wire [2 : 0]                              s00_axi_arprot,
    input  wire                                      s00_axi_arvalid,
    output wire                                      s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1 : 0]         s00_axi_rdata,
    output wire [1 : 0]                              s00_axi_rresp,
    output wire                                      s00_axi_rvalid,
    input  wire                                      s00_axi_rready
);

axil_regs_slave_lite_v1_0_S00_AXI #(
    .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
    .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
) axil_regs_slave_lite_v1_0_S00_AXI_inst (
    .S_AXI_ACLK    (s00_axi_aclk),
    .S_AXI_ARESETN (s00_axi_aresetn),

    .S_AXI_AWADDR  (s00_axi_awaddr),
    .S_AXI_AWPROT  (s00_axi_awprot),
    .S_AXI_AWVALID (s00_axi_awvalid),
    .S_AXI_AWREADY (s00_axi_awready),

    .S_AXI_WDATA   (s00_axi_wdata),
    .S_AXI_WSTRB   (s00_axi_wstrb),
    .S_AXI_WVALID  (s00_axi_wvalid),
    .S_AXI_WREADY  (s00_axi_wready),

    .S_AXI_BRESP   (s00_axi_bresp),
    .S_AXI_BVALID  (s00_axi_bvalid),
    .S_AXI_BREADY  (s00_axi_bready),

    .S_AXI_ARADDR  (s00_axi_araddr),
    .S_AXI_ARPROT  (s00_axi_arprot),
    .S_AXI_ARVALID (s00_axi_arvalid),
    .S_AXI_ARREADY (s00_axi_arready),

    .S_AXI_RDATA   (s00_axi_rdata),
    .S_AXI_RRESP   (s00_axi_rresp),
    .S_AXI_RVALID  (s00_axi_rvalid),
    .S_AXI_RREADY  (s00_axi_rready),

    .enable               (enable),
    .soft_reset           (soft_reset),
    .sample_period        (sample_period),
    .useAXI               (useAXI),

    .clear_error          (clear_error),
    .reset_sample_counter (reset_sample_counter),
    .cpu_clear_irq        (cpu_clear_irq),

    .busy                 (busy),
    .error                (error),
    .read_in_progress     (read_in_progress),
    .packet_done          (packet_done),
    .sample_count         (sample_count),
    .error_code           (error_code),
    .state                (state),

    .data_word0           (data_word0),
    .data_word1           (data_word1),
    .data_word2           (data_word2),
    .data_word3           (data_word3),
    .data_word4           (data_word4),
    .data_word5           (data_word5),
    .data_word6           (data_word6),
    .data_word7           (data_word7)
);

endmodule
