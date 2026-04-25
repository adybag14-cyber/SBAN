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
- `scripts/build_v34_runtime_prewarm.py` for the generated runtime prewarm pack, compatibility seed/open/knowledge files, eval assets, and stats
- `scripts/vocab_size_probe_v34.py` for larger-vocabulary collision and dense-memory estimates through 65,536 buckets
- `scripts/ci_smoke_v34.py` for the current product smoke gate and default-prewarm checks
- `scripts/run_v34_release.py` for the current packaged benchmark, dialogue suite, runtime-prewarm eval, and vocabulary probe
- `scripts/make_v34_deliverables.py` for report, summary, PDF, demo bundle, repo zip, and workstation recipe generation
- `scripts/package_v34_demo.py` for the newcomer demo bundle
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
8. For every new SBAN generation, update this skill with the generation-specific lessons, commit and push the finished release changes, monitor the GitHub CI suite, and if CI fails, debug, fix, re-commit, re-push, and monitor again until the suite is green or a concrete external blocker is documented.
9. A version upgrade is not complete after push CI alone. Trigger the versioned GitHub full release suite workflow, push the matching release tag such as `v34.0.0` so the release bundle workflow publishes GitHub Release assets, monitor both workflows, and verify the GitHub Release contains the expected demo assets before calling the generation shipped.
10. For v34 and later, verify runtime prewarm assets, vocab probe JSON, GitHub Release demo assets, and any manually uploaded report/summary/PDF/repo assets before calling a full release complete.

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
- The v26 product lessons are the next step after that:
  keep deterministic free-chat composition ahead of fuzzy open-seed retrieval for the prompts you can answer safely,
  add a separate broad free-chat scripted battery instead of relying only on one main session asset,
  treat Zig-upstream operational and file-location prompts as explicit supported product behavior when local source assets are provided,
  keep team and other natural session facts on the structured memory path rather than letting name extraction swallow them,
  extend the hardening ladder to 20M before talking about 100M again,
  and only claim a 100M result if a completed JSON artifact actually exists under `docs/results/`.
- The v27 product lessons are the next step after that:
  keep the grounded release seed honest enough that the first overview answer still matches the scripted release expectations,
  validate the exact user-reported failure prompts directly instead of trusting only the curated eval batteries,
  keep dog, project, and tomorrow-style session facts on the structured memory path so broader memory claims stay true in runtime behavior,
  treat the stronger short-suite continuation profile and the 20M hardening profile as separate release-tier configurations when the stronger profile hits `OutOfMemory` on the longer horizon,
  and upgrade the CI and release smoke path together with the runtime so the tagged automation cannot quietly keep shipping the previous generation.
- The v28 product lessons are the stress-report repair step:
  preserve the v27 numeric profile while fixing stale release identity strings,
  make session-eval matching boundary-aware so short values cannot false-pass inside unrelated words,
  keep cat, dog, launch-date, generic `our X is Y`, project, and tomorrow-style session facts on the structured memory path,
  add explicit bounded behavior for current facts, translation, summarization, exponent math, speed/rate word problems, and reported coding prompts,
  truncate long prompt display in eval output,
  and assert actual backend use in CI smoke checks instead of trusting configured backend strings.
- The v31 product lessons are the synthetic-knowledge and runtime-hardening step:
  generate the broader knowledge asset with deterministic scripts instead of manual conversation transcripts,
  load that asset through an explicit `knowledge_path` separate from grounded and open-chat seeds,
  validate general knowledge, Zig code, JSON, algebra, huge-math bounds, source-boundary behavior, and secret rejection with a versioned generated-knowledge session eval,
  probe larger vocab sizes before changing the dense byte-vocab core because collision reductions come with steep order-table memory cost,
  cap session files, retained facts, retained turns, and printed output so evaluation and demos cannot bypass safety limits,
  keep unindexed source-location and live-current prompts on an honest uncertainty path,
  and update both the repo skill and installed Codex skill before committing every new generation.
- The v34 product lessons are the runtime-prewarm step:
  inspect colleague zip baselines directly when supplied,
  preserve v33's powerchat/retrieval/instruction-memory work instead of jumping from an older Git tag,
  generate the default runtime prewarm pack with `scripts/build_v34_runtime_prewarm.py`,
  make the normal chat path work without explicit seed/open/knowledge arguments,
  keep compatibility seed/open/knowledge files generated for older scripts and packages,
  verify broad stable facts, reasoning, real-world triage, Python, SQL, and Zig code prompts through `scripts/ci_smoke_v34.py`,
  extend vocab probes through 65,536 buckets while keeping the dense byte-vocab core unchanged,
  and keep live-current or unsupported source-location claims behind explicit external-lookup boundaries.
- The release profile is search-sensitive. Preserve explicit overrides in release scripts instead of assuming raw defaults are the winning profile.

## Long-run release notes

- `python scripts/run_v31_release.py --skip-build --resume` should be the default recovery path after an interrupted long hardening run.
- The near-100M v22 artifact is not just "the same profile but longer"; it intentionally disables the order-4, order-5, and continuation expert bonuses so the measurement stays bounded and reproducible.
- If a long run fails with `OutOfMemory`, inspect both bundle allocation and retained capacity in dead neurons before assuming the model itself is fundamentally too large.
- For the v31 era, keep the core hosted release suite split from the independent 10M, 20M, and 100M workflows, and make the runner label configurable because the repo may not actually have a larger self-hosted runner registered.

## Deliverables

For a new release:

1. Run `python scripts/build_v34_runtime_prewarm.py` and `python scripts/vocab_size_probe_v34.py` or the next-generation equivalents.
2. Run `python scripts/run_v34_release.py` or the next-generation equivalent.
3. Run `python scripts/make_v34_deliverables.py` or the next-generation equivalent.
4. Confirm the versioned paper PDF, executive summary, repo zip, demo bundle, runtime prewarm JSON, generated knowledge compatibility JSON, and vocab probe JSON exist under `deliverables/` or `docs/results/`.
5. Update `README.md` and `references/release_profiles.md` so the current release can be reproduced without extra context.
6. If CI or release workflows were requested, confirm `.github/workflows/` contains the current versioned automation.
7. Commit and push the release after local validation, then verify the pushed GitHub checks complete successfully.
8. Trigger the versioned full release suite workflow on GitHub and monitor it.
9. Create and push the release tag for the generation so `Release Demo Bundles` runs, then verify the GitHub Release exists and has the expected Windows and Linux demo zip assets.
10. If previous generations uploaded report/summary/PDF/repo zip assets manually, upload the current generation equivalents and verify the GitHub Release asset list.

## When to read references

- Read `references/release_profiles.md` when you need the current benchmark thresholds, release profile, exact result filenames, or the release caveat wording.
