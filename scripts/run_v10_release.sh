#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT_DIR/scripts/build_with_local_zig.sh" >/dev/null
BIN="$ROOT_DIR/zig-out/bin/zig_sban"
OUT_DIR="$ROOT_DIR/docs/results/v10"
mkdir -p "$OUT_DIR"
run_case() {
  local dataset="$1"; local out_json="$2"; local mode="$3"; local bits="$4"; shift 4
  "$BIN" eval-variant "$dataset" "$out_json" "$mode" "$bits" default "$@"
}
run_case "$ROOT_DIR/data/enwik8" "$OUT_DIR/unified_prefix_v10_working.json" prefix 5 10000 5000 4096 label=sban_v10_working_profile enable_long_term=false min_parents_for_birth=4
run_case "$ROOT_DIR/data/enwik8" "$OUT_DIR/unified_drift_v10_working.json" drift 5 10000 5000 4096 label=sban_v10_working_profile enable_long_term=false min_parents_for_birth=4
run_case "$ROOT_DIR/data/elastic_probe.bin" "$OUT_DIR/unified_probe_v10_working.json" prefix 5 29000 5000 4096 label=sban_v10_working_profile enable_long_term=false min_parents_for_birth=4
run_case "$ROOT_DIR/data/enwik8" "$OUT_DIR/best_prefix_v10_5bit_bm20.json" prefix 5 10000 5000 4096 label=sban_v10_prefix_best enable_long_term=false birth_margin=20
run_case "$ROOT_DIR/data/enwik8" "$OUT_DIR/best_drift_v10_5bit_bm24.json" drift 5 10000 5000 4096 label=sban_v10_drift_best enable_long_term=false birth_margin=24
run_case "$ROOT_DIR/data/elastic_probe.bin" "$OUT_DIR/best_probe_v10_5bit_bm24.json" prefix 5 29000 5000 4096 label=sban_v10_probe_best enable_long_term=false birth_margin=24
