# CtrlSysV4

CtrlSysV4 is a Red Pitaya / Zynq acquisition design for collecting one ICM-20948 sensor frame together with a burst of Intan RHD2164 frames, packing the result into a fixed-size DMA packet, and streaming that packet through AXI DMA to the processor. The current hardware configuration is:

- 4 ICM MISO channels on a shared SPI bus (one MOSI, CS, SCLK, and individual MISO).
- 8 synthetic Intan channels generated in FPGA logic by `Intan_reader.sv`.
- 1024-bit AXI4-Stream packet words into the block design DMA path.
- 24,576 byte fixed DMA packets, including a 256 byte metadata trailer.
- 1 ms default ICM packet cadence from the Red Pitaya test program.
- 30:1 nominal Intan-to-ICM sampling ratio.

The design was built to make packet integrity easy to verify from software. Every packet has a fixed byte length and a trailer containing magic bytes, packet size, valid-data size, frame counts, frame offsets, error flags, and drop counters.

## Repository Layout

```text
.
|-- IP/ctrlsys_core/              Packaged Vivado user IP generated from source/hdl
|-- Vivado_CtrlSysV4/             Vivado block design project
|-- build/                        Generated bitstreams, .bit.bin files, temp projects
|-- source/
|   |-- constraints/              Project-level XDC constraints
|   |-- cpp/redpitaya/            Red Pitaya userspace test/streaming programs
|   |-- hdl/                      Primary RTL sources for the CtrlSys core
|   |-- python/                   Desktop receiver, analysis, and layout tools
|   |-- redpitaya/                Device tree overlay sources
|   |-- scripts/                  Vivado build, package, simulation, and utility scripts
|   `-- tests/hdl/                HDL testbenches
```

The packaged IP under `IP/ctrlsys_core/src` is generated from the HDL source tree by `source/scripts/repackage_ctrlsys_core_ip.tcl`. Treat `source/hdl` as the design source of truth and `IP/ctrlsys_core` as a generated Vivado package.

## Data Path Overview

At runtime, the control path and data path are:

1. `axil_regs` exposes control/status registers to the PS over AXI4-Lite.
2. `stopwatch_64` provides a 64-bit fabric-clock timestamp.
3. `acquisition_controller` emits scheduled start pulses for ICM and Intan reads.
4. `ICM_reader` performs an SPI burst read across the configured ICM MISO lines.
5. `Intan_reader` generates synthetic Intan frames for datapath testing.
6. `packet_writer` snapshots available Intan frames when an ICM frame is ready, appends the ICM frame, zero pads, and emits a 256 byte trailer.
7. `packet_buffer` stores complete 1024-bit packet words and reports when a whole packet is available.
8. `packet_to_axis` drains one complete packet to AXI4-Stream with `tlast` on the final word.
9. AXI DMA S2MM writes the packet into reserved or `u-dma-buf` memory.
10. The Red Pitaya C program streams packet words to the desktop receiver over TCP.
11. `source/python/redpitaya_dma_receiver.py` reconstructs bytes, decodes trailers, prints payloads, and writes timing CSVs.

## Packet Layout

Current constants:

| Item | Value |
| --- | ---: |
| `NUM_ICM` | 4 |
| `NUM_INTAN` | 8 |
| `ICM_DATA_BYTES` | 20 |
| `INTAN_DATA_BYTES` | 64 |
| `INTAN_SAMPLING_RATIO` | 30 |
| `AXIS_DATA_WIDTH` | 1024 bits |
| AXI bytes per word | 128 |
| `PACKET_BYTES` | 24576 |
| `PACKET_AXIS_WORDS` | 192 |
| `PACKET_TRAILER_BYTES` | 256 |
| Trailer offset | 24320 / `0x5f00` |

Frame sizes:

| Frame | Contents | Bytes |
| --- | --- | ---: |
| Intan frame | `init_read_ts`, `done_read_ts`, 8 measurements of 1 byte sensor ID + 64 data bytes | 536 |
| ICM frame | `init_read_ts`, `done_read_ts`, 4 measurements of 1 byte sensor ID + 20 data bytes | 100 |

Steady-state packets usually contain 30 Intan frames and 1 ICM frame:

```text
30 * 536 + 100 = 16180 valid data bytes
```

The packet writer then pads with zeros until byte offset `0x5f00`, where the 256 byte trailer begins. Because the Intan period is derived by integer division from the ICM period, occasional 31-Intan-frame packets can occur. These are valid as long as the trailer fields match the payload layout and no drop/error flags are set.

## Trailer Format

The packet trailer is big-endian field-by-field and starts at byte offset `PACKET_BYTES - PACKET_TRAILER_BYTES` (`0x5f00`).

| Offset in trailer | Size | Field | Expected / meaning |
| ---: | ---: | --- | --- |
| `0x00` | 8 | magic | `ff ff ff ff ff ff ff ff` |
| `0x08` | 4 | packet number | FPGA packet counter, starting at 0 after reset |
| `0x0c` | 4 | trailer bytes | 256 |
| `0x10` | 4 | packet bytes | 24576 |
| `0x14` | 4 | valid data bytes | Intan bytes + ICM bytes |
| `0x18` | 4 | Intan frame count | Number of Intan frames in this packet |
| `0x1c` | 4 | max Intan frame count | 45 for the current fixed packet size |
| `0x20` | 4 | ICM frame count | 1 for normal packets |
| `0x24` | 4 | ICM frame start index | Usually `intan_frame_count * 536` |
| `0x28` | 4 | trailer start index | 24320 / `0x5f00` |
| `0x2c` | 4 | flags | Bitfield described below |
| `0x30` | 4 | dropped Intan frames | Count since previous packet snapshot |
| `0x34` | 4 | dropped ICM frames | Count since previous packet snapshot |
| `0x38` | 192 | Intan frame start indices | Up to 48 big-endian offsets |
| `0xf8` | 8 | reserved | Zero |

Flag bits:

| Bit | Meaning |
| ---: | --- |
| 0 | At least one Intan frame was dropped before this packet |
| 1 | At least one ICM frame was dropped before this packet |
| 2 | The packet reached `MAX_INTAN_FRAMES_PER_PACKET` |

Known-good steady-state trailer example:

```text
magic=ff ff ff ff ff ff ff ff
trailer_bytes=256
packet_bytes=24576
valid_data_bytes=16180
intan_frame_count=30
max_intan_frame_count=45
icm_frame_count=1
icm_offset=16080
trailer_offset=24320
intan_offsets=[0, 536, 1072, ... 15544]
flags=0x00000000
dropped_intan=0
dropped_icm=0
padding_bytes=8140
frame_words=6144
```

## AXI4-Lite Register Map

The CtrlSys core is controlled through a 64 byte AXI4-Lite register block. The current Red Pitaya C code expects the CtrlSys base address at `0x40000000`.

| Offset | Access | Name | Description |
| ---: | --- | --- | --- |
| `0x00` | R/W | control | Bit 0 enable, bit 1 soft reset, bit 2 use AXI Quad SPI path |
| `0x04` | R/W | sample period | ICM sample period in 125 MHz fabric-clock ticks |
| `0x08` | R | reserved | Reads zero |
| `0x0c` | W | command | Bit 0 clear error, bit 1 reset sample counter, bit 2 clear packet IRQ |
| `0x10` | R | status | `{state, packet_done, read_in_progress, error, busy}` in low bits |
| `0x14` | R | sample count | Increments when `packet_writer` completes a packet |
| `0x18` | R | reserved | Reads zero |
| `0x1c` | R | error code | `1` means packet FIFO overflow or underflow was latched |
| `0x20` | R | data word 0 | Snapshot/debug word: sample count at packet completion |
| `0x24` | R | data word 1 | Snapshot/debug word: packet AXI word count |
| `0x28` | R | data word 2 | Snapshot/debug word: packet buffer word depth |
| `0x2c` | R | data word 3 | ICM init timestamp low word |
| `0x30` | R | data word 4 | ICM init timestamp high word |
| `0x34` | R | data word 5 | ICM done timestamp low word |
| `0x38` | R | data word 6 | ICM done timestamp high word |
| `0x3c` | R | data word 7 | Packet byte count |

The default `sample_period` reset value in the AXI-Lite slave is 5000 ticks, but the Red Pitaya `intan8_icm4_dma_interrupt_test` program writes `SENSOR_TEST_1MS_TICKS` (`125000`) before starting the interrupt DMA run.

## HDL Source File Reference

### `config_pkg.sv`

Defines the shared constants, packed frame types, packet trailer type, and derived packet sizes used throughout the design. Important constants include sensor counts, data-byte widths, the Intan sampling ratio, packet byte count, trailer byte count, AXI stream width, and packet buffer depth. The frame and trailer types are used by readers, packet writer, tests, and tooling to keep the byte layout consistent.

### `ctrlsys_core.sv`

Top-level RTL module packaged as the custom Vivado IP. It ties together the AXI-Lite register block, timestamp counter, scheduler, ICM SPI reader, synthetic Intan reader, packet writer, packet FIFO, AXI stream adapter, and SPI mux. It derives:

```systemverilog
icm_sample_period = axil_sample_period;
intan_sample_period = axil_sample_period / INTAN_SAMPLING_RATIO;
```

It also latches FIFO overflow/underflow errors, exposes debug words through AXI-Lite, and raises a sticky `packet_done_irq` bit until software clears it.

### `acquisition_controller.sv`

Generates one-clock `startRead_ICM` and `startRead_Intan` pulses while acquisition is enabled. It keeps independent previous-sample timestamps for the ICM and Intan paths and advances them by the ideal configured periods, rather than by read completion time. This keeps the two schedules phase-locked and avoids long-term drift from read latency.

### `stopwatch_64.sv`

A simple 64-bit free-running timestamp counter in the PL clock domain. It resets to zero on core reset and increments once per fabric clock. At 125 MHz, wraparound is practically irrelevant for lab captures.

### `ICM_reader.sv`

SPI burst reader for ICM-20948 data. It drives a shared `sclk`, `mosi`, and active-low chip-select, and samples all `NUM_ICM` MISO lines in parallel. The default register address is `7'd45`, corresponding to ICM-20948 `ACCEL_XOUT_H`. Each frame captures:

