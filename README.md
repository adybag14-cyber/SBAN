# SBAN v23.5

SBAN v23.5 is the current technical backend release of the Sparse Bridge-Adaptive Network runtime.

This release keeps the established numeric engine-health suite on the proven single-thread CPU profile while extending CUDA deeper into the stack. The v23 conversational runtime remains in place, but v23.5 adds a real numeric CUDA backend for `eval-variant`, a `numeric-accel-info` probe command, and measured CPU versus `cpu_mt` versus CUDA comparisons for both dialogue retrieval and numeric scoring.

## Headline goals

- Keep the original packaged prefix, drift, probe, 250k, 1M, and 10M checks stable on the proven numeric fallback profile.
- Keep the v23.5 chat seed and product surface stable while re-versioning the bundle and starter files cleanly.
- Preserve CPU fallback automatically and prefer accelerated paths only where they actually help.
- Expose numeric CPU, `cpu_mt`, and CUDA backends for experimentation without changing the packaged regression baseline.

## Main files

- Runtime: `src/network.zig`, `src/dialogue.zig`, `src/main.zig`
- Numeric profile knobs: `src/config.zig`
- Dialogue assets: `data/sban_dialogue_seed_v23_5.txt`, `data/sban_chat_eval_prompts_v23_5.txt`, `data/sban_session_eval_v23_5.txt`
- Release scripts: `scripts/run_v23_5_release.py`, `scripts/make_v23_5_deliverables.py`, `scripts/package_v23_5_demo.py`
- Release notes and thresholds: `references/release_profiles.md`

## Build

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

## Try the v23.5 runtime from source

One-shot free chat:

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v23.5" 180 seed_path=data/sban_dialogue_seed_v23_5.txt backend=cpu mode=free allow_generation=true
```

Continuing-session examples:

```bash
zig-out/bin/zig_sban chat-demo "hi i am tom and i need help" 180 seed_path=data/sban_dialogue_seed_v23_5.txt session_path=session_v23_5.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "can you recall my name" 180 seed_path=data/sban_dialogue_seed_v23_5.txt session_path=session_v23_5.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "i am from london" 180 seed_path=data/sban_dialogue_seed_v23_5.txt session_path=session_v23_5.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where am i from" 180 seed_path=data/sban_dialogue_seed_v23_5.txt session_path=session_v23_5.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "i work in the sbx lab" 180 seed_path=data/sban_dialogue_seed_v23_5.txt session_path=session_v23_5.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what lab do i work in" 180 seed_path=data/sban_dialogue_seed_v23_5.txt session_path=session_v23_5.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what command shows cuda support" 180 seed_path=data/sban_dialogue_seed_v23_5.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what command shows numeric cuda support" 180 seed_path=data/sban_dialogue_seed_v23_5.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "tell me a joke" 180 seed_path=data/sban_dialogue_seed_v23_5.txt backend=cpu mode=free allow_generation=true
```

Inspect GPU availability:

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v23_5.txt backend=cuda
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v23_5.txt backend=cpu_mt threads=4
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1
```

If you want to benchmark raw retrieval throughput directly, use:

```bash
zig-out/bin/zig_sban accel-bench docs/results/v23_5/accel_prompts_v23_5_bench.txt backend=cuda seed_path=docs/results/v23_5/accel_seed_v23_5_bench.txt iterations=4
```

If you want to force the older generic GPU selection path instead of naming CUDA or OpenCL explicitly, add `backend=gpu`.

## Run the measured v23.5 suite

```bash
python scripts/run_v23_5_release.py
```

To reuse an existing `zig-out` binary:

```bash
python scripts/run_v23_5_release.py --skip-build
```

This writes the measured artifacts to `docs/results/v23_5/`, including:

- `unified_prefix_v23_5_release.json`
- `unified_drift_v23_5_release.json`
- `unified_probe_v23_5_release.json`
- `longrun_v23_5_250k.json`
- `longrun_v23_5_1m.json`
- `longrun_v23_5_10m.json`
- `chat_eval_v23_5_hybrid.txt`
- `chat_eval_v23_5_free.txt`
- `chat_session_eval_v23_5.txt`
- `accel_info_v23_5_cpu_mt.txt`
- `accel_info_v23_5_cuda.txt`
- `numeric_accel_info_v23_5_cpu.txt`
- `numeric_accel_info_v23_5_cpu_mt.txt`
- `numeric_accel_info_v23_5_cuda.txt`
- `accel_bench_v23_5.json`
- `numeric_backend_v23_5.json`

## Generate the v23.5 report, summary, paper, demo bundle, and repo zip

```bash
python scripts/make_v23_5_deliverables.py
```

Generated outputs include:

- `SBAN_v23_5_REPORT.md`
- `SBAN_v23_5_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v23_5_follow_up_research_paper.pdf`
- `deliverables/v23_5/SBAN_v23_5_repo.zip`
- `deliverables/v23_5/demo/SBAN_v23_5_windows_x86_64_demo.zip` on Windows

## Package the newcomer demo directly

```bash
python scripts/package_v23_5_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

Linux example:

```bash
python scripts/package_v23_5_demo.py --binary zig-out/bin/zig_sban --platform linux_x86_64
```

The newcomer scripts still default to `backend=cpu` for the bundled grounded corpus, but the default chat loop runs in free mode with safe conversational composition enabled. Retrieval CUDA and `cpu_mt` experiments remain available through `backend=cuda`, `backend=cpu_mt`, `accel-info`, and `accel-bench`, while numeric backend experiments now use `numeric-accel-info` plus `numeric_backend=cpu_mt` or `numeric_backend=cuda` on `eval-variant`.

## CI and release automation

- `.github/workflows/ci.yml` builds and tests SBAN on Windows and Ubuntu and runs the v23.5 session smoke checks.
- `.github/workflows/release.yml` packages v23.5 demo bundles for Windows and Linux and uploads them on `v23.5*` tags.

## Important benchmark note

The numeric suite is still an engine-health and hardening profile, not a broad generalization benchmark. V23.5 intentionally keeps the packaged numeric suite on the single-thread CPU fallback because accelerated numeric backends should only become the default when the measured end-to-end release profile actually wins.

## Bottom line

V23.5 is the backend release that extends CUDA beyond dialogue retrieval into the numeric stack while keeping the v23 chat surface, artifact knowledge, session memory, and grounded uncertainty behavior stable.

