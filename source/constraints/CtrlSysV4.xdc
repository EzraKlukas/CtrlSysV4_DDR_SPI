# Shared ICM SPI bus on the Red Pitaya expansion connector.
# NUM_ICM is 4 in config_pkg.sv, so all four MISO inputs are constrained even
# if only spi_miso_0[0] and spi_miso_0[1] are physically populated.
#
# DIO0_P: SCLK
# DIO0_N: MOSI
# DIO1_N: active-low CS
# DIO1_P: MISO[0]
# DIO2_P: MISO[1]
# DIO2_N: MISO[2]
# DIO3_P: MISO[3]
#
# ICM SPI pins.
set_property PACKAGE_PIN G17 [get_ports spi_sclk_0]
set_property PACKAGE_PIN G18 [get_ports spi_mosi_0]
set_property PACKAGE_PIN H16 [get_ports {spi_miso_0[0]}]
set_property PACKAGE_PIN J18 [get_ports {spi_miso_0[1]}]
set_property PACKAGE_PIN H18 [get_ports {spi_miso_0[2]}]
set_property PACKAGE_PIN K17 [get_ports {spi_miso_0[3]}]
set_property PACKAGE_PIN H17 [get_ports spi_cs_n_0]

# Shared Intan SPI outputs.
set_property PACKAGE_PIN K18 [get_ports intan_sclk_0]
set_property PACKAGE_PIN L14 [get_ports intan_mosi_0]
set_property PACKAGE_PIN L15 [get_ports intan_cs_n_0]

# One independent MISO return per possible Intan sensor.
set_property PACKAGE_PIN L16 [get_ports {intan_miso_0[0]}]
set_property PACKAGE_PIN L17 [get_ports {intan_miso_0[1]}]
set_property PACKAGE_PIN Y9 [get_ports {intan_miso_0[2]}]
set_property PACKAGE_PIN Y8 [get_ports {intan_miso_0[3]}]
set_property PACKAGE_PIN Y12 [get_ports {intan_miso_0[4]}]
set_property PACKAGE_PIN Y13 [get_ports {intan_miso_0[5]}]
set_property PACKAGE_PIN Y7 [get_ports {intan_miso_0[6]}]
set_property PACKAGE_PIN Y6 [get_ports {intan_miso_0[7]}]

# Setting ICM IOSTANDARD.
set_property IOSTANDARD LVCMOS33 [get_ports {spi_sclk_0 spi_mosi_0 spi_cs_n_0}]
set_property IOSTANDARD LVCMOS33 [get_ports {spi_miso_0[0] spi_miso_0[1] spi_miso_0[2] spi_miso_0[3]}]

# Setting Intan IOSTANDARD.
set_property IOSTANDARD LVCMOS33 [get_ports {intan_sclk_0 intan_mosi_0 intan_cs_n_0}]
set_property IOSTANDARD LVCMOS33 [get_ports {
        intan_miso_0[0]
        intan_miso_0[1]
        intan_miso_0[2]
        intan_miso_0[3]
        intan_miso_0[4]
        intan_miso_0[5]
        intan_miso_0[6]
        intan_miso_0[7]
    }]

set_property DRIVE 8 [get_ports {spi_sclk_0 spi_mosi_0 spi_cs_n_0}]
set_property SLEW FAST [get_ports {spi_sclk_0 spi_mosi_0 spi_cs_n_0}]

# Slow edges and modest drive are sufficient for a few-megahertz SPI bus.
set_property DRIVE 4 [get_ports {intan_sclk_0 intan_mosi_0 intan_cs_n_0}]
set_property SLEW SLOW [get_ports {intan_sclk_0 intan_mosi_0 intan_cs_n_0}]

# Prevent unused future MISO inputs from floating during one-sensor testing.
set_property PULLDOWN TRUE [get_ports {
        intan_miso_0[1]
        intan_miso_0[2]
        intan_miso_0[3]
        intan_miso_0[4]
        intan_miso_0[5]
        intan_miso_0[6]
        intan_miso_0[7]
    }]
