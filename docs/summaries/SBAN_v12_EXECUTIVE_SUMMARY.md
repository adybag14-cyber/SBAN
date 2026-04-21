# SBAN v12 Executive Summary

## Project name

**SBAN v12 - long-run hardening and interactive demo release**

## Project goal

Carry SBAN past the earlier short-suite tuning loop and make it look more like a **real working experimental system** by doing three things at once:

- preserve the best compact elastic short-suite operating point,
- validate a much longer stream run with a hardened profile,
- and prove that SBAN can emit short replies to simple requests through a real model-driven demo path.

## Current status

SBAN v12 is a working Zig release that:

- builds reproducibly from the uploaded Zig tarball,
- ships with a compact short-suite profile that matches the strongest v11 maintained-suite operating point,
- adds a **250k-prediction** long-run benchmark and a stronger long-run profile than the compact release default,
- and includes a `chat-demo` command backed by an actual SBAN byte-generation loop.

## Main empirical findings

### Maintained short target suite

Unified compact profile:

- Prefix: **41.8450%**
- Drift: **42.1950%**
- Probe: **69.2612%**

Best specialized profile in this release layer:

- Drift: **42.3625%**

### Long-run stress result

On the 250k contiguous prefix run:

- compact elastic profile: **39.7248%**
- hardened fixed-capacity long-term profile: **39.9212%**
- order-2 baseline: **40.2228%**

The hardened profile is better than the compact release profile by **+0.1964 pp**, but it does not yet beat order-2 on that longer horizon.

### Demo response result

Bundled smoke-demo for `hello are you ok`:

```text
prompt=hello are you ok
response=I am here and ready.
```

## What changed in the architecture

1. **Carry-memory persistence scoring** helps reduce needless carry churn.
2. **Saturation-aware birth controls** provide a stronger anti-clutter mechanism for future workloads.
3. **SBAN-driven response generation** is now exposed as a real command-line demo path.
4. **Long-run profile separation** becomes explicit: the short-suite winner and the long-run winner are no longer treated as the same operating point.

## What the current system demonstrates

1. **Real reproducible execution** with the uploaded Zig binary.
2. **Stable short-suite performance** at the v11 compact level.
3. **Longer-horizon stress handling** with an operating point better suited to long exposure than the compact short-suite profile.
4. **Simple reply generation** through an SBAN-driven autoregressive demo command.

## Important limitations

1. v12 does **not materially improve the maintained short suite over v11**.
2. The best long-run profile is still below the order-2 baseline.
3. The reply path is a real runnable demo, but not a full conversational model.
4. Bridge-heavy regional structure is still not the dominant win condition.
5. Long-term memory remains workload-sensitive and is not yet the best short-suite choice.

## Highest-value next steps

### Near term

- Build a larger dialogue seed and evaluate reply quality beyond smoke tests.
- Add checkpoint/resume support for long runs.
- Tune long-term quality gates specifically for long contiguous streams.

### Mid term

- Separate deployment presets into short-horizon, long-horizon, and interactive profiles.
- Add more formal real-world tasks beyond byte benchmarks, such as small command-response corpora and structured streaming logs.
- Revisit regional hierarchy only after longer workloads show that the extra structure is clearly paying for itself.

## Bottom line

SBAN v12 is best understood as a **hardening release**. It keeps the strongest compact elastic short-suite operating point alive, adds a longer-run profile that works better on sustained exposure, and proves that the runtime can now emit simple replies through a real SBAN-driven demo path. It is more runnable and more usable than the earlier line, but it is not yet the final architecture ceiling of SBAN.
