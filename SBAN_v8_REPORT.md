# SBAN v10 report

## What changed in this v8 pass

SBAN v10 focuses on **serious architecture stress-tuning**, not just another bit sweep.

Two concrete improvements were added to the runtime and release flow:

1. `eval-variant` now accepts **live config overrides** like `max_carry_memories=48` and `enable_long_term=false`, so the runtime can be stress-tuned without recompiling for each candidate.
2. The v8 release packages a **search script** and a **stress run script** so the best operating points can be reproduced directly.

## Main tuning result

The strongest unified v8 operating point I found is a **6-bit stress default** with:

- `max_carry_memories=48`

That single change improved all three target protocols at once relative to the untuned 6-bit comparison run.

## Unified v8 stress profile

Files:

- `docs/results/v8/unified_prefix_v8_6bit_stress.json`
- `docs/results/v8/unified_drift_v8_6bit_stress.json`
- `docs/results/v8/unified_probe_v8_6bit_stress.json`

Results:

- **Prefix:** 41.5900%
- **Drift:** 42.0050%
- **Probe:** 69.0836%

Comparison versus the untuned 6-bit comparison run:

- **Prefix:** +0.2150 pp
- **Drift:** +0.0875 pp
- **Probe:** +0.0655 pp

This is the cleanest v8 answer to “get real improvements from the model” because the same tuning change helps the whole target suite.

## Best specialized operating points

### 1. Prefix best

File: `docs/results/v8/best_prefix_v8_5bit_nolong.json`

Profile:

- 5-bit default
- `enable_long_term=false`

Result:

- **41.7575%**

### 2. Drift best

File: `docs/results/v8/best_drift_v8_5bit_nolong.json`

Profile:

- 5-bit default
- `enable_long_term=false`

Result:

- **42.2175%**

### 3. Probe best

File: `docs/results/v8/best_probe_v8_6bit_pp600.json`

Profile:

- 6-bit default
- `promotion_precision_ppm=600`

Result:

- **69.0853%**

## Improvement versus the uploaded target JSONs

Using the uploaded target values as the comparison anchor:

- Uploaded prefix target: **40.9975%**
- Uploaded drift target: **41.5350%**
- Uploaded probe target: **68.6121%**

The best v8 profiles improve over those targets by:

- **Prefix:** +0.7600 pp
- **Drift:** +0.6825 pp
- **Probe:** +0.4733 pp

## Improvement versus the best v7 results from the prior iteration

Using the best v7 results previously packaged in this conversation:

- v7 prefix best: **41.4650%**
- v7 drift best: **41.9180%**
- v7 probe best: **69.0180%**

The best v8 profiles improve by:

- **Prefix:** +0.2925 pp
- **Drift:** +0.2995 pp
- **Probe:** +0.0673 pp

## Interpretation

The strong v8 pattern is now clear:

1. the runtime still prefers a **compact single-region end state** on these target protocols,
2. bridge memories remain effectively unused here,
3. **carry-memory budget** is a real lever for unified improvement,
4. disabling long-term memory helps the short 40k prefix/drift targets,
5. but keeping long-term memory is still valuable for the longer hard-to-easy probe.

So the current best interpretation is not “more regions” or “more bridges.” It is **better operating-point control over a compact elastic learner**.

## Recommended v8 operating points

If one profile must be used everywhere:

- **Use the unified 6-bit stress profile** with `max_carry_memories=48`.

If protocol-specific tuning is allowed:

- **Prefix:** 5-bit with `enable_long_term=false`
- **Drift:** 5-bit with `enable_long_term=false`
- **Probe:** 6-bit with `promotion_precision_ppm=600`

## Files added for v8

- `scripts/run_v8_stress.sh`
- `scripts/search_v8_profiles.py`
- `SBAN_v8_REPORT.md`

## Caveat

This is a real empirical improvement pass, but it is still a **stress-tuned research artifact**, not proof that SBAN has reached its final architecture ceiling. The best improvements here come from better operating profiles and runtime control, not from a dramatic new region/bridge breakthrough.
