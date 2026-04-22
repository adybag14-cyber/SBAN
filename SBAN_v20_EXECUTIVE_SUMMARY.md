# SBAN v20 Executive Summary

## Project name

**SBAN v20 - stable engine-health release, continuing-session chat, and stronger practical usability**

## What this release accomplishes

SBAN v20 moves the project forward in five concrete ways:

- it keeps the packaged numeric engine-health suite near the v19 baseline,
- it adds continuing-session chat through `session_path`,
- it adds lightweight symbolic recall and arithmetic handling,
- it adds a scripted multi-turn session evaluation path,
- and it upgrades the newcomer demo so new users can keep chatting without restarting from scratch.

## Main measured results

### Numeric engine-health suite

- Prefix: **99.6350%** vs v19 **99.6350%** (+0.0000 pp)
- Drift: **99.5400%** vs v19 **99.5400%** (+0.0000 pp)
- Probe: **99.9000%** vs v19 **99.9000%** (+0.0000 pp)
- 250k long run: **99.4076%** vs v19 **99.4076%** (+0.0000 pp)
- 1M long run: **99.4344%** vs v19 **99.4344%** (+0.0000 pp)

### Chat and session evaluation

- Hybrid prompt set: **53 / 53** non-empty with **48** anchored and **5** symbolic
- Free prompt set: **53 / 53** non-empty with **48** retrieved and **5** symbolic
- Multi-turn session eval: **6 / 6** expectation checks passed

## What changed technically

1. Added transcript-backed continuing sessions through `chat-demo ... session_path=...`.
2. Added lightweight symbolic helpers for name recall, arithmetic, and newcomer help prompts.
3. Added `chat-session-eval` for honest multi-turn evaluation.
4. Updated the demo packaging and starter scripts to preserve one session across turns.
5. Updated the SBAN research skill and release references for future continuation work.

## Best interpretation

V20 is the usability release. It preserves the strong numeric runtime core from v19 while making the architecture easier for new users to talk to, test, and understand.

## Known limitations

- The numeric release still depends on self-seeded transductive benchmarking.
- The symbolic helpers are intentionally narrow.
- The session model is transcript-backed, not a dedicated long-lived state service.
- Broader held-out evaluation remains necessary for stronger intelligence claims.
