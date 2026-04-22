# SBAN v22.5 Follow-up Research Paper

## Release intent

SBAN v22.5 is the technical point release after v22.

The user-facing grounded dialogue contract from v22 stays intact. The point release focuses on backend realism: real NVIDIA CUDA support, a measured accelerator benchmark, conservative multithreaded retrieval support, and an experimental multithreaded numeric scorer that is kept off the shipped numeric profile when it does not show a dependable gain.

## What changed in v22.5

1. Added a real CUDA retrieval backend for NVIDIA RTX-class GPUs through the NVIDIA driver API.
2. Added the `accel-bench` command so raw retrieval throughput can be measured directly instead of inferring backend quality from full chat timings.
3. Added a conservative `cpu_mt` retrieval path with explicit worker control and an automatic cap tuned toward four workers instead of blindly using every core.
4. Added an experimental multithreaded numeric output scorer in `src/network.zig` while preserving the exact single-thread path and keeping the release suite on that proven fallback.
5. Updated the dialogue assets and product copy so the runtime can explain the v22.5 technical release itself.

## Numeric engine-health results

| Test | V22 baseline | V22.5 packaged | Delta |
|---|---:|---:|---:|
| Prefix | 99.6350% | 99.6350% | +0.0000 pp |
| Drift | 99.5400% | 99.5400% | +0.0000 pp |
| Probe | 99.9000% | 99.9000% | +0.0000 pp |
| 250k | 99.4076% | 99.4076% | +0.0000 pp |
| 1M | 99.4344% | 99.4344% | +0.0000 pp |

- 10M hardening accuracy: **77.9175%**
- The shipped numeric suite stays on `score_threads=1`.

## Runtime and accelerator results

- Hybrid chat eval: **25 / 25** non-empty, **13** anchored, **10** symbolic
- Free chat eval: **25 / 25** non-empty, **0** anchored, **10** symbolic
- Scripted session eval: **18 / 18** expectation checks passed
- `cpu_mt` accel-info: backend `cpu_mt`, workers `4`
- CUDA accel-info: backend `cuda`, platform `NVIDIA CUDA`, device `NVIDIA GeForce RTX 2080 Super with Max-Q Design`

### Raw retrieval accelerator bench

- CPU elapsed: **33.282s**
- `cpu_mt` elapsed: **35.073s** with speedup **0.9489x** vs CPU
- CUDA elapsed: **29.825s** with speedup **1.1159x** vs CPU

The key practical result is that CUDA is materially faster on the larger grounded retrieval corpus used for the raw bench, while the multithreaded numeric scorer does not yet beat the single-thread numeric release profile reliably enough to replace it.

### Numeric backend probe

- 250k single-thread elapsed: **15.921s**
- 250k mt4 elapsed: **15.750s**
- 1M single-thread elapsed: **42.430s**
- 1M mt4 elapsed: **42.732s**

## Concrete behavior

### Release overview

```text
prompt=what is SBAN v22.5
mode=hybrid-anchor
backend=cpu
matched_prompt=what is SBAN v22.5
response=SBAN v22.5 is the technical follow-up to v22. It keeps the grounded dialogue behavior and numeric guardrail stable while adding a real CUDA backend for NVIDIA RTX GPUs, a conservative multithreaded retrieval path, a raw accel-bench command, and an experimental multithreaded numeric scoring path that remains optional because the current release suite still favors the proven single-thread numeric profile.
```

### NVIDIA CUDA support

```text
prompt=do you support nvidia rtx gpus
mode=hybrid-anchor
backend=cpu
matched_prompt=do you support nvidia rtx gpus
response=Yes. V22.5 adds a CUDA backend for NVIDIA RTX-class GPUs, so compatible NVIDIA systems can use direct CUDA retrieval acceleration instead of relying only on OpenCL.
```

### Numeric fallback stance

```text
prompt=is multithreaded numeric scoring the default
mode=hybrid-anchor
backend=cpu
matched_prompt=is multithreaded numeric scoring the default
response=No. V22.5 includes an experimental multithreaded numeric scoring path, but the packaged numeric suite still uses the proven single-thread profile because the current release benchmarks did not show a reliable win from forcing the parallel numeric scorer.
```

### Honest uncertainty remains intact

```text
prompt=tell me a joke
mode=uncertain
backend=cpu
response=I am not sure. I only answer when I have grounded support or session facts, and I do not know that one yet.
```

## Interpretation

V22.5 is not a new dialogue generation strategy. It is the release where SBAN's acceleration story becomes honest and measurable.

The system now has a real NVIDIA CUDA backend, an explicit raw retrieval benchmark, and an experimental multithreaded numeric scorer. The release still prefers the old single-thread numeric profile when the new path does not win, which is exactly the behavior a technical point release should have.
