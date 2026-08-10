#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_root="${TMPDIR:-/tmp}/ctrlsys_verilator_regression"
mkdir -p "$build_root"
cd "$repo_root"

run_test() {
    local top="$1"
    shift
    local build_dir="$build_root/$top"
    local build_log="$build_root/${top}_build.log"

    printf 'Building %s\n' "$top"
    verilator --binary --timing -Wall -Wno-fatal --top-module "$top" \
        -Mdir "$build_dir" "$@" >"$build_log" 2>&1
    "$build_dir/V$top"
}

run_test intan_program_tb \
    source/hdl/config_pkg.sv \
    source/hdl/intan_program.sv \
    source/tests/hdl/intan_program_tb.sv

run_test intan_spi_word_engine_tb \
    source/hdl/config_pkg.sv \
    source/hdl/intan_spi_word_engine.sv \
    source/tests/models/rhd2164_model.sv \
    source/tests/hdl/intan_spi_word_engine_tb.sv

run_test intan_cmd_sequencer_tb \
    source/hdl/config_pkg.sv \
    source/hdl/intan_spi_word_engine.sv \
    source/hdl/intan_cmd_sequencer.sv \
    source/tests/models/rhd2164_model.sv \
    source/tests/hdl/intan_cmd_sequencer_tb.sv

run_test intan_acq_engine_tb \
    source/hdl/config_pkg.sv \
    source/hdl/intan_spi_word_engine.sv \
    source/hdl/intan_cmd_sequencer.sv \
    source/hdl/intan_acq_engine.sv \
    source/tests/models/rhd2164_model.sv \
    source/tests/hdl/intan_acq_engine_tb.sv

run_test intan_acq_engine_contract_tb \
    source/hdl/config_pkg.sv \
    source/hdl/intan_acq_engine.sv \
    source/tests/hdl/intan_acq_engine_contract_tb.sv

run_test acquisition_controller_tb \
    source/hdl/config_pkg.sv \
    source/hdl/acquisition_controller.sv \
    source/tests/hdl/acquisition_controller_tb.sv

run_test SPI_path_tb \
    source/hdl/config_pkg.sv \
    source/hdl/ICM_reader.sv \
    source/hdl/SPI_mux.sv \
    source/tests/hdl/SPI_path_tb.sv

run_test packet_path_layout_tb \
    source/hdl/config_pkg.sv \
    source/hdl/packet_writer.sv \
    source/hdl/packet_buffer.sv \
    source/hdl/packet_to_axis.sv \
    source/tests/hdl/packet_path_layout_tb.sv

run_test packet_to_axis_packet_available_tb \
    source/hdl/config_pkg.sv \
    source/hdl/packet_buffer.sv \
    source/hdl/packet_to_axis.sv \
    source/tests/hdl/packet_to_axis_packet_available_tb.sv

run_test integrate_intan_packet_path_layout_tb \
    source/hdl/config_pkg.sv \
    source/hdl/intan_program.sv \
    source/hdl/intan_spi_word_engine.sv \
    source/hdl/intan_cmd_sequencer.sv \
    source/hdl/intan_acq_engine.sv \
    source/hdl/intan_reader.sv \
    source/hdl/packet_writer.sv \
    source/hdl/packet_buffer.sv \
    source/hdl/packet_to_axis.sv \
    source/tests/models/rhd2164_model.sv \
    source/tests/hdl/integrate_intan_packet_path_layout_tb.sv

run_test ctrlsys_core_tb \
    source/hdl/config_pkg.sv \
    source/hdl/acquisition_controller.sv \
    source/hdl/axil_regs_slave_lite_v1_0_S00_AXI.v \
    source/hdl/axil_regs.v \
    source/hdl/stopwatch_64.sv \
    source/hdl/ICM_reader.sv \
    source/hdl/intan_program.sv \
    source/hdl/intan_spi_word_engine.sv \
    source/hdl/intan_cmd_sequencer.sv \
    source/hdl/intan_acq_engine.sv \
    source/hdl/intan_reader.sv \
    source/hdl/packet_writer.sv \
    source/hdl/SPI_mux.sv \
    source/hdl/packet_buffer.sv \
    source/hdl/packet_to_axis.sv \
    source/hdl/ctrlsys_core.sv \
    source/tests/models/rhd2164_model.sv \
    source/tests/hdl/ctrlsys_core_tb.sv

printf 'PASS: all Verilator regressions\n'
