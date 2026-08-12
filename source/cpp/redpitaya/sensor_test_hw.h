#ifndef SENSOR_TEST_HW_H
#define SENSOR_TEST_HW_H

#include <stddef.h>
#include <stdint.h>

#define SENSOR_TEST_DEFAULT_UDMABUF "/dev/udmabuf0"
#define SENSOR_TEST_DEFAULT_UIO "/dev/uio/api"
#define SENSOR_TEST_SAMPLE_CLOCK_HZ 125000000u
#define SENSOR_TEST_1MS_TICKS (SENSOR_TEST_SAMPLE_CLOCK_HZ / 1000u)
#define SENSOR_TEST_FRAME_WORDS 9u
#define SENSOR_TEST_INTAN8_ICM4_PACKET_BYTES 24576u
#define SENSOR_TEST_INTAN8_ICM4_PACKET_WORDS 6144u
#define SENSOR_TEST_ICM_INTAN_PACKET_BYTES SENSOR_TEST_INTAN8_ICM4_PACKET_BYTES
#define SENSOR_TEST_ICM_INTAN_PACKET_WORDS SENSOR_TEST_INTAN8_ICM4_PACKET_WORDS
#define SENSOR_TEST_NUM_INTAN 8u
#define SENSOR_TEST_INTAN_CHANNELS 64u
#define SENSOR_TEST_INTAN_BITS_PER_SAMPLE 16u
#define SENSOR_TEST_INTAN_SAMPLING_RATIO 2u
#define SENSOR_TEST_INTAN_DATA_BYTES                                           \
  (SENSOR_TEST_INTAN_CHANNELS * SENSOR_TEST_INTAN_BITS_PER_SAMPLE / 8u)
#define SENSOR_TEST_INTAN_MEASUREMENT_BYTES (1u + SENSOR_TEST_INTAN_DATA_BYTES)
#define SENSOR_TEST_INTAN_FRAME_BYTES                                          \
  (16u + SENSOR_TEST_NUM_INTAN * SENSOR_TEST_INTAN_MEASUREMENT_BYTES)
#define SENSOR_TEST_NUM_ICM 4u
#define SENSOR_TEST_ICM_DATA_BYTES 20u
#define SENSOR_TEST_ICM_MEASUREMENT_BYTES (1u + SENSOR_TEST_ICM_DATA_BYTES)
#define SENSOR_TEST_ICM_FRAME_BYTES                                            \
  (16u + SENSOR_TEST_NUM_ICM * SENSOR_TEST_ICM_MEASUREMENT_BYTES)
#define SENSOR_TEST_PACKET_TRAILER_BYTES 256u
#define SENSOR_TEST_PACKET_TRAILER_OFFSET                                      \
  (SENSOR_TEST_INTAN8_ICM4_PACKET_BYTES - SENSOR_TEST_PACKET_TRAILER_BYTES)
#define SENSOR_TEST_PACKET_INTAN_OFFSET_COUNT 48u
#define SENSOR_TEST_MAX_INTAN_FRAMES_PER_PACKET 23u
#define SENSOR_TEST_EXPECTED_INTAN_FRAMES_PER_PACKET                           \
  SENSOR_TEST_INTAN_SAMPLING_RATIO

#define SENSOR_TEST_CORE_CONTROL 0x00u
#define SENSOR_TEST_CORE_PERIOD 0x04u
#define SENSOR_TEST_CORE_MISSED_INTAN 0x08u
#define SENSOR_TEST_CORE_COMMAND 0x0cu
#define SENSOR_TEST_CORE_STATUS 0x10u
#define SENSOR_TEST_CORE_COUNT 0x14u
#define SENSOR_TEST_CORE_MISSED_ICM 0x18u
#define SENSOR_TEST_CORE_ERROR 0x1cu
#define SENSOR_TEST_CORE_DATA0 0x20u

#define SENSOR_TEST_CONTROL_ENABLE (1u << 0)
#define SENSOR_TEST_CONTROL_RESET (1u << 1)
#define SENSOR_TEST_CONTROL_USE_AXI (1u << 2)
#define SENSOR_TEST_COMMAND_CLEAR_ERROR (1u << 0)
#define SENSOR_TEST_COMMAND_RESET_SAMPLE_COUNT (1u << 1)
#define SENSOR_TEST_COMMAND_CLEAR_PACKET_IRQ (1u << 2)

#define SENSOR_TEST_STATUS_BUSY (1u << 0)
#define SENSOR_TEST_STATUS_ERROR (1u << 1)
#define SENSOR_TEST_STATUS_READ_IN_PROGRESS (1u << 2)
#define SENSOR_TEST_STATUS_PACKET_DONE (1u << 3)
#define SENSOR_TEST_STATUS_INTAN_INITIALIZED (1u << 8)
#define SENSOR_TEST_STATUS_INTAN_BUSY (1u << 9)
#define SENSOR_TEST_STATUS_INTAN_INIT_ERROR (1u << 10)
#define SENSOR_TEST_STATUS_ACQUISITION_ACTIVE (1u << 11)
#define SENSOR_TEST_STATUS_FIFO_OVERFLOW (1u << 12)
#define SENSOR_TEST_STATUS_FIFO_UNDERFLOW (1u << 13)
#define SENSOR_TEST_STATUS_MISSED_INTAN (1u << 14)
#define SENSOR_TEST_STATUS_MISSED_ICM (1u << 15)

#define SENSOR_TEST_ERROR_FIFO_OVERFLOW (1u << 0)
#define SENSOR_TEST_ERROR_FIFO_UNDERFLOW (1u << 1)
#define SENSOR_TEST_ERROR_INTAN_INIT (1u << 2)
#define SENSOR_TEST_ERROR_MISSED_INTAN (1u << 3)
#define SENSOR_TEST_ERROR_MISSED_ICM (1u << 4)
#define SENSOR_TEST_TCP_MAGIC 0x4353444du /* "CSDM" */
#define SENSOR_TEST_TCP_VERSION 1u

typedef struct sensor_test sensor_test_t;

int sensor_test_open(sensor_test_t **test);
int sensor_test_initialize_icm20948(sensor_test_t *test);
int sensor_test_prepare_dma_udmabuf(sensor_test_t *test, const char *device);
int sensor_test_prepare_dma_reserved(sensor_test_t *test,
                                     uint64_t physical_address);
int sensor_test_prepare_dma_udmabuf_sized(sensor_test_t *test,
                                          const char *device,
                                          size_t required_bytes);
int sensor_test_prepare_dma_reserved_sized(sensor_test_t *test,
                                           uint64_t physical_address,
                                           size_t required_bytes);
int sensor_test_run_axil_only(sensor_test_t *test);
int sensor_test_run_dma(sensor_test_t *test);
int sensor_test_run_dma_interrupts(sensor_test_t *test, const char *uio_device,
                                   unsigned transfer_count,
                                   uint32_t sample_period_ticks, int stream_fd,
                                   int print_frames);
int sensor_test_run_dma_interrupts_sized(sensor_test_t *test,
                                         const char *uio_device,
                                         unsigned transfer_count,
                                         uint32_t sample_period_ticks,
                                         int stream_fd, int print_frames,
                                         size_t transfer_bytes);
void sensor_test_close(sensor_test_t *test);

#endif
