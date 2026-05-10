#!/usr/bin/env python3
"""Parse the FastReadSpike logcat capture from perf-sweep.sh and emit a
per-WPM frame-timing summary. The spike logs:
  TOK i=N target=Tms actual=A.ABms jitter=Jms tok="..."
between every two token swaps. The delta between target and actual is
the runtime jitter (Choreographer + Compose recomposition + ART). Drop
the first 5 samples per run as warmup (cold dispatcher, no JIT).

  python3 perf-report.py [/tmp/spike-perf.log]
"""

import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

LOG = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/spike-perf.log")

START_RE = re.compile(r"RUN_START wpm=(\d+) tokens=(\d+)")
TOK_RE = re.compile(r"TOK i=\d+ target=(\d+)ms actual=([\d.]+)ms jitter=(\d+)ms")

def main() -> None:
    if not LOG.exists():
        sys.exit(f"❌ no log at {LOG}")
    lines = LOG.read_text().splitlines()

    runs: list[tuple[int, list[tuple[int, float, int]]]] = []
    current_wpm: int | None = None
    current_samples: list[tuple[int, float, int]] = []

    for line in lines:
        m = START_RE.search(line)
        if m:
            if current_wpm is not None:
                runs.append((current_wpm, current_samples))
            current_wpm = int(m.group(1))
            current_samples = []
            continue
        m = TOK_RE.search(line)
        if m and current_wpm is not None:
            current_samples.append((int(m.group(1)), float(m.group(2)), int(m.group(3))))
    if current_wpm is not None:
        runs.append((current_wpm, current_samples))

    print(f"\n{'WPM':>4} {'samples':>8} {'avg_jitter':>11} {'p50':>7} {'p95':>7} {'p99':>7} {'max':>7} {'>16ms':>7} {'>33ms':>7}")
    print("-" * 78)
    for wpm, samples in runs:
        if len(samples) < 10:
            print(f"{wpm:>4} {len(samples):>8}   (too few samples)")
            continue
        warmup = 5
        jitters = [s[2] for s in samples[warmup:]]
        avg = sum(jitters) / len(jitters)
        p50 = statistics.median(jitters)
        sorted_j = sorted(jitters)
        p95 = sorted_j[int(len(sorted_j) * 0.95)]
        p99 = sorted_j[int(len(sorted_j) * 0.99)]
        mx = max(jitters)
        above_16 = sum(1 for j in jitters if j > 16)
        above_33 = sum(1 for j in jitters if j > 33)
        pct16 = above_16 / len(jitters) * 100
        pct33 = above_33 / len(jitters) * 100
        print(
            f"{wpm:>4} {len(jitters):>8} {avg:>10.2f}ms {p50:>5}ms {p95:>5}ms "
            f"{p99:>5}ms {mx:>5}ms {pct16:>5.1f}% {pct33:>5.1f}%"
        )

    print("\nLegend:")
    print("  >16ms  = jitter exceeded one 60Hz frame budget (16.67 ms)")
    print("  >33ms  = jitter exceeded two 60Hz frames; user-visible stutter")
    print(
        "\nVerdict heuristic: avg < 5 ms, p99 < 16 ms, >33ms < 0.5% on "
        "Pixel 8 hardware = matches the iOS 'silky' bar at the same WPM."
    )

if __name__ == "__main__":
    main()
