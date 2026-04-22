# SBAN Release Profiles

## Current baseline for next-generation work

Use the packaged v19 release as the baseline when testing a successor unless the benchmark target changes.

### v19 packaged metrics

- Prefix: `99.6350%`
- Drift: `99.5400%`
- Probe: `99.9000%`
- 250k: `99.4076%`
- 1M: `99.4344%`

### v20 target relative to v19

The v20 research goal is **stability, not a larger numeric jump**:

- keep each packaged numeric benchmark within roughly `±1.0` percentage point of the v19 packaged baseline
- improve free chat behavior on the versioned prompt set
- pass the versioned scripted session evaluation

## v20 release commands

Run the measured suite:

```bash
python scripts/run_v20_release.py
```

Generate the packaged report, summary, PDF, demo bundle, and repo zip:

```bash
python scripts/make_v20_deliverables.py
```

## v20 shipped numeric profile

The packaged v20 numeric suite intentionally keeps the same core profile as v19 because the numeric suite now serves as an engine-health guardrail.

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

## Interpretation guardrails

- The v20 numeric release remains self-seeded and transductive.
- The continuing-session demo is a separate user-facing artifact.
- Do not blur the numeric benchmark story and the usability story together.
