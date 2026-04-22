# SBAN v23.5 Executive Summary

SBAN v23.5 is the technical backend upgrade after v23. The packaged numeric suite stays on the original single-thread CPU baseline, the v23 conversational runtime remains stable, and CUDA now reaches both the dialogue retrieval path and the numeric output-scoring path.

Measured release outcomes:

- Prefix: 99.6350%
- Drift: 99.5400%
- Probe: 99.9000%
- 250k: 99.4076%
- 1M: 99.4344%
- 10M: 77.9175%
- Hybrid chat eval: 47/47 non-empty
- Free chat eval: 47/47 non-empty
- Session eval: 23/23 passed

Backend outcome:

- Retrieval CUDA speedup vs CPU: 6.2352x
- Retrieval `cpu_mt` speedup vs CPU: 0.9245x
- Numeric CUDA speedup vs CPU at 250k: 0.3714x
- Numeric CUDA speedup vs CPU at 1M: 0.2875x
- Numeric CUDA probe: configured `cuda`, used `cuda`, device `NVIDIA GeForce RTX 2080 Super with Max-Q Design`

Release stance:

- keep `numeric_backend=cpu` and `score_threads=1` as the packaged default until accelerated numeric runs prove a dependable end-to-end win
- keep the v23 grounded chat behavior and versioned assets intact for end users
- expose `numeric-accel-info` plus measured CPU versus `cpu_mt` versus CUDA timing so future tuning can be guided by data rather than guesswork
