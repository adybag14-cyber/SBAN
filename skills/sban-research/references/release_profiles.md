# SBAN Release Profiles

## v16 packaged baseline

- Prefix: `45.1625%`
- Drift: `44.8500%`
- Probe: `71.3767%`
- 250k: `46.1572%`
- 1M: `43.2688%`
- Hybrid chat: `36 / 36` anchored, `36 / 36` non-empty

## v17 packaged release profile

- bits: `4`
- key overrides:
  - `enable_long_term=true`
  - `birth_margin=20`
  - `min_parents_for_birth=4`
  - `max_carry_memories=64`
  - `max_hidden_per_hop=48`
  - `propagation_depth=3`
  - `long_term_bonus_ppm=1120`
  - `long_term_bonus_precision_ppm=580`
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
  - `hybrid_support_prior=1`
  - `hybrid_evidence_prior=0`

## Current release commands

Build and run the release suite:

```bash
python scripts/run_v17_release.py
```

Generate the report, summary, PDF, and repo zip:

```bash
python scripts/make_v17_deliverables.py
```

## Expected result files

- `docs/results/v17/unified_prefix_v17_release.json`
- `docs/results/v17/unified_drift_v17_release.json`
- `docs/results/v17/unified_probe_v17_release.json`
- `docs/results/v17/longrun_v17_250k.json`
- `docs/results/v17/longrun_v17_1m.json`
- `docs/results/v17/chat_eval_v17_hybrid.txt`
- `docs/results/v17/chat_eval_v17_free.txt`
