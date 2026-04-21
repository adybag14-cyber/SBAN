# SBAN v11 Report

## Release intent

SBAN v11 pushes the current SBAN line toward a more **reproducible, stress-tested, and operationally usable** runtime. The release work focused on three fronts at the same time:

1. **Build reproducibility** using the uploaded local Zig binary and a deterministic wrapper script.
2. **Architecture and code cleanup** around carry-state selection and birth-pressure hooks.
3. **Stress tuning** on the maintained short target suite so the delivered repo ships with working profiles instead of only abstract ideas.

## What changed in v11

### 1. Local-Zig reproducible build path

The repo now carries a first-class build path through `scripts/build_with_local_zig.sh`, and the v11 release runner uses the uploaded Zig tarball directly rather than assuming a system installation.

### 2. Carry-state refinement in code

The runtime now includes:

- signature-aware carry diversity plumbing,
- precision-gated carry scoring hooks,
- support-aware carry scoring,
- a birth-pressure threshold hook for stronger future homeostatic control.

The strongest measured code-level effect in this release was on **drift robustness under a matched tuned profile**: the same 5-bit no-long-term profile with `birth_margin=21` and `min_parents_for_birth=4` moved from **42.1325%** on the v10 runtime to **42.1950%** on the v11 runtime.

### 3. Stress-tuned working profiles

The best practical profiles on the maintained suite are now:

- **Unified working profile:** 5-bit default, `enable_long_term=false`, `birth_margin=21`, `min_parents_for_birth=4`, `max_carry_memories=48`, `max_hidden_per_hop=32`, `propagation_depth=2`.
- **Best drift profile:** same compact family, but with `birth_margin=20`.

## Main v11 results

### Unified working profile

- Prefix: **41.8450%**
- Drift: **42.1950%**
- Probe: **69.2612%**

### Best specialized profiles

- Prefix: **41.8450%**
- Drift: **42.3625%**
- Probe: **69.2612%**

### v11 unified versus fixed-capacity comparator

- Prefix delta: **+0.5125 pp**
- Drift delta: **+0.0225 pp**
- Probe delta: **+0.2431 pp**

### Best specialized v11 versus best specialized v10

- Prefix delta: **+0.0325 pp**
- Drift delta: **+0.0325 pp**
- Probe delta: **+0.0638 pp**

### Best specialized v11 versus best specialized v8

- Prefix delta: **+0.0875 pp**
- Drift delta: **+0.1450 pp**
- Probe delta: **+0.1759 pp**

## Operational interpretation

The strongest current SBAN still behaves as a **compact elastic learner**:

- final live region count stays at **1** on all maintained v11 winners,
- bridge births remain effectively **0**,
- the best working profiles still disable long-term memory for this short suite,
- the elasticity advantage is clearest on **prefix** and especially on the **hard-to-easy probe**.

That means v11 improves the system as a **real runnable model**, but it does not yet claim that the bridge-heavy or long-term-heavy form is already the dominant operating regime.

## Known limitations

1. The best short-suite profiles still prefer `enable_long_term=false`, so the long-term subsystem is not yet the main source of gain.
2. Bridge memories remain functionally dormant on the maintained suite.
3. The strongest claims are still on the maintained short target suite, not yet on a complete rerun of the original published v4 protocol.
4. The runtime still reports top-1 vote accuracy rather than calibrated probabilities.
5. Synapses and state are still not bit-packed for a hardware-efficiency story.

## Recommended next work after v11

1. Revisit long-term memory with a workload where carry depth and delayed reuse genuinely matter.
2. Add a second stress layer that searches longer-horizon corpora and memory budgets rather than only the short suite.
3. Build a publication-grade reproducibility script that reruns both the maintained suite and the original v4 publication suite in one pass.
4. Keep bridge machinery available, but do not promote it as the main story until a workload proves it is paying for itself.
