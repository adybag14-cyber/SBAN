# SBAN v26

SBAN v26 is the current conversational product release of the Sparse Bridge-Adaptive Network runtime.

This release keeps the packaged numeric suite on the proven single-thread CPU baseline, extends the hardening ladder to `20M`, and upgrades the user-facing chat runtime so ordinary free-chat prompts, natural fact memory, operational answers, and Zig-upstream questions are much less brittle than earlier releases.

## Headline goals

- Keep the established prefix, drift, probe, `250k`, `1M`, and `10M` numeric guardrail stable on the original CPU release profile.
- Extend the hardening suite with a measured `20M` run.
- Ship a real v26 grounded seed plus a separate curated and dataset-enriched v26 open-chat seed.
- Fix the earlier free-chat failure modes where ordinary prompts either fell to uncertainty or overmatched unrelated SBAN answers.
- Broaden deterministic coverage for everyday explanations, writing help, coding help, natural session memory, and Zig-upstream operational questions.
- Keep CUDA, `cpu_mt`, and OpenCL measured explicitly instead of promoting them by preference.

## Main files

- Runtime:
  - `src/network.zig`
  - `src/dialogue.zig`
  - `src/main.zig`
- Numeric profile knobs:
  - `src/config.zig`
- Dialogue assets:
  - `data/sban_dialogue_seed_v26.txt`
  - `data/sban_dialogue_open_seed_v26.txt`
  - `data/sban_chat_eval_prompts_v26.txt`
  - `data/sban_session_eval_v26.txt`
  - `data/sban_open_chat_session_eval_v26.txt`
  - `data/sban_broad_chat_session_eval_v26.txt`
- Seed builder:
  - `scripts/build_v26_open_seed.py`
- Release scripts:
  - `scripts/run_v26_release.py`
  - `scripts/make_v26_deliverables.py`
  - `scripts/package_v26_demo.py`
- Release thresholds and caveats:
  - `references/release_profiles.md`

## Build

If `zig` is not on `PATH`, either pass `--zig-exe` to the release script or use the extracted local toolchain path, for example:

```bash
C:/Users/Ady/Downloads/zig-x86_64-windows-0.17.0-dev.87+9b177a7d2/zig-x86_64-windows-0.17.0-dev.87+9b177a7d2/zig.exe build test
C:/Users/Ady/Downloads/zig-x86_64-windows-0.17.0-dev.87+9b177a7d2/zig-x86_64-windows-0.17.0-dev.87+9b177a7d2/zig.exe build -Doptimize=ReleaseFast
```

If `zig` is already configured:

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

## Try the v26 runtime from source

One-shot free chat:

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v26" 180 seed_path=data/sban_dialogue_seed_v26.txt open_seed_path=data/sban_dialogue_open_seed_v26.txt backend=auto mode=free allow_generation=true
```

Continuing-session examples:

```bash
zig-out/bin/zig_sban chat-demo "hi i am tom and i need help" 180 seed_path=data/sban_dialogue_seed_v26.txt open_seed_path=data/sban_dialogue_open_seed_v26.txt session_path=session_v26.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "can you recall my name" 180 seed_path=data/sban_dialogue_seed_v26.txt open_seed_path=data/sban_dialogue_open_seed_v26.txt session_path=session_v26.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "our team is atlas" 180 seed_path=data/sban_dialogue_seed_v26.txt open_seed_path=data/sban_dialogue_open_seed_v26.txt session_path=session_v26.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what team am i on" 180 seed_path=data/sban_dialogue_seed_v26.txt open_seed_path=data/sban_dialogue_open_seed_v26.txt session_path=session_v26.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "i am from london" 180 seed_path=data/sban_dialogue_seed_v26.txt open_seed_path=data/sban_dialogue_open_seed_v26.txt session_path=session_v26.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where am i from" 180 seed_path=data/sban_dialogue_seed_v26.txt open_seed_path=data/sban_dialogue_open_seed_v26.txt session_path=session_v26.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what files ship in the bundle" 180 seed_path=data/sban_dialogue_seed_v26.txt open_seed_path=data/sban_dialogue_open_seed_v26.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what command shows cuda support" 180 seed_path=data/sban_dialogue_seed_v26.txt open_seed_path=data/sban_dialogue_open_seed_v26.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "write a python class for a stack" 180 seed_path=data/sban_dialogue_seed_v26.txt open_seed_path=data/sban_dialogue_open_seed_v26.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what is json" 180 seed_path=data/sban_dialogue_seed_v26.txt open_seed_path=data/sban_dialogue_open_seed_v26.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where is std.hashmap implemented in zig upstream" 180 seed_path=data/sban_dialogue_seed_v26.txt open_seed_path=data/sban_dialogue_open_seed_v26.txt backend=auto mode=free allow_generation=true
```

## Inspect accelerator support

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v26.txt backend=cuda
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v26.txt backend=cpu_mt threads=4
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu_mt score_threads=4 parallel_score_min_predictive_nodes=1
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1
```

