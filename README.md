# SBAN v25

SBAN v25 is the current conversational product release of the Sparse Bridge-Adaptive Network runtime.

This release keeps the established numeric engine-health suite on the proven single-thread CPU profile while materially broadening the shipped free-chat surface. v25 keeps the measured CPU, `cpu_mt`, CUDA, and OpenCL backend stack from the recent backend work, but adds a real v25 grounded seed, a separate v25 open-chat seed, broader operational answers, stronger session-memory behavior, and a wider deterministic free-chat path for ordinary prompts.

## Headline goals

- Keep the original packaged prefix, drift, probe, 250k, 1M, and 10M checks stable on the proven numeric fallback profile.
- Ship a truthful v25 grounded seed plus a separate curated and dataset-enriched v25 open-chat seed.
- Make the default free-chat loop materially broader for everyday prompts without pretending SBAN is a broad general knowledge model.
- Preserve CPU fallback automatically and prefer accelerated paths only where they actually help.
- Keep measuring CUDA and `cpu_mt` explicitly for retrieval and numeric experiments without changing the packaged numeric regression baseline.

## Main files

- Runtime: `src/network.zig`, `src/dialogue.zig`, `src/main.zig`
- Numeric profile knobs: `src/config.zig`
- Dialogue assets:
  - `data/sban_dialogue_seed_v25.txt`
  - `data/sban_dialogue_open_seed_v25.txt`
  - `data/sban_chat_eval_prompts_v25.txt`
  - `data/sban_session_eval_v25.txt`
  - `data/sban_open_chat_session_eval_v25.txt`
- Seed builder:
  - `scripts/build_v25_open_seed.py`
- Release scripts:
  - `scripts/run_v25_release.py`
  - `scripts/make_v25_deliverables.py`
  - `scripts/package_v25_demo.py`
- Release notes and thresholds: `references/release_profiles.md`

## Build

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

## Try the v25 runtime from source

One-shot free chat:

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v25" 180 seed_path=data/sban_dialogue_seed_v25.txt open_seed_path=data/sban_dialogue_open_seed_v25.txt backend=auto mode=free allow_generation=true
```

Continuing-session examples:

```bash
zig-out/bin/zig_sban chat-demo "hi i am tom and i need help" 180 seed_path=data/sban_dialogue_seed_v25.txt open_seed_path=data/sban_dialogue_open_seed_v25.txt session_path=session_v25.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "can you recall my name" 180 seed_path=data/sban_dialogue_seed_v25.txt open_seed_path=data/sban_dialogue_open_seed_v25.txt session_path=session_v25.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "i am from london" 180 seed_path=data/sban_dialogue_seed_v25.txt open_seed_path=data/sban_dialogue_open_seed_v25.txt session_path=session_v25.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where am i from" 180 seed_path=data/sban_dialogue_seed_v25.txt open_seed_path=data/sban_dialogue_open_seed_v25.txt session_path=session_v25.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what files ship in the bundle" 180 seed_path=data/sban_dialogue_seed_v25.txt open_seed_path=data/sban_dialogue_open_seed_v25.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what command shows cuda support" 180 seed_path=data/sban_dialogue_seed_v25.txt open_seed_path=data/sban_dialogue_open_seed_v25.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "help me write a meeting agenda" 180 seed_path=data/sban_dialogue_seed_v25.txt open_seed_path=data/sban_dialogue_open_seed_v25.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what is photosynthesis in simple terms" 180 seed_path=data/sban_dialogue_seed_v25.txt open_seed_path=data/sban_dialogue_open_seed_v25.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "write a python function to reverse a string" 180 seed_path=data/sban_dialogue_seed_v25.txt open_seed_path=data/sban_dialogue_open_seed_v25.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what is 15% of 240" 180 seed_path=data/sban_dialogue_seed_v25.txt open_seed_path=data/sban_dialogue_open_seed_v25.txt backend=auto mode=free allow_generation=true
```

Inspect GPU availability:

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v25.txt backend=cuda
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v25.txt backend=cpu_mt threads=4
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1
```

