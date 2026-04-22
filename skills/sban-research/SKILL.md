---
name: sban-research
description: Use when working on the SBAN research runtime, especially when planning or implementing a new iteration, reproducing the current release benchmarks, extending the sequence-expert architecture, or generating the packaged report, summary, and repo zip deliverables.
---

# SBAN Research

Use this skill when the task is to continue SBAN research work inside this repository.

## Start here

Read only the files that matter for the current subtask:

- `README.md` for the current release entry points
- `src/network.zig` for the numeric runtime and expert-routing logic
- `src/dialogue.zig` for the grounded chat runtime, session memory, symbolic helpers, persistence, and CPU or GPU retrieval support
- `src/config.zig` for searchable profile knobs
- `src/main.zig` for CLI behavior and release-facing commands
- `scripts/run_v21_release.py` for the packaged benchmark and dialogue suite
- `scripts/make_v21_deliverables.py` for report, summary, PDF, demo bundle, and repo zip generation
- `scripts/package_v21_demo.py` for the newcomer demo bundle
- `references/release_profiles.md` for the current baseline, targets, shipped profile details, and caveat wording

If you need the release targets or commands, read `references/release_profiles.md`.

## Workflow

1. Reproduce the current release before changing code.
2. Make the smallest architecture change that can plausibly move the measured suite.
3. Validate short numeric checks first because they are cheap.
4. Validate longer numeric runs only after the short suite looks stable.
5. When the release focus is usability, validate the versioned chat-eval and chat-session-eval assets directly against the failure modes being fixed.
6. Regenerate deliverables only after the measured suite and packaged demo behavior are stable.
7. If the user asks for a product demo or release packaging, validate the newcomer demo bundle and GitHub workflow files before finishing.

## Guardrails

- Treat the packaged current-release numbers in `references/release_profiles.md` as the comparison baseline unless the user explicitly changes the benchmark target.
- Do not claim a new generation unless the benchmark JSON files exist in `docs/results/`.
- Keep chat evaluation honest:
  use exact prompt and seed files, and if the old metric is already saturated, expand the prompt set rather than pretending a saturated score improved without more coverage.
- When the release focus is usability rather than another numeric jump, keep the numeric suite stable and add versioned reliability checks instead of inventing a misleading one-shot metric.
- Prefer adding or tuning deterministic scripts in `scripts/` over leaving release logic in ad hoc shell history.
- State clearly when a numeric release uses a seeded or otherwise transductive protocol.
- Separate the product demo story from the numeric benchmark story when the release uses a specialized benchmark profile.
- For GPU support, keep CPU fallback automatic and validate `accel-info` rather than assuming compatible OpenCL hardware exists everywhere.

## Architecture notes

- `src/network.zig` contains the release-critical numeric routing logic.
- The v19 release adds a deep continuation expert and segment-aware reseeding controls on top of the earlier higher-order sparse path.
- The v20 release keeps the v19 numeric core but upgrades the chat and demo packaging around continuing-session usability.
- The v21 release adds a dedicated `src/dialogue.zig` runtime with stricter grounding, general session facts, safer persistence, stronger symbolic handling, and an optional OpenCL retrieval path.
- The release profile is search-sensitive. Preserve explicit overrides in release scripts instead of assuming raw defaults are the winning profile.

## Deliverables

For a new release:

1. Run `python scripts/run_v21_release.py` or the next-generation equivalent.
2. Run `python scripts/make_v21_deliverables.py` or the next-generation equivalent.
3. Confirm the versioned paper PDF, executive summary, repo zip, and demo bundle exist under `deliverables/`.
4. Update `README.md` so the current release can be reproduced without extra context.
5. If CI or release workflows were requested, confirm `.github/workflows/` contains the current versioned automation.

## When to read references

- Read `references/release_profiles.md` when you need the current benchmark thresholds, release profile, exact result filenames, or the release caveat wording.
