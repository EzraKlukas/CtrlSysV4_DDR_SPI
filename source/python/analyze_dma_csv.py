#!/usr/bin/env python3
"""Analyze CSV captures from redpitaya_dma_receiver.py."""

from __future__ import annotations

import argparse
import csv
import math
from array import array
from dataclasses import dataclass
from pathlib import Path


SAMPLE_CLOCK_HZ = 125_000_000


@dataclass
class RunningStats:
    count: int = 0
    mean: float = 0.0
    m2: float = 0.0
    minimum: float | None = None
    maximum: float | None = None

    def add(self, value: float) -> None:
        self.count += 1
        delta = value - self.mean
        self.mean += delta / self.count
        self.m2 += delta * (value - self.mean)
        self.minimum = value if self.minimum is None else min(self.minimum, value)
        self.maximum = value if self.maximum is None else max(self.maximum, value)

    @property
    def stddev(self) -> float:
        if self.count < 2:
            return 0.0
        return math.sqrt(self.m2 / (self.count - 1))


@dataclass
class Anomaly:
    row: int
    sequence: int
    previous: int
    current: int
    detail: str


def percentile(sorted_values: list[float], percent: float) -> float:
    if not sorted_values:
        return 0.0
    if len(sorted_values) == 1:
        return sorted_values[0]

    position = (len(sorted_values) - 1) * percent / 100.0
    low = math.floor(position)
    high = math.ceil(position)
    if low == high:
        return sorted_values[low]
    weight = position - low
    return sorted_values[low] * (1.0 - weight) + sorted_values[high] * weight


def print_stats(name: str, stats: RunningStats, values: array) -> None:
    sorted_values = sorted(values)
    print(f"{name}:")
    print(f"  count: {stats.count}")
    print(f"  mean:  {stats.mean:.6f}")
    print(f"  std:   {stats.stddev:.6f}")
    print(f"  min:   {(stats.minimum or 0.0):.6f}")
    print(f"  p50:   {percentile(sorted_values, 50):.6f}")
    print(f"  p95:   {percentile(sorted_values, 95):.6f}")
    print(f"  p99:   {percentile(sorted_values, 99):.6f}")
    print(f"  p99.9: {percentile(sorted_values, 99.9):.6f}")
    print(f"  max:   {(stats.maximum or 0.0):.6f}")


