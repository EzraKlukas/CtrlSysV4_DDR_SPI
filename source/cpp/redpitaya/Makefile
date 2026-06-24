CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra -Wpedantic -std=c11

.PHONY: all clean

all: single_sensor_test dma_interrupt_test

single_sensor_test: single_sensor_test.c sensor_test_hw.c sensor_test_hw.h
	$(CC) $(CFLAGS) -o $@ single_sensor_test.c sensor_test_hw.c

dma_interrupt_test: dma_interrupt_test.c sensor_test_hw.c sensor_test_hw.h
	$(CC) $(CFLAGS) -o $@ dma_interrupt_test.c sensor_test_hw.c

clean:
	rm -f single_sensor_test dma_interrupt_test
