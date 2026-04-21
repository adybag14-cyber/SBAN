#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/zig-out/bin/zig_sban"
OUT="$ROOT/docs/results"

mkdir -p "$OUT"

"$BIN" eval-variant "$ROOT/data/enwik8" "$OUT/variant_prefix_v7_best_7bit.json" prefix 7 default 10000 5000 4096
"$BIN" eval-variant "$ROOT/data/enwik8" "$OUT/variant_drift_v7_best_6bit.json" drift 6 default 10000 5000 4096
"$BIN" eval-variant "$ROOT/data/elastic_probe.bin" "$OUT/variant_probe_v7_best_6bit.json" prefix 6 default 29000 5000 4096

"$BIN" eval-variant "$ROOT/data/enwik8" "$OUT/variant_prefix_v7_best_7bit_fixed.json" prefix 7 fixed_capacity 10000 5000 4096
"$BIN" eval-variant "$ROOT/data/enwik8" "$OUT/variant_drift_v7_best_6bit_fixed.json" drift 6 fixed_capacity 10000 5000 4096
"$BIN" eval-variant "$ROOT/data/elastic_probe.bin" "$OUT/variant_probe_v7_best_6bit_fixed.json" prefix 6 fixed_capacity 29000 5000 4096
