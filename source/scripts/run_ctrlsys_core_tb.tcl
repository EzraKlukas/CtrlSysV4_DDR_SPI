# Run the complete ctrlsys_core AXI-Lite + RHD2164 + AXI-Stream regression.
# This is behavioral simulation only; it does not instantiate the Xilinx DMA.
#
# Batch usage:
#   vivado -mode batch -source source/scripts/run_ctrlsys_core_tb.tcl

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set project_dir [file normalize [file join $repo_root build ctrlsys_core_tb_project]]

file delete -force $project_dir
create_project -force ctrlsys_core_tb $project_dir -part xc7z020clg400-1

set hdl_files [list \
    [file join $repo_root source hdl config_pkg.sv] \
    [file join $repo_root source hdl acquisition_controller.sv] \
    [file join $repo_root source hdl axil_regs_slave_lite_v1_0_S00_AXI.v] \
    [file join $repo_root source hdl axil_regs.v] \
    [file join $repo_root source hdl stopwatch_64.sv] \
    [file join $repo_root source hdl ICM_reader.sv] \
    [file join $repo_root source hdl intan_program.sv] \
    [file join $repo_root source hdl intan_spi_word_engine.sv] \
    [file join $repo_root source hdl intan_cmd_sequencer.sv] \
    [file join $repo_root source hdl intan_acq_engine.sv] \
    [file join $repo_root source hdl intan_reader.sv] \
    [file join $repo_root source hdl packet_writer.sv] \
    [file join $repo_root source hdl SPI_mux.sv] \
    [file join $repo_root source hdl packet_buffer.sv] \
    [file join $repo_root source hdl packet_to_axis.sv] \
    [file join $repo_root source hdl ctrlsys_core.sv] \
    [file join $repo_root source tests models rhd2164_model.sv] \
    [file join $repo_root source tests hdl ctrlsys_core_tb.sv]]

add_files -norecurse -fileset sim_1 $hdl_files
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top ctrlsys_core_tb [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
