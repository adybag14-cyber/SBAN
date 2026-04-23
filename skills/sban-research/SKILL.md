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
- `scripts/run_v25_release.py` for the current packaged benchmark and dialogue suite
- `scripts/make_v25_deliverables.py` for report, summary, PDF, demo bundle, repo zip, and workstation recipe generation
- `scripts/package_v25_demo.py` for the newcomer demo bundle
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
- For GPU support, keep CPU fallback automatic and validate `accel-info` plus `nvidia-smi` rather than assuming compatible OpenCL or CUDA hardware exists everywhere.
- Treat backend speed claims as measured claims. Add or update an explicit accelerator benchmark instead of inferring GPU wins from chat latency alone.
- Remember the dialogue loader safety cap: oversized synthetic seed assets will fail around 4 MiB unless you redesign the loader.

## Architecture notes

- `src/network.zig` contains the release-critical numeric routing logic.
- The v19 release adds a deep continuation expert and segment-aware reseeding controls on top of the earlier higher-order sparse path.
- The v20 release keeps the v19 numeric core but upgrades the chat and demo packaging around continuing-session usability.
- The v21 release adds a dedicated `src/dialogue.zig` runtime with stricter grounding, general session facts, safer persistence, stronger symbolic handling, and an optional OpenCL retrieval path.
- The v22 release keeps that grounding contract but broadens paraphrase tolerance, makes fact memory more natural, removes the retained-turn cap, adds explicit divide-by-zero handling, and extends the hardening suite to 10M and near-100M runs.
- The v22.5 release keeps the v22 product behavior but adds a real CUDA backend for NVIDIA RTX GPUs, a raw `accel-bench` command, conservative `cpu_mt` retrieval support, and an experimental multithreaded numeric output scorer.
- The v23 release is the conversational repair release: real versioned dialogue assets, deterministic operational answers, stronger hardware-aware retrieval guards, and constrained free-chat composition instead of the older stale-feeling char-level fallback.
- The v23.5 release is the technical backend follow-up: keep the v23 conversation surface stable, add a numeric scoring backend selector in `src/network.zig`, add a dedicated sparse numeric CUDA module, expose a `numeric-accel-info` probe in `src/main.zig`, and measure CPU versus `cpu_mt` versus CUDA on the numeric `eval-variant` path without changing the packaged CPU baseline until the measured suite earns it.
- The v24 release is the conversational product follow-up: keep the v23.5 numeric and backend stack stable, ship a truthful versioned grounded seed plus a separate open-chat seed, validate broader free chat with a versioned open-chat scripted session eval, and keep unsupported factual questions on the uncertainty path instead of broadening by hallucination.
- The v22 numeric release also learned three practical hardening lessons:
  use a streamed single-variant path when `include_baseline=false`,
  release dead-memory outgoing capacity in `src/network.zig` instead of retaining it forever,
  and keep the near-100M run on a memory-bounded long-horizon profile instead of forcing the full short-suite higher-order expert stack.
- The v22.5 backend lessons are different:
  verify the discrete GPU with `nvidia-smi` while the CUDA workload is live,
  keep the packaged numeric suite on the single-thread path unless the multithreaded numeric scorer proves itself on the shipped profile,
  and expect CUDA speedups to show up more clearly in raw retrieval benches than in short end-to-end chat timings.
- The v23 product lessons are separate:
  keep single-turn `chat-eval` assets free of session-dependent recall prompts,
  answer starter-file, artifact-path, and backend-command questions operationally when the runtime can know them exactly,
  keep retrieval semantic guards strong enough that hardware prompts do not fall into benchmark blurbs,
  and record `nvidia-smi` driver output in the results when the local NVIDIA stack changes.
- The v23.5 backend lessons are different again:
  treat dialogue retrieval CUDA and numeric CUDA as separate measured claims,
  validate the numeric path with `numeric-accel-info` before inferring that `eval-variant` is actually using the RTX device,
  keep `numeric_backend=cpu` plus `score_threads=1` as the packaged default until end-to-end timings prove otherwise,
  and remember that per-step CUDA wins can disappear if host-side packing dominates, so backend promotion has to follow measured elapsed time rather than architectural preference.
- The v24 product lessons are separate again:
  keep the grounded release seed and the broader open-chat seed separate,
  use curated assistant-safe open-chat pairs rather than raw dialogue data that makes the assistant claim human tastes or biography,
  validate broader conversation with a scripted open-chat session asset instead of only looking at non-empty counts,
  keep roadmap routing narrow so it does not hijack ordinary overview or artifact-path questions,
  and treat natural `i am ...` statements carefully so emotional or support prompts are not misparsed as names.
- The v25 product lessons are the next step:
  broaden free chat by routing non-domain prompts into the open-chat path before grounded SBAN retrieval,
  keep the grounded seed and the open-chat seed versioned separately so stale release answers do not leak across generations,
  use a reproducible seed builder plus a curated assistant-safe corpus instead of pretending broad capability came from a single hand-written prompt file,
  validate broader everyday prompts directly with versioned session assets instead of claiming "99 percent" from anecdotes,
  and keep unsupported prompts on an honest uncertainty path even after widening paraphrase coverage and light factual support.
- The release profile is search-sensitive. Preserve explicit overrides in release scripts instead of assuming raw defaults are the winning profile.

## Long-run release notes

- `python scripts/run_v25_release.py --skip-build --resume` should be the default recovery path after an interrupted long hardening run.
- The near-100M v22 artifact is not just "the same profile but longer"; it intentionally disables the order-4, order-5, and continuation expert bonuses so the measurement stays bounded and reproducible.
- If a long run fails with `OutOfMemory`, inspect both bundle allocation and retained capacity in dead neurons before assuming the model itself is fundamentally too large.

## Deliverables

For a new release:

1. Run `python scripts/run_v25_release.py` or the next-generation equivalent.
2. Run `python scripts/make_v25_deliverables.py` or the next-generation equivalent.
3. Confirm the versioned paper PDF, executive summary, repo zip, and demo bundle exist under `deliverables/`.
4. Update `README.md` so the current release can be reproduced without extra context.
5. If CI or release workflows were requested, confirm `.github/workflows/` contains the current versioned automation.

## When to read references

- Read `references/release_profiles.md` when you need the current benchmark thresholds, release profile, exact result filenames, or the release caveat wording.

