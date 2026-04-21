# Executive Summary - SBAN v10 Project Status

## Project name

**SBAN v10 - Selective Compact Elastic SBAN with Quality-Gated Long-Term Control**

## Project goal

Push SBAN past the earlier stress-tuned v8/v9 state and test whether the architecture can behave more like a real working model: easier to build, easier to run, easier to regression-test, and more selective about when extra structure is actually allowed to influence prediction.

## What was done in v10

### 1. Real architectural refinement of the long-term subsystem

The long-term subsystem is no longer treated as a simple on/off bonus path. V10 adds:

- **quality-gated long-term output scaling** so weak long memories do not get the same contribution bonus as strong long memories
- a **selection penalty for low-precision long memories** so they are less likely to dominate carry state or birth-parent selection

This is the most important code-level architectural change in v10.

### 2. Better working-profile discovery

The strongest release-grade working profile on the maintained suite is:

- **5-bit default**
- `enable_long_term=false`
- `min_parents_for_birth=4`

That profile improves all three maintained targets at once.

### 3. Real build-process hardening

V10 adds a build wrapper that uses the provided Zig tarball directly and creates a stable binary path. The repo also includes a scripted release runner and a focused search harness.

## Main empirical results

### Best unified working profile

- **Prefix:** **41.8100%**
- **Drift:** **42.2475%**
- **Probe:** **69.1129%**

### Best specialized profiles

- **Prefix best:** **41.8125%**
- **Drift best:** **42.3300%**
- **Probe best:** **69.1974%**

## Why these results matter

### Relative to the maintained operational v4 anchor

V10 unified improves the maintained target-suite anchor by about:

- **+0.8125 pp** on prefix
- **+0.7125 pp** on drift
- **+0.5008 pp** on the probe

### Relative to the best specialized v8 profiles summarized in the v9 paper

V10 unified is ahead by about:

- **+0.0525 pp** on prefix
- **+0.0300 pp** on drift
- **+0.0276 pp** on probe

V10 best specialized is ahead by about:

- **+0.0550 pp** on prefix
- **+0.1125 pp** on drift
- **+0.1121 pp** on probe

## What the current system now demonstrates

1. A **real, reproducible build path** from the provided Zig binary tarball.
2. A **single release-grade working profile** that improves all three maintained targets.
3. An SBAN operating point that is more clearly a **compact elastic working model** rather than a bridge-heavy graph expansion story.
4. A runtime that is easier to use as an actual experimental system because build, run, and search are all scripted.

## Important operational interpretation

The current strongest SBAN does **not** win by using more and more regional and bridge structure. It wins by being **selective**:

- stricter about which short memories are born
- harsher on low-quality long memories
- comfortable collapsing to a compact one-region state

This is a serious improvement in usability and controllability even though it is not yet the final architectural endpoint.

## Known limitations

1. The best current profiles are still essentially **single-region compact profiles**.
2. The strongest v10 claims are on the **maintained short target suite**, not yet a full replacement rerun of the original v4 publication protocol.
3. Long-term memory is currently most convincing as an **optional quality-filtered subsystem**, not yet as a universally winning component.
4. Scores are still vote values rather than calibrated probabilities.
5. Synapses are still not bit-packed in RAM.
6. The controller is still hand-designed rather than learned.

## Future work with highest expected value

### Near term

- Re-run v10 unified and specialized profiles on the **full original v4 publication protocol**.
- Add **runtime memory accounting** and bit-packing work.
- Create explicit **short-horizon** and **long-horizon** presets.
- Extend the search harness to compare more regime-specific controller settings.

### Mid term

- Add a **learned or meta-optimized controller**.
- Test workloads where long-term memory should matter more than on the current maintained suite.
- Revisit hierarchical region stacks only after showing a task where richer structure clearly pays for itself.

## Bottom line

**SBAN v10 is the strongest "real working model" state reached so far in this workspace.** It is better not because it proves the largest or most complex SBAN, but because it finds a more selective and controllable operating regime, improves the maintained regression targets, hardens the build and run workflow, and makes the system more realistic to operate as continuing scientific software.
