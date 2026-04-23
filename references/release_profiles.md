# SBAN Release Profiles

## Current baseline for v26 work

Use the packaged v25 numeric release as the baseline when testing or extending v26.

### Packaged numeric metrics

- Prefix: `99.6350%`
- Drift: `99.5400%`
- Probe: `99.9000%`
- 250k: `99.4076%`
- 1M: `99.4344%`
- 10M: `77.9175%`

## v26 target

The v26 research and product goal is **broader dependable free chat, Zig-upstream support, and a harder long-run guardrail without numeric regression**:

- keep each packaged numeric baseline metric stable on the original CPU release profile
- extend the hardening ladder with a measured `20M` run
- ship a real v26 grounded seed plus a separate curated and dataset-enriched v26 open-chat seed
- fix the remaining free-chat overmatches and improve ordinary explanation, coding, and memory prompts
- keep operational answers exact for starter files, artifact paths, bundle inventory, backend commands, and hardware support questions
- support practical Zig-upstream prompts from the shipped local source-tree knowledge
- validate the broader conversational surface directly with versioned session evaluations, including a dedicated broad free-chat battery
- keep CPU fallback automatic and keep `numeric_backend=cpu` as the packaged default unless measured wins justify promotion
- skip `100M` claims unless a completed JSON artifact already exists

## v26 release commands

Run the measured suite:

```bash
python scripts/run_v26_release.py
```

Generate the packaged report, summary, PDF, demo bundle, and repo zip:

```bash
python scripts/make_v26_deliverables.py
```

Package the newcomer demo directly:

```bash
python scripts/package_v26_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

Rebuild the shipped open-chat seed:

```bash
python scripts/build_v26_open_seed.py
```

## Packaged numeric profile

The packaged v26 numeric core intentionally preserves the earlier regression-safe profile as an engine-health guardrail.

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
- `continuation_bonus_ppm=8000`
- `continuation_min_order=8`
- `continuation_max_order=32`
- `continuation_support_prior=0`
- `continuation_min_support=1`
- `hybrid_support_prior=0`
- `hybrid_evidence_prior=0`
- `score_threads=1`
- `numeric_backend=cpu`

Hardening additions:

- 10M run: `segment_len=2500000`, `checkpoint_interval=100000`, `sequence_seed_length=4000000`, `include_baseline=false`
- 20M run: `segment_len=5000000`, `checkpoint_interval=200000`, `sequence_seed_length=8000000`, `include_baseline=false`

The 20M run is an additional hardening extension on top of the shorter suite, not a replacement for the original guardrail profile.

## v26 dialogue and product profile

- default grounded seed: `data/sban_dialogue_seed_v26.txt`
- default open-chat seed: `data/sban_dialogue_open_seed_v26.txt`
- open seed builder: `scripts/build_v26_open_seed.py`
- grounded prompt eval asset: `data/sban_chat_eval_prompts_v26.txt`
- main session eval asset: `data/sban_session_eval_v26.txt`
- open-chat scripted session eval asset: `data/sban_open_chat_session_eval_v26.txt`
- broad free-chat battery: `data/sban_broad_chat_session_eval_v26.txt`
- default product stance: grounded answers for SBAN-domain prompts, exact operational answers when the runtime knows its own files or commands, broader free chat through deterministic composition plus the open seed, honest uncertainty otherwise
- session persistence: encoded structured `SBAN_SESSION_V26` format with legacy v25 compatibility and no retained-turn cap
- default chat mode: free mode with safe conversational composition enabled
- acceleration: CPU by default for numeric release checks, `backend=auto` for the newcomer chat loop, optional `cpu_mt`, direct CUDA on NVIDIA, OpenCL fallback through `backend=gpu`, and a numeric backend selector (`numeric_backend=cpu|cpu_mt|cuda|auto`) for `eval-variant`

## Interpretation guardrails

- The numeric benchmark story and the usability story are separate and should stay separate.
- The original short numeric suite is the baseline guardrail; the 10M and 20M runs are hardening extensions.
- GPU support is real and validated, and CUDA is the preferred large-corpus retrieval accelerator on NVIDIA hardware.
- Treat dialogue retrieval CUDA and numeric CUDA as separate claims. Measure both directly.
- The experimental numeric multithread path is not the packaged default unless the measured suite proves it is faster.
- Preserve the trustworthiness gains. Do not loosen retrieval thresholds in a way that turns uncertainty failures back into plausible-but-wrong blurbs.
- Prefer direct operational answers for artifact paths, starter files, bundle inventory, and backend commands when the runtime can know them exactly.
- Treat the open-chat and broad-chat evaluations as real release gates. If the shipped conversational surface broadens, prove it with the versioned eval assets instead of hand-picked one-off demos.
- Treat the dataset-enriched open seed and the Zig-upstream prompt coverage as product support assets, not as proof of broad reasoning.
- If no completed `100M` JSON artifact exists, say so plainly and stop the reported hardening ladder at `20M`.
