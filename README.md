# SBAN v28

SBAN v28 is the current stress-report repair and free-chat reliability release of the Sparse Bridge-Adaptive Network runtime.

This release keeps the packaged numeric suite on the single-thread CPU release path and preserves the v27 continuation profile, while fixing the v27 stress-report issues around stale release labels, loose session-eval matching, incomplete memory aliases, long-prompt log amplification, backend-step assertions, and unclear capability boundaries.

## Headline goals

- Preserve the established prefix, drift, probe, `250k`, `1M`, `10M`, and `20M` numeric guardrails on the packaged CPU release path.
- Ship a real v28 grounded seed plus a separate curated and dataset-enriched v28 open-chat seed.
- Fix the reported false-positive eval matcher by using boundary-aware expectation matching.
- Expand natural session memory around project, cat-name, dog-name, date-like, generic `our X is Y`, and tomorrow-style notes.
- Add explicit responses for static current-fact boundaries, translation limits, supplied-text summaries, exponent math, speed/rate word problems, and the reported prime-checking code prompt.
- Keep CUDA, `cpu_mt`, and OpenCL measured explicitly and assert actual backend use in CI smoke checks instead of trusting configured backend strings.

## Main files

- Runtime:
  - `src/network.zig`
  - `src/dialogue.zig`
  - `src/main.zig`
- Numeric profile knobs:
  - `src/config.zig`
- Dialogue assets:
  - `data/sban_dialogue_seed_v28.txt`
  - `data/sban_dialogue_open_seed_v28.txt`
  - `data/sban_chat_eval_prompts_v28.txt`
  - `data/sban_session_eval_v28.txt`
  - `data/sban_open_chat_session_eval_v28.txt`
  - `data/sban_broad_chat_session_eval_v28.txt`
- Seed builder:
  - `scripts/build_v28_open_seed.py`
- Release scripts:
  - `scripts/run_v28_release.py`
  - `scripts/make_v28_deliverables.py`
  - `scripts/package_v28_demo.py`
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

## Try the v28 runtime from source

One-shot free chat:

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v28" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt backend=auto mode=free allow_generation=true
```

Continuing-session examples:

```bash
zig-out/bin/zig_sban chat-demo "hi i am tom and i need help" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt session_path=session_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "can you recall my name" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt session_path=session_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "our team is atlas" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt session_path=session_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what team am i on" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt session_path=session_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "i am from london" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt session_path=session_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where am i from" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt session_path=session_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "my dog is luna" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt session_path=session_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what is my dog name" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt session_path=session_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "my cat is io" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt session_path=session_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what is my cat name" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt session_path=session_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "our project is nebula" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt session_path=session_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what project are we on" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt session_path=session_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "remember that my launch date is tuesday" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt session_path=session_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "when is my launch date" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt session_path=session_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what files ship in the bundle" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what command shows cuda support" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "write a python class for a stack" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "what is json" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "calculate 2^10" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "translate hello to spanish" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "summarize: SBAN v28 fixes stale labels and tightens eval matching" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where is std.hashmap implemented in zig upstream" 180 seed_path=data/sban_dialogue_seed_v28.txt open_seed_path=data/sban_dialogue_open_seed_v28.txt backend=auto mode=free allow_generation=true
```

## Inspect accelerator support

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v28.txt backend=cuda
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v28.txt backend=cpu_mt threads=4
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu_mt score_threads=4 parallel_score_min_predictive_nodes=1
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1
```

Raw retrieval throughput:

```bash
zig-out/bin/zig_sban accel-bench docs/results/v28/accel_prompts_v28_bench.txt backend=cuda seed_path=docs/results/v28/accel_seed_v28_bench.txt iterations=4
```

## Rebuild the expanded v28 open seed

The shipped `data/sban_dialogue_open_seed_v28.txt` is built from the earlier open seed, curated v28 additions, optional filtered SQuAD coverage, and Zig-upstream prompts derived from the local Zig source zip.

```bash
python scripts/build_v28_open_seed.py
```

To skip optional dataset loading:

```bash
python scripts/build_v28_open_seed.py --no-datasets
```

## Run the measured v28 suite

```bash
python scripts/run_v28_release.py
```

To reuse an existing `zig-out` binary:

```bash
python scripts/run_v28_release.py --skip-build
```

If `zig` is not on `PATH`:

```bash
python scripts/run_v28_release.py --zig-exe "C:/Users/Ady/Downloads/zig-x86_64-windows-0.17.0-dev.87+9b177a7d2/zig-x86_64-windows-0.17.0-dev.87+9b177a7d2/zig.exe"
```

This writes measured artifacts to `docs/results/v28/`, including:

- `unified_prefix_v28_release.json`
- `unified_drift_v28_release.json`
- `unified_probe_v28_release.json`
- `longrun_v28_250k.json`
- `longrun_v28_1m.json`
- `longrun_v28_10m.json`
- `longrun_v28_20m.json`
- `chat_eval_v28_hybrid.txt`
- `chat_eval_v28_free.txt`
- `chat_session_eval_v28.txt`
- `open_chat_session_eval_v28.txt`
- `broad_chat_session_eval_v28.txt`
- `accel_info_v28_cpu_mt.txt`
- `accel_info_v28_cuda.txt`
- `numeric_accel_info_v28_cpu.txt`
- `numeric_accel_info_v28_cpu_mt.txt`
- `numeric_accel_info_v28_cuda.txt`
- `accel_bench_v28.json`
- `numeric_backend_v28.json`
- `STATUS.md`

## Generate the v28 report, summary, paper, demo bundle, and repo zip

```bash
python scripts/make_v28_deliverables.py
```

Generated outputs include:

- `SBAN_v28_REPORT.md`
- `SBAN_v28_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v28_follow_up_research_paper.pdf`
- `deliverables/v28/SBAN_v28_repo.zip`
- `deliverables/v28/demo/SBAN_v28_windows_x86_64_demo.zip` on Windows
- `deliverables/v28/demo/SBAN_v28_linux_x86_64_demo.zip` on Linux

## Package the newcomer demo directly

```bash
python scripts/package_v28_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

Linux example:

```bash
python scripts/package_v28_demo.py --binary zig-out/bin/zig_sban --platform linux_x86_64
```

The newcomer scripts use `backend=auto` and load both the grounded and open-chat v28 seeds. Small bundled workloads still often stay on CPU, while larger NVIDIA-backed retrieval workloads can promote to CUDA automatically. The packaged numeric suite stays on `numeric_backend=cpu`; v28 keeps the v27 CPU profile stable and strengthens backend reporting instead of promoting accelerated numeric backends prematurely.

## CI and release automation

- `.github/workflows/ci.yml` builds and tests SBAN on Windows and Ubuntu and runs the v28 session smoke checks, the v28 open-chat smoke checks, and the v28 broad-chat battery.
- `.github/workflows/release.yml` packages v28 demo bundles for Windows and Linux and uploads them on `v28*` tags.

## Important benchmark note

The numeric suite is still an engine-health and hardening profile, not a broad generalization benchmark. v28 intentionally keeps the packaged numeric suite on the single-thread CPU path and reuses the measured v27 continuation profile so product/reporting fixes are not mixed with numeric-profile churn. A completed hosted `100M` CPU artifact is included only as an external reference and not folded into the ordinary local release gate.

## Product note

v28 is stricter and more dependable than v27, but it is still not a broad general knowledge model. It should answer grounded SBAN questions, remembered session facts, short math, practical writing and coding prompts, Zig-upstream operational questions, and a wider set of ordinary conversational prompts well, while clearly bounding live/current facts and declining unsupported questions honestly.
