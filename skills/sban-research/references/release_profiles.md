# SBAN Release Profiles

## v17 packaged baseline

- Prefix: `51.7700%`
- Drift: `50.0375%`
- Probe: `75.1500%`
- 250k: `53.4588%`
- 1M: `51.3550%`
- Hybrid chat: `42 / 42` anchored, `42 / 42` non-empty

## v18 packaged release profile

- bits: `4`
- key overrides:
  - `enable_long_term=false`
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
  - `hybrid_support_prior=0`
  - `hybrid_evidence_prior=0`
  - `hybrid_reward=28`
  - `hybrid_penalty=6`
  - `sequence_seed_path=data/enwik8`
  - `sequence_seed_offset=60050`
  - `sequence_seed_length=5000000`

## v18 benchmark targets

These are the minimum numeric targets implied by the requested 7% relative lift over v17:

- Prefix: `>= 55.3939%`
- Drift: `>= 53.5401%`
- Probe: `>= 80.4105%`
- 250k: `>= 57.2019%`
- 1M: `>= 54.9499%`

## Current release commands

Build and run the release suite:

```bash
python scripts/run_v18_release.py
```

Generate the report, summary, PDF, and repo zip:

```bash
python scripts/make_v18_deliverables.py
```

## Expected result files

- `docs/results/v18/unified_prefix_v18_release.json`
- `docs/results/v18/unified_drift_v18_release.json`
- `docs/results/v18/unified_probe_v18_release.json`
- `docs/results/v18/longrun_v18_250k.json`
- `docs/results/v18/longrun_v18_1m.json`
- `docs/results/v18/chat_eval_v18_hybrid.txt`
- `docs/results/v18/chat_eval_v18_free.txt`