- Read start timestamp.
- Read done timestamp.
- One sensor ID and `ICM_DATA_BYTES` data bytes for each ICM channel.

The SPI clock is generated from the PL clock using `SCLK_HALF_PERIOD_CYCLES`; the default is 63, approximately 1 MHz from 125 MHz.

### `Intan_reader.sv`

Synthetic Intan frame source used for packet-path and DMA-path validation before physical Intan hardware is connected. On each start pulse, it emits one frame after `DONE_DELAY_CYCLES`. Each channel gets a sensor ID and deterministic 32-bit words based on:

```systemverilog
sample_counter + sensor_idx * 32 + word_idx
```

This makes the Intan path useful for checking frame ordering, byte ordering, packet offsets, and dropped-frame behavior without depending on real Intan SPI hardware.

### `packet_writer.sv`

Builds fixed-size DMA packets. It accepts asynchronous frame-done pulses from the ICM and Intan readers, stores completed Intan frames in an internal byte FIFO, and starts a packet when:

- An ICM frame is pending.
- A full packet worth of FIFO space is available.
- No previous output word is waiting.

At packet start it snapshots the number of complete Intan frames currently available, then streams:

1. The snapshotted Intan frames.
2. The ICM frame.
3. Zero padding through byte offset `PACKET_TRAILER_OFFSET_BYTES`.
4. A 256 byte metadata trailer.

