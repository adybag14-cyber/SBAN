#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT_DIR/zig-out/bin/zig_sban"
OUT_DIR="$ROOT_DIR/docs/results/v8"
mkdir -p "$OUT_DIR"

run_variant() {
  local dataset="$1"
  local out_json="$2"
  local mode="$3"
  local bits="$4"
  local variant="$5"
  local seg_len="$6"
  shift 6
  "$BIN" eval-variant "$dataset" "$out_json" "$mode" "$bits" "$variant" "$seg_len" 5000 4096 "$@"
}

run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/unified_prefix_v8_6bit_stress.json" prefix 6 default 10000 label=sban_v10_6bit_stress_default max_carry_memories=48
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/unified_drift_v8_6bit_stress.json" drift 6 default 10000 label=sban_v10_6bit_stress_default max_carry_memories=48
run_variant "$ROOT_DIR/data/elastic_probe.bin" "$OUT_DIR/unified_probe_v8_6bit_stress.json" prefix 6 default 29000 label=sban_v10_6bit_stress_default max_carry_memories=48

run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/best_prefix_v8_5bit_nolong.json" prefix 5 default 10000 label=sban_v10_prefix_best_5bit_nolong enable_long_term=false
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/best_drift_v8_5bit_nolong.json" drift 5 default 10000 label=sban_v10_drift_best_5bit_nolong enable_long_term=false
run_variant "$ROOT_DIR/data/elastic_probe.bin" "$OUT_DIR/best_probe_v8_6bit_pp600.json" prefix 6 default 29000 label=sban_v10_probe_best_6bit_pp600 promotion_precision_ppm=600

run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/base_prefix_v8_6bit.json" prefix 6 default 10000 label=sban_v10_6bit_base
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/base_drift_v8_6bit.json" drift 6 default 10000 label=sban_v10_6bit_base
run_variant "$ROOT_DIR/data/elastic_probe.bin" "$OUT_DIR/base_probe_v8_6bit.json" prefix 6 default 29000 label=sban_v10_6bit_base
