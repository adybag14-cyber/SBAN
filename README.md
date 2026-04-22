# SBAN v22.5

SBAN v22.5 is the current technical research release of the Sparse Bridge-Adaptive Network runtime.

This point release keeps the established numeric engine-health suite on the proven single-thread profile while adding a real CUDA backend for NVIDIA RTX GPUs, a raw accelerator benchmark command, conservative multithreaded retrieval support, and an experimental multithreaded numeric scorer that remains optional when it does not beat the fallback path.

## Headline goals

- Keep the original packaged prefix, drift, probe, 250k, 1M, and 10M checks stable on the proven numeric fallback profile.
- Add measurable backend realism: real NVIDIA CUDA retrieval acceleration, `accel-bench`, and explicit `cpu_mt` retrieval support.
- Preserve CPU fallback automatically and prefer accelerated paths only where they actually help.

## Main files

- Runtime: `src/network.zig`, `src/dialogue.zig`, `src/main.zig`
- Numeric profile knobs: `src/config.zig`
- Dialogue assets: `data/sban_dialogue_seed_v22.txt`, `data/sban_chat_eval_prompts_v22_5.txt`, `data/sban_session_eval_v22_5.txt`
- Release scripts: `scripts/run_v22_5_release.py`, `scripts/make_v22_5_deliverables.py`, `scripts/package_v22_5_demo.py`
- Release notes and thresholds: `references/release_profiles.md`

## Build

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

## Try the v22.5 chat runtime from source

One-shot grounded chat:

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v22.5" 160 seed_path=data/sban_dialogue_seed_v22.txt backend=cpu
```

Continuing-session examples:

```bash
zig-out/bin/zig_sban chat-demo "hi i am tom and i need help" 160 seed_path=data/sban_dialogue_seed_v22.txt session_path=session_v22.txt backend=cpu
zig-out/bin/zig_sban chat-demo "can you recall my name" 160 seed_path=data/sban_dialogue_seed_v22.txt session_path=session_v22.txt backend=cpu
zig-out/bin/zig_sban chat-demo "i live in london" 160 seed_path=data/sban_dialogue_seed_v22.txt session_path=session_v22.txt backend=cpu
zig-out/bin/zig_sban chat-demo "what city do i live in" 160 seed_path=data/sban_dialogue_seed_v22.txt session_path=session_v22.txt backend=cpu
zig-out/bin/zig_sban chat-demo "my role is researcher" 160 seed_path=data/sban_dialogue_seed_v22.txt session_path=session_v22.txt backend=cpu
zig-out/bin/zig_sban chat-demo "what is my role" 160 seed_path=data/sban_dialogue_seed_v22.txt session_path=session_v22.txt backend=cpu
zig-out/bin/zig_sban chat-demo "what is 3 / 0" 160 seed_path=data/sban_dialogue_seed_v22.txt backend=cpu
```

Inspect GPU availability:

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v22.txt backend=cuda
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v22.txt backend=cpu_mt threads=4
```

If you want to benchmark raw retrieval throughput directly, use:

```bash
zig-out/bin/zig_sban accel-bench docs/results/v22_5/accel_prompts_v22_5_bench.txt backend=cuda seed_path=docs/results/v22_5/accel_seed_v22_5_bench.txt iterations=4
```

If you want to force the older generic GPU selection path instead of naming CUDA or OpenCL explicitly, add `backend=gpu`.

## Run the measured v22.5 suite

```bash
python scripts/run_v22_5_release.py
```

To reuse an existing `zig-out` binary:

```bash
python scripts/run_v22_5_release.py --skip-build
```

This writes the measured artifacts to `docs/results/v22_5/`, including:

- `unified_prefix_v22_5_release.json`
- `unified_drift_v22_5_release.json`
- `unified_probe_v22_5_release.json`
- `longrun_v22_5_250k.json`
- `longrun_v22_5_1m.json`
- `longrun_v22_5_10m.json`
- `chat_eval_v22_5_hybrid.txt`
- `chat_eval_v22_5_free.txt`
- `chat_session_eval_v22_5.txt`
- `accel_info_v22_5_cpu_mt.txt`
- `accel_info_v22_5_cuda.txt`
- `accel_bench_v22_5.json`
- `numeric_backend_v22_5.json`

## Generate the v22.5 report, summary, paper, demo bundle, and repo zip

```bash
python scripts/make_v22_5_deliverables.py
```

Generated outputs include:

- `SBAN_v22_5_REPORT.md`
- `SBAN_v22_5_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v22_5_follow_up_research_paper.pdf`
- `deliverables/v22_5/SBAN_v22_5_repo.zip`
- `deliverables/v22_5/demo/SBAN_v22_5_windows_x86_64_demo.zip` on Windows

## Package the newcomer demo directly

```bash
python scripts/package_v22_5_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

Linux example:

```bash
python scripts/package_v22_5_demo.py --binary zig-out/bin/zig_sban --platform linux_x86_64
```

The newcomer scripts still default to `backend=cpu` for the bundled small grounded corpus. CUDA and `cpu_mt` experiments remain available explicitly through `backend=cuda`, `backend=cpu_mt`, `accel-info`, and `accel-bench`.

## CI and release automation

- `.github/workflows/ci.yml` builds and tests SBAN on Windows and Ubuntu and runs the v22.5 session smoke checks.
- `.github/workflows/release.yml` packages v22.5 demo bundles for Windows and Linux and uploads them on `v22*` tags.

## Important benchmark note

The numeric suite is still an engine-health and hardening profile, not a broad generalization benchmark. The v22.5 point release intentionally keeps the packaged numeric suite on the single-thread fallback because the experimental multithreaded numeric scorer did not show a dependable win on the shipped 250k and 1M profiles.

## Bottom line

V22.5 is the release where SBAN's acceleration story becomes real without pretending every new backend deserves to replace the old fallback.
