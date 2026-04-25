# SBAN v34

SBAN v34 is a non-transformer sparse byte-adaptive network/runtime research prototype. It imports the v33 powerchat work from the colleague baseline, then pushes the architecture toward a default warm-start runtime: generated prewarm knowledge, practical coding snippets, reasoning helpers, session memory, and bounded operational answers are loaded without requiring separate seed/open/knowledge arguments.

This is still a local static/offline prototype. It does not become a live-current web model, and it should keep asking for external lookup or supplied sources for recent facts, prices, schedules, office holders, and unsupported source-tree locations.

## Main v34 Additions

- `NetworkVariant.v34_arch` and `v34ReleaseConfig(bits)`.
- Default chat and accelerator corpus path is `data/sban_runtime_prewarm_v34.txt`.
- `scripts/build_v34_runtime_prewarm.py` generates the v34 prewarm pack, compatibility seed/open/knowledge files, session eval assets, prompt evals, demo prompts, and JSON stats.
- The default `chat-demo`, `chat-eval`, and `chat-session-eval` no longer need `seed_path`, `open_seed_path`, or `knowledge_path`; pass `prewarm_path=...` only when testing an alternate generated pack.
- Expanded warm-start coverage for stable science, computing, security, geography, literature, history, civics, economics, reasoning, real-world task triage, Python BFS, SQL aggregation, and Zig `defer`, allocators, errors, file cleanup, and slice reversal.
- Larger vocabulary probe now tests 256 through 65,536 buckets and records dense-table cost under `docs/results/v34/vocab_size_probe_v34.json`.
- v34 CI and release workflows run `scripts/ci_smoke_v34.py`, the hosted-compatible v34 release suite, and v34 demo bundle packaging.

## Build

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

The release binary is installed at:

```bash
zig-out/bin/zig_sban
```

## Generate v34 Assets

```bash
python scripts/build_v34_runtime_prewarm.py
python scripts/vocab_size_probe_v34.py
```

Generated assets include:

- `data/sban_runtime_prewarm_v34.txt`
- `data/sban_dialogue_seed_v34.txt`
- `data/sban_dialogue_open_seed_v34.txt`
- `data/sban_synthetic_knowledge_v34.txt`
- `data/sban_chat_eval_prompts_v34.txt`
- `data/sban_session_eval_v34.txt`
- `data/sban_knowledge_session_eval_v34.txt`
- `docs/results/v34/runtime_prewarm_v34.json`
- `docs/results/v34/synthetic_knowledge_v34.json`
- `docs/results/v34/vocab_size_probe_v34.json`

## Try v34

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v34" 260
zig-out/bin/zig_sban chat-demo "what is DNS" 260
zig-out/bin/zig_sban chat-demo "what is entropy" 260
zig-out/bin/zig_sban chat-demo "what does defer do in Zig" 260
zig-out/bin/zig_sban chat-demo "write a Zig function to reverse a slice" 420
zig-out/bin/zig_sban chat-demo "write Python BFS for a graph" 420
zig-out/bin/zig_sban chat-demo "how do I triage an outage" 260
zig-out/bin/zig_sban chat-demo "who is the current president today" 260
```

## Validate

```bash
python scripts/ci_smoke_v34.py
python scripts/run_v34_release.py --skip-cuda --benchmarks prefix,drift,probe,long_250k,long_1m
python scripts/make_v34_deliverables.py
```

The v34 release suite keeps the v29 packaged numeric guardrails as the health baseline while treating the v34 warm-start evals as the product capability gate.
