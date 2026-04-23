# SBAN v25 Executive Summary

SBAN v25 is the conversational product release after v24. The packaged numeric suite stays on the original single-thread CPU baseline, the measured backend stack remains intact, and the major release work is on the user-facing chat surface.

Measured release outcomes:

- Prefix: 99.6350%
- Drift: 99.5400%
- Probe: 99.9000%
- 250k: 99.4076%
- 1M: 99.4344%
- 10M: 77.9175%
- Hybrid chat eval: 67/67 non-empty with 20 uncertain
- Free chat eval: 67/67 non-empty with 1 uncertain
- Main session eval: 29/29 passed
- Open-chat session eval: 30/30 passed

Product outcome:

- real v25 grounded seed shipped
- separate curated and dataset-enriched v25 open-chat seed shipped
- bundle inventory, artifact paths, starter files, CUDA commands, and hardware prompts answer operationally and correctly
- broader free chat now covers planning, writing, brainstorming, stress support, casual preference boundaries, and session-memory follow-ups directly
- unsupported factual prompts still return honest uncertainty

Backend outcome:

- Retrieval CUDA speedup vs CPU: 7.0946x
- Retrieval `cpu_mt` speedup vs CPU: 1.0341x
- Numeric CUDA speedup vs CPU at 250k: 0.2097x
- Numeric CUDA speedup vs CPU at 1M: 0.1675x
- Numeric CUDA probe: configured `cuda`, used `cuda`, device `NVIDIA GeForce RTX 2080 Super with Max-Q Design`

Release stance:

- keep `numeric_backend=cpu` and `score_threads=1` as the packaged default until accelerated numeric runs prove a dependable end-to-end win
- ship free mode with both the grounded and open-chat v25 seeds as the default conversational product surface
- treat v25 as a calmer and broader assistant, not as a claim of broad general knowledge
