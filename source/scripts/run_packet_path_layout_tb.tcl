# Run the full packet writer -> FIFO -> AXI stream layout regression.
#
# Batch usage:
#   vivado -mode batch -source source/scripts/run_packet_path_layout_tb.tcl

set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set project_dir [file normalize [file join $repo_root build packet_path_layout_tb_project]]

file delete -force $project_dir
create_project -force packet_path_layout_tb $project_dir -part xc7z020clg400-1

set hdl_files [list \
    [file join $repo_root source hdl config_pkg.sv] \
    [file join $repo_root source hdl packet_writer.sv] \
    [file join $repo_root source hdl packet_buffer.sv] \
    [file join $repo_root source hdl packet_to_axis.sv] \
    [file join $repo_root source tests hdl packet_path_layout_tb.sv]]

add_files -norecurse -fileset sim_1 $hdl_files
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top packet_path_layout_tb [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
