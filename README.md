# CtrlSysV4 capstone handoff

CtrlSysV4 is a Red Pitaya FPGA project for reading ICM-20948 motion sensors and Intan RHD2164 acquisition chips. The FPGA collects samples, packs them, and sends them to the Red Pitaya processor using direct memory access (DMA). A program on the Red Pitaya can forward the packets to a desktop over TCP.

For your feature, start with the working bitstream supplied separately on the Red Pitaya. Use it to establish a baseline before building or loading a modified FPGA image.

## Status at handoff

- **Intan sensors.** The Intan interface is unfinished. During bench bring-up, we reliably initialized and communicated with the connected RHD2164 hardware at a **2 kHz acquisition cadence** (one read every 0.5 ms). The checked-in design uses a 2.5 MHz SPI clock and enables Intan sensor 0. The packet format has slots for eight sensors. Bring-up across all eight inputs and sustained sampling through DMA and TCP with physical Intan data remain to be validated.
- **Gordon Zhao’s acquisition and streaming baseline.** Gordon brought up the ICM-20948 SPI read path and the FPGA-to-processor DMA and desktop TCP path using synthetic Intan frames. His 64-bit AXI4-Stream packet path, fixed 24,576-byte packets with a metadata trailer, and Red Pitaya and Python capture tools are the foundation of this branch. His last upstream snapshot is `2915e13`, merged here in `f5a574a`. The repository also includes a [100,000-packet desktop timing capture](build/test_100000.csv) from the earlier development stage.
- **FPGA integration.** The checked-in Vivado project already wires the custom core to DMA and exposes the sensor ports. The [board constraints](source/constraints/CtrlSysV4.xdc) define the FPGA pins and electrical settings. The design uses a 125 MHz fabric clock, with a default 1 kHz ICM cadence and 2 kHz Intan cadence.

## Get started

1. Start from the branch shared with your team. If you have write access, create a feature branch from that checkout with `git switch -c capstone/your-feature`. If you use a fork, make the feature branch from the same handoff revision in your fork.
2. Record the filename or build ID of the bitstream supplied with the Red Pitaya and use the host tools from the matching source revision. The FPGA source baseline for this handoff is `b1484c9`. The bitstreams already checked into `build/` are older artifacts.
3. Follow the [Red Pitaya bring-up guide](source/cpp/redpitaya/README.md) to run a short board-only DMA test and, if your feature uses the desktop stream, a short TCP capture. Save the command lines, a decoded trailer, and any status or error output so you can compare against them after changes.

## Find the code for your feature

| If your feature touches… | Start here |
| --- | --- |
| Desktop capture or analysis | [Python receiver](source/python/redpitaya_dma_receiver.py) and [CSV timing analysis](source/python/analyze_dma_csv.py) |
| Red Pitaya userspace, interrupts, or DMA | [Sensor and DMA helpers](source/cpp/redpitaya/sensor_test_hw.c) and [combined capture program](source/cpp/redpitaya/intan8_icm4_dma_interrupt_test.c). The program uses Linux UIO to receive DMA completion interrupts. |
| Packet contents or FPGA streaming | [Frame and packet types](source/hdl/config_pkg.sv), [packet writer](source/hdl/packet_writer.sv), [packet FIFO](source/hdl/packet_buffer.sv), and [AXI4-Stream adapter](source/hdl/packet_to_axis.sv) |
| IP integration and board wiring | [Top-level RTL](source/hdl/ctrlsys_core.sv), [Vivado block design](Vivado_CtrlSysV5_2026_1/Vivado_CtrlSysV5_2026_1.srcs/sources_1/bd/design_1/design_1.bd), and [pin constraints](source/constraints/CtrlSysV4.xdc) |
| Sampling schedules or sensor SPI | [Acquisition controller](source/hdl/acquisition_controller.sv), [ICM reader](source/hdl/ICM_reader.sv), [Intan reader](source/hdl/intan_reader.sv), and [Intan command program](source/hdl/intan_program.sv) |

The [acquisition reference](docs/acquisition-reference.md) gives the packet and register maps, the Intan initialization diagnostics, and the testbench commands. The register interface (AXI4-Lite) handles settings and status. Sample bytes travel through the separate DMA path.

For host-only work, you can use the supplied FPGA image. For RTL work, edit `source/hdl/` and run the simulation suite from the repository root. Vivado uses generated copies in `IP/ctrlsys_core/`.

```sh
bash source/scripts/run_verilator_regression.sh
```

To build a new FPGA image, use Vivado 2026.1 from a clean, committed checkout. The [build script](source/scripts/build_redpitaya_bitstream.tcl) repackages the core, regenerates the Vivado block design products, implements the design, and checks routed setup and hold timing.

```sh
vivado -mode batch -source source/scripts/build_redpitaya_bitstream.tcl -tclargs -jobs 4
```

The script writes the `.bit`, Red Pitaya `.bit.bin`, timing reports, and a manifest with the source commit and artifact checksums under `build/deploy/`.

## Where to resume Intan work

1. Establish a repeatable sensor-0 baseline. Check initialization and capture the first failed response, if any, using the [AXI4-Lite diagnostic page](docs/acquisition-reference.md#axi4-lite-register-map). If a mismatch repeats, compare its command index and actual and expected words against a scope or logic-analyzer trace.
2. Enable additional sensors using `INTAN_MASK` as hardware becomes available. Verify each return line and repeat initialization and read checks at the target cadence.
3. Run a sustained capture with physical sensors and check the Intan read-start timestamps, packet sequence and trailer fields, and the FPGA missed-read and dropped-frame counters. Use FPGA timestamps to measure the sensor cadence and desktop arrival times to measure delivery. The userspace DMA loop is driven by Linux interrupt scheduling and can block on TCP or console output.
