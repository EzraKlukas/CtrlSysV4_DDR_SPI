#include "sensor_test_hw.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void usage(const char *program)
{
    fprintf(stderr,
            "Usage: %s [--no-dma | --udmabuf /dev/udmabuf0 | "
            "--phys RESERVED_ADDRESS]\n",
            program);
}

int main(int argc, char **argv)
{
    const char *udmabuf = SENSOR_TEST_DEFAULT_UDMABUF;
    uint64_t reserved_address = 0;
    int use_reserved = 0;
    int no_dma = 0;
    int result = EXIT_FAILURE;
    sensor_test_t *test = NULL;

    if (argc == 2 && strcmp(argv[1], "--no-dma") == 0) {
        no_dma = 1;
    } else if (argc == 3 && strcmp(argv[1], "--udmabuf") == 0) {
        udmabuf = argv[2];
    } else if (argc == 3 && strcmp(argv[1], "--phys") == 0) {
        char *end;
        reserved_address = strtoull(argv[2], &end, 0);
        if (*argv[2] == '\0' || *end != '\0' || (reserved_address & 3u)) {
            usage(argv[0]);
            return EXIT_FAILURE;
        }
        use_reserved = 1;
    } else if (argc != 1) {
        usage(argv[0]);
        return EXIT_FAILURE;
    }

    if (sensor_test_open(&test) != 0 ||
        sensor_test_initialize_icm20948(test) != 0)
        goto cleanup;

    if (no_dma) {
        result = sensor_test_run_axil_only(test) == 0 ? EXIT_SUCCESS
                                                     : EXIT_FAILURE;
        goto cleanup;
    }

    if (use_reserved) {
        if (sensor_test_prepare_dma_reserved(test, reserved_address) != 0)
            goto cleanup;
    } else if (sensor_test_prepare_dma_udmabuf(test, udmabuf) != 0) {
        goto cleanup;
    }

    result = sensor_test_run_dma(test) == 0 ? EXIT_SUCCESS : EXIT_FAILURE;

cleanup:
    sensor_test_close(test);
    return result;
}
