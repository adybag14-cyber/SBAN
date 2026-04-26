# SBAN v36 Executive Summary

SBAN v36 is the runtime-learning, limitation-repair, and Zig/Rust coding follow-up after v35. The packaged numeric suite still ships on the safe single-thread CPU path and keeps the stable CPU profile while the user-facing runtime gains a default generated prewarm pack, a generated learned reasoning corpus, larger-vocabulary probe, safer session persistence with forget/delete/no-store semantics, exact JSON slot preservation, simple quadratic solving, repaired word-problem arithmetic, and stricter release checks.

Measured release outcomes:

- Prefix: 99.6650%
- Drift: 99.5675%
- Probe: 99.9112%
- 250k: 99.4632%
- 1M: 99.5334%
- 10M: 78.3230%
- 20M guardrail: 78.4756%
- Hybrid chat eval: 17/17 non-empty with 0 uncertain
- Free chat eval: 17/17 non-empty with 0 uncertain
- Main session eval: 12/12 passed
- Open-chat session eval: 3/3 passed
- Broad free-chat battery: 4/4 passed
- Generated knowledge eval: 3/3 passed
- Learned reasoning eval: 3/3 passed
- v36 limitation-regression eval: 8/8 passed
- Runtime prewarm pairs: 55
- Learned corpus examples: 55 total, 40 online
- 65536-vocab probe collisions: 271 vs 5838 at 256 buckets

Product outcome:

- default v36 runtime prewarm pack shipped
- learned reasoning corpus from online dataset adapters shipped
- compatibility v36 seed, open-seed, and generated knowledge files shipped
- deterministic and generated coverage widened for learned syllogisms, arithmetic reasoning, simple quadratics, safe huge math, linear equations, translation, summarization, Zig/Rust coding, exact JSON, science, geography, literature, planning, task triage, and source-boundary prompts
- session persistence now rejects likely secrets, caps loaded session bytes, caps retained facts/turns, and frees encoded save fields
- bundle inventory, artifact paths, starter files, CUDA commands, and hardware prompts answer operationally and correctly
- broader free chat now covers planning, writing, brainstorming, support prompts, generated general knowledge, practical Zig/Rust snippets, and Zig upstream file-location questions directly
- unsupported live-current or unindexed source-location prompts still return honest boundaries

Backend outcome:

- Retrieval CUDA speedup vs CPU: not measured
- Retrieval `cpu_mt` speedup vs CPU: 0.2447x
- Numeric CUDA speedup vs CPU at 250k: not measured
- Numeric CUDA speedup vs CPU at 1M: not measured
- Numeric CUDA probe: configured `cuda`, used `skipped`, device `unknown`

Release stance:

- keep `numeric_backend=cpu` and `score_threads=1` as the packaged default until accelerated numeric runs prove a dependable end-to-end win
- ship free mode with the generated runtime prewarm pack and learned reasoning corpus as the default conversational product surface
- treat v36 as a broader offline/runtime-updatable assistant, not as a live-current web oracle
- report the carried-forward 20M guardrail transparently for hosted-compatible release runs, and skip 100M claims unless a completed JSON artifact actually exists
