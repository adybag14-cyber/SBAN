# SBAN v16 Executive Summary

## Project name

**SBAN v16 - regime-aware hybrid experts, long-horizon stress scaling, and broader working-model evaluation**

## What this release accomplishes

SBAN v16 moves the project forward in three concrete ways:

- it preserves the strong v15 short-suite behavior with a stable compact profile,
- it adds a new recent-context expert and shared expert mixing for long non-stationary streams,
- and it validates the system on the completed 250k line plus a broader working-model chat evaluation.

## Main measured results

### Compact short suite

- Prefix: **45.1625%**
- Drift: **44.8500%**
- Probe: **71.3767%**

Relative to v15, the compact short profile was held effectively flat:

- Prefix: **+0.0000 pp**
- Drift: **+0.0000 pp**
- Probe: **+0.0000 pp**

### Long-run stress


- 250k regime-aware compact: **46.1572%**
- 250k order-2 baseline: **40.2228%**
- delta vs v15 250k compact: **+0.4696 pp**
- 1M regime-aware compact: **43.2688%**
- 1M order-2 baseline: **38.2872%**


### Interactive evaluation

- Hybrid-mode prompt set: **36 anchored**, **0 retrieved**, **36 non-empty** out of **36**
- Free-mode prompt set: runnable, but still materially weaker than hybrid mode

## What changed technically

1. Added a **recent-context order-two expert** backed by a bounded sliding window.
2. Added stronger **shared expert-weight adaptation** to track which specialist is currently best.
3. Added broader **v16 seed and prompt coverage** plus related-prompt retrieval fallback.
4. Preserved a stable short-suite profile rather than forcing the new expert into every operating mode.
5. Added new v16 release and deliverable scripts.

## Best interpretation

SBAN v16 is a long-horizon and scalability improvement rather than a short-suite headline chase. The main completed measured win is the 250k long-run gain, while the short packaged profile stays strong and the reply path remains fully operational across a broader prompt set.

## Known limitations

- The recent expert helps longer streams more than the packaged short suite.
- Free generation remains much weaker than anchored hybrid responses.
- Multi-million debug runs are still expensive without checkpoint/resume.
- Bridge structure still is not the main source of the best gains.
