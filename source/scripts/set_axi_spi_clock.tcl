# Set AXI Quad SPI to a breakout-friendly clock rate.
set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir ".." ".."]]
set project_path [file join $repo_root "Vivado_CtrlSysV4" "Vivado_CtrlSysV4.xpr"]
set bd_path [file join $repo_root "Vivado_CtrlSysV4" "Vivado_CtrlSysV4.srcs" \
    "sources_1" "bd" "design_1" "design_1.bd"]

open_project $project_path
update_ip_catalog -rebuild
set core_ips [get_ips -all -quiet *ctrlsys_core*]
if {[llength $core_ips] > 0} {
    upgrade_ip $core_ips
}
open_bd_design $bd_path

# AXI Quad SPI only supports ratios through 16. Give its SPI engine a
# dedicated 10 MHz fabric clock while leaving AXI-Lite at 50 MHz.
set ps [get_bd_cells processing_system7_0]
set_property -dict [list \
    CONFIG.PCW_EN_CLK1_PORT {1} \
    CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {10.000000}] $ps
set_property CONFIG.C_SCK_RATIO 16 [get_bd_cells axi_quad_spi_0]

set ext_spi_clk [get_bd_pins axi_quad_spi_0/ext_spi_clk]
set old_net [get_bd_nets -quiet -of_objects $ext_spi_clk]
if {$old_net ne ""} {
    disconnect_bd_net $old_net $ext_spi_clk
}
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] $ext_spi_clk

validate_bd_design
save_bd_design

generate_target all [get_files $bd_path]
puts "AXI Quad SPI clock: 10 MHz / 16 = 625 kHz"
close_project
