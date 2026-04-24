# SBAN v29

SBAN v29 is the synthetic-knowledge, runtime-hardening, and Zig-coding release of the Sparse Bridge-Adaptive Network runtime.

This generation keeps the packaged numeric suite on the stable single-thread CPU release path while addressing the v28 architecture stress report: larger-vocabulary probing, generated general-knowledge coverage, Zig coding help, safer session persistence, secret rejection, exact-math bounds, displayed response caps, source-location boundaries, and numeric `auto` backend semantics.

## Headline Goals

- Preserve the established prefix, drift, probe, `250k`, `1M`, `10M`, and `20M` numeric guardrails on the packaged CPU release path.
- Ship a real v29 grounded seed, a separate v29 open-chat seed, and a generated synthetic knowledge pack loaded through `knowledge_path`.
- Add generated coverage for science, geography, literature, civics, economics, real-world task triage, Zig allocator/error/defer/slice concepts, and practical coding snippets.
- Fix the unsafe huge-number path by refusing exact-number casts outside the safe range, and add simple linear-equation handling.
- Cap session file loading, retained turns, retained facts, and printed responses; reject secrets instead of writing them to memory.
- Test larger vocabulary sizes from 256 through 16384 buckets and document the sparse-index recommendation before changing the dense core vocabulary.
- Keep CUDA, `cpu_mt`, and OpenCL measured explicitly and assert actual backend use in CI smoke checks instead of trusting configured backend strings.

## Main Files

- Runtime:
  - `src/network.zig`
  - `src/dialogue.zig`
  - `src/main.zig`
- Numeric profile knobs:
  - `src/config.zig`
- Dialogue and knowledge assets:
  - `data/sban_dialogue_seed_v29.txt`
  - `data/sban_dialogue_open_seed_v29.txt`
  - `data/sban_synthetic_knowledge_v29.txt`
  - `data/sban_chat_eval_prompts_v29.txt`
  - `data/sban_session_eval_v29.txt`
  - `data/sban_open_chat_session_eval_v29.txt`
  - `data/sban_broad_chat_session_eval_v29.txt`
  - `data/sban_knowledge_session_eval_v29.txt`
- Asset builders and probes:
  - `scripts/build_v29_synthetic_knowledge.py`
  - `scripts/vocab_size_probe_v29.py`
- Release scripts:
  - `scripts/run_v29_release.py`
  - `scripts/make_v29_deliverables.py`
  - `scripts/package_v29_demo.py`
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

## Try the v29 Runtime From Source

