#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT_DIR/scripts/build_with_local_zig.sh" "${1:-/mnt/data/zig-x86_64-linux-0.17.0-dev.87+9b177a7d2.tar.xz}" >/dev/null
BIN="$ROOT_DIR/zig-out/bin/zig_sban"
OUT_DIR="$ROOT_DIR/docs/results/v15"
mkdir -p "$OUT_DIR"
COMPACT=(enable_long_term=false birth_margin=21 min_parents_for_birth=4 max_carry_memories=48 max_hidden_per_hop=32 propagation_depth=2 birth_pressure_threshold_bonus=0 birth_saturation_threshold_bonus=0 birth_saturation_parent_boost=0)
HARDENED=(enable_long_term=true birth_margin=20 min_parents_for_birth=4 max_carry_memories=64 max_hidden_per_hop=48 propagation_depth=3 long_term_bonus_ppm=1120 long_term_bonus_precision_ppm=580 birth_pressure_threshold_bonus=0 birth_saturation_threshold_bonus=0 birth_saturation_parent_boost=0)
run_variant() {
  local dataset="$1"; local out_json="$2"; local mode="$3"; local bits="$4"; local variant="$5"; local seg_len="$6"; shift 6
  "$BIN" eval-variant "$dataset" "$out_json" "$mode" "$bits" "$variant" "$seg_len" 5000 4096 "$@"
}
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/unified_prefix_v15_compact.json" prefix 5 default 10000 label=sban_v15_compact_profile "${COMPACT[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/unified_drift_v15_compact.json" drift 5 default 10000 label=sban_v15_compact_profile "${COMPACT[@]}"
run_variant "$ROOT_DIR/data/elastic_probe.bin" "$OUT_DIR/unified_probe_v15_compact.json" prefix 5 default 29000 label=sban_v15_compact_profile "${COMPACT[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/longrun_compact_v15_250k.json" prefix 5 default 62500 label=sban_v15_longrun_compact "${COMPACT[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/longrun_hardened_v15_250k.json" prefix 5 fixed_capacity 62500 label=sban_v15_longrun_hardened "${HARDENED[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/longrun_compact_v15_1m.json" prefix 5 default 250000 label=sban_v15_longrun_compact_1m "${COMPACT[@]}"
"$BIN" chat-demo "what changed in v15" 96 seed_path=data/sban_dialogue_seed_v15.txt > "$OUT_DIR/chat_demo_v15_changes.txt"
"$BIN" chat-demo "what is the architecture now" 96 seed_path=data/sban_dialogue_seed_v15.txt > "$OUT_DIR/chat_demo_v15_architecture.txt"
"$BIN" chat-eval "$ROOT_DIR/data/sban_chat_eval_prompts_v15.txt" seed_path=data/sban_dialogue_seed_v15.txt > "$OUT_DIR/chat_eval_v15_hybrid.txt"
"$BIN" chat-eval "$ROOT_DIR/data/sban_chat_eval_prompts_v15.txt" mode=free seed_path=data/sban_dialogue_seed_v15.txt > "$OUT_DIR/chat_eval_v15_free.txt"
