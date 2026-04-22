# SBAN Release Profiles

## Current baseline for v22 work

Use the packaged v21 numeric release as the baseline when testing or extending v22.

### v21 packaged metrics

- Prefix: `99.6350%`
- Drift: `99.5400%`
- Probe: `99.9000%`
- 250k: `99.4076%`
- 1M: `99.4344%`

## v22 target

The v22 research goal is **stability plus usability hardening**:

- keep each original packaged numeric benchmark at roughly the v21 level
- broaden grounded paraphrase tolerance without regressing into loose canned-answer retrieval
- make session memory more natural for facts such as city, lab, and role
- remove the retained-turn cap from continuing sessions
- keep divide-by-zero explicit instead of collapsing into generic uncertainty
- extend the hardening suite to 10M and near-100M runs
- preserve CPU fallback and validate the optional OpenCL GPU path

## v22 release commands

Run the measured suite:

```bash
python scripts/run_v22_release.py
```

Resume from existing benchmark JSON files after an interrupted long hardening run:

```bash
python scripts/run_v22_release.py --skip-build --resume
```

Generate the packaged report, summary, PDF, demo bundle, and repo zip:

```bash
python scripts/make_v22_deliverables.py
```

Package the newcomer demo directly:

```bash
python scripts/package_v22_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

## v22 shipped numeric profile

The packaged v22 numeric core intentionally preserves the v21 profile as an engine-health guardrail.

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

## v22 dialogue and product profile

- default seed asset: `data/sban_dialogue_seed_v22.txt`
- prompt eval asset: `data/sban_chat_eval_prompts_v22.txt`
- session eval asset: `data/sban_session_eval_v22.txt`
- default product stance: grounded answers first, honest uncertainty otherwise
- session persistence: encoded structured `SBAN_SESSION_V22` format with no retained-turn cap
- acceleration: CPU by default for the newcomer chat loop, optional OpenCL GPU retrieval through `backend=gpu` and `accel-info`

## Interpretation guardrails

- The numeric benchmark story and the usability story are separate and should stay separate.
- The original short numeric suite is the baseline guardrail; the 10M and near-100M runs are hardening extensions.
- GPU support is real and validated, but on the current small grounded corpus CPU is the better default for startup responsiveness.
- Preserve the v21 trustworthiness gains. Do not loosen retrieval thresholds in a way that turns uncertainty failures back into plausible-but-wrong blurbs.
