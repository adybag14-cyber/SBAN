# SBAN v28 Executive Summary

SBAN v28 is the stress-report repair and free-chat reliability follow-up after v27. The packaged numeric suite still ships on the safe single-thread CPU path and keeps the v27 numeric profile stable while the user-facing runtime, release identity, eval strictness, memory aliases, and backend reporting are tightened.

Measured release outcomes:

- Prefix: 99.6650%
- Drift: 99.5675%
- Probe: 99.9112%
- 250k: 99.4632%
- 1M: 99.5334%
- 10M: 78.3230%
- 20M guardrail: 78.4756%
- Hybrid chat eval: 86/86 non-empty with 43 uncertain
- Free chat eval: 86/86 non-empty with 2 uncertain
- Main session eval: 57/57 passed
- Open-chat session eval: 71/71 passed
- Broad free-chat battery: 73/73 passed

Product outcome:

- real v28 grounded seed shipped
- separate curated and dataset-enriched v28 open-chat seed shipped
- deterministic coverage widened for the reported exponent, rate word-problem, translation, summarization, coding, explanation, rewrite, planning, and light-knowledge prompts
- bundle inventory, artifact paths, starter files, CUDA commands, and hardware prompts answer operationally and correctly
- broader free chat now covers planning, writing, brainstorming, stress support, casual preference boundaries, richer session-memory follow-ups, and Zig upstream file-location questions directly
- unsupported factual prompts still return honest uncertainty

Backend outcome:

- Retrieval CUDA speedup vs CPU: not measured
- Retrieval `cpu_mt` speedup vs CPU: 0.9599x
- Numeric CUDA speedup vs CPU at 250k: not measured
- Numeric CUDA speedup vs CPU at 1M: not measured
- Numeric CUDA probe: configured `cuda`, used `skipped`, device `unknown`

Release stance:

- keep `numeric_backend=cpu` and `score_threads=1` as the packaged default until accelerated numeric runs prove a dependable end-to-end win
- ship free mode with both the grounded and open-chat v28 seeds as the default conversational product surface
- treat v28 as a calmer and broader assistant, not as a claim of broad general knowledge
- report the carried-forward 20M guardrail transparently, and skip 100M claims unless a completed JSON artifact actually exists
