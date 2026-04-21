# SBAN v17 Executive Summary

## Project name

**SBAN v17 - sparse order-three routing, stronger release profile, and full-suite benchmark jump**

## What this release accomplishes

SBAN v17 moves the project forward in four concrete ways:

- it adds a sparse order-three sequence expert to the runtime,
- it adds support and evidence controls for expert routing plus local-boundary expert resets,
- it finds a materially stronger packaged release profile,
- and it clears the requested 5% relative-improvement target on every packaged numeric benchmark.

## Main measured results

### Prediction suite

- Prefix: **51.7700%** vs v16 **45.1625%** (+14.63%)
- Drift: **50.0375%** vs v16 **44.8500%** (+11.57%)
- Probe: **75.1500%** vs v16 **71.3767%** (+5.29%)
- 250k long run: **53.4588%** vs v16 **46.1572%** (+15.82%)
- 1M long run: **51.3550%** vs v16 **43.2688%** (+18.69%)

### Interactive evaluation

- Hybrid-mode prompt set: **42 anchored**, **0 retrieved**, **42 non-empty** out of **42**
- Free-mode prompt set: still runnable and non-empty, but much weaker than anchored mode

## What changed technically

1. Added a **sparse order-three expert** over observed contexts.
2. Added **support and evidence priors** for expert blending plus **local expert resets** at drift boundaries.
3. Found a stronger v17 release profile with long-term memory enabled and deeper propagation.
4. Expanded the v17 prompt set to **42** anchored prompts for hybrid chat evaluation.
5. Added new cross-platform v17 release and deliverable scripts.

## Best interpretation

V17 is not just a stability release. It is the first SBAN generation in this repo that breaks the prior short-suite ceiling and the long-run ceiling at the same time with one packaged release profile.

## Known limitations

- Free continuation still trails anchored hybrid responses by a wide margin.
- Multi-million jobs still need checkpoint and resume support.
- Broader held-out corpus validation should be added next.
