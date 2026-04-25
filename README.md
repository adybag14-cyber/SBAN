# SBAN v35

SBAN v35 is a non-transformer sparse byte-adaptive network/runtime research prototype. It extends the v34 warm-start runtime with a data-generated learned reasoning corpus so reply quality can improve by regenerating training assets instead of expanding `src/dialogue.zig`.

This is still a local bounded prototype. It is not a live-current web oracle, and it should keep asking for external lookup or supplied sources for recent facts, prices, schedules, office holders, and unsupported source-tree locations.

## Main v35 Additions

- `NetworkVariant.v35_arch` and `v35ReleaseConfig(bits)`.
- Default chat corpus path: `data/sban_runtime_prewarm_v35.txt`.
- Default learned reasoning path: `data/sban_learned_reasoning_v35.txt`.
- `scripts/build_v35_runtime_prewarm.py` builds the runtime prewarm pack, learned reasoning corpus, cold seed, compatibility seed/open/knowledge files, session eval assets, prompt evals, demo prompts, and JSON manifests.
- The learned corpus builder uses online dataset adapters for `openai/gsm8k`, `Ritu27/StrategyQA`, and `HuggingFaceFW/CommonsenseQA`, then records source counts in `docs/results/v35/autolearn_manifest_v35.json`.
- The normal `chat-demo`, `chat-eval`, and `chat-session-eval` paths load prewarm and learned assets by default. Pass `prewarm_path=none learned_path=none` for cold-mode checks.
- Session memory now supports structured forget/delete requests and normalizes filler such as `now` from remembered fact values.
- JSON name/age prompts preserve requested values instead of returning a canned age.
- Larger vocabulary probe still tests 256 through 65,536 buckets and records dense-table cost under `docs/results/v35/vocab_size_probe_v35.json`.
- v35 CI and release workflows run `scripts/ci_smoke_v35.py`, the hosted-compatible v35 release suite, and v35 demo bundle packaging.

## Build

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

The release binary is installed at:

```bash
zig-out/bin/zig_sban
```

## Generate v35 Assets

```bash
python scripts/build_v35_runtime_prewarm.py --force-refresh
python scripts/vocab_size_probe_v35.py
```

Generated assets include:

- `data/sban_runtime_prewarm_v35.txt`
- `data/sban_learned_reasoning_v35.txt`
- `data/sban_cold_seed_v35.txt`
- `data/sban_dialogue_seed_v35.txt`
- `data/sban_dialogue_open_seed_v35.txt`
- `data/sban_synthetic_knowledge_v35.txt`
- `data/sban_chat_eval_prompts_v35.txt`
- `data/sban_session_eval_v35.txt`
- `data/sban_learned_session_eval_v35.txt`
- `docs/results/v35/runtime_prewarm_v35.json`
- `docs/results/v35/autolearn_manifest_v35.json`
- `docs/results/v35/vocab_size_probe_v35.json`

## Try v35

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v35" 260
zig-out/bin/zig_sban chat-demo "how does SBAN v35 learn without editing dialogue.zig" 320
zig-out/bin/zig_sban chat-demo "If all daxes are lums, and some lums are norps, are all daxes definitely norps? Explain." 320
zig-out/bin/zig_sban chat-demo "generate JSON with name Ada and age 37" 180
zig-out/bin/zig_sban chat-demo "my dog is max now" 180 session_path=session_v35.txt
zig-out/bin/zig_sban chat-demo "forget my dog name" 180 session_path=session_v35.txt
zig-out/bin/zig_sban chat-demo "write a Zig function to reverse a slice" 420
zig-out/bin/zig_sban chat-demo "who is the current president today" 260
```

## Validate

```bash
python scripts/build_v35_runtime_prewarm.py
python scripts/vocab_size_probe_v35.py
zig build test
zig build -Doptimize=ReleaseFast
python scripts/ci_smoke_v35.py
python scripts/run_v35_release.py --skip-cuda --benchmarks prefix,drift,probe,long_250k,long_1m
python scripts/make_v35_deliverables.py
```

The v35 release suite keeps the packaged numeric guardrails as the engine-health baseline while treating the learned corpus, cold-mode boundary, session forget, exact JSON, and broad dialogue evals as the product capability gate.
