# SBAN v22.5 Executive Summary

SBAN v22.5 is the technical point release after v22. It keeps the v22 grounded dialogue behavior and numeric engine-health baseline stable while adding a real CUDA retrieval backend for NVIDIA RTX GPUs, a raw accelerator benchmark command, conservative multithreaded retrieval support, and an experimental multithreaded numeric scorer.

Measured release outcomes:

- Prefix: 99.6350%
- Drift: 99.5400%
- Probe: 99.9000%
- 250k: 99.4076%
- 1M: 99.4344%
- 10M: 77.9175%
- Hybrid chat eval: 25/25 non-empty
- Session eval: 18/18 passed

Acceleration outcome:

- CUDA raw retrieval bench speedup vs CPU: 1.1159x
- CPU_MT raw retrieval bench speedup vs CPU: 0.9489x
- Shipped numeric suite remains on single-thread fallback because the multithreaded numeric path did not show a dependable win on the release profile.