One-shot free chat:

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v29" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt backend=auto mode=free allow_generation=true
```

Generated knowledge, Zig coding, and safety examples:

```bash
zig-out/bin/zig_sban chat-demo "what causes tides" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "who wrote pride and prejudice" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "write a zig function to reverse a slice" 220 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "create a json object with name Ada and age 42" 220 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "solve 3x + 5 = 20" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "calculate 2^1000" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "where is HashMap implemented in the Linux kernel source" 220 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt backend=auto mode=free allow_generation=true
```

Continuing-session examples:

```bash
zig-out/bin/zig_sban chat-demo "hi i am tom and i need help" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt session_path=session_v29.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "can you recall my name" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt session_path=session_v29.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "remember that my launch date is tuesday" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt session_path=session_v29.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "when is my launch date" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt session_path=session_v29.txt backend=auto mode=free allow_generation=true
zig-out/bin/zig_sban chat-demo "remember my api key is sk-test" 180 seed_path=data/sban_dialogue_seed_v29.txt open_seed_path=data/sban_dialogue_open_seed_v29.txt knowledge_path=data/sban_synthetic_knowledge_v29.txt session_path=session_v29.txt backend=auto mode=free allow_generation=true
```

## Inspect Accelerator Support

```bash
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v29.txt backend=cuda
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v29.txt backend=cpu_mt threads=4
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu
zig-out/bin/zig_sban numeric-accel-info numeric_backend=cpu_mt score_threads=4 parallel_score_min_predictive_nodes=1
zig-out/bin/zig_sban numeric-accel-info numeric_backend=auto cuda_min_scoring_edges=1
```

Raw retrieval throughput:

```bash
zig-out/bin/zig_sban accel-bench docs/results/v29/accel_prompts_v29_bench.txt backend=cuda seed_path=docs/results/v29/accel_seed_v29_bench.txt iterations=4
```

## Rebuild Generated Knowledge and Vocab Probe

The shipped `data/sban_synthetic_knowledge_v29.txt` and expanded `data/sban_dialogue_open_seed_v29.txt` are built by a deterministic generator. The generated records are not authored conversation transcripts.

```bash
python scripts/build_v29_synthetic_knowledge.py
python scripts/vocab_size_probe_v29.py
```

The vocab probe writes `docs/results/v29/vocab_size_probe_v29.json` and compares 256, 512, 1024, 2048, 4096, 8192, and 16384 bucket sizes.

## Run the Measured v29 Suite

```bash
python scripts/run_v29_release.py
```

To reuse an existing `zig-out` binary:

```bash
python scripts/run_v29_release.py --skip-build
```

If `zig` is not on `PATH`:

```bash
python scripts/run_v29_release.py --zig-exe "C:/Users/Ady/Downloads/zig-x86_64-windows-0.17.0-dev.87+9b177a7d2/zig-x86_64-windows-0.17.0-dev.87+9b177a7d2/zig.exe"
```

This writes measured artifacts to `docs/results/v29/`, including:

- `unified_prefix_v29_release.json`
- `unified_drift_v29_release.json`
- `unified_probe_v29_release.json`
- `longrun_v29_250k.json`
- `longrun_v29_1m.json`
- `longrun_v29_10m.json`
- `longrun_v29_20m.json`
- `chat_eval_v29_hybrid.txt`
- `chat_eval_v29_free.txt`
- `chat_session_eval_v29.txt`
- `open_chat_session_eval_v29.txt`
- `broad_chat_session_eval_v29.txt`
- `knowledge_session_eval_v29.txt`
- `synthetic_knowledge_v29.json`
- `vocab_size_probe_v29.json`
- `accel_info_v29_cpu_mt.txt`
- `accel_info_v29_cuda.txt`
- `numeric_accel_info_v29_cpu.txt`
- `numeric_accel_info_v29_cpu_mt.txt`
- `numeric_accel_info_v29_cuda.txt`
- `accel_bench_v29.json`
- `numeric_backend_v29.json`
- `STATUS.md`

## Generate the v29 Report, Summary, Paper, Demo Bundle, and Repo Zip

```bash
python scripts/make_v29_deliverables.py
```

Generated outputs include:

- `SBAN_v29_REPORT.md`
- `SBAN_v29_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v29_follow_up_research_paper.pdf`
- `deliverables/v29/SBAN_v29_repo.zip`
- `deliverables/v29/demo/SBAN_v29_windows_x86_64_demo.zip` on Windows
- `deliverables/v29/demo/SBAN_v29_linux_x86_64_demo.zip` on Linux

## Package the Newcomer Demo Directly

```bash
python scripts/package_v29_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

Linux example:

```bash
python scripts/package_v29_demo.py --binary zig-out/bin/zig_sban --platform linux_x86_64
```

The newcomer scripts use `backend=auto` and load the grounded seed, open-chat seed, and generated synthetic knowledge pack. Small bundled workloads still often stay on CPU, while larger NVIDIA-backed retrieval workloads can promote to CUDA automatically. The packaged numeric suite stays on `numeric_backend=cpu`; v29 keeps the stable CPU profile while hardening the product runtime.

## CI and Release Automation

- `.github/workflows/ci.yml` builds and tests SBAN on Windows and Ubuntu and runs the v29 smoke suite, including generated knowledge and vocab checks.
- `.github/workflows/v29-release-suite.yml` runs the hosted-compatible v29 release suite.
- `.github/workflows/v29-long-hardening.yml` runs configurable longer hardening jobs.
- `.github/workflows/v29-100m-check.yml` runs the optional 100M job.
- `.github/workflows/release.yml` packages v29 demo bundles for Windows and Linux and uploads them on `v29*` tags.

## Important Benchmark Note

The numeric suite is still an engine-health and hardening profile, not a broad generalization benchmark. v29 intentionally keeps the packaged numeric suite on the single-thread CPU path so product, safety, and generated-knowledge improvements are not mixed with numeric-profile churn. A completed hosted `100M` CPU artifact is included only as an external reference and not folded into the ordinary local release gate.

## Product Note

v29 is materially broader than v28 through generated offline knowledge assets and stronger deterministic reasoning helpers, but it is not a live-current web oracle. It should answer the shipped general-knowledge, real-world task, Zig coding, session-memory, short math, algebra, and SBAN operational prompts while clearly bounding live/current facts and unindexed source-tree questions.