Important implementation details:

- The Intan byte FIFO is marked as distributed RAM so the combinational read model matches synthesis.
- The 1024-bit output word is built with a shift-register packer instead of a dynamic byte-lane part-select.
- The trailer is generated by a combinational byte serializer rather than by writing many bytes into an unpacked memory or relying on packed-struct byte slicing.

Those choices avoid Vivado synthesis pitfalls that can otherwise pass behavioral simulation while corrupting byte lanes or trailer fields in hardware.

### `packet_buffer.sv`

Synchronous BRAM FIFO for full packet words. It stores `DATA_WIDTH`-bit words and tracks the exact word count. In addition to ordinary `empty` and `full`, it reports:

- `packet_space`: at least one complete packet can still be written.
- `packet_available`: at least one complete packet is ready to be read.

The complete-packet signals prevent AXI streaming from starting before the writer has committed a whole fixed-size packet.

### `packet_to_axis.sv`

Reads complete packets out of `packet_buffer` and drives an AXI4-Stream master interface. Because the FIFO has synchronous read latency, the state machine explicitly requests a word, waits for the read data, captures it, then presents it with `m_axis_tvalid`. It asserts `m_axis_tlast` on the final packet word and sets `m_axis_tkeep` from `PACKET_LAST_BYTES`.

