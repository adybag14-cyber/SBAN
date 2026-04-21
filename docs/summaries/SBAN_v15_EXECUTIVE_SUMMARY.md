# SBAN v15 Executive Summary

## Project name

**SBAN v15 - hybrid sequence-expert architecture, hardened build, and broader working-model evaluation**

## What this release accomplishes

SBAN v15 pushes the project forward in three concrete ways:

- it hardens the build so the runtime is reliably runnable on the target machine,
- it adds a new adaptive **hybrid expert** layer that mixes SBAN memory scores with online sequence experts,
- and it validates the system on short protocols, longer stress runs, and a wider prompt-set reply evaluation.

## Main measured results

### Compact short suite

- Prefix: **45.1625%**
- Drift: **44.8500%**
- Probe: **71.3767%**

Relative to the stored v14 compact reference (41.8450% prefix, 42.2175% drift, 69.2612% probe), the v15 compact profile improved by:

- Prefix: **+3.3175 pp**
- Drift: **+2.6325 pp**
- Probe: **+2.1155 pp**

### Long-run stress

- 250k compact: **45.6876%**
- 250k hardened: **45.5380%**
- 250k order-2 baseline: **40.2228%**
- 1M compact: **41.2728%**
- 1M order-2 baseline: **38.2872%**

### Interactive evaluation

- Hybrid-mode prompt set: **27 / 27** anchored coherent replies
- Free-mode prompt set: runnable, but still repetitive and much weaker than hybrid mode

## What changed technically

1. **Safer build target and smoke-tested fallback** across optimization modes.
2. **Adaptive hybrid experts**: SBAN graph output + order-1 expert + order-2 expert + burst-context expert.
3. **Online expert-weight adaptation** based on recent correctness.
4. **Expanded v15 dialogue seed and prompt files**.
5. **New v15 release and deliverable scripts**.

## Current limitations

1. Free generation remains weak.
2. Bridge-heavy regional structure is still not the main source of improvement.
3. The hardened 1M profile still needs deeper search.
4. SBAN is still a research runtime, not a finished general conversational system.

## Best interpretation

SBAN v15 is a real architecture improvement. It is no longer only a hardening release. The hybrid sequence-expert idea produced a large short-suite gain while preserving long-run stability and broadening practical reply coverage. The system is materially stronger as a working model than the v14 line.
