#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT_DIR/scripts/build_with_local_zig.sh" "${1:-/mnt/data/zig-x86_64-linux-0.17.0-dev.87+9b177a7d2.tar.xz}" >/dev/null
BIN="$ROOT_DIR/zig-out/bin/zig_sban"
OUT_DIR="$ROOT_DIR/docs/results/v16"
mkdir -p "$OUT_DIR"
SHORT=(enable_long_term=false birth_margin=21 min_parents_for_birth=4 max_carry_memories=48 max_hidden_per_hop=32 propagation_depth=2 birth_pressure_threshold_bonus=0 birth_saturation_threshold_bonus=0 birth_saturation_parent_boost=0 recent_markov2_bonus_ppm=0 hybrid_share_ppm=0 hybrid_recent_drift_bonus=0)
LONG=(enable_long_term=false birth_margin=21 min_parents_for_birth=4 max_carry_memories=48 max_hidden_per_hop=32 propagation_depth=2 birth_pressure_threshold_bonus=0 birth_saturation_threshold_bonus=0 birth_saturation_parent_boost=0 recent_markov2_bonus_ppm=760 hybrid_share_ppm=20 hybrid_recent_drift_bonus=12 recent_expert_window=8192)
run_variant() {
  local dataset="$1"; local out_json="$2"; local mode="$3"; local bits="$4"; local variant="$5"; local seg_len="$6"; shift 6
  "$BIN" eval-variant "$dataset" "$out_json" "$mode" "$bits" "$variant" "$seg_len" 5000 4096 "$@"
}
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/unified_prefix_v16_compact.json" prefix 5 default 10000 label=sban_v16_short_compact "${SHORT[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/unified_drift_v16_compact.json" drift 5 default 10000 label=sban_v16_short_compact "${SHORT[@]}"
run_variant "$ROOT_DIR/data/elastic_probe.bin" "$OUT_DIR/unified_probe_v16_compact.json" prefix 5 default 29000 label=sban_v16_short_compact "${SHORT[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/longrun_compact_v16_250k.json" prefix 5 default 62500 label=sban_v16_longrun_recent8k_250k "${LONG[@]}"
run_variant "$ROOT_DIR/data/enwik8" "$OUT_DIR/longrun_compact_v16_2m.json" prefix 5 default 500000 label=sban_v16_longrun_recent8k_2m "${LONG[@]}"
"$BIN" chat-demo "what changed in v16" 96 seed_path=data/sban_dialogue_seed_v16.txt > "$OUT_DIR/chat_demo_v16_changes.txt"
"$BIN" chat-demo "explain the new routing logic" 96 seed_path=data/sban_dialogue_seed_v16.txt > "$OUT_DIR/chat_demo_v16_routing.txt"
"$BIN" chat-demo "how do you respond when the prompt is only loosely related" 96 seed_path=data/sban_dialogue_seed_v16.txt > "$OUT_DIR/chat_demo_v16_related.txt"
"$BIN" chat-eval "$ROOT_DIR/data/sban_chat_eval_prompts_v16.txt" seed_path=data/sban_dialogue_seed_v16.txt > "$OUT_DIR/chat_eval_v16_hybrid.txt"
"$BIN" chat-eval "$ROOT_DIR/data/sban_chat_eval_prompts_v16.txt" mode=free seed_path=data/sban_dialogue_seed_v16.txt > "$OUT_DIR/chat_eval_v16_free.txt"
