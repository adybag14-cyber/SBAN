# SBAN v21 Executive Summary

## Project name

**SBAN v21 - grounded dialogue, general session memory, safer persistence, and first CPU or GPU retrieval acceleration**

## What this release accomplishes

SBAN v21 turns the current chat surface into a calmer and more trustworthy runtime:

- unsupported prompts now return honest uncertainty instead of irrelevant canned blurbs,
- retrieval matching is stricter and avoids version-crossing mistakes,
- session memory stores general user facts such as names and favorite colors,
- arithmetic now handles negatives and decimals safely,
- session persistence uses a structured encoded format instead of raw transcript text,
- missing assets return friendly diagnostics,
- and retrieval can run on CPU or use an OpenCL-capable GPU when available.

## Main measured results

### Numeric engine-health suite

- Prefix: **99.6350%** vs v20 **99.6350%** (+0.0000 pp)
- Drift: **99.5400%** vs v20 **99.5400%** (+0.0000 pp)
- Probe: **99.9000%** vs v20 **99.9000%** (+0.0000 pp)
- 250k long run: **99.4076%** vs v20 **99.4076%** (+0.0000 pp)
- 1M long run: **99.4344%** vs v20 **99.4344%** (+0.0000 pp)

### Chat and reliability evaluation

- Hybrid prompt set: **58 / 58** non-empty with **49** anchored, **6** symbolic, and **3** explicit uncertainty replies
- Free prompt set: **58 / 58** non-empty with **6** symbolic and **3** explicit uncertainty replies
- Multi-turn session eval: **9 / 9** expectation checks passed

### Local acceleration check

- backend: **gpu**
- platform: **NVIDIA CUDA**
- device: **NVIDIA GeForce RTX 2080 Super with Max-Q Design**


## What changed technically

1. Added `src/dialogue.zig` as the grounded dialogue runtime for matching, memory, math, persistence, and acceleration.
2. Added structured v21 session files with encoded fact and turn storage.
3. Added version-aware retrieval rejection and stronger uncertainty behavior.
4. Added an optional OpenCL retrieval backend with automatic CPU fallback.
5. Added versioned v21 prompt assets, scripted session evaluation, release scripts, and packaged demo bundles.

## Best interpretation

V21 is the trustworthiness release. It preserves the stabilized numeric core from v20 while making the runtime substantially safer and more useful for real conversational work.

## Known limitations

- The numeric benchmark story still needs careful release-method wording.
- The runtime is intentionally conservative on unsupported open-domain prompts.
- GPU acceleration currently targets retrieval scoring rather than the whole runtime.
- Session memory remains transcript-scoped rather than global.
