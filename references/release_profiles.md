# SBAN Release Profiles

## Current baseline for v28 work

Use the packaged v27 numeric release as the baseline when testing or extending v28.

### Packaged v27 numeric metrics

- Prefix: `99.6650%`
- Drift: `99.5675%`
- Probe: `99.9112%`
- 250k: `99.4632%`
- 1M: `99.5334%`
- 10M: `78.3230%`
- 20M: `78.4756%`

## v28 target

The v28 research and product goal is **stress-report repair, stricter release validation, broader natural session memory aliases, and stable numeric guardrails without giving up the safe fallback path**:

- preserve the packaged CPU short-suite and hardening metrics while keeping `numeric_backend=cpu` and `score_threads=1` as the release default
- ship a real v28 grounded seed plus a separate curated and dataset-enriched v28 open-chat seed
- replace stale v26/v21/v22 user-facing labels in the v28 runtime, experiment metadata, scripts, and generated artifacts
- fix loose expectation matching with word-boundary checks and add a false-positive guard
- support cat, dog, project, launch-date/date-like, generic `our X is Y`, and tomorrow-style session facts in addition to earlier name, team, role, and location memory
- add explicit static current-fact, translation, summarization, exponent, rate-problem, and reported coding-prompt behavior
- keep operational answers exact for starter files, artifact paths, bundle inventory, backend commands, and hardware support questions
- keep Zig-upstream support intact on the shipped local source-tree prompts
- validate the broader conversational surface directly with versioned session evaluations, including a dedicated broad free-chat battery
- assert actual `cpu_mt` and CUDA backend execution when those backends are requested and available
- keep CPU fallback automatic and keep accelerated numeric paths opt-in until measured wins justify promotion
- only report a `100M` point when a completed JSON artifact actually exists

## v28 release commands

Run the measured suite:

```bash
python scripts/run_v28_release.py
```

Generate the packaged report, summary, PDF, demo bundle, and repo zip:

```bash
python scripts/make_v28_deliverables.py
```

Package the newcomer demo directly:

```bash
python scripts/package_v28_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

Rebuild the shipped open-chat seed:

```bash
python scripts/build_v28_open_seed.py
```

## Packaged numeric profile

The packaged v28 numeric core keeps the safe single-thread CPU release stance and reuses the v27 continuation profile so product and reporting repairs are isolated from numeric-profile churn.

Common network overrides:

- bits: `4`
- `enable_long_term=false`
- `history_lags=32`
- `birth_margin=21`
- `min_parents_for_birth=4`
- `max_carry_memories=48`
- `max_hidden_per_hop=32`
- `propagation_depth=2`
- `birth_pressure_threshold_bonus=0`
- `birth_saturation_threshold_bonus=0`
- `birth_saturation_parent_boost=0`
- `hybrid_share_ppm=0`
- `hybrid_recent_drift_bonus=0`
- `recent_markov2_bonus_ppm=0`
- `burst_bonus_ppm=520`
- `markov1_bonus_ppm=340`
- `markov2_bonus_ppm=760`
- `markov3_bonus_ppm=1900`
- `markov4_bonus_ppm=2400`
- `markov5_bonus_ppm=2800`
- `continuation_bonus_ppm=9200`
- `continuation_min_order=6`
- `continuation_max_order=32`
- `continuation_support_prior=0`
- `continuation_min_support=1`
- `hybrid_support_prior=0`
- `hybrid_evidence_prior=0`
- `score_threads=1`
- `numeric_backend=cpu`

Hardening additions:

- 10M run: `segment_len=2500000`, `checkpoint_interval=100000`, `sequence_seed_length=4000000`, `include_baseline=false`
- 20M run: `segment_len=5000000`, `checkpoint_interval=200000`, `sequence_seed_length=8000000`, `include_baseline=false`, plus bounded continuation overrides `continuation_bonus_ppm=8000` and `continuation_min_order=8`

The short suite and 10M run use the v27 stronger continuation profile. The 20M run stays on a bounded continuation fallback because the stronger profile hit `OutOfMemory` at 20M on this workstation.

## v28 dialogue and product profile

- default grounded seed: `data/sban_dialogue_seed_v28.txt`
- default open-chat seed: `data/sban_dialogue_open_seed_v28.txt`
- open seed builder: `scripts/build_v28_open_seed.py`
- grounded prompt eval asset: `data/sban_chat_eval_prompts_v28.txt`
- main session eval asset: `data/sban_session_eval_v28.txt`
- open-chat scripted session eval asset: `data/sban_open_chat_session_eval_v28.txt`
- broad free-chat battery: `data/sban_broad_chat_session_eval_v28.txt`
- default product stance: grounded answers for SBAN-domain prompts, exact operational answers when the runtime knows its own files or commands, broader free chat through deterministic composition plus the v28 open seed, explicit static-boundary messaging for current facts, honest uncertainty otherwise
- session persistence: encoded structured `SBAN_SESSION_V28` format with legacy v27/v26 compatibility and no retained-turn cap
- default chat mode: free mode with safe conversational composition enabled
- acceleration: CPU by default for numeric release checks, `backend=auto` for the newcomer chat loop, optional `cpu_mt`, direct CUDA on NVIDIA, OpenCL fallback through `backend=gpu`, and a numeric backend selector (`numeric_backend=cpu|cpu_mt|cuda|auto`) for `eval-variant`

## Interpretation guardrails

- The numeric benchmark story and the conversational usability story are separate and should stay separate.
- The short numeric suite remains the baseline guardrail; the 10M and 20M runs are hardening extensions.
- GPU support is real and validated, and CUDA is the preferred large-corpus retrieval accelerator on NVIDIA hardware.
- Treat dialogue retrieval CUDA and numeric CUDA as separate claims. Measure both directly.
- The packaged numeric release still stays on CPU until accelerated numeric runs prove a dependable end-to-end win.
- Preserve the trustworthiness gains. Do not loosen retrieval thresholds in a way that turns uncertainty failures back into plausible-but-wrong blurbs.
- Prefer direct operational answers for artifact paths, starter files, bundle inventory, and backend commands when the runtime can know them exactly.
- Treat the open-chat and broad-chat evaluations as real release gates. If the shipped conversational surface broadens, prove it with the versioned eval assets instead of hand-picked one-off demos.
- Treat the dataset-enriched open seed and the Zig-upstream prompt coverage as product support assets, not as proof of broad reasoning.
- A completed hosted `100M` CPU artifact exists for the v26-era profile, so it can be cited as an additional hardening datapoint, but it is not the packaged v28 release gate.