### `SPI_mux.sv`

Arbitrates the physical ICM SPI bus between:

- The acquisition `ICM_reader`.
- The AXI Quad SPI core controlled by software.

When `axi_enable` is asserted and the acquisition reader is not busy, the external bus is driven by the AXI SPI signals. Otherwise, the acquisition reader owns the bus. The AXI path sees only `spi_miso[0]`; the acquisition path receives all configured MISO lines.

### `axil_regs.v`

Thin wrapper around the generated/custom AXI4-Lite slave implementation. It exposes friendly signal names to `ctrlsys_core` and instantiates `axil_regs_slave_lite_v1_0_S00_AXI`.

### `axil_regs_slave_lite_v1_0_S00_AXI.v`

AXI4-Lite slave register file. It accepts independent AW and W handshakes, supports byte strobes for writable registers, emits one-cycle command pulses, and multiplexes status/debug registers onto the read data bus. It implements the register map documented above.

## HDL Tests

### `source/tests/hdl/packet_path_layout_tb.sv`

End-to-end packet-path regression for:

```text
packet_writer -> packet_buffer -> packet_to_axis
```

It creates deterministic Intan and ICM frames, captures the AXI stream bytes, and checks packet length, FIFO errors, trailer magic, trailer size, packet size, and trailer start offset.

Run:

```powershell
vivado -mode batch -source source/scripts/run_packet_path_layout_tb.tcl
```

Expected:

```text
PASS packet_path_layout_tb
```

### `source/tests/hdl/packet_to_axis_packet_available_tb.sv`

Regression for complete-packet gating. It verifies that `packet_to_axis` does not begin streaming just because the FIFO is nonempty; it waits for `packet_available`, meaning a full fixed-size packet has been written.

### `source/tests/hdl/SPI_path_tb.sv`

SPI path testbench for basic bus/read behavior with a small sensor count and short data payload. Useful for checking SPI timing and muxed readback behavior independently of the full packet path.

## Vivado Build Flow

Run these from the repository root in a shell with Vivado on `PATH`.

Check RTL elaboration:

```powershell
vivado -mode batch -source source/scripts/check_hdl.tcl
```

Run packet layout simulation:

```powershell
vivado -mode batch -source source/scripts/run_packet_path_layout_tb.tcl
```

Repackage the custom IP:

```powershell
vivado -mode batch -source source/scripts/repackage_ctrlsys_core_ip.tcl
```

Rebuild the Vivado bitstream:

```powershell
vivado -mode batch -source source/scripts/rebuild_bitstream.tcl
```

Convert the `.bit` to a Red Pitaya-friendly `.bit.bin`:

```powershell
vivado -mode batch -source source/scripts/bit2bin-bit.tcl
```

Primary generated artifacts:

```text
build/design_1_wrapper.bit
build/design_1_wrapper.bit.bin
```

## Vivado Helper Scripts

