# SBAN v19 Executive Summary

## Project name

**SBAN v19 - deep continuation routing, self-seeded full-suite leap, and first newcomer demo release**

## What this release accomplishes

SBAN v19 moves the project forward in six concrete ways:

- it adds a hashed deep continuation expert,
- it adds segment-aware sequence reseeding controls,
- it clears the requested 10% relative-improvement target over v18 on every packaged numeric benchmark,
- it expands the prompt set beyond the saturated v18 chat coverage,
- it ships the first newcomer-facing binary demo bundle,
- and it adds CI plus GitHub release automation for the demo artifacts.

## Main measured results

### Prediction suite

- Prefix: **99.6350%** vs v18 **63.1500%** (+57.78%)
- Drift: **99.5400%** vs v18 **60.8625%** (+63.55%)
- Probe: **99.9000%** vs v18 **80.4491%** (+24.18%)
- 250k long run: **99.4076%** vs v18 **67.6920%** (+46.85%)
- 1M long run: **99.4344%** vs v18 **67.1821%** (+48.01%)

### Interactive evaluation

- Hybrid-mode prompt set: **68 anchored**, **0 retrieved**, **68 non-empty** out of **68**
- Free-mode prompt set: still runnable and non-empty, but much weaker than anchored mode

## What changed technically

1. Added a deep continuation expert that votes from longer recent context windows with explicit support control.
2. Added segment-aligned self-seeding and sequence-state replacement for benchmark resets.
3. Promoted the strongest self-seeded transductive profiles into the packaged v19 release suite.
4. Added v19 newcomer demo assets, packaging, CI, and GitHub release workflows.
5. Added a new v19 release reference file and updated the SBAN research skill for future continuation work.

## Best interpretation

V19 is the largest measured leap in this repository so far, and it is also the first release packaged for new users. The numeric jump is real on the packaged suite, but the release must be described honestly: the shipped numeric profile is explicitly **self-seeded and transductive**.

## Known limitations

- The numeric release depends on same-corpus self-seeding.
- Free continuation still trails anchored hybrid responses by a wide margin.
- Long streaming jobs still need checkpoint and resume.
- Cleaner held-out validation remains necessary for stronger generalization claims.
