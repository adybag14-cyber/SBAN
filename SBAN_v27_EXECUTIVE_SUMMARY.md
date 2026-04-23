# SBAN v27 Executive Summary

SBAN v27 is the product and free-chat follow-up after v26. The packaged numeric suite still ships on the safe single-thread CPU path, but the v27 release profile materially improves that CPU baseline while the user-facing chat surface gets broader and less brittle.

Measured release outcomes:

- Prefix: 99.6650%
- Drift: 99.5675%
- Probe: 99.9112%
- 250k: 99.4632%
- 1M: 99.5334%
- 10M: 78.3230%
- 20M: 78.4756%
- Hybrid chat eval: 72/72 non-empty with 37 uncertain
- Free chat eval: 72/72 non-empty with 2 uncertain
- Main session eval: 43/43 passed
- Open-chat session eval: 66/66 passed
- Broad free-chat battery: 63/63 passed

Product outcome:

- real v27 grounded seed shipped
- separate curated and dataset-enriched v27 open-chat seed shipped
- deterministic coverage widened for common coding, explanation, rewrite, planning, and light-knowledge prompts
- bundle inventory, artifact paths, starter files, CUDA commands, and hardware prompts answer operationally and correctly
- broader free chat now covers planning, writing, brainstorming, stress support, casual preference boundaries, richer session-memory follow-ups, and Zig upstream file-location questions directly
- unsupported factual prompts still return honest uncertainty

Backend outcome:

- Retrieval CUDA speedup vs CPU: 7.0590x
- Retrieval `cpu_mt` speedup vs CPU: 1.0297x
- Numeric CUDA speedup vs CPU at 250k: 0.2883x
- Numeric CUDA speedup vs CPU at 1M: 0.1766x
- Numeric CUDA probe: configured `cuda`, used `cuda`, device `NVIDIA GeForce RTX 2080 Super with Max-Q Design`

Release stance:

- keep `numeric_backend=cpu` and `score_threads=1` as the packaged default until accelerated numeric runs prove a dependable end-to-end win
- ship free mode with both the grounded and open-chat v27 seeds as the default conversational product surface
- treat v27 as a calmer and broader assistant, not as a claim of broad general knowledge
- report the new 20M hardening extension, and skip 100M claims unless a completed JSON artifact actually exists
