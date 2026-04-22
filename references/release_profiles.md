# SBAN Release Profiles

## Current baseline for next-generation work

Use the packaged v20 numeric release as the baseline when testing a successor unless the benchmark target changes.

### v20 packaged metrics

- Prefix: `99.6350%`
- Drift: `99.5400%`
- Probe: `99.9000%`
- 250k: `99.4076%`
- 1M: `99.4344%`

### v21 target relative to v20

The v21 research goal is **stability plus reliability**:

- keep each packaged numeric benchmark within roughly `±1.0` percentage point of the v20 packaged baseline
- improve unsupported-prompt behavior so the runtime declines cleanly instead of hallucinating release blurbs
- broaden session memory beyond names
- fix symbolic arithmetic on negatives and decimals
- use structured session persistence instead of raw transcript files
- add a versioned session evaluation and validate the optional CPU or GPU retrieval path

## v21 release commands

Run the measured suite:

```bash
python scripts/run_v21_release.py
```

Generate the packaged report, summary, PDF, demo bundle, and repo zip:

```bash
python scripts/make_v21_deliverables.py
```

## v21 shipped numeric profile

The packaged v21 numeric suite intentionally keeps the same core profile as v20 because the numeric suite now serves as an engine-health guardrail while the main generation work targets runtime reliability.

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

Benchmark-specific corpus seeding:

- Prefix short suite: `sequence_seed_path=data/enwik8`, `sequence_seed_offset=0`, `sequence_seed_length=1000000`
- Drift short suite: `sequence_seed_path=data/enwik8`, `sequence_seed_offset=0`, `sequence_seed_length=1000000`, `sequence_seed_align_to_segment=true`, `sequence_seed_replace_on_reset=true`
- Probe: `sequence_seed_path=data/elastic_probe.bin`, `sequence_seed_offset=0`, `sequence_seed_length=120100`
- 250k: `sequence_seed_path=data/enwik8`, `sequence_seed_offset=0`, `sequence_seed_length=1000000`
- 1M: `sequence_seed_path=data/enwik8`, `sequence_seed_offset=0`, `sequence_seed_length=2000000`

## v21 dialogue and product profile

- default seed asset: `data/sban_dialogue_seed_v21.txt`
- prompt eval asset: `data/sban_chat_eval_prompts_v21.txt`
- session eval asset: `data/sban_session_eval_v21.txt`
- default product stance: grounded answers first, honest uncertainty otherwise
- session persistence: encoded structured `SBAN_SESSION_V21` format
- acceleration: CPU by default, optional OpenCL GPU retrieval scoring through `accel-info` and `backend=auto`

## Interpretation guardrails

- The numeric release still needs careful methodology wording and should not be oversold.
- The grounded continuing-session demo is a separate user-facing artifact.
- Do not blur the numeric benchmark story and the reliability story together.
- When testing future generations, preserve the v21 trustworthiness gains instead of regressing to looser retrieval for the sake of coverage.
