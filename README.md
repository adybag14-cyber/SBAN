# SBAN v23

SBAN v23 is the current conversational research release of the Sparse Bridge-Adaptive Network runtime.

This release keeps the established numeric engine-health suite on the proven single-thread profile while repairing the actual chat product surface: a real v23 dialogue seed, broader paraphrase and operational coverage, stronger natural session memory, safer hardware-aware retrieval, and a default free-chat loop that behaves more like a calm collaborator than a scripted demo.

## Headline goals

- Keep the original packaged prefix, drift, probe, 250k, 1M, and 10M checks stable on the proven numeric fallback profile.
- Ship a real v23 chat seed that knows the current starter files, artifact paths, CUDA commands, backend comparisons, and roadmap stance.
- Preserve CPU fallback automatically and prefer accelerated paths only where they actually help.
- Make default free chat useful without abandoning grounded uncertainty.

## Main files

- Runtime: `src/network.zig`, `src/dialogue.zig`, `src/main.zig`
- Numeric profile knobs: `src/config.zig`
- Dialogue assets: `data/sban_dialogue_seed_v23.txt`, `data/sban_chat_eval_prompts_v23.txt`, `data/sban_session_eval_v23.txt`
- Release scripts: `scripts/run_v23_release.py`, `scripts/make_v23_deliverables.py`, `scripts/package_v23_demo.py`
- Release notes and thresholds: `references/release_profiles.md`

## Build

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

## Try the v23 chat runtime from source

One-shot free chat:

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v23" 180 seed_path=data/sban_dialogue_seed_v23.txt backend=cpu mode=free allow_generation=true
```

Continuing-session examples:

```bash
zig-out/bin/zig_sban chat-demo "hi i am tom and i need help" 180 seed_path=data/sban_dialogue_seed_v23.txt session_path=session_v23.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "can you recall my name" 180 seed_path=data/sban_dialogue_seed_v23.txt session_path=session_v23.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "i am from london" 180 seed_path=data/sban_dialogue_seed_v23.txt session_path=session_v23.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where am i from" 180 seed_path=data/sban_dialogue_seed_v23.txt session_path=session_v23.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "i work in the sbx lab" 180 seed_path=data/sban_dialogue_seed_v23.txt session_path=session_v23.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what lab do i work in" 180 seed_path=data/sban_dialogue_seed_v23.txt session_path=session_v23.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what command shows cuda support" 180 seed_path=data/sban_dialogue_seed_v23.txt backend=cpu mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "tell me a joke" 180 seed_path=data/sban_dialogue_seed_v23.txt backend=cpu mode=free allow_generation=true
```

Inspect GPU availability:

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v23.txt backend=cuda
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v23.txt backend=cpu_mt threads=4
```

If you want to benchmark raw retrieval throughput directly, use:

```bash
zig-out/bin/zig_sban accel-bench docs/results/v23/accel_prompts_v23_bench.txt backend=cuda seed_path=docs/results/v23/accel_seed_v23_bench.txt iterations=4
```

If you want to force the older generic GPU selection path instead of naming CUDA or OpenCL explicitly, add `backend=gpu`.

## Run the measured v23 suite

```bash
python scripts/run_v23_release.py
```

To reuse an existing `zig-out` binary:

```bash
python scripts/run_v23_release.py --skip-build
```

This writes the measured artifacts to `docs/results/v23/`, including:

- `unified_prefix_v23_release.json`
- `unified_drift_v23_release.json`
- `unified_probe_v23_release.json`
- `longrun_v23_250k.json`
- `longrun_v23_1m.json`
- `longrun_v23_10m.json`
- `chat_eval_v23_hybrid.txt`
- `chat_eval_v23_free.txt`
- `chat_session_eval_v23.txt`
- `accel_info_v23_cpu_mt.txt`
- `accel_info_v23_cuda.txt`
- `accel_bench_v23.json`
- `numeric_backend_v23.json`

## Generate the v23 report, summary, paper, demo bundle, and repo zip

```bash
python scripts/make_v23_deliverables.py
```

Generated outputs include:

- `SBAN_v23_REPORT.md`
- `SBAN_v23_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v23_follow_up_research_paper.pdf`
- `deliverables/v23/SBAN_v23_repo.zip`
- `deliverables/v23/demo/SBAN_v23_windows_x86_64_demo.zip` on Windows

## Package the newcomer demo directly

```bash
python scripts/package_v23_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

Linux example:

```bash
python scripts/package_v23_demo.py --binary zig-out/bin/zig_sban --platform linux_x86_64
```

The newcomer scripts still default to `backend=cpu` for the bundled grounded corpus, but the default chat loop now runs in free mode with safe conversational composition enabled. CUDA and `cpu_mt` experiments remain available explicitly through `backend=cuda`, `backend=cpu_mt`, `accel-info`, and `accel-bench`.

## CI and release automation

- `.github/workflows/ci.yml` builds and tests SBAN on Windows and Ubuntu and runs the v23 session smoke checks.
- `.github/workflows/release.yml` packages v23 demo bundles for Windows and Linux and uploads them on `v23*` tags.

## Important benchmark note

The numeric suite is still an engine-health and hardening profile, not a broad generalization benchmark. V23 intentionally keeps the packaged numeric suite on the single-thread fallback because the experimental multithreaded numeric scorer still has not shown a dependable win on the shipped profiles.

## Bottom line

V23 is the release where SBAN's chat surface finally catches up to the backend work: the runtime knows its own files and commands, handles more natural session memory, answers a useful slice of free conversation, and still refuses to bluff when support is weak.