| Script | Purpose |
| --- | --- |
| `source/scripts/check_hdl.tcl` | Creates an in-memory project, reads RTL, and runs `synth_design -rtl` on `ctrlsys_core`. |
| `source/scripts/run_packet_path_layout_tb.tcl` | Creates a temporary simulation project and runs the packet path regression. |
| `source/scripts/repackage_ctrlsys_core_ip.tcl` | Rebuilds `IP/ctrlsys_core` from the current RTL and configures Vivado IP metadata. |
| `source/scripts/rebuild_bitstream.tcl` | Opens the Vivado project, refreshes the custom IP, reruns synthesis/implementation, writes the bitstream, and copies it into `build`. |
| `source/scripts/bit2bin-bit.tcl` | Uses `bootgen` to convert the newest bitstream into `.bit.bin` for Red Pitaya loading. |
| `source/scripts/generate_constraints.tcl` | Generates or updates project-level board constraints. |
| `source/scripts/set_axi_spi_clock.tcl` | Utility for AXI Quad SPI clock configuration. |
| `source/scripts/check_synth_util.tcl` | Utility script for synthesis utilization checks. |
| `source/scripts/check_packet_buffer_util.tcl` | Utility script focused on packet-buffer resource use. |

## Red Pitaya Software

The Red Pitaya userspace programs live under `source/cpp/redpitaya`.

Compile the current end-to-end test directly from source on the Red Pitaya:

```sh
cd source/cpp/redpitaya
gcc -O2 -Wall -Wextra -Wpedantic -std=c11 \
    -o intan8_icm4_dma_interrupt_test \
    intan8_icm4_dma_interrupt_test.c sensor_test_hw.c
```

Other test binaries can be compiled the same way:

```sh
gcc -O2 -Wall -Wextra -Wpedantic -std=c11 \
    -o single_sensor_test single_sensor_test.c sensor_test_hw.c

gcc -O2 -Wall -Wextra -Wpedantic -std=c11 \
    -o dma_interrupt_test dma_interrupt_test.c sensor_test_hw.c

gcc -O2 -Wall -Wextra -Wpedantic -std=c11 \
    -o ICM_Intan_test ICM_Intan_test.c sensor_test_hw.c
```

Important files:

| File | Purpose |
| --- | --- |
| `sensor_test_hw.c/.h` | Common low-level helpers for `/dev/mem`, AXI-Lite registers, AXI DMA, UIO interrupts, TCP streaming, ICM initialization, and DMA buffer setup. |
| `intan8_icm4_dma_interrupt_test.c` | Main current end-to-end test for 8 synthetic Intan channels + 4 ICM channels. Streams fixed-size 24,576 byte DMA packets over TCP. |
| `single_sensor_test.c` | Older/smaller single ICM bring-up test that can compare AXI-Lite data and DMA data. |
| `dma_interrupt_test.c` | DMA interrupt test harness. |
| `ICM_Intan_test.c` | ICM + Intan oriented test harness. |

Typical current run on the Red Pitaya:

```sh
./intan8_icm4_dma_interrupt_test --phys 0x1000000 --count 0
```

The `--phys 0x1000000` address is commonly the Red Pitaya Deep Memory Mode reserved region. The program can also use `u-dma-buf` if configured.

## Desktop Python Tools

| File | Purpose |
| --- | --- |
| `source/python/redpitaya_dma_receiver.py` | TCP client that receives Red Pitaya DMA packets, reconstructs packet bytes from DMA words, decodes trailers/payloads, prints raw bytes, writes CSVs, and can plot timing. |
| `source/python/analyze_dma_csv.py` | Analyzes CSV captures for PC inter-arrival timing, FPGA timestamp interval, latency, read duration, and sequence/count anomalies. |
| `source/python/generate_packet_layout.py` | Generates an HTML/SVG visualization of packet layout from the SystemVerilog configuration. |

Trailer-only verification:

```powershell
python source/python/redpitaya_dma_receiver.py rp-f0f85a --count 100 --quiet --print-trailer --print-packets 100
```

Raw packet inspection:

```powershell
python source/python/redpitaya_dma_receiver.py rp-f0f85a --count 1 --quiet --print-raw-bytes --raw-bytes-per-line 128
```

