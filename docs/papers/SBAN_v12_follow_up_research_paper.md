# SBAN v12 Report

## Release intent

SBAN v12 pushes the post-v11 line in a different direction from the earlier short-suite-only tuning loop. The release work focused on three concrete goals:

1. **hold the compact elastic operating point** on the maintained short target suite,
2. **harden the system for a much longer stream exposure**, and
3. **prove the runtime can answer simple requests** through a real SBAN-driven response path.

## What changed in v12

### 1. Response-capable demo path

The runtime now exposes a `chat-demo` command. It trains a byte-level SBAN instance on a small dialogue seed corpus, conditions on a quoted user prompt, and autoregressively generates a short reply using the model's own predicted next bytes. This is still a small demo-scale interface, but it is an actual SBAN response loop rather than an external stub.

### 2. Carry-memory persistence hook

Carry-memory refresh can now reward memories that survived the previous carry set. The goal is to reduce unnecessary churn and make the runtime less jittery under longer stream exposure.

### 3. Saturation-aware birth controls

The architecture now includes saturation-aware birth controls that can raise the birth threshold and parent requirement when short-memory occupancy is already high. On the maintained short suite, the best v12 release profiles disable this extra guard, but the mechanism is now present for harder anti-clutter workloads.

### 4. Long-run hardened operating profile

The v12 release includes a dedicated **250k-prediction contiguous prefix stress run**. The strongest long-run profile uses a fixed-capacity, long-term-enabled operating point rather than the short-suite compact elastic default.

## Main v12 results

### Maintained short target suite

- Unified compact profile:
  - Prefix: **41.8450%**
  - Drift: **42.1950%**
  - Probe: **69.2612%**
- Best drift profile:
  - Drift: **42.3625%**

### Unified compact profile versus matched fixed-capacity comparator

- Prefix delta: **+0.5125 pp**
- Drift delta: **+0.0225 pp**
- Probe delta: **+0.2431 pp**

### Long-run hardening result

On a **250k-prediction contiguous prefix run**:

- Compact elastic profile: **39.7248%**
- Hardened long-run profile: **39.9212%**
- Order-2 baseline in the same result JSON: **40.2228%**

That means the hardened long-run profile improves on the compact elastic release profile by **+0.1964 pp**, but remains **-0.3016 pp** behind the order-2 baseline on that longer horizon.

### Demo reply path

Bundled chat-demo output for the target prompt:

```text
prompt=hello are you ok
response=I am here and ready.
```

## Operational interpretation

The strongest short-suite profile in v12 remains the same compact elastic operating family that already worked in v11. The real advance in v12 is therefore **functional hardening rather than a large headline gain on the short suite**:

- the build path remains reproducible through the uploaded Zig tarball,
- the repo now ships with a real SBAN-driven reply mode,
- and the release includes a longer-horizon operating point that is better than the compact short-suite profile on the 250k run.

## Known limitations

1. The maintained short target suite does **not materially beat v11**. v12 mainly preserves that level while adding long-run and interactive capability.
2. The hardened 250k long-run profile still stays below the order-2 baseline.
3. The chat demo is proof of runnable response behavior, not proof of a production-grade assistant.
4. Bridge-heavy multi-region behavior is still not the main source of gain.
5. The runtime still reports vote accuracy, not calibrated probabilities.

## Recommended next work after v12

1. Build a second dialogue corpus and measure response quality more formally instead of only shipping a smoke-demo path.
2. Search longer-horizon profiles more aggressively, especially long-term quality gates and memory-budget schedules.
3. Add checkpoint export and resume so long-run experiments can be staged rather than only run from scratch.
4. Revisit saturation-aware birth controls on workloads where short-memory clutter is more damaging than on the maintained short suite.
