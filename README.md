# SBAN v21

SBAN v21 is the current research release of the Sparse Bridge-Adaptive Network runtime. This generation keeps the packaged numeric engine-health suite stable while upgrading the chat surface into a more grounded and dependable collaborator: stronger uncertainty handling, broader session memory, safer persistence, more robust short math, and first CPU or GPU retrieval acceleration.

## Headline v21 results

- Prefix: stable against the v20 packaged baseline
- Drift: stable against the v20 packaged baseline
- Probe: stable against the v20 packaged baseline
- 250k long run: stable against the v20 packaged baseline
- 1M long run: stable against the v20 packaged baseline
- Hybrid chat eval: expanded v21 prompt set with full non-empty coverage and explicit uncertainty instead of canned drift
- Free chat eval: same grounded behavior with reliable symbolic handling and clean decline paths
- Session eval: scripted multi-turn recall, arithmetic, and unsupported-prompt checks all passing
- Acceleration: CPU path remains the default baseline, with optional OpenCL GPU retrieval scoring when available

The numeric suite is still the engine-health check. The main v21 product claim is that the runtime is now much less willing to bluff.

## Important benchmark caveat

The packaged numeric release must still be described according to the release methodology documented in `references/release_profiles.md`.

That caveat applies to the numeric benchmark story.

The grounded continuing chat demo is a separate user-facing artifact built on the same runtime.

## What changed in v21

- replaced the loose seeded-demo matcher with stricter grounded retrieval and version-aware rejection
- expanded session memory from name-only recall to general facts such as favorite colors and preferences
- added safer arithmetic handling for negatives, decimals, and parentheses
- replaced raw transcript persistence with structured encoded session files
- improved missing-asset diagnostics so missing seeds report user-facing errors instead of raw file failures
- added an optional OpenCL retrieval backend so the runtime can use CPU or GPU
- broadened the v21 prompt assets and session evaluation around reliability and end-user trust
- updated the newcomer demo bundle, release scripts, and GitHub automation for the v21 surface

## Build

If `zig` is already on `PATH`:

```bash
zig build -Doptimize=ReleaseSafe
```

If you want to use a local Zig executable path on Windows:

```bash
python scripts/run_v21_release.py --zig-exe C:\path\to\zig.exe
```

## Try the v21 demo from source

After building:

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v21" 160 seed_path=data/sban_dialogue_seed_v21.txt backend=auto
```

To keep a continuing session:

```bash
zig-out/bin/zig_sban chat-demo "hi i am tom and i need help" 160 seed_path=data/sban_dialogue_seed_v21.txt session_path=session_v21.txt backend=auto
zig-out/bin/zig_sban chat-demo "can you recall my name" 160 seed_path=data/sban_dialogue_seed_v21.txt session_path=session_v21.txt backend=auto
zig-out/bin/zig_sban chat-demo "my favorite color is blue" 160 seed_path=data/sban_dialogue_seed_v21.txt session_path=session_v21.txt backend=auto
zig-out/bin/zig_sban chat-demo "what is my favorite color" 160 seed_path=data/sban_dialogue_seed_v21.txt session_path=session_v21.txt backend=auto
```

To inspect the optional acceleration path:

```bash
zig-out/bin/zig_sban accel-info
```

The packaged newcomer bundles generated for releases use the same `session_path` flow behind `SBAN_v21_Start.bat` and `SBAN_v21_Start.sh`.

## Run the v21 release suite

With `zig` on `PATH`:

```bash
python scripts/run_v21_release.py
```

Reuse an existing build:

```bash
python scripts/run_v21_release.py --skip-build
```

This writes the packaged release artifacts to `docs/results/v21/`.

## Generate the v21 paper, summary, demo bundle, and repo zip

```bash
python scripts/make_v21_deliverables.py
```

This generates:

- `SBAN_v21_REPORT.md`
- `SBAN_v21_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v21_follow_up_research_paper.pdf`
- `deliverables/v21/`
- `deliverables/v21/SBAN_v21_repo.zip`
- `deliverables/v21/demo/SBAN_v21_windows_x86_64_demo.zip`

## Package only the newcomer demo bundle

```bash
python scripts/package_v21_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

## GitHub automation

- `.github/workflows/ci.yml` builds and tests SBAN v21 on Windows and Ubuntu and runs smoke checks for the grounded session surface
- `.github/workflows/release.yml` builds the packaged Windows and Linux newcomer bundles and uploads them to tagged GitHub releases

## Main files

- `src/network.zig`
- `src/config.zig`
- `src/experiment.zig`
- `src/dialogue.zig`
- `src/main.zig`
- `scripts/run_v21_release.py`
- `scripts/make_v21_deliverables.py`
- `scripts/package_v21_demo.py`
- `references/release_profiles.md`
- `docs/results/v21/`
- `data/sban_dialogue_seed_v21.txt`
- `data/sban_chat_eval_prompts_v21.txt`
- `data/sban_session_eval_v21.txt`
- `demo/`
- `skills/sban-research/SKILL.md`

## Bottom line

SBAN v21 is the grounded-runtime release. It keeps the stabilized numeric core from v20 while making the architecture much more reliable to question, challenge, and continue across turns.
