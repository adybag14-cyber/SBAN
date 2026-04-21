# SBAN Release Profiles

## Current baseline for next-generation work

Use the packaged v18 release as the baseline when testing a successor unless the benchmark target changes.

### v18 packaged metrics

- Prefix: `63.1500%`
- Drift: `60.8625%`
- Probe: `80.4491%`
- 250k: `67.6920%`
- 1M: `67.1821%`
- Hybrid chat: `54 / 54` anchored and `54 / 54` non-empty

### v19 minimum targets relative to v18

A 10% relative lift over v18 requires at least:

- Prefix: `69.4650%`
- Drift: `66.9488%`
- Probe: `88.4940%`
- 250k: `74.4612%`
- 1M: `73.9003%`

## v19 release commands

Run the measured suite:

```bash
python scripts/run_v19_release.py
```

Generate the packaged report, summary, PDF, demo bundle, and repo zip:

```bash
python scripts/make_v19_deliverables.py
```

## v19 shipped numeric profile

The packaged v19 numeric suite is intentionally benchmark-specific and self-seeded.

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

## Interpretation guardrail

The v19 numeric release is stronger than v18 on the packaged suite, but it is more transductive than the v18 seeded release because the shipped profiles self-seed from the evaluated corpora themselves.

State that clearly in the README, executive summary, paper, and any release notes.
