`timescale 1ns / 1ps

/*
Name: Gordon Zhao
File: SPI_mux.sv
Description: arbitrates the sensor SPI bus between the acquisition reader and
an AXI-controlled SPI master
*/

module SPI_mux #(
    parameter integer NUM_SENSORS = 1
) (
    input logic axi_enable,

    input  logic                   reader_sclk,
    input  logic                   reader_mosi,
    input  logic                   reader_cs_n,
    output logic [NUM_SENSORS-1:0] reader_miso,

    input  logic axi_sclk,
    input  logic axi_mosi,
    input  logic axi_cs_n,
    output logic axi_miso,

    output logic                   spi_sclk,
    output logic                   spi_mosi,
    output logic                   spi_cs_n,
    input  logic [NUM_SENSORS-1:0] spi_miso
);

    initial begin
        if (NUM_SENSORS < 1) $error("SPI_mux requires NUM_SENSORS >= 1");
    end

    always_comb begin
        reader_miso = spi_miso;
        axi_miso = spi_miso[0];

        spi_sclk = reader_sclk;
        spi_mosi = reader_mosi;
        spi_cs_n = reader_cs_n;

        if (axi_enable) begin
            spi_sclk = axi_sclk;
            spi_mosi = axi_mosi;
            spi_cs_n = axi_cs_n;
        end
    end

endmodule
