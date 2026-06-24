#!/usr/bin/env python3
"""Receive CtrlSys DMA samples from dma_interrupt_test over TCP."""

from __future__ import annotations

import argparse
import datetime as dt
import socket
import struct
import time


MAGIC = 0x4353444D  # "CSDM"
VERSION = 1
FRAME_WORDS = 9
PACKET_WORDS = 6 + FRAME_WORDS
PACKET_STRUCT = struct.Struct("!" + "I" * PACKET_WORDS)
SAMPLE_CLOCK_HZ = 125_000_000


def recv_exact(sock: socket.socket, length: int) -> bytes:
    chunks: list[bytes] = []
    remaining = length
    while remaining:
        chunk = sock.recv(remaining)
        if not chunk:
            raise EOFError("TCP connection closed")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def timestamp_text(epoch_ns: int) -> str:
    timestamp = dt.datetime.fromtimestamp(epoch_ns / 1_000_000_000).astimezone()
    return timestamp.isoformat(timespec="microseconds")


def sensor_bytes_from_frame(frame: tuple[int, ...]) -> bytes:
    data_words = frame[4:9]
    values = []
    for index in range(20):
        word = data_words[4 - index // 4]
        shift = (3 - index % 4) * 8
        values.append((word >> shift) & 0xFF)
    return bytes(values)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Receive timestamped CtrlSys DMA samples over TCP."
    )
    parser.add_argument("host", help="Red Pitaya hostname or IP address")
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--count", type=int, default=0,
                        help="number of packets to receive; 0 means forever")
    parser.add_argument("--raw-hex", action="store_true",
                        help="also print the 20 sensor bytes as hex")
    args = parser.parse_args()

    packet_size = PACKET_STRUCT.size
    first_perf_ns: int | None = None
    previous_perf_ns: int | None = None
    received = 0

    with socket.create_connection((args.host, args.port)) as sock:
        print(f"connected to {args.host}:{args.port}, packet_size={packet_size}")

        while args.count == 0 or received < args.count:
            payload = recv_exact(sock, packet_size)
            arrival_epoch_ns = time.time_ns()
            arrival_perf_ns = time.perf_counter_ns()

            if first_perf_ns is None:
                first_perf_ns = arrival_perf_ns
            delta_ms = 0.0 if previous_perf_ns is None else (
                arrival_perf_ns - previous_perf_ns
            ) / 1_000_000
            elapsed_ms = (arrival_perf_ns - first_perf_ns) / 1_000_000
            previous_perf_ns = arrival_perf_ns

            words = PACKET_STRUCT.unpack(payload)
            magic, version, sequence, irq_count, core_count, frame_words = words[:6]
            frame = words[6:]

            if magic != MAGIC:
                raise ValueError(f"bad magic 0x{magic:08x}")
            if version != VERSION:
                raise ValueError(f"unsupported version {version}")
            if frame_words != FRAME_WORDS:
                raise ValueError(f"unexpected frame_words {frame_words}")

            start_ticks = (frame[1] << 32) | frame[0]
            done_ticks = (frame[3] << 32) | frame[2]
            read_us = (done_ticks - start_ticks) * 1_000_000 / SAMPLE_CLOCK_HZ

            line = (
                f"{timestamp_text(arrival_epoch_ns)} "
                f"elapsed_ms={elapsed_ms:.3f} delta_ms={delta_ms:.3f} "
                f"seq={sequence} irq={irq_count} core_count={core_count} "
                f"fpga_start={start_ticks} fpga_done={done_ticks} "
                f"read_us={read_us:.3f}"
            )
            if args.raw_hex:
                line += " sensor_hex=" + sensor_bytes_from_frame(frame).hex(" ")
            print(line, flush=True)

            received += 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
