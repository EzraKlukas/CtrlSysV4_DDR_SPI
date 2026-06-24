# Red Pitaya single-sensor test

This program tests one acquisition through both the CtrlSys AXI-Lite registers
and the AXI DMA S2MM path. It expects the current block-design addresses:

- CtrlSys core: `0x40000000`
- AXI DMA: `0x40400000`
- AXI Quad SPI: `0x41e00000`
- One streamed frame: 36 bytes

The DMA needs memory that is physically contiguous and unavailable to normal
Linux allocation. The default is `/dev/udmabuf0`; do not substitute a normal
`malloc` address.

Build and run as root:

```sh
make
sudo ./single_sensor_test
```

To test the sensor through AXI-Lite without configuring DMA or reserving RAM:

```sh
sudo ./single_sensor_test --no-dma
```

This waits for one SPI acquisition and reads the 20 sensor bytes from the
core's `data_word3` through `data_word7` registers. The completed-read
timestamp is not exposed in the AXI-Lite snapshot; it is present in the DMA
frame.

Before either test, the program uses AXI Quad SPI to select user bank 0 and
report the ICM-20948 `WHO_AM_I` value (normally `0xEA`). An unexpected value
produces a warning but does not stop the test. The program then resets and
wakes the device, disables its host I2C interface, and enables its
accelerometer and gyroscope.
The final six bytes of the 20-byte burst are external-sensor-data registers;
the program configures the ICM-20948 auxiliary I2C master to keep the internal
AK09916 magnetometer's `HXL` through `HZH` registers in those bytes.

To select another u-dma-buf device:

```sh
sudo ./single_sensor_test --udmabuf /dev/udmabuf1
```

If u-dma-buf is unavailable on a Red Pitaya image, first check the board's
existing Deep Memory Mode reserved region:

```sh
monitor -r
```

For the default 32 MiB region this reports a start address of `0x1000000`.
Use that address with `--phys`:

```sh
sudo ./single_sensor_test --phys 0x1000000
```

The program accepts a `--phys` address that is either outside `/proc/iomem`
System RAM or inside the Red Pitaya `monitor -r` reserved memory range.

As another bring-up option, reserve the top 16 MiB of the 512 MiB DDR by
changing the kernel boot argument from `mem=512M` to `mem=496M`, then reboot.
Confirm that Linux no longer owns that region:

```sh
cat /proc/cmdline
grep "System RAM" /proc/iomem
```

The command line must contain `mem=496M`, and System RAM must end at
`0x1effffff`. The test can then use the first address above Linux RAM:

```sh
sudo ./single_sensor_test --phys 0x1f000000
```

The program refuses a `--phys` address that still overlaps a System RAM range
unless Red Pitaya's `monitor -r` reports that address as reserved.

The program resets the core and DMA, arms one 36-byte S2MM transfer, performs
one SPI burst read beginning at ICM-20948 register `0x2D`, stops acquisition,
prints the timestamps and 20 sensor bytes, and verifies that the DMA data
matches the core's AXI-Lite snapshot.
