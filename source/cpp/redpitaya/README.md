# Red Pitaya bring-up

Start with the working bitstream supplied with the board and a checkout of the matching host tools. These steps are for the combined CtrlSys image described in the [capstone handoff](../../../README.md). The image uses 24,576-byte DMA packets and expects the CtrlSys registers at `0x40000000`, AXI DMA at `0x40400000`, and AXI Quad SPI at `0x41e00000`.

## Board-only DMA check

From the repository checkout on the Red Pitaya, build the combined test.

```sh
make -C source/cpp/redpitaya intan8_icm4_dma_interrupt_test
```

The test needs root access for the hardware mappings, a Linux userspace I/O (UIO) device for DMA completion interrupts, and a DMA buffer. It defaults to `/dev/uio/api` and `/dev/udmabuf0`. If the UIO device is missing, check the board image and the [device-tree overlay source](../../redpitaya/dma_irq_uio_overlay.dts). Use `--uio` if the DMA interrupt device has a different path.

With the connected sensors and the supplied image, capture ten packets with TCP disabled.

```sh
sudo ./source/cpp/redpitaya/intan8_icm4_dma_interrupt_test --count 10 --no-tcp --quiet
```

If the board uses a different u-dma-buf device, pass `--udmabuf` with its path. On a board set up for reserved Deep Memory Mode, run `monitor -r` and pass the reported reserved-memory base with `--phys`. The program checks the address against the board's memory map before arming DMA.

The program configures the ICM, waits for Intan initialization, then enables acquisition. The short run exits successfully after receiving and validating ten packets. If it reports an Intan initialization timeout, save the diagnostic output and check the enabled MISO line against the [board constraints](../../constraints/CtrlSysV4.xdc). The [register map](../../../docs/acquisition-reference.md#axi4-lite-register-map) explains how to read the captured command index and response mismatch. If initialization succeeds but no packets arrive, check the DMA completion interrupt and UIO mapping.

## Desktop TCP check

On the Red Pitaya, repeat the test with TCP enabled. Include the same buffer and UIO options you used above. The board waits for a client on port 5000 before starting acquisition.

```sh
sudo ./source/cpp/redpitaya/intan8_icm4_dma_interrupt_test --count 100 --quiet
```

On the desktop, run the receiver from the repository root, substituting the board's hostname or IP address for `BOARD_HOST`.

```sh
python3 source/python/redpitaya_dma_receiver.py BOARD_HOST \
  --count 100 --quiet --print-trailer --csv capstone-baseline.csv
```

Check that the trailer validates, the packet sequence progresses, and the trailer's dropped-frame counts stay at zero. At the default cadence there is usually one ICM frame and two Intan frames per packet. The checked-in FPGA configuration fills the Intan sensor-0 slot from hardware and leaves the other sample slots zeroed. The receiver's `--print-sensor-data` option can display decoded samples. The CSV records desktop arrival times and ICM timestamps for comparing delivery with the FPGA's packet cadence.

The older `single_sensor_test` and `dma_interrupt_test` utilities target a legacy 36-byte ICM frame. Use the combined test above with the supplied CtrlSys image.
