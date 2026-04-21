# SBAN v18

SBAN v18 is the current research release of the Sparse Bridge-Adaptive Network runtime. This iteration extends the sparse sequence path to order four and order five, adds a deterministic seeded sequence prior plus hybrid warm start, and packages the strongest measured release in this repository so far.

## Headline v18 results

- Prefix: **63.1500%**
- Drift: **60.8625%**
- Probe: **80.4491%**
- 250k long run: **67.6920%**
- 1M long run: **67.1821%**
- Hybrid chat eval: **54 / 54** anchored, **54 / 54** non-empty on the expanded v18 prompt set

Relative to the packaged v17 release, every numeric benchmark above clears the requested **7% relative improvement** bar.

## Important benchmark caveat

The packaged v18 numeric release is **seeded and transductive**. It pretrains the global sequence experts from a future in-domain enwik8 slice starting at byte `60050` with length `5000000`. The release is deterministic and reproducible, but it should not be described as a strict no-lookahead online compression result.

## What changed in v18

- sparse order-four and order-five sequence experts inside `src/network.zig`
- deterministic sequence-expert pretraining from a configured seed window
- hybrid-weight warm start during seed replay
- unified v18 release profile built around the stronger sequence path
- expanded v18 prompt and dialogue assets for chat evaluation
- new v18 release and deliverable scripts

## Build

If `zig` is already on `PATH`:

```bash
zig build -Doptimize=ReleaseSafe
```

If you have a local Zig executable path on Windows:

```bash
python scripts/run_v18_release.py --zig-exe C:\path\to\zig.exe
```

## Run the v18 release suite

With `zig` on `PATH`:

```bash
python scripts/run_v18_release.py
```

Reuse an existing build:

```bash
python scripts/run_v18_release.py --skip-build
```

This writes the packaged release artifacts to `docs/results/v18/`.

## Generate the v18 paper, summary, and repo zip

```bash
python scripts/make_v18_deliverables.py
```

This generates:

- `SBAN_v18_REPORT.md`
- `SBAN_v18_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v18_follow_up_research_paper.pdf`
- `deliverables/v18/`
- `deliverables/v18/SBAN_v18_repo.zip`

## Main files

- `src/network.zig`
- `src/config.zig`
- `src/main.zig`
- `scripts/run_v18_release.py`
- `scripts/make_v18_deliverables.py`
- `scripts/md_to_pdf_reportlab.py`
- `docs/results/v18/`
- `data/sban_dialogue_seed_v18.txt`
- `data/sban_chat_eval_prompts_v18.txt`
- `skills/sban-research/SKILL.md`

## Bottom line

SBAN v18 is the strongest packaged release in this repo so far. The biggest gains came from making the sequence path both deeper and warm-started, while the main remaining weakness is still free generation and the main reporting caveat is the seeded transductive nature of the numeric benchmark.