Decoded payload spot check:

```powershell
python source/python/redpitaya_dma_receiver.py rp-f0f85a --count 1 --quiet --print-sensor-data
```

Long timing capture:

```powershell
python source/python/redpitaya_dma_receiver.py rp-f0f85a --count 10000 --quiet --csv build/dma_10k.csv
python source/python/analyze_dma_csv.py build/dma_10k.csv --expected-ms 1.0
```

## Validation Checklist

For the current synthetic-Intan setup, a healthy run should show:

- TCP receiver connects and selects DMA word byte order `little`.
- Packet sequence numbers increment by one.
- UIO interrupt count increments by one per packet.
- Core packet count increments by one per FPGA packet. If a desktop receiver connects to an already-running Red Pitaya process, the first reported IRQ may be nonzero.
- Trailer magic is `ff ff ff ff ff ff ff ff`.
- `trailer_bytes=256`.
- `packet_bytes=24576`.
- `trailer_offset=24320`.
- `frame_words=6144`.
- Steady-state `intan_frame_count` is usually 30.
- Occasional 31-frame packets are valid because `125000 / 30` is truncated to 4166 ticks, making the synthetic Intan schedule slightly faster than exactly 30 kHz.
- `icm_frame_count=1`.
- `dropped_intan=0`, `dropped_icm=0`, and `flags=0`.
- Intan offsets are multiples of 536.
- ICM offset equals `intan_frame_count * 536`.
- `valid_data_bytes` equals `intan_frame_count * 536 + 100`.
- Synthetic Intan frame 0 sensor IDs decode as physical order `[7, 6, 5, 4, 3, 2, 1, 0]`.

With only two physical ICM sensors connected and the other MISO pins floating, the disconnected ICM channels may decode as all `ff` or noisy-looking data. That is expected and should be judged separately from packet/trailer integrity.

## Device Tree and Constraints

`source/redpitaya` contains device tree overlay sources used to expose the DMA interrupt and memory-related resources to Linux:

| File | Purpose |
| --- | --- |
| `dma_irq_uio_overlay.dts` | UIO overlay for the DMA interrupt path. |
| `dtraw.dts` | Raw/device-tree bring-up source. |

`source/constraints/CtrlSysV4.xdc` contains project-level constraints, including board-specific pins and clocking. The custom IP package intentionally avoids board pin constraints; those stay in the Vivado project.

## Common Bring-Up Sequence

1. Rebuild and upload `build/design_1_wrapper.bit.bin` to the Red Pitaya.
2. Compile the Red Pitaya C test program directly with `gcc`.
3. Start the Red Pitaya interrupt DMA streamer.
4. Start the desktop Python receiver.
5. Verify trailers with `--print-trailer`.
6. Spot-check synthetic Intan payload with `--print-sensor-data`.
7. Run a long CSV capture and analyze timing/anomalies.

Example:

```sh
# Red Pitaya
cd ~/gordo/cpp
./intan8_icm4_dma_interrupt_test --phys 0x1000000 --count 0
```

```powershell
# Desktop
python source/python/redpitaya_dma_receiver.py rp-f0f85a --count 100 --quiet --print-trailer --print-packets 100
python source/python/redpitaya_dma_receiver.py rp-f0f85a --count 10000 --quiet --csv build/dma_10k.csv
python source/python/analyze_dma_csv.py build/dma_10k.csv --expected-ms 1.0
```

## Notes on Synthesis-Safe Packet Construction

This project relies on exact byte ordering. A few implementation patterns are intentionally conservative:

- Avoid packed-struct trailer serialization in synthesized packet output logic.
- Avoid bulk writes to an unpacked trailer byte memory in one clock.
- Avoid variable byte-lane writes into a 1024-bit output word.
- Use a combinational trailer byte serializer and a shift-register output packer.
- Wait for a complete packet in `packet_buffer` before `packet_to_axis` begins streaming.

These choices are important because some dynamic part-select and inferred-memory patterns can pass behavioral simulation while producing incorrect packet bytes in hardware.
