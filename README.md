# SBAN v24

SBAN v24 is the current conversational product release of the Sparse Bridge-Adaptive Network runtime.

This release keeps the established numeric engine-health suite on the proven single-thread CPU profile while upgrading the shipped chat surface. V24 keeps the measured CPU, `cpu_mt`, CUDA, and OpenCL backend stack from the recent backend work, but adds a real v24 grounded seed, a separate v24 open-chat seed, broader operational answers, stronger session-memory behavior, and a wider free-chat path for ordinary conversation.

## Headline goals

- Keep the original packaged prefix, drift, probe, 250k, 1M, and 10M checks stable on the proven numeric fallback profile.
- Ship a truthful v24 grounded seed plus a separate curated v24 open-chat seed.
- Make the default free-chat loop materially broader without pretending SBAN is a broad general knowledge model.
- Preserve CPU fallback automatically and prefer accelerated paths only where they actually help.
- Keep measuring CUDA and `cpu_mt` explicitly for retrieval and numeric experiments without changing the packaged numeric regression baseline.

## Main files

- Runtime: `src/network.zig`, `src/dialogue.zig`, `src/main.zig`
- Numeric profile knobs: `src/config.zig`
- Dialogue assets:
  - `data/sban_dialogue_seed_v24.txt`
  - `data/sban_dialogue_open_seed_v24.txt`
  - `data/sban_chat_eval_prompts_v24.txt`
  - `data/sban_session_eval_v24.txt`
  - `data/sban_open_chat_session_eval_v24.txt`
- Release scripts:
  - `scripts/run_v24_release.py`
  - `scripts/make_v24_deliverables.py`
  - `scripts/package_v24_demo.py`
- Release notes and thresholds: `references/release_profiles.md`

## Build

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

## Try the v24 runtime from source

One-shot free chat:

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v24" 180 seed_path=data/sban_dialogue_seed_v24.txt open_seed_path=data/sban_dialogue_open_seed_v24.txt backend=auto mode=free allow_generation=true
```

Continuing-session examples:

```bash
zig-out/bin/zig_sban chat-demo "hi i am tom and i need help" 180 seed_path=data/sban_dialogue_seed_v24.txt open_seed_path=data/sban_dialogue_open_seed_v24.txt session_path=session_v24.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "can you recall my name" 180 seed_path=data/sban_dialogue_seed_v24.txt open_seed_path=data/sban_dialogue_open_seed_v24.txt session_path=session_v24.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "i am from london" 180 seed_path=data/sban_dialogue_seed_v24.txt open_seed_path=data/sban_dialogue_open_seed_v24.txt session_path=session_v24.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where am i from" 180 seed_path=data/sban_dialogue_seed_v24.txt open_seed_path=data/sban_dialogue_open_seed_v24.txt session_path=session_v24.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what files ship in the bundle" 180 seed_path=data/sban_dialogue_seed_v24.txt open_seed_path=data/sban_dialogue_open_seed_v24.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what command shows cuda support" 180 seed_path=data/sban_dialogue_seed_v24.txt open_seed_path=data/sban_dialogue_open_seed_v24.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "can you help me plan tomorrow" 180 seed_path=data/sban_dialogue_seed_v24.txt open_seed_path=data/sban_dialogue_open_seed_v24.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what should i do this weekend" 180 seed_path=data/sban_dialogue_seed_v24.txt open_seed_path=data/sban_dialogue_open_seed_v24.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what is the capital of peru" 180 seed_path=data/sban_dialogue_seed_v24.txt open_seed_path=data/sban_dialogue_open_seed_v24.txt backend=auto mode=free allow_generation=true
```

Inspect GPU availability:

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v24.txt backend=cuda
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v24.txt backend=cpu_mt threads=4
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1
```

If you want to benchmark raw retrieval throughput directly, use:

```bash
zig-out/bin/zig_sban accel-bench docs/results/v24/accel_prompts_v24_bench.txt backend=cuda seed_path=docs/results/v24/accel_seed_v24_bench.txt iterations=4
```

If you want to force the older generic GPU selection path instead of naming CUDA or OpenCL explicitly, add `backend=gpu`.

## Run the measured v24 suite

```bash
python scripts/run_v24_release.py
```

To reuse an existing `zig-out` binary:

```bash
python scripts/run_v24_release.py --skip-build
```

This writes the measured artifacts to `docs/results/v24/`, including:

- `unified_prefix_v24_release.json`
- `unified_drift_v24_release.json`
- `unified_probe_v24_release.json`
- `longrun_v24_250k.json`
- `longrun_v24_1m.json`
- `longrun_v24_10m.json`
- `chat_eval_v24_hybrid.txt`
- `chat_eval_v24_free.txt`
- `chat_session_eval_v24.txt`
- `open_chat_session_eval_v24.txt`
- `accel_info_v24_cpu_mt.txt`
- `accel_info_v24_cuda.txt`
- `numeric_accel_info_v24_cpu.txt`
- `numeric_accel_info_v24_cpu_mt.txt`
- `numeric_accel_info_v24_cuda.txt`
- `accel_bench_v24.json`
- `numeric_backend_v24.json`

## Generate the v24 report, summary, paper, demo bundle, and repo zip

```bash
python scripts/make_v24_deliverables.py
```

Generated outputs include:

- `SBAN_v24_REPORT.md`
- `SBAN_v24_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v24_follow_up_research_paper.pdf`
- `deliverables/v24/SBAN_v24_repo.zip`
- `deliverables/v24/demo/SBAN_v24_windows_x86_64_demo.zip` on Windows

## Package the newcomer demo directly

```bash
python scripts/package_v24_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

Linux example:

```bash
python scripts/package_v24_demo.py --binary zig-out/bin/zig_sban --platform linux_x86_64
```

The newcomer scripts use `backend=auto` and load both the grounded and open-chat v24 seeds. Small bundled workloads still often resolve to CPU, while larger NVIDIA-backed retrieval workloads can promote themselves to CUDA automatically. Retrieval CUDA and `cpu_mt` experiments remain available through `backend=cuda`, `backend=cpu_mt`, `accel-info`, and `accel-bench`, while the packaged numeric suite stays on `numeric_backend=cpu` and numeric `cpu_mt` or CUDA remain explicit experiments through `numeric-accel-info` plus `eval-variant`.

## CI and release automation

- `.github/workflows/ci.yml` builds and tests SBAN on Windows and Ubuntu and runs both the main v24 session smoke checks and the v24 open-chat smoke checks.
- `.github/workflows/release.yml` packages v24 demo bundles for Windows and Linux and uploads them on `v24*` tags.

## Important benchmark note

The numeric suite is still an engine-health and hardening profile, not a broad generalization benchmark. V24 intentionally keeps the packaged numeric suite on the single-thread CPU fallback because accelerated numeric backends should only become the default when the measured end-to-end release profile actually wins.

## Product note

V24 is much broader and calmer in free chat than v23, but it is still not a broad general knowledge model. It should answer grounded SBAN questions, remembered session facts, short math, and a wider set of ordinary conversational prompts well, while still declining unsupported factual questions honestly.

## Bottom line

V24 is the product release that keeps the proven backend stack and numeric guardrail intact while making SBAN feel much closer to a dependable collaborator in actual continuing chat.
