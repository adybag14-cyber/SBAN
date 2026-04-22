# SBAN v23 Executive Summary

SBAN v23 is the conversational repair release after v22.5. The numeric engine-health suite stays stable, CUDA support remains healthy on the local NVIDIA system, and the user-facing runtime now ships with a real v23 chat seed plus stronger operational, retrieval, memory, and free-chat behavior.

Measured release outcomes:

- Prefix: 99.6350%
- Drift: 99.5400%
- Probe: 99.9000%
- 250k: 99.4076%
- 1M: 99.4344%
- 10M: 77.9175%
- Hybrid chat eval: 42/42 non-empty
- Free chat eval: 42/42 non-empty
- Session eval: 21/21 passed

Product outcome:

- starter files, artifact paths, CUDA commands, backend comparisons, RTX support questions, and roadmap prompts now have grounded v23 answers
- natural fact memory now handles phrases such as `i am from london` and `i work in the sbx lab`
- free chat can answer greetings, identity, thanks, favorite-color style small talk, and jokes without collapsing into stale release blurbs
- noise prompts still decline honestly

Acceleration outcome:

- CUDA raw retrieval bench speedup vs CPU: 6.4667x
- CPU_MT raw retrieval bench speedup vs CPU: 1.0106x
- shipped numeric suite remains on single-thread fallback because the multithreaded numeric path still has not shown a dependable release-profile win
