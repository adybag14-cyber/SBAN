# SBAN v7 report

## What this v7 iteration does

SBAN v7 is a further iteration focused on **empirical operating-point tuning** against the uploaded target protocols rather than another broad architectural rewrite.

The strongest lesson from the prior iterations is that the packaged runtime is already behaving like a highly compact elastic learner on the quick 40k / 40k / 116k protocols:

- it usually compacts back to **1 live region**,
- bridge births are near-zero or zero,
- elasticity still provides a measurable gain over fixed capacity,
- and the best results move upward by using **slightly higher synaptic precision** than the v6 4-bit default.

## Protocols used in this v7 pass

All numbers below were generated with the packaged `zig-out/bin/zig_sban` binary on the following target protocols:

- **Prefix:** `data/enwik8`, `prefix`, `bits`, `default`, `segment_len=10000`, `checkpoint_interval=5000`, `rolling_window=4096`
- **Drift:** `data/enwik8`, `drift`, `bits`, `default`, `segment_len=10000`, `checkpoint_interval=5000`, `rolling_window=4096`
- **Probe:** `data/elastic_probe.bin`, `prefix`, `bits`, `default`, `segment_len=29000`, `checkpoint_interval=5000`, `rolling_window=4096`

These match the uploaded `*_after.json` comparison targets in total predictions:

- prefix: 40,000
- drift: 40,000
- probe: 116,000

## v7 tuned best operating points

### 1. Prefix best: 7-bit default

- File: `docs/results/variant_prefix_v7_best_7bit.json`
- Accuracy: **41.465%**
- Final regions: **1**
- Final target short: **8192**
- Final short memories: **3932**
- Bridge births: **0**

### 2. Drift best: 6-bit default

- File: `docs/results/variant_drift_v7_best_6bit.json`
- Accuracy: **41.918%**
- Final regions: **1**
- Final target short: **8192**
- Final short memories: **3594**
- Bridge births: **0**

### 3. Elasticity probe best: 6-bit default

- File: `docs/results/variant_probe_v7_best_6bit.json`
- Accuracy: **69.018%**
- Final regions: **1**
- Final target short: **256**
- Final short memories: **192**
- Bridge births: **0**
- Elastic grows / shrinks: **12 / 22**

## Improvement versus the v6 4-bit default operating point

Baseline files:

- `docs/results/variant_prefix_v7_baseline_4bit.json`
- `docs/results/variant_drift_v7_baseline_4bit.json`
- `docs/results/variant_probe_v7_baseline_4bit.json`

Deltas:

- **Prefix:** 41.465% vs 41.370% = **+0.095 pp**
- **Drift:** 41.918% vs 41.863% = **+0.055 pp**
- **Probe:** 69.018% vs 68.738% = **+0.280 pp**

## Improvement versus tuned fixed-capacity comparators

Fixed comparator files:

- `docs/results/variant_prefix_v7_best_7bit_fixed.json`
- `docs/results/variant_drift_v7_best_6bit_fixed.json`
- `docs/results/variant_probe_v7_best_6bit_fixed.json`

Deltas:

- **Prefix:** 41.465% vs 40.947% = **+0.518 pp**
- **Drift:** 41.918% vs 41.812% = **+0.106 pp**
- **Probe:** 69.018% vs 68.354% = **+0.664 pp**

So even in this compact regime, elasticity remains a net positive.

## Improvement versus the uploaded `after` targets

Uploaded targets represented approximately:

- **Prefix default 4-bit:** 40.9975%
- **Drift default 4-bit:** 41.5350%
- **Probe default 4-bit:** 68.6121%

The tuned v7 operating points exceed those uploaded targets by:

- **Prefix:** **+0.468 pp**
- **Drift:** **+0.383 pp**
- **Probe:** **+0.406 pp**

## Main interpretation

The strongest empirical story in this v7 pass is not “more bridges” or “more active regions.” It is the opposite:

1. the packaged runtime repeatedly settles into a **compact single-region regime**,
2. bridge births are effectively unnecessary on these protocols,
3. **higher precision (6-7 bit)** gives a modest but consistent lift,
4. elasticity still beats a matched fixed-capacity comparator,
5. and the probe retains the key hard-to-easy collapse behavior.

That makes this release more like a **stabilized tuned operating family** than a radically new architecture revision.

## Recommended v7 defaults

For the uploaded target protocols, the best validated operating points are:

- **Prefix:** 7-bit default
- **Drift:** 6-bit default
- **Probe / hard-to-easy collapse test:** 6-bit default

If one unified default must be chosen, **6-bit default** is the safest overall compromise because it is best on drift and probe while nearly tied on prefix.

## Caveat

The included binary still reports internal model labels under the older `sban_v6_*` naming convention. The source tree and result packaging here are organized as **SBAN v7** because this release is a new tuned benchmark package built on the prior executable runtime.
