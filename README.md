# SBAN v36

SBAN v36 is a non-transformer sparse byte-adaptive network/runtime research prototype. It extends the v35 auto-learned runtime with limitation-regression training, stricter routing before fuzzy retrieval, no-store memory semantics, simple quadratic solving, repaired running-total word problems, broader exact JSON slot filling, and practical Zig/Rust/Python coding help.

This is still a local bounded prototype. It is not a live-current web oracle, and it should keep asking for external lookup or supplied sources for recent facts, prices, schedules, office holders, weather, and unsupported source-tree locations.

## Main v36 Additions

- `NetworkVariant.v36_arch` and `v36ReleaseConfig(bits)`.
- Default chat corpus path: `data/sban_runtime_prewarm_v36.txt`.
- Default learned reasoning path: `data/sban_learned_reasoning_v36.txt`.
- `scripts/build_v36_runtime_prewarm.py` builds the runtime prewarm pack, learned reasoning corpus, limitation eval, cold seed, compatibility seed/open/knowledge files, prompt evals, demo prompts, and JSON manifests.
- The learned corpus builder uses online dataset adapters for `openai/gsm8k`, `Ritu27/StrategyQA`, and `HuggingFaceFW/CommonsenseQA`, then records source counts in `docs/results/v36/autolearn_manifest_v36.json`.
- The normal `chat-demo`, `chat-eval`, and `chat-session-eval` paths load prewarm and learned assets by default. Pass `prewarm_path=none learned_path=none` for cold-mode checks.
- Near-miss prompts now route through symbolic helpers before learned retrieval for quantified negation, `x^2 = n`, word-problem arithmetic, JSON slot filling, and supported coding requests.
- Session memory now rejects explicit no-store and negated facts such as `my dog is not max`, while preserving structured forget/delete behavior.
- Larger vocabulary probe still tests 256 through 65,536 buckets and records dense-table cost under `docs/results/v36/vocab_size_probe_v36.json`.
- v36 CI and release workflows run `scripts/ci_smoke_v36.py`, the hosted-compatible v36 release suite, the independent hardening workflows, and v36 demo bundle packaging.

## Build

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

The release binary is installed at:

```bash
zig-out/bin/zig_sban
```

## Generate v36 Assets

```bash
python scripts/build_v36_runtime_prewarm.py --force-refresh
python scripts/vocab_size_probe_v36.py
```

Generated assets include:

- `data/sban_runtime_prewarm_v36.txt`
- `data/sban_learned_reasoning_v36.txt`
- `data/sban_cold_seed_v36.txt`
- `data/sban_dialogue_seed_v36.txt`
- `data/sban_dialogue_open_seed_v36.txt`
- `data/sban_synthetic_knowledge_v36.txt`
- `data/sban_chat_eval_prompts_v36.txt`
- `data/sban_session_eval_v36.txt`
- `data/sban_learned_session_eval_v36.txt`
- `data/sban_limitations_session_eval_v36.txt`
- `docs/results/v36/runtime_prewarm_v36.json`
- `docs/results/v36/autolearn_manifest_v36.json`
- `docs/results/v36/vocab_size_probe_v36.json`

## Try v36

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v36" 260
zig-out/bin/zig_sban chat-demo "how does SBAN v36 learn without editing dialogue.zig" 320
zig-out/bin/zig_sban chat-demo "If no blickets are wugs and all glims are blickets, can any glim be a wug?" 260
zig-out/bin/zig_sban chat-demo "solve x^2 = 4" 180
zig-out/bin/zig_sban chat-demo "Sam has 14 apples, gives away 5, then buys 8. How many apples does Sam have?" 220
zig-out/bin/zig_sban chat-demo "generate JSON with name Jane Doe and age 0" 180
zig-out/bin/zig_sban chat-demo "please do not remember that my cat is io" 180 session_path=session_v36.txt
zig-out/bin/zig_sban chat-demo "write a Rust async HTTP server" 420
zig-out/bin/zig_sban chat-demo "who is the current president today" 260
zig-out/bin/zig_sban chat-demo "what is the weather tomorrow" 260
```

## Validate

```bash
python scripts/build_v36_runtime_prewarm.py
python scripts/vocab_size_probe_v36.py
zig build test
zig build -Doptimize=ReleaseFast
python scripts/ci_smoke_v36.py
python scripts/run_v36_release.py --skip-cuda --benchmarks prefix,drift,probe,long_250k,long_1m
python scripts/make_v36_deliverables.py
```

The v36 release suite keeps the packaged numeric guardrails as the engine-health baseline while treating the learned corpus, cold-mode boundary, no-store memory behavior, exact JSON, limitation-regression prompts, and broad dialogue evals as the product capability gate.
