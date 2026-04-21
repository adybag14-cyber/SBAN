# SBAN v13 Executive Summary

## Project name

**SBAN v13 - very-long-run hardening and anchored interactive runtime release**

## Project goal

Push SBAN further toward a **real working experimental system** by doing three things at the same time:

- preserve the best compact elastic maintained-suite operating point,
- validate a much longer **1,000,000-prediction** stream exposure,
- and replace the weak free-form reply loop with a more coherent request-response subsystem.

## Current status

SBAN v13 is a working Zig release that:

- builds reproducibly from the uploaded Zig tarball,
- keeps the strongest compact maintained-suite profile alive,
- adds a dedicated **prompt-anchor dialogue subsystem** and multi-prompt chat evaluation,
- includes both **250k** and **1M** long-run stress results,
- and makes the runtime more usable as a real model demo while staying honest about its limits.

## Main empirical findings

### Maintained short target suite

Unified compact profile:

- Prefix: **41.8450%**
- Drift: **42.1950%**
- Probe: **69.2612%**

Best specialized result in this release layer:

- Drift: **42.3625%**

### Very-long-run stress results

250k prefix stress:

- compact elastic: **39.7860%**
- hardened long-run: **39.9212%**
- order-2 baseline: **40.2228%**

1M prefix stress:

- compact elastic: **32.6300%**
- hardened long-run: **32.7872%**
- order-2 baseline: **38.2872%**

The hardened profile beats the compact profile by **+0.1352 pp** on 250k and **+0.1572 pp** on 1M, but SBAN still remains well below order-2 on the 1M run.

### Interactive response results

Anchor-mode evaluation on the bundled prompt set:

- turns: **12**
- coherent anchored replies: **12 / 12**
- non-empty replies: **12 / 12**

The free-generation mode still collapses into repetitive fragments, while the anchored mode answers the full evaluation set coherently.

## What changed in the architecture

1. **Carry-quality scoring** now uses recent win-loss balance when refreshing carry memories.  
2. **Prompt-anchor dialogue matching** gives SBAN a more coherent interactive subsystem.  
3. **Multi-prompt chat evaluation** makes response quality testable instead of anecdotal.  
4. **1M-run stress harness** pushes the runtime much farther than the earlier 250k release.

## What the current system demonstrates

1. **Real reproducible execution** with the uploaded Zig binary.  
2. **Stable maintained-suite behavior** at the strong v12 level.  
3. **Very-long-run stress evidence** through a million-prediction release run.  
4. **Coherent short replies over a range of prompts** through a built-in anchored dialogue subsystem.

## Important limitations

1. v13 does **not materially improve the maintained short suite over v12**.  
2. The 1M long-run profile is still **far below** order-2.  
3. The interactive gain is **retrieval-assisted**, not proof of a solved generative conversational model.  
4. Bridge-heavy regional structure is still not the dominant source of gain.  
5. The architecture still needs a stronger long-horizon learning strategy.

## Highest-value next steps

### Near term

- Add checkpoint/resume for very long runs.  
- Expand the dialogue corpus and evaluate held-out prompts.  
- Search long-run profiles more aggressively around long-term quality controls.

### Mid term

- Re-run the best profiles on the full original publication protocol.  
- Add more realistic interactive workloads beyond anchored short replies.  
- Revisit richer regional hierarchy only after longer workloads justify it.

## Bottom line

SBAN v13 is best understood as a **serious hardening and usability release**. It proves that the runtime can survive a much longer stream exposure and can answer a range of short requests coherently through a reproducible built-in subsystem. The system is more real and more usable than the earlier line, but it is still not a finished long-horizon learning architecture.
