# CtrlSysV4 RHD2164 acquisition core

CtrlSysV4 acquires eight Intan RHD2164 sensors and four ICM sensors, assembles fixed-size packets, and presents those packets at an AXI4-Stream DMA boundary. Intan sample data never travels through AXI-Lite.

```text
RHD2164 pins
  -> intan_reader
       -> intan_acq_engine
       -> intan_cmd_sequencer
       -> intan_spi_word_engine
  -> packet_writer -> packet_buffer -> packet_to_axis -> AXI4-Stream S2MM DMA

AXI4-Lite -> control, status, counters, and debug words only
```

`source/hdl` is the RTL source of truth. Files under `IP/ctrlsys_core/src` are generated package copies and must not be used for lint or simulation. The checked-in package contains the updated interface as version 1.2.

## Production configuration

| Item | Value |
|---|---:|
| Fabric clock | 125 MHz |
| ICM base period | 125,000 ticks / 1 ms / approximately 1 kHz |
| `INTAN_SAMPLING_RATIO` | 2 |
| Intan period | 62,500 ticks / 0.5 ms / approximately 2 kHz |
| Intan SPI half-period divider | 25 fabric clocks |
| Intan SCLK | 2.5 MHz |
| Intan CS setup / hold | 25 clocks / 200 ns each |
| Intan CS-high time | 20 clocks / 160 ns |
| AXI stream width | 64 bits / 8 bytes |
| Fixed packet | 24,576 bytes / 3,072 AXI beats |
| Trailer | 256 bytes at byte 24,320 (`0x5f00`) |

The 2.5 MHz SCLK is intentionally conservative for initial hardware operation. Testbenches may override the divider to reduce simulation time. SPI activity is synchronous to `clk`; changing the fabric clock without recalculating these integer timing constants changes the physical bus timing.

## Intan program and reader contract

[`source/hdl/intan_program.sv`](source/hdl/intan_program.sv) contains the static production initialization program, expected A/B responses for every sensor, and the 32-command acquisition program. The response sequencer sends two extra words to flush the RHD2164 two-command pipeline. The command and response ports remain packed multidimensional arrays and are indexed directly by command and sensor.

`intan_reader` is a wiring wrapper only; its state lives in the three modules shown above. Its status contract is:

- `initialized`: level; high only after an initialization response set matches.
- `init_done_pulse`: one `clk` cycle after successful initialization only.
- `frame_done_pulse`: one `clk` cycle after a complete acquisition frame has already been registered.
- `busy`: level while an initialization or acquisition command sequence is active.
- `error`: level after a failed initialization; cleared when a new initialization attempt is accepted.

Reads before initialization and requests while busy are ignored. Failed initialization cannot produce `frame_done_pulse`. `ctrlsys_core` connects only `frame_done_pulse` to `packet_writer`, so initialization cannot enqueue an empty sample frame.

The physical top-level Intan interface is shared `intan_sclk`, shared `intan_mosi`, shared active-low `intan_cs_n`, and `intan_miso[7:0]` with one return line per sensor. No physical pin assignment is specified in this repository checkpoint.

## Acquisition scheduling

The scheduler requests initialization with a one-cycle pulse whenever the Intan subsystem is uninitialized and idle. It waits for an attempt to become busy and, after a failure, emits a fresh retry pulse rather than holding a level-sensitive start.

Acquisition is active only when `enable && intan_initialized`. This effective condition is edge-detected. If software enables acquisition while initialization is still running, successful initialization anchors both schedules at the current timestamp and issues the first eligible ICM and Intan reads. ICM reads are never requested while the ICM reader is busy; Intan reads are issued only while initialized and idle.

For an on-time read, the next deadline advances from the previous scheduled timestamp, preserving ideal-time scheduling. A deadline encountered while its reader is busy increments that reader's missed counter and re-anchors at the current timestamp. A reader that is idle but at least two periods late also records one miss, issues one current read, and re-anchors. In either case the controller does not burst stale reads to catch up. A zero period disables periodic deadlines.

## Frame and packet format

All scalar fields and packed payload fields are serialized most-significant byte first. Within the packed `Intan_frame_t`, physical sensor records appear in descending packed-index order (sensor ID 7 first through ID 0). Within each sensor payload, channel 63 appears first and channel 0 last in the byte stream. Host decoding restores logical channel numbering.

Response A maps to channels 0–31 and response B to channels 32–63. Every assignment includes the sensor index. Each channel is one unsigned 16-bit sample in the byte stream.

