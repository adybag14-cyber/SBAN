# SBAN v27

SBAN v27 is the current product and free-chat release of the Sparse Bridge-Adaptive Network runtime.

This release keeps the packaged numeric suite on the single-thread CPU release path, improves that CPU profile with a stronger continuation setting through `10M`, keeps a bounded `20M` fallback profile for stability, and upgrades the user-facing chat runtime so ordinary free-chat prompts, natural fact memory, operational answers, and Zig-upstream questions are much less brittle than earlier releases.

## Headline goals

- Improve the established prefix, drift, probe, `250k`, `1M`, and `10M` numeric guardrail on the packaged CPU release path.
- Extend the hardening suite with a measured `20M` run and keep the completed hosted `100M` CPU artifact available as an external reference.
- Ship a real v27 grounded seed plus a separate curated and dataset-enriched v27 open-chat seed.
- Fix the earlier free-chat failure modes where ordinary prompts either fell to uncertainty or overmatched unrelated SBAN answers.
- Broaden deterministic coverage for everyday explanations, writing help, coding help, natural session memory, and Zig-upstream operational questions.
- Expand natural session memory around project, pet-name, and tomorrow-style notes.
- Keep CUDA, `cpu_mt`, and OpenCL measured explicitly instead of promoting them by preference.

## Main files

- Runtime:
  - `src/network.zig`
  - `src/dialogue.zig`
  - `src/main.zig`
- Numeric profile knobs:
  - `src/config.zig`
- Dialogue assets:
  - `data/sban_dialogue_seed_v27.txt`
  - `data/sban_dialogue_open_seed_v27.txt`
  - `data/sban_chat_eval_prompts_v27.txt`
  - `data/sban_session_eval_v27.txt`
  - `data/sban_open_chat_session_eval_v27.txt`
  - `data/sban_broad_chat_session_eval_v27.txt`
- Seed builder:
  - `scripts/build_v27_open_seed.py`
- Release scripts:
  - `scripts/run_v27_release.py`
  - `scripts/make_v27_deliverables.py`
  - `scripts/package_v27_demo.py`
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

## Try the v27 runtime from source

One-shot free chat:

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v27" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt backend=auto mode=free allow_generation=true
```

Continuing-session examples:

```bash
zig-out/bin/zig_sban chat-demo "hi i am tom and i need help" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt session_path=session_v27.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "can you recall my name" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt session_path=session_v27.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "our team is atlas" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt session_path=session_v27.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what team am i on" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt session_path=session_v27.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "i am from london" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt session_path=session_v27.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where am i from" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt session_path=session_v27.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "my dog is luna" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt session_path=session_v27.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what is my dog name" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt session_path=session_v27.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "our project is nebula" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt session_path=session_v27.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what project are we on" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt session_path=session_v27.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what files ship in the bundle" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what command shows cuda support" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "write a python class for a stack" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what is json" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where is std.hashmap implemented in zig upstream" 180 seed_path=data/sban_dialogue_seed_v27.txt open_seed_path=data/sban_dialogue_open_seed_v27.txt backend=auto mode=free allow_generation=true
```

## Inspect accelerator support

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v27.txt backend=cuda
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v27.txt backend=cpu_mt threads=4
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu_mt score_threads=4 parallel_score_min_predictive_nodes=1
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1
```

Raw retrieval throughput:

```bash
zig-out/bin/zig_sban accel-bench docs/results/v27/accel_prompts_v27_bench.txt backend=cuda seed_path=docs/results/v27/accel_seed_v27_bench.txt iterations=4
```

## Rebuild the expanded v27 open seed

The shipped `data/sban_dialogue_open_seed_v27.txt` is built from the earlier open seed, curated v27 additions, optional filtered SQuAD coverage, and Zig-upstream prompts derived from the local Zig source zip.

```bash
python scripts/build_v27_open_seed.py
```

To skip optional dataset loading:

```bash
python scripts/build_v27_open_seed.py --no-datasets
```

## Run the measured v27 suite

```bash
python scripts/run_v27_release.py
```

To reuse an existing `zig-out` binary:

```bash
python scripts/run_v27_release.py --skip-build
```

If `zig` is not on `PATH`:

```bash
python scripts/run_v27_release.py --zig-exe "C:/Users/Ady/Downloads/zig-x86_64-windows-0.17.0-dev.87+9b177a7d2/zig-x86_64-windows-0.17.0-dev.87+9b177a7d2/zig.exe"
```

This writes measured artifacts to `docs/results/v27/`, including:

- `unified_prefix_v27_release.json`
- `unified_drift_v27_release.json`
- `unified_probe_v27_release.json`
- `longrun_v27_250k.json`
- `longrun_v27_1m.json`
- `longrun_v27_10m.json`
- `longrun_v27_20m.json`
- `chat_eval_v27_hybrid.txt`
- `chat_eval_v27_free.txt`
- `chat_session_eval_v27.txt`
- `open_chat_session_eval_v27.txt`
- `broad_chat_session_eval_v27.txt`
- `accel_info_v27_cpu_mt.txt`
- `accel_info_v27_cuda.txt`
- `numeric_accel_info_v27_cpu.txt`
- `numeric_accel_info_v27_cpu_mt.txt`
- `numeric_accel_info_v27_cuda.txt`
- `accel_bench_v27.json`
- `numeric_backend_v27.json`
- `STATUS.md`

## Generate the v27 report, summary, paper, demo bundle, and repo zip

```bash
python scripts/make_v27_deliverables.py
```

Generated outputs include:

- `SBAN_v27_REPORT.md`
- `SBAN_v27_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v27_follow_up_research_paper.pdf`
- `deliverables/v27/SBAN_v27_repo.zip`
- `deliverables/v27/demo/SBAN_v27_windows_x86_64_demo.zip` on Windows
- `deliverables/v27/demo/SBAN_v27_linux_x86_64_demo.zip` on Linux

## Package the newcomer demo directly

```bash
python scripts/package_v27_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

Linux example:

```bash
python scripts/package_v27_demo.py --binary zig-out/bin/zig_sban --platform linux_x86_64
```

The newcomer scripts use `backend=auto` and load both the grounded and open-chat v27 seeds. Small bundled workloads still often stay on CPU, while larger NVIDIA-backed retrieval workloads can promote to CUDA automatically. The packaged numeric suite stays on `numeric_backend=cpu`; v27 improves that CPU profile directly instead of promoting accelerated numeric backends prematurely.

## CI and release automation

- `.github/workflows/ci.yml` builds and tests SBAN on Windows and Ubuntu and runs the v27 session smoke checks, the v27 open-chat smoke checks, and the v27 broad-chat battery.
- `.github/workflows/release.yml` packages v27 demo bundles for Windows and Linux and uploads them on `v27*` tags.

## Important benchmark note

The numeric suite is still an engine-health and hardening profile, not a broad generalization benchmark. v27 intentionally keeps the packaged numeric suite on the single-thread CPU path, improves that path through `10M`, and uses a bounded continuation fallback for the `20M` point because the stronger short-suite profile hit `OutOfMemory` at that horizon on this workstation. A completed hosted `100M` CPU artifact is included only as an external reference and not folded into the ordinary local release gate.

## Product note

v27 is materially broader and more dependable in free chat than v26, but it is still not a broad general knowledge model. It should answer grounded SBAN questions, remembered session facts, short math, practical writing and coding prompts, Zig-upstream operational questions, and a wider set of ordinary conversational prompts well, while still declining unsupported questions honestly.
