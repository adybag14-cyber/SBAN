---
name: sban-research
description: Use when working on the SBAN research runtime, especially when planning or implementing a new iteration, reproducing the current release benchmarks, extending the sequence-expert architecture, or generating the packaged report, summary, and repo zip deliverables.
---

# SBAN Research

Use this skill when the task is to continue SBAN research work inside this repository.

## Start here

Read only the files that matter for the current subtask:

- `README.md` for the current release entry points
- `src/network.zig` for the runtime and expert-routing logic
- `src/config.zig` for searchable profile knobs
- `src/main.zig` for CLI behavior and chat evaluation
- `scripts/run_v18_release.py` for the packaged benchmark suite
- `scripts/make_v18_deliverables.py` for report, summary, PDF, and repo zip generation

If you need the release targets or commands, read `references/release_profiles.md`.

## Workflow

1. Reproduce the current release before changing code.
2. Make the smallest architecture change that can plausibly move the measured suite.
3. Validate short suite first because it is cheap.
4. Validate 250k next.
5. Validate 1M only after the short suite and 250k look good.
6. Regenerate deliverables only after the measured suite is stable.

## Guardrails

- Treat the packaged current-release numbers in `references/release_profiles.md` as the comparison baseline unless the user explicitly changes the benchmark target.
- Do not claim a new generation unless the benchmark JSON files exist in `docs/results/`.
- Keep chat evaluation honest:
  use exact prompt/seed files, and if the old metric is already saturated, expand the prompt set rather than pretending a 100% metric improved without adding coverage.
- Prefer adding or tuning deterministic scripts in `scripts/` over leaving release logic in ad hoc shell history.
- State clearly when a numeric release is seeded or otherwise transductive.

## Architecture notes

- `src/network.zig` contains the release-critical routing logic.
- The v18 release extends the sparse path through order four and order five and adds seeded sequence-expert pretraining plus a hybrid warm start.
- The release profile is search-sensitive. Preserve explicit overrides in release scripts instead of assuming raw defaults are the winning profile.

## Deliverables

For a new release:

1. Run `python scripts/run_v17_release.py` or the next-generation equivalent.
2. Run `python scripts/make_v18_deliverables.py` or the next-generation equivalent.
3. Confirm the versioned paper PDF, executive summary, and repo zip exist under `deliverables/`.
4. Update `README.md` so the current release can be reproduced without extra context.

## When to read references

- Read `references/release_profiles.md` when you need the current benchmark thresholds, release profile, or exact result filenames.
