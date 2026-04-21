# SBAN v17

SBAN v17 is the current research release of the Sparse Bridge-Adaptive Network runtime. This iteration focuses on a sparse order-three sequence expert, stronger release-profile tuning, and better long-run behavior without giving up the short suite.

## Headline v17 results

- Prefix: **51.7700%**
- Drift: **50.0375%**
- Probe: **75.1500%**
- 250k long run: **53.4588%**
- 1M long run: **51.3550%**
- Hybrid chat eval: **42 / 42** anchored, **42 / 42** non-empty on the expanded v17 prompt set

Relative to the packaged v16 release, every numeric benchmark above clears the requested **5% relative improvement** bar.

## What changed in v17

- sparse order-three sequence expert inside `src/network.zig`
- support and evidence controls for expert blending
- local expert reset at drift boundaries while preserving global sequence counts
- stronger v17 release profile with long-term memory enabled and deeper propagation
- cross-platform v17 release and deliverable scripts

## Build

If `zig` is already on `PATH`:

```bash
zig build -Doptimize=ReleaseSafe
```

If you have a local Zig executable path on Windows:

```bash
python scripts/run_v17_release.py --zig-exe C:\path\to\zig.exe
```

## Run the v17 release suite

With `zig` on `PATH`:

```bash
python scripts/run_v17_release.py
```

Reuse an existing build:

```bash
python scripts/run_v17_release.py --skip-build
```

This writes the packaged release artifacts to `docs/results/v17/`.

## Generate the v17 paper, summary, and repo zip

```bash
python scripts/make_v17_deliverables.py
```

This generates:

- `SBAN_v17_REPORT.md`
- `SBAN_v17_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v17_follow_up_research_paper.pdf`
- `deliverables/v17/`
- `deliverables/v17/SBAN_v17_repo.zip`

## Main files

- `src/network.zig`
- `src/config.zig`
- `src/main.zig`
- `scripts/run_v17_release.py`
- `scripts/make_v17_deliverables.py`
- `scripts/md_to_pdf_reportlab.py`
- `docs/results/v17/`
- `data/sban_dialogue_seed_v17.txt`
- `data/sban_chat_eval_prompts_v17.txt`

## Bottom line

SBAN v17 is the first repo generation here that clears the prior short-suite ceiling and the long-run ceiling at the same time with one packaged release profile. The main remaining weakness is still free generation and the lack of checkpoint/resume for very long jobs.
