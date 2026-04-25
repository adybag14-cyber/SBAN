# SBAN v34 Executive Summary

SBAN v34 is the runtime-prewarm, powerchat, and Zig-coding follow-up after v33. The packaged numeric suite still ships on the safe single-thread CPU path and keeps the stable CPU profile while the user-facing runtime gains a default generated prewarm pack, larger-vocabulary probe, safer session persistence, safe huge-math behavior, and stricter release checks.

Measured release outcomes:

- Prefix: 99.6650%
- Drift: 99.5675%
- Probe: 99.9112%
- 250k: 99.4632%
- 1M: 99.5334%
- 10M: 78.3230%
- 20M guardrail: 78.4756%
- Hybrid chat eval: 30/30 non-empty with 1 uncertain
- Free chat eval: 30/30 non-empty with 0 uncertain
- Main session eval: 30/30 passed
- Open-chat session eval: 30/30 passed
- Broad free-chat battery: 30/30 passed
- Generated knowledge eval: 30/30 passed
- Runtime prewarm pairs: 402
- 65536-vocab probe collisions: 232 vs 5416 at 256 buckets

Product outcome:

- default v34 runtime prewarm pack shipped
- compatibility v34 seed, open-seed, and generated knowledge files shipped
- deterministic and generated coverage widened for safe huge math, linear equations, translation, summarization, Zig coding, JSON, science, geography, literature, planning, task triage, and source-boundary prompts
- session persistence now rejects likely secrets, caps loaded session bytes, caps retained facts/turns, and frees encoded save fields
- bundle inventory, artifact paths, starter files, CUDA commands, and hardware prompts answer operationally and correctly
- broader free chat now covers planning, writing, brainstorming, support prompts, generated general knowledge, practical Zig snippets, and Zig upstream file-location questions directly
- unsupported live-current or unindexed source-location prompts still return honest boundaries

Backend outcome:

- Retrieval CUDA speedup vs CPU: not measured
- Retrieval `cpu_mt` speedup vs CPU: 0.2276x
- Numeric CUDA speedup vs CPU at 250k: not measured
- Numeric CUDA speedup vs CPU at 1M: not measured
- Numeric CUDA probe: configured `cuda`, used `skipped`, device `unknown`

Release stance:

- keep `numeric_backend=cpu` and `score_threads=1` as the packaged default until accelerated numeric runs prove a dependable end-to-end win
- ship free mode with the generated runtime prewarm pack as the default conversational product surface
- treat v34 as a broader offline/runtime-updatable assistant, not as a live-current web oracle
- report the carried-forward 20M guardrail transparently after local and GitHub-hosted memory pressure, and skip 100M claims unless a completed JSON artifact actually exists
