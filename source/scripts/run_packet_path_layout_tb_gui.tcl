# GUI waveform version of packet_path_layout_tb

set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize [file join $script_dir .. ..]]
set project_dir [file normalize [file join $repo_root build packet_path_layout_tb_project_gui]]

file delete -force $project_dir

create_project -force packet_path_layout_tb_gui $project_dir -part xc7z020clg400-1

set hdl_files [list \
    [file join $repo_root source hdl config_pkg.sv] \
    [file join $repo_root source hdl packet_writer.sv] \
    [file join $repo_root source hdl packet_buffer.sv] \
    [file join $repo_root source hdl packet_to_axis.sv] \
    [file join $repo_root source tests hdl packet_path_layout_tb.sv] \
]

add_files -norecurse -fileset sim_1 $hdl_files
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top packet_path_layout_tb [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral

# Top-level testbench drivers
add_wave_divider {TB clock/reset}
add_wave /packet_path_layout_tb/clk
add_wave /packet_path_layout_tb/rst

add_wave_divider {Frame inputs to packet_writer}
add_wave /packet_path_layout_tb/intan_done
add_wave -radix hex /packet_path_layout_tb/intan_frame
add_wave /packet_path_layout_tb/icm_done
add_wave -radix hex /packet_path_layout_tb/icm_frame

# packet_writer boundary
add_wave_divider {packet_writer output}
add_wave /packet_path_layout_tb/writer_ready
add_wave /packet_path_layout_tb/writer_word_valid
add_wave /packet_path_layout_tb/writer_word_ready
add_wave -radix hex /packet_path_layout_tb/writer_word_data
add_wave /packet_path_layout_tb/writer_packet_done

# packet_buffer boundary
add_wave_divider {packet_buffer}
add_wave /packet_path_layout_tb/fifo_rd_en
add_wave -radix hex /packet_path_layout_tb/fifo_rd_data
add_wave /packet_path_layout_tb/fifo_full
add_wave /packet_path_layout_tb/fifo_packet_space
add_wave /packet_path_layout_tb/fifo_packet_available
add_wave /packet_path_layout_tb/fifo_overflow
add_wave /packet_path_layout_tb/fifo_underflow

# AXI-stream output
add_wave_divider {packet_to_axis / AXI stream}
add_wave /packet_path_layout_tb/axis_valid
add_wave /packet_path_layout_tb/axis_ready
add_wave -radix hex /packet_path_layout_tb/axis_data
add_wave -radix hex /packet_path_layout_tb/axis_keep
add_wave /packet_path_layout_tb/axis_last

# Testbench counters
add_wave_divider {TB counters}
add_wave -radix unsigned /packet_path_layout_tb/byte_count
add_wave -radix unsigned /packet_path_layout_tb/beat_count
add_wave -radix unsigned /packet_path_layout_tb/packet_done_count

run all
