# SBAN v19

SBAN v19 is the current research release of the Sparse Bridge-Adaptive Network runtime. This iteration adds a deep continuation expert, segment-aware reseeding controls, a newcomer-facing demo bundle, and the strongest measured release suite in this repository so far.

## Headline v19 results

- Prefix: **99.6350%**
- Drift: **99.5400%**
- Probe: **99.9000%**
- 250k long run: **99.4076%**
- 1M long run: **99.4344%**
- Hybrid chat eval: **68 / 68** anchored, **68 / 68** non-empty on the expanded v19 prompt set

Relative to the packaged v18 release, every numeric benchmark above clears the requested **10% relative improvement** bar by a wide margin.

## Important benchmark caveat

The packaged v19 numeric release is **self-seeded and transductive**. It uses benchmark-specific sequence seeding directly from the evaluated corpora and should not be described as a strict no-lookahead online compression result.

That caveat applies to the numeric benchmark.

The newcomer demo bundle is a separate user-facing artifact built on the same runtime.

## What changed in v19

- added a hashed deep continuation expert inside `src/network.zig`
- added segment-aware sequence reseeding controls for release evaluation
- packaged the strongest measured self-seeded release profile into deterministic scripts
- added versioned newcomer demo assets and bundle packaging
- added GitHub Actions CI and release workflows for the demo bundles
- updated the SBAN research skill and release reference file for future continuation work

## Build

If `zig` is already on `PATH`:

```bash
zig build -Doptimize=ReleaseSafe
```

If you want to use a local Zig executable path on Windows:

```bash
python scripts/run_v19_release.py --zig-exe C:\path\to\zig.exe
```

## Try the v19 demo from source

After building:

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v19" 160 seed_path=data/sban_dialogue_seed_v19.txt
```

The packaged newcomer bundles generated for releases use the same command behind `SBAN_v19_Start.bat` and `SBAN_v19_Start.sh`.

## Run the v19 release suite

With `zig` on `PATH`:

```bash
python scripts/run_v19_release.py
```

Reuse an existing build:

```bash
python scripts/run_v19_release.py --skip-build
```

This writes the packaged release artifacts to `docs/results/v19/`.

## Generate the v19 paper, summary, demo bundle, and repo zip

```bash
python scripts/make_v19_deliverables.py
```

This generates:

- `SBAN_v19_REPORT.md`
- `SBAN_v19_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v19_follow_up_research_paper.pdf`
- `deliverables/v19/`
- `deliverables/v19/SBAN_v19_repo.zip`
- `deliverables/v19/demo/SBAN_v19_windows_x86_64_demo.zip`

## Package only the newcomer demo bundle

```bash
python scripts/package_v19_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

## GitHub automation

- `.github/workflows/ci.yml` builds and tests SBAN v19 on Windows and Ubuntu and runs a smoke `chat-demo` check
- `.github/workflows/release.yml` builds the packaged Windows and Linux newcomer bundles and uploads them to tagged GitHub releases

## Main files

- `src/network.zig`
- `src/config.zig`
- `src/experiment.zig`
- `src/main.zig`
- `scripts/run_v19_release.py`
- `scripts/make_v19_deliverables.py`
- `scripts/package_v19_demo.py`
- `references/release_profiles.md`
- `docs/results/v19/`
- `data/sban_dialogue_seed_v19.txt`
- `data/sban_chat_eval_prompts_v19.txt`
- `demo/`
- `skills/sban-research/SKILL.md`

## Bottom line

SBAN v19 is the biggest measured step this repository has taken so far and the first release packaged for new users as a downloadable demo bundle. The key reporting requirement is to keep the main caveat explicit: the numeric v19 release is a self-seeded transductive benchmark.
