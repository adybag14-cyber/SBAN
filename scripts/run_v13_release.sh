#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT_DIR/scripts/build_with_local_zig.sh" "${1:-/mnt/data/zig-x86_64-linux-0.17.0-dev.87+9b177a7d2.tar.xz}" >/dev/null
BIN="$ROOT_DIR/zig-out/bin/zig_sban"
OUT_DIR="$ROOT_DIR/docs/results/v13"
mkdir -p "$OUT_DIR"
BASE=(birth_pressure_threshold_bonus=0 birth_saturation_threshold_bonus=0 birth_saturation_parent_boost=0)
COMPACT=(enable_long_term=false birth_margin=21 min_parents_for_birth=4 max_carry_memories=48 max_hidden_per_hop=32 propagation_depth=2 "${BASE[@]}")
DRIFT_BEST=(enable_long_term=false birth_margin=20 min_parents_for_birth=4 max_carry_memories=48 max_hidden_per_hop=32 propagation_depth=2 "${BASE[@]}")
HARDENED=(enable_long_term=true birth_margin=20 min_parents_for_birth=4 max_carry_memories=64 max_hidden_per_hop=48 propagation_depth=3 long_term_bonus_ppm=1120 long_term_bonus_precision_ppm=580 "${BASE[@]}")
run_variant() {
  local dataset="$1"; local out_json="$2"; local mode="$3"; local bits="$4"; local variant="$5"; local seg_len="$6"; shift 6
  "$BIN" eval-variant "$dataset" "$out_json" "$mode" "$bits" "$variant" "$seg_len" 5000 4096 "$@"
}
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/unified_prefix_v13_compact.json" prefix 5 default 10000 label=sban_v13_compact_profile "${COMPACT[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/unified_drift_v13_compact.json" drift 5 default 10000 label=sban_v13_compact_profile "${COMPACT[@]}"
run_variant "$ROOT_DIR/data/elastic_probe.bin" "$OUT_DIR/unified_probe_v13_compact.json" prefix 5 default 29000 label=sban_v13_compact_profile "${COMPACT[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/fixed_prefix_v13_compact.json" prefix 5 fixed_capacity 10000 label=sban_v13_compact_fixed "${COMPACT[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/fixed_drift_v13_compact.json" drift 5 fixed_capacity 10000 label=sban_v13_compact_fixed "${COMPACT[@]}"
run_variant "$ROOT_DIR/data/elastic_probe.bin" "$OUT_DIR/fixed_probe_v13_compact.json" prefix 5 fixed_capacity 29000 label=sban_v13_compact_fixed "${COMPACT[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/best_drift_v13_profile.json" drift 5 default 10000 label=sban_v13_drift_best "${DRIFT_BEST[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/longrun_compact_v13_250k.json" prefix 5 default 62500 label=sban_v13_longrun_compact "${COMPACT[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/longrun_hardened_v13_250k.json" prefix 5 fixed_capacity 62500 label=sban_v13_longrun_hardened "${HARDENED[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/longrun_compact_v13_1m.json" prefix 5 default 250000 label=sban_v13_longrun_compact_1m "${COMPACT[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/longrun_hardened_v13_1m.json" prefix 5 fixed_capacity 250000 label=sban_v13_longrun_hardened_1m "${HARDENED[@]}"
"$BIN" chat-demo "hello are you ok" 96 > "$OUT_DIR/chat_demo_hello.txt"
"$BIN" chat-demo "what are the current limitations" 96 > "$OUT_DIR/chat_demo_limits.txt"
"$BIN" chat-eval "$ROOT_DIR/data/sban_chat_eval_prompts.txt" > "$OUT_DIR/chat_eval_anchor.txt"
"$BIN" chat-eval "$ROOT_DIR/data/sban_chat_eval_prompts.txt" mode=free > "$OUT_DIR/chat_eval_free.txt"
