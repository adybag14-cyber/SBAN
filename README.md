# SBAN v22

SBAN v22 is the current research release of the Sparse Bridge-Adaptive Network runtime.

This generation keeps the established numeric engine-health suite stable, broadens grounded paraphrase tolerance, makes session memory more natural, removes the retained-turn cap from continuing sessions, adds explicit divide-by-zero handling, and extends the hardening suite to 10M and near-100M runs.

## Headline goals

- Keep the original packaged prefix, drift, probe, 250k, and 1M checks at the v21 baseline rather than chasing another misleading benchmark jump.
- Make the runtime feel more usable in real conversation: broader paraphrase coverage, calmer uncertainty behavior, natural fact memory, and safer long sessions.
- Preserve CPU and GPU support while defaulting the newcomer chat loop to CPU because the v22 grounded corpus is small enough that CPU startup is faster on typical single-prompt interactions.

## Main files

- Runtime: `src/network.zig`, `src/dialogue.zig`, `src/main.zig`
- Numeric profile knobs: `src/config.zig`
- Dialogue assets: `data/sban_dialogue_seed_v22.txt`, `data/sban_chat_eval_prompts_v22.txt`, `data/sban_session_eval_v22.txt`
- Release scripts: `scripts/run_v22_release.py`, `scripts/make_v22_deliverables.py`, `scripts/package_v22_demo.py`
- Release notes and thresholds: `references/release_profiles.md`

## Build

```bash
zig build test
zig build -Doptimize=ReleaseFast
```

## Try the v22 chat runtime from source

One-shot grounded chat:

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v22" 160 seed_path=data/sban_dialogue_seed_v22.txt backend=cpu
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
zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v22.txt
```

If you want to force the OpenCL retrieval path instead of the default CPU newcomer path, add `backend=gpu`.

## Run the measured v22 suite

```bash
python scripts/run_v22_release.py
```

To reuse an existing `zig-out` binary:

```bash
python scripts/run_v22_release.py --skip-build
```

To continue after an interrupted long hardening run without rerunning finished benchmark JSON files:

```bash
python scripts/run_v22_release.py --skip-build --resume
```

This writes the measured artifacts to `docs/results/v22/`, including:

- `unified_prefix_v22_release.json`
- `unified_drift_v22_release.json`
- `unified_probe_v22_release.json`
- `longrun_v22_250k.json`
- `longrun_v22_1m.json`
- `longrun_v22_10m.json`
- `longrun_v22_100m.json`
- `chat_eval_v22_hybrid.txt`
- `chat_eval_v22_free.txt`
- `chat_session_eval_v22.txt`
- `accel_info_v22.txt`

## Generate the v22 report, summary, paper, demo bundle, and repo zip

```bash
python scripts/make_v22_deliverables.py
```

Generated outputs include:

- `SBAN_v22_REPORT.md`
- `SBAN_v22_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v22_follow_up_research_paper.pdf`
- `deliverables/v22/SBAN_v22_repo.zip`
- `deliverables/v22/demo/SBAN_v22_windows_x86_64_demo.zip` on Windows

## Package the newcomer demo directly

```bash
python scripts/package_v22_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

Linux example:

```bash
python scripts/package_v22_demo.py --binary zig-out/bin/zig_sban --platform linux_x86_64
```

The newcomer scripts default to `backend=cpu` for faster small-corpus startup. GPU experiments remain available through `backend=gpu` and `accel-info`.

## CI and release automation

- `.github/workflows/ci.yml` builds and tests SBAN v22 on Windows and Ubuntu and runs the v22 session smoke checks.
- `.github/workflows/release.yml` packages v22 demo bundles for Windows and Linux and uploads them on `v22*` tags.

## Important benchmark note

The numeric suite is an engine-health and hardening profile, not a broad generalization benchmark. The 10M run keeps the common release profile, while the near-100M run uses a memory-bounded long-horizon profile that disables the order-4, order-5, and continuation expert tables so the full-corpus hardening pass can complete on commodity hardware. The near-100M run still uses the largest exact prediction window that fits inside the 100,000,000-byte `enwik8` corpus, so the measured run is just under a literal 100,000,000 predictions.

## Bottom line

V22 is the release where SBAN becomes less brittle in ordinary language without relaxing the trustworthiness rule introduced in v21.
