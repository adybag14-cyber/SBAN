#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT_DIR/scripts/build_with_local_zig.sh" "${1:-/mnt/data/zig-x86_64-linux-0.17.0-dev.87+9b177a7d2.tar.xz}" >/dev/null
BIN="$ROOT_DIR/zig-out/bin/zig_sban"
OUT_DIR="$ROOT_DIR/docs/results/v11"
mkdir -p "$OUT_DIR"
run_case() {
  local dataset="$1"; local out_json="$2"; local mode="$3"; local bits="$4"; local variant="$5"; local seg_len="$6"; shift 6
  "$BIN" eval-variant "$dataset" "$out_json" "$mode" "$bits" "$variant" "$seg_len" 5000 4096 "$@"
}
COMMON=(enable_long_term=false max_carry_memories=48 max_hidden_per_hop=32 propagation_depth=2 birth_pressure_threshold_bonus=0)
run_case "$ROOT_DIR/data/enwik8" "$OUT_DIR/unified_prefix_v11_working.json" prefix 5 default 10000 label=sban_v11_working_profile birth_margin=21 min_parents_for_birth=4 "${COMMON[@]}"
run_case "$ROOT_DIR/data/enwik8" "$OUT_DIR/unified_drift_v11_working.json" drift 5 default 10000 label=sban_v11_working_profile birth_margin=21 min_parents_for_birth=4 "${COMMON[@]}"
run_case "$ROOT_DIR/data/elastic_probe.bin" "$OUT_DIR/unified_probe_v11_working.json" prefix 5 default 29000 label=sban_v11_working_profile birth_margin=21 min_parents_for_birth=4 "${COMMON[@]}"
run_case "$ROOT_DIR/data/enwik8" "$OUT_DIR/unified_prefix_v11_fixed.json" prefix 5 fixed_capacity 10000 label=sban_v11_fixed_profile birth_margin=21 min_parents_for_birth=4 "${COMMON[@]}"
run_case "$ROOT_DIR/data/enwik8" "$OUT_DIR/unified_drift_v11_fixed.json" drift 5 fixed_capacity 10000 label=sban_v11_fixed_profile birth_margin=21 min_parents_for_birth=4 "${COMMON[@]}"
run_case "$ROOT_DIR/data/elastic_probe.bin" "$OUT_DIR/unified_probe_v11_fixed.json" prefix 5 fixed_capacity 29000 label=sban_v11_fixed_profile birth_margin=21 min_parents_for_birth=4 "${COMMON[@]}"
run_case "$ROOT_DIR/data/enwik8" "$OUT_DIR/best_prefix_v11_5bit_bm21_mp4.json" prefix 5 default 10000 label=sban_v11_prefix_best birth_margin=21 min_parents_for_birth=4 "${COMMON[@]}"
run_case "$ROOT_DIR/data/enwik8" "$OUT_DIR/best_drift_v11_5bit_bm20_mp4.json" drift 5 default 10000 label=sban_v11_drift_best birth_margin=20 min_parents_for_birth=4 "${COMMON[@]}"
run_case "$ROOT_DIR/data/elastic_probe.bin" "$OUT_DIR/best_probe_v11_5bit_bm21_mp4.json" prefix 5 default 29000 label=sban_v11_probe_best birth_margin=21 min_parents_for_birth=4 "${COMMON[@]}"