Raw retrieval throughput:

```bash
zig-out/bin/zig_sban accel-bench docs/results/v26/accel_prompts_v26_bench.txt backend=cuda seed_path=docs/results/v26/accel_seed_v26_bench.txt iterations=4
```

## Rebuild the expanded v26 open seed

The shipped `data/sban_dialogue_open_seed_v26.txt` is built from the earlier open seed, curated v26 additions, optional filtered SQuAD coverage, and Zig-upstream prompts derived from the local Zig source zip.

```bash
python scripts/build_v26_open_seed.py
```

To skip optional dataset loading:

```bash
python scripts/build_v26_open_seed.py --no-datasets
```

## Run the measured v26 suite

```bash
python scripts/run_v26_release.py
```

To reuse an existing `zig-out` binary:

```bash
python scripts/run_v26_release.py --skip-build
```

If `zig` is not on `PATH`:

```bash
python scripts/run_v26_release.py --zig-exe "C:/Users/Ady/Downloads/zig-x86_64-windows-0.17.0-dev.87+9b177a7d2/zig-x86_64-windows-0.17.0-dev.87+9b177a7d2/zig.exe"
```

This writes measured artifacts to `docs/results/v26/`, including:

- `unified_prefix_v26_release.json`
- `unified_drift_v26_release.json`
- `unified_probe_v26_release.json`
- `longrun_v26_250k.json`
- `longrun_v26_1m.json`
- `longrun_v26_10m.json`
- `longrun_v26_20m.json`
- `chat_eval_v26_hybrid.txt`
- `chat_eval_v26_free.txt`
- `chat_session_eval_v26.txt`
- `open_chat_session_eval_v26.txt`
- `broad_chat_session_eval_v26.txt`
- `accel_info_v26_cpu_mt.txt`
- `accel_info_v26_cuda.txt`
- `numeric_accel_info_v26_cpu.txt`
- `numeric_accel_info_v26_cpu_mt.txt`
- `numeric_accel_info_v26_cuda.txt`
- `accel_bench_v26.json`
- `numeric_backend_v26.json`
- `STATUS.md`

## Generate the v26 report, summary, paper, demo bundle, and repo zip

```bash
python scripts/make_v26_deliverables.py
```

Generated outputs include:

- `SBAN_v26_REPORT.md`
- `SBAN_v26_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v26_follow_up_research_paper.pdf`
- `deliverables/v26/SBAN_v26_repo.zip`
- `deliverables/v26/demo/SBAN_v26_windows_x86_64_demo.zip` on Windows
- `deliverables/v26/demo/SBAN_v26_linux_x86_64_demo.zip` on Linux

## Package the newcomer demo directly

```bash
python scripts/package_v26_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

Linux example:

```bash
python scripts/package_v26_demo.py --binary zig-out/bin/zig_sban --platform linux_x86_64
```

The newcomer scripts use `backend=auto` and load both the grounded and open-chat v26 seeds. Small bundled workloads still often stay on CPU, while larger NVIDIA-backed retrieval workloads can promote to CUDA automatically. The packaged numeric suite still stays on `numeric_backend=cpu` until accelerated numeric runs prove a dependable end-to-end win.

## CI and release automation

- `.github/workflows/ci.yml` builds and tests SBAN on Windows and Ubuntu and runs the v26 session smoke checks, the v26 open-chat smoke checks, and the v26 broad-chat battery.
- `.github/workflows/release.yml` packages v26 demo bundles for Windows and Linux and uploads them on `v26*` tags.

## Important benchmark note

The numeric suite is still an engine-health and hardening profile, not a broad generalization benchmark. v26 intentionally keeps the packaged numeric suite on the single-thread CPU fallback and extends the hardening ladder to `20M`. A `100M` result is only reported if a completed JSON artifact already exists under `docs/results/`; otherwise it is skipped rather than inferred.

## Product note

v26 is materially broader and more dependable in free chat than v25, but it is still not a broad general knowledge model. It should answer grounded SBAN questions, remembered session facts, short math, practical writing and coding prompts, Zig-upstream operational questions, and a wider set of ordinary conversational prompts well, while still declining unsupported questions honestly.