| Structure | Composition | Bytes |
|---|---|---:|
| Intan measurement | 1 sensor-ID byte + 64 x 2 sample bytes | 129 |
| Intan frame | 8-byte start timestamp + 8-byte done timestamp + 8 measurements | 1,048 |
| ICM measurement | 1 sensor-ID byte + 20 data bytes | 21 |
| ICM frame | 16 timestamp bytes + 4 measurements | 100 |

An ICM completion closes a packet. The packet contains every complete buffered Intan frame included in that snapshot, then one ICM frame, zero padding to byte 24,319, and the 256-byte trailer. At the nominal 2:1 cadence a steady packet normally has two Intan frames, but that expectation is not the physical capacity.

The capacity is derived independently:

```text
floor((24320 data bytes - 100 ICM bytes) / 1048 Intan bytes) = 23 Intan frames
```

The trailer uses big-endian 32-bit fields:

| Trailer offset | Bytes | Field |
|---:|---:|---|
| `0x00` | 8 | all-ones magic |
| `0x08` | 4 | packet number |
| `0x0c` | 4 | trailer bytes, 256 |
| `0x10` | 4 | packet bytes, 24,576 |
| `0x14` | 4 | valid data bytes: `intan_count * 1048 + 100` |
| `0x18` | 4 | included Intan frame count |
| `0x1c` | 4 | maximum Intan frame count, 23 |
| `0x20` | 4 | ICM frame count, normally 1 |
| `0x24` | 4 | ICM start byte: `intan_count * 1048` |
| `0x28` | 4 | trailer start byte, 24,320 |
| `0x2c` | 4 | flags: bit 0 dropped Intan, bit 1 dropped ICM, bit 2 capacity reached |
| `0x30` | 4 | dropped Intan frames since the prior packet snapshot |
| `0x34` | 4 | dropped ICM frames since the prior packet snapshot |
| `0x38` | 192 | 48 Intan start offsets; used entries are `index * 1048` |
| `0xf8` | 8 | reserved, zero |

The fixed packet size is aligned to the 8-byte AXI word. Consequently all eight `tkeep` bits are asserted on every one of the 3,072 beats, and `tlast` is asserted only on the final beat at index 3,071. `packet_to_axis` holds `tvalid`, `tdata`, `tkeep`, and `tlast` stable during backpressure.

## AXI4-Lite register map

AXI4-Lite is control/status only. Reset leaves acquisition disabled and sets the ICM base period to 125,000 ticks. Initialization is independent of `enable`, allowing software to wait for the sensors before arming DMA.

| Address | Access | Definition |
|---:|:---:|---|
| `0x00` | R/W | control: bit 0 enable, bit 1 synchronous core soft reset, bit 2 route ICM pins to AXI SPI while the hardware reader is idle |
| `0x04` | R/W | ICM base period in 125 MHz ticks; Intan period is this value divided by 2 |
| `0x08` | R | missed Intan opportunity count |
| `0x0c` | W | one-cycle commands: bit 0 clear error latch/mask, bit 1 reset packet/sample count, bit 2 clear packet-done IRQ latch |
| `0x10` | R | status bitmask described below |
| `0x14` | R | completed packet count |
| `0x18` | R | missed ICM opportunity count |
| `0x1c` | R | sticky error bitmask described below |
| `0x20` | R | packet-completion debug word 0: prior packet count |
| `0x24` | R | debug word 1: packet AXI words, 3,072 |
| `0x28` | R | debug word 2: packet-buffer depth in AXI words |
| `0x2c` | R | debug word 3: ICM start timestamp low word |
| `0x30` | R | debug word 4: ICM start timestamp high word |
| `0x34` | R | debug word 5: ICM done timestamp low word |
| `0x38` | R | debug word 6: ICM done timestamp high word |
| `0x3c` | R | debug word 7: packet bytes, 24,576 |

Status at `0x10` preserves the original low bits:

| Bit | Meaning |
|---:|---|
| 0 | aggregate busy (`ICM busy || Intan busy`) |
| 1 | sticky error latch |
| 2 | aggregate read in progress |
| 3 | sticky packet completion/IRQ |
| 4 | AXI-SPI routing requested; it becomes effective when the ICM reader is idle |
| 5 | ICM hardware reader busy |
| 8 | Intan initialized |
| 9 | Intan busy |
| 10 | sticky Intan initialization error |
| 11 | acquisition active (`enable && initialized`) |
| 12 | sticky packet FIFO overflow |
| 13 | sticky packet FIFO underflow |
| 14 | missed Intan counter is nonzero |
| 15 | missed ICM counter is nonzero |

