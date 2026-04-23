# SBAN Release Profiles

## Current baseline for v25 work

Use the packaged v24 numeric release as the baseline when testing or extending v25.

### Packaged numeric metrics

- Prefix: `99.6350%`
- Drift: `99.5400%`
- Probe: `99.9000%`
- 250k: `99.4076%`
- 1M: `99.4344%`
- 10M: `77.9175%`

## v25 target

The v25 research and product goal is **broader real free chat without numeric regression**:

- keep each original packaged numeric benchmark at roughly the v24 level on the original CPU release profile
- ship a real v25 grounded seed plus a separate curated and dataset-enriched v25 open-chat seed
- fix the narrow free-chat failure mode where ordinary prompts either fell to uncertainty or overmatched SBAN-domain blurbs
- keep operational answers exact for starter files, artifact paths, bundle inventory, backend commands, and hardware support questions
- broaden deterministic free-chat composition for everyday planning, writing, explanation, coding, light knowledge, and short math prompts
- validate the broader conversational surface directly with versioned session evaluations instead of only counting non-empty outputs
- keep CPU fallback automatic and keep `numeric_backend=cpu` as the packaged default unless measured wins justify promotion
- keep measuring CPU versus `cpu_mt` versus CUDA on the numeric path explicitly instead of inferring backend wins from chat latency

## v25 release commands

Run the measured suite:

```bash
python scripts/run_v25_release.py
```

Generate the packaged report, summary, PDF, demo bundle, and repo zip:

```bash
python scripts/make_v25_deliverables.py
```

Package the newcomer demo directly:

```bash
python scripts/package_v25_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

Rebuild the shipped open-chat seed:

```bash
python scripts/build_v25_open_seed.py
```

## Packaged numeric profile

The packaged v25 numeric core intentionally preserves the earlier regression-safe profile as an engine-health guardrail.

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

Hardening additions:

- 10M run: `segment_len=2500000`, `checkpoint_interval=100000`, `sequence_seed_length=4000000`
- Near-100M run: `segment_len=24999999`, `checkpoint_interval=1000000`, `sequence_seed_length=8000000`, `include_baseline=false`, `markov4_bonus_ppm=0`, `markov5_bonus_ppm=0`, `continuation_bonus_ppm=0`

The near-100M run is intentionally just under a literal 100,000,000 predictions because the exact `enwik8` corpus length is `100,000,000` bytes and prefix evaluation needs `total_predictions + 1` tokens.

The 100M-class run is a long-horizon hardening profile rather than a strict copy of the short-suite common profile. It disables the order-4, order-5, and continuation expert bonuses so the long run does not waste memory and time maintaining expert tables that are not part of that hardened measurement.

## v25 dialogue and product profile

- default grounded seed: `data/sban_dialogue_seed_v25.txt`
- default open-chat seed: `data/sban_dialogue_open_seed_v25.txt`
- open seed builder: `scripts/build_v25_open_seed.py`
- grounded prompt eval asset: `data/sban_chat_eval_prompts_v25.txt`
- main session eval asset: `data/sban_session_eval_v25.txt`
- open-chat scripted session eval asset: `data/sban_open_chat_session_eval_v25.txt`
- default product stance: grounded answers for SBAN-domain prompts, exact operational answers when the runtime knows its own files or commands, broader free chat through deterministic composition plus the open seed, honest uncertainty otherwise
- session persistence: encoded structured `SBAN_SESSION_V25` format with legacy v24 compatibility and no retained-turn cap
- default chat mode: free mode with safe conversational composition enabled
- acceleration: CPU by default for numeric release checks, `backend=auto` for the newcomer chat loop, optional `cpu_mt`, direct CUDA on NVIDIA, OpenCL fallback through `backend=gpu`, and a numeric backend selector (`numeric_backend=cpu|cpu_mt|cuda|auto`) for `eval-variant`

## Interpretation guardrails

- The numeric benchmark story and the usability story are separate and should stay separate.
- The original short numeric suite is the baseline guardrail; the 10M and near-100M runs are hardening extensions.
- GPU support is real and validated, and CUDA is the preferred large-corpus retrieval accelerator on NVIDIA hardware.
- Treat dialogue retrieval CUDA and numeric CUDA as separate claims. Measure both directly.
- The experimental numeric multithread path is not the packaged default unless the measured suite proves it is faster.
- Preserve the v21-to-v24 trustworthiness gains. Do not loosen retrieval thresholds in a way that turns uncertainty failures back into plausible-but-wrong blurbs.
- Prefer direct operational answers for artifact paths, starter files, bundle inventory, and backend commands when the runtime can know them exactly, instead of forcing those questions through fuzzy retrieval.
- Treat the open-chat evaluation as a real release gate: if the shipped conversational surface broadens, prove it with the versioned open-chat session asset instead of hand-picked one-off demos.
- Treat the dataset-enriched open seed as a product support asset, not as proof of broad reasoning. Broader coverage should still be described honestly.
