# Executive Summary - SBAN v11

## Project status

SBAN v11 is a further step toward making SBAN a **real, runnable, research-grade online model** rather than only a sequence of hand-tuned artifacts. The release combines code changes, build cleanup, and stress-tested operating profiles.

## What v11 added

- a **local-Zig build path** that uses the uploaded Zig binary directly,
- **carry-state selection refinements** in code,
- a **birth-pressure control hook** for future homeostatic tightening,
- bundled **v11 release scripts** and saved result JSONs.

## Best validated v11 results

### Unified working profile

- Prefix: **41.8450%**
- Drift: **42.1950%**
- Probe: **69.2612%**

### Best specialized profiles

- Prefix: **41.8450%**
- Drift: **42.3625%**
- Probe: **69.2612%**

## Main takeaways

1. SBAN v11 is **fully buildable and runnable** from the uploaded Zig tarball.
2. The best current operating regime remains a **compact elastic short-memory learner**.
3. On the maintained suite, v11 specialized profiles improve over v10 specialized by **+0.0325 pp prefix**, **+0.0325 pp drift**, and **+0.0638 pp probe**.
4. The unified v11 working profile beats the matched fixed-capacity comparator by **+0.5125 pp prefix**, **+0.0225 pp drift**, and **+0.2431 pp probe**.

## Known limitations

- long-term memory is still not the winning mode on the maintained short suite,
- bridge births remain effectively zero on the best runs,
- the strongest validation remains the maintained suite rather than a full rerun of the original v4 publication sweep,
- the model still uses vote-style outputs rather than calibrated probabilities,
- memory and synapse storage are not yet packed for hardware efficiency.

## Future direction

The highest-value path after v11 is to keep SBAN grounded in what is actually working: compact elastic learning, reproducible release engineering, and workload-driven subsystem validation. Long-term memory, richer regional structure, and stronger bridge rules should continue, but only where measured workloads show that the added structure is truly useful.