If you want to benchmark raw retrieval throughput directly, use:

```bash
zig-out/bin/zig_sban accel-bench docs/results/v25/accel_prompts_v25_bench.txt backend=cuda seed_path=docs/results/v25/accel_seed_v25_bench.txt iterations=4
```

If you want to force the older generic GPU selection path instead of naming CUDA or OpenCL explicitly, add `backend=gpu`.

## Rebuild the expanded v25 open seed

The shipped `data/sban_dialogue_open_seed_v25.txt` is a curated seed built from the earlier open seed, hand-added practical prompts, and optional filtered SQuAD pairs.

```bash
python scripts/build_v25_open_seed.py
```

To skip the optional `datasets` dependency and network-backed SQuAD load:

```bash
python scripts/build_v25_open_seed.py --no-datasets
```

## Run the measured v25 suite

```bash
python scripts/run_v25_release.py
```

To reuse an existing `zig-out` binary:

```bash
python scripts/run_v25_release.py --skip-build
```

This writes the measured artifacts to `docs/results/v25/`, including:

- `unified_prefix_v25_release.json`
- `unified_drift_v25_release.json`
- `unified_probe_v25_release.json`
- `longrun_v25_250k.json`
- `longrun_v25_1m.json`
- `longrun_v25_10m.json`
- `chat_eval_v25_hybrid.txt`
- `chat_eval_v25_free.txt`
- `chat_session_eval_v25.txt`
- `open_chat_session_eval_v25.txt`
- `accel_info_v25_cpu_mt.txt`
- `accel_info_v25_cuda.txt`
- `numeric_accel_info_v25_cpu.txt`
- `numeric_accel_info_v25_cpu_mt.txt`
- `numeric_accel_info_v25_cuda.txt`
- `accel_bench_v25.json`
- `numeric_backend_v25.json`

## Generate the v25 report, summary, paper, demo bundle, and repo zip

```bash
python scripts/make_v25_deliverables.py
```

Generated outputs include:

- `SBAN_v25_REPORT.md`
- `SBAN_v25_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v25_follow_up_research_paper.pdf`
- `deliverables/v25/SBAN_v25_repo.zip`
- `deliverables/v25/demo/SBAN_v25_windows_x86_64_demo.zip` on Windows

## Package the newcomer demo directly

```bash
python scripts/package_v25_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

Linux example:

```bash
python scripts/package_v25_demo.py --binary zig-out/bin/zig_sban --platform linux_x86_64
```

The newcomer scripts use `backend=auto` and load both the grounded and open-chat v25 seeds. Small bundled workloads still often resolve to CPU, while larger NVIDIA-backed retrieval workloads can promote themselves to CUDA automatically. Retrieval CUDA and `cpu_mt` experiments remain available through `backend=cuda`, `backend=cpu_mt`, `accel-info`, and `accel-bench`, while the packaged numeric suite stays on `numeric_backend=cpu` and numeric `cpu_mt` or CUDA remain explicit experiments through `numeric-accel-info` plus `eval-variant`.

## CI and release automation

- `.github/workflows/ci.yml` builds and tests SBAN on Windows and Ubuntu and runs both the main v25 session smoke checks and the v25 open-chat smoke checks.
- `.github/workflows/release.yml` packages v25 demo bundles for Windows and Linux and uploads them on `v25*` tags.

## Important benchmark note

The numeric suite is still an engine-health and hardening profile, not a broad generalization benchmark. v25 intentionally keeps the packaged numeric suite on the single-thread CPU fallback because accelerated numeric backends should only become the default when the measured end-to-end release profile actually wins.

## Product note

v25 is materially broader and calmer in free chat than v24, but it is still not a broad general knowledge model. It should answer grounded SBAN questions, remembered session facts, short math, and a wider set of ordinary conversational prompts well, while still declining unsupported factual questions honestly.

## Bottom line

v25 is the product release that keeps the proven backend stack and numeric guardrail intact while making SBAN substantially more useful for ordinary continuing chat.
