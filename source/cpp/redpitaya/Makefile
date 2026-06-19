CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra -Wpedantic -std=c11

.PHONY: all clean

all: single_sensor_test

single_sensor_test: single_sensor_test.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f single_sensor_test