`error_code` at `0x1c` is a sticky ORed bitmask, not a numeric last-error code:

| Bit | Meaning |
|---:|---|
| 0 | packet FIFO overflow |
| 1 | packet FIFO underflow |
| 2 | Intan initialization failure |
| 3 | missed Intan opportunity |
| 4 | missed ICM opportunity |

Writing command bit 0 clears the stored error mask deterministically, except for a fault that is still active on that same clock. Missed counters clear on core reset; clearing the error mask does not erase their history.

Deasserting acquisition enable holds the packet writer, packet FIFO, and AXI-stream adapter in reset, so stopping in the middle of packet construction cannot leave a partial packet queued for a later run. Intan initialization remains active while this data path is reset.

The current design assumes `clk` and `s00_axi_aclk` are the same fabric clock, as in the existing integration. Do not connect them to unrelated clocks without adding and verifying CDC handling.

## Host tools and DMA lifecycle

`source/cpp/redpitaya/sensor_test_hw.[ch]` defines the register, status, error, frame, and packet constants. The packet-sized interrupt path resets/configures the core once, waits up to two seconds for Intan initialization, resets and starts S2MM once, arms one 24,576-byte transfer, and then enables acquisition once. After each completion, the DMA mapping is synchronized for CPU access and copied before the live buffer is promptly rearmed. Validation, streaming, and printing use the completed copy, never the rearmed DMA buffer. The core and DMA are disabled only on stop or error recovery.

`source/python/redpitaya_dma_receiver.py` validates the fixed trailer and offsets and decodes all 64 big-endian 16-bit channels for each sensor. DMA word byte order may still depend on the processor/DMA capture path; the receiver's existing byte-order scoring remains available for that boundary. `source/python/generate_packet_layout.py` derives Intan sizes from `INTAN_BITS_PER_WORD` and `INTAN_CHANNELS`.

## Verification

The self-checking SystemVerilog tests are in `source/tests/hdl`, with the behavioral RHD2164 model in `source/tests/models`. They cover SPI timing at the model's 12 ns MISO delay, two-command pipeline flushing, static program contents, initialization success/failure/retry, pulse contracts, scheduling/missed deadlines, full 8 x 64 channel packing, repeated frames, packet layout, FIFO-to-AXI transfer, backpressure, `tkeep`, `tlast`, and the complete core through the AXI4-Stream boundary.

Run the complete open-source regression with:

```sh
bash source/scripts/run_verilator_regression.sh
```

Vivado behavioral regressions, when Vivado is installed:

```sh
vivado -mode batch -source source/scripts/run_packet_path_layout_tb.tcl
vivado -mode batch -source source/scripts/run_integrate_intan_packet_path_layout_tb.tcl
vivado -mode batch -source source/scripts/run_ctrlsys_core_tb.tcl
```

The full-core test uses AXI-Lite BFM tasks and eight RHD2164 models and stops at AXI4-Stream; it does not instantiate Xilinx DMA. `check_hdl.tcl` and `check_synth_util.tcl` contain `synth_design` and are intentionally not part of the pre-synthesis regression commands.

Host-side checks:

```sh
python3 -m py_compile source/python/analyze_dma_csv.py \
  source/python/generate_packet_layout.py source/python/redpitaya_dma_receiver.py
gcc -std=c11 -Wall -Wextra -Wpedantic -fsyntax-only source/cpp/redpitaya/*.c
```

## Remaining board-integration work

The following steps are deliberately user-owned and have not been run here:

1. Run `repackage_ctrlsys_core_ip.tcl` under licensed Vivado 2026.1 to generate and validate `user.org:user:ctrlsys_core:1.2` from `source/hdl`.
2. Refresh the IP catalog and upgrade/replace the block-design core instance; reconnect its incompatible 64-bit `m_axis` interface.
3. Expose and connect the external shared Intan SCLK/MOSI/CS and eight individual MISO nets.
4. Add board-specific XDC package-pin and electrical constraints; no pin assignments are invented here.
5. Confirm the block design supplies the same 125 MHz clock to `clk` and AXI-Lite, or address CDC explicitly if that is changed.
6. Run synthesis, inspect inferred memory/resources, close timing, implement, and generate the bitstream.
7. Bring up one sensor first, verify physical SPI timing/signal integrity, then expand to all sensors and validate sustained DMA operation.
