# SBAN v6 report

## Goal
Push beyond the fresh SBAN v5 fork and keep chasing the strong elastic behavior described in the uploaded v4 materials, especially the hard-to-easy probe where the model should grow under pressure and then shrink aggressively when the stream becomes simple.

## What changed in v6

1. **Entropy-aware shrink controller**
   - Added `interval_confident` tracking.
   - When an interval is both low-surprise and highly confident, SBAN v6 shrinks faster with a larger collapse step instead of only using the small generic shrink step.

2. **Stricter bridge admission**
   - Removed the permissive fallback that could create bridges on generic surprise alone.
   - New bridges now need a clearer secondary-region error advantage, or a stronger diversity-plus-misprediction condition.

3. **Bridge retirement pressure**
   - Bridge memories lose some utility and reputation when the supposed secondary region stops carrying higher error burden than the primary region.

4. **Lower bridge carry bias**
   - Carry-memory selection now gives bridge memories a smaller bonus so they do not dominate transient state just for being bridges.

5. **New evaluation command**
   - Added `eval-variant` so a single SBAN variant can be run quickly without paying the full ablation cost every iteration.

## v6 results on the full uploaded protocols (single-variant runs)

| Protocol | v6 default | v6 fixed capacity | Delta (default - fixed) |
|---|---:|---:|---:|
| Prefix 10k x 4 | 41.370% | 41.042% | +0.328 pp |
| Drift 10k x 4 | 41.862% | 41.780% | +0.082 pp |
| Elastic probe 29k x 4 | 68.738% | 68.316% | +0.422 pp |

## Elastic behavior reached by v6 default

- **Prefix:** target 8192, short memories 3917, grows 12, shrinks 0, final regions 1
- **Drift:** target 8192, short memories 3592, grows 12, shrinks 0, final regions 1
- **Probe:** target 256, short memories 192, grows 12, shrinks 22, final regions 1

## Interpretation

- v6 keeps the **positive elasticity effect** against its own fixed-capacity counterpart on all three reproduced protocols.
- The strongest v6 behavior is on the hard-to-easy probe: it ends at **target 256** with only **192 short memories**, while the fixed-capacity comparator stays stuck at **4096**.
- Bridge births were driven down sharply: prefix 4, drift 0, probe 4.
- This is **not yet an exact reproduction** of the uploaded `*_after.json` state, because the structural trajectory is different even where the accuracy is similar.

## Key output files

- `docs/results/variant_prefix_v6_default.json`
- `docs/results/variant_drift_v6_default.json`
- `docs/results/variant_probe_v6_default.json`
- `docs/results/variant_prefix_v6_fixed.json`
- `docs/results/variant_drift_v6_fixed.json`
- `docs/results/variant_probe_v6_fixed.json`