def maybe_add_plot_point(
    rows_seen: int,
    max_points: int,
    sequence: int,
    pc_delta_ms: float,
    fpga_delta_ms: float,
    x_values: list[int],
    pc_values: list[float],
    fpga_values: list[float],
) -> None:
    if max_points <= 0:
        return
    stride = max(1, rows_seen // max_points)
    if rows_seen <= max_points or rows_seen % stride == 0:
        x_values.append(sequence)
        pc_values.append(pc_delta_ms)
        fpga_values.append(fpga_delta_ms)


def plot_inter_arrivals(
    x_values: list[int],
    pc_values: list[float],
    fpga_values: list[float],
    title: str,
) -> None:
    if not x_values:
        print("no plot points collected")
        return

    try:
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib is not installed; install it with: python -m pip install matplotlib")
        return

    fig, ax = plt.subplots(figsize=(11, 5))
    ax.plot(x_values, pc_values, ".", color="tab:orange",
            markersize=2, label="PC inter-arrival")
    ax.set_xlabel("sample sequence")
    ax.set_ylabel("PC inter-arrival (ms)")
    ax.tick_params(axis="y", labelcolor="tab:orange")
    ax.grid(True, alpha=0.3)

    fpga_ax = ax.twinx()
    fpga_ax.plot(x_values, fpga_values, ".", color="tab:blue",
                 markersize=2, label="FPGA start inter-arrival")
    fpga_ax.set_ylabel("FPGA start inter-arrival (ms)")
    fpga_ax.tick_params(axis="y", labelcolor="tab:blue")

    lines = ax.get_lines() + fpga_ax.get_lines()
    labels = [line.get_label() for line in lines]
    ax.legend(lines, labels, loc="best")
    fig.suptitle(title)
    fig.tight_layout()
    plt.show()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Analyze Red Pitaya DMA receiver CSV captures."
    )
    parser.add_argument("csv_path", type=Path)
    parser.add_argument("--clock-hz", type=float, default=SAMPLE_CLOCK_HZ)
    parser.add_argument("--expected-ms", type=float, default=1.0,
                        help="expected FPGA sample interval in milliseconds")
    parser.add_argument("--tolerance-ticks", type=int, default=0,
                        help="allowed FPGA inter-arrival tick error")
    parser.add_argument("--plot", action="store_true")
    parser.add_argument("--max-plot-points", type=int, default=200_000,
                        help="downsample plot to roughly this many points")
    parser.add_argument("--show-anomalies", type=int, default=20,
                        help="number of anomalies to print")
    args = parser.parse_args()

    expected_ticks = round(args.clock_hz * args.expected_ms / 1000.0)
    expected_ms_from_ticks = expected_ticks * 1000.0 / args.clock_hz

    pc_stats = RunningStats()
    fpga_stats = RunningStats()
    latency_stats = RunningStats()
    read_stats = RunningStats()
    pc_values = array("d")
    fpga_values = array("d")
    latency_values = array("d")
    read_values = array("d")

    plot_x: list[int] = []
    plot_pc: list[float] = []
    plot_fpga: list[float] = []

    sequence_anomalies: list[Anomaly] = []
    core_count_anomalies: list[Anomaly] = []
    irq_count_anomalies: list[Anomaly] = []
    fpga_anomalies: list[Anomaly] = []
    late_pc_rows: list[tuple[int, int, float]] = []

    first_start_ticks: int | None = None
    previous_sequence: int | None = None
    previous_core_count: int | None = None
    previous_irq_count: int | None = None
    previous_start_ticks: int | None = None
    rows = 0

    with args.csv_path.open(newline="", encoding="utf-8") as csv_file:
        reader = csv.DictReader(csv_file)
        for row_index, row in enumerate(reader, start=2):
            rows += 1
            sequence = int(row["sequence"])
            irq_count = int(row["irq_count"])
            core_count = int(row["core_count"])
            pc_elapsed_ms = float(row["pc_elapsed_ms"])
            pc_delta_ms = float(row["pc_inter_arrival_ms"])
            start_ticks = int(row["fpga_start_ticks"])
            read_us = float(row["read_us"])

            if first_start_ticks is None:
                first_start_ticks = start_ticks

            fpga_delta_ticks = (
                0 if previous_start_ticks is None
                else start_ticks - previous_start_ticks
            )
            fpga_delta_ms = fpga_delta_ticks * 1000.0 / args.clock_hz
            fpga_elapsed_ms = (start_ticks - first_start_ticks) * 1000.0 / args.clock_hz
            relative_latency_ms = pc_elapsed_ms - fpga_elapsed_ms

            if previous_sequence is not None and sequence != previous_sequence + 1:
                sequence_anomalies.append(Anomaly(
                    row_index, sequence, previous_sequence, sequence,
                    f"expected sequence {previous_sequence + 1}",
                ))
            if previous_core_count is not None and core_count != previous_core_count + 1:
                core_count_anomalies.append(Anomaly(
                    row_index, sequence, previous_core_count, core_count,
                    f"expected core_count {previous_core_count + 1}",
                ))
            if previous_irq_count is not None and irq_count != previous_irq_count + 1:
                irq_count_anomalies.append(Anomaly(
                    row_index, sequence, previous_irq_count, irq_count,
                    f"expected irq_count {previous_irq_count + 1}",
                ))
            if previous_start_ticks is not None:
                tick_error = fpga_delta_ticks - expected_ticks
                if abs(tick_error) > args.tolerance_ticks:
                    detail = (
                        f"delta_ticks={fpga_delta_ticks}, "
                        f"expected={expected_ticks}, error={tick_error}"
                    )
                    fpga_anomalies.append(Anomaly(
                        row_index, sequence, previous_start_ticks,
                        start_ticks, detail,
                    ))

                pc_stats.add(pc_delta_ms)
                fpga_stats.add(fpga_delta_ms)
                latency_stats.add(relative_latency_ms)
                read_stats.add(read_us)
                pc_values.append(pc_delta_ms)
                fpga_values.append(fpga_delta_ms)
                latency_values.append(relative_latency_ms)
                read_values.append(read_us)

                if pc_delta_ms > expected_ms_from_ticks * 2:
                    late_pc_rows.append((row_index, sequence, pc_delta_ms))

                maybe_add_plot_point(
                    rows,
                    args.max_plot_points,
                    sequence,
                    pc_delta_ms,
                    fpga_delta_ms,
                    plot_x,
                    plot_pc,
                    plot_fpga,
                )

            previous_sequence = sequence
            previous_core_count = core_count
            previous_irq_count = irq_count
            previous_start_ticks = start_ticks

    print(f"CSV: {args.csv_path}")
    print(f"rows: {rows}")
    print(f"expected FPGA interval: {expected_ticks} ticks ({expected_ms_from_ticks:.6f} ms)")
    print()

    if rows == 0:
        return 0

    print("Continuity checks:")
    print(f"  sequence gaps:       {len(sequence_anomalies)}")
    print(f"  core_count gaps:     {len(core_count_anomalies)}")
    print(f"  irq_count gaps:      {len(irq_count_anomalies)}")
    print(f"  FPGA timing misses:  {len(fpga_anomalies)}")
    if not sequence_anomalies and not core_count_anomalies and not fpga_anomalies:
        print("  result: no dropped/generated-sample gaps detected")
    else:
        print("  result: investigate anomalies below")
    print()

    print_stats("PC inter-arrival ms", pc_stats, pc_values)
    print()
    print_stats("FPGA start inter-arrival ms", fpga_stats, fpga_values)
    print()
    print_stats("Relative receive latency ms", latency_stats, latency_values)
    print("  note: this is PC elapsed minus FPGA elapsed, aligned to the first sample.")
    print("        It measures queueing/jitter drift, not absolute one-way latency.")
    print()
    print_stats("Sensor read duration us", read_stats, read_values)
    print()

    print(f"PC inter-arrival rows > 2x expected: {len(late_pc_rows)}")
    for row_index, sequence, pc_delta_ms in late_pc_rows[:args.show_anomalies]:
        print(f"  row {row_index}: seq={sequence}, pc_delta_ms={pc_delta_ms:.6f}")
    if len(late_pc_rows) > args.show_anomalies:
        print(f"  ... {len(late_pc_rows) - args.show_anomalies} more")
    print()

    for name, anomalies in [
        ("sequence", sequence_anomalies),
        ("core_count", core_count_anomalies),
        ("irq_count", irq_count_anomalies),
        ("fpga", fpga_anomalies),
    ]:
        if anomalies:
            print(f"{name} anomalies:")
            for anomaly in anomalies[:args.show_anomalies]:
                print(
                    f"  row {anomaly.row}: seq={anomaly.sequence}, "
                    f"prev={anomaly.previous}, current={anomaly.current}, "
                    f"{anomaly.detail}"
                )
            if len(anomalies) > args.show_anomalies:
                print(f"  ... {len(anomalies) - args.show_anomalies} more")
            print()

    if args.plot:
        plot_inter_arrivals(
            plot_x,
            plot_pc,
            plot_fpga,
            f"{args.csv_path.name} inter-arrival timing",
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
