# Executive Summary - SBAN v4 Project Status

## Project name

**SBAN v4 - Elastic Regional Synaptic Birth-Death Assembly Network**

## Project goal

Refine SBAN into a more scientifically ambitious online byte-learning system with:

- runtime **growth and shrink** of its memory target,
- region-tagged sparse pathways that can become a basis for future parallel execution,
- conservative **bridge memories** for cross-region conjunctions,
- continued local reputation, promotion, demotion, pruning, and slot recycling,
- reproducible evaluation on real **enwik8** byte streams in Zig.

## Current status

The repo now delivers a working end-to-end **v4 research artifact** with:

- a Zig implementation of elastic short-memory sizing,
- region-local score lanes and region-tagged memories,
- conservative bridge-memory scaffolding,
- 1-bit through 8-bit sweeps on enwik8,
- 4-bit ablation studies,
- a longer contiguous-prefix stress run,
- an explicit **elasticity probe** that demonstrates runtime growth and shrink,
- a regenerated paper, figures, and summary pipeline.

## Main architectural changes from v3

### 1. Elastic short-memory target

SBAN v4 no longer uses only a fixed live-memory target. It can raise or lower its short-memory budget during runtime based on surprise, birth pressure, and utilization.

### 2. Region-tagged sparse lanes

Memories now carry a **region identity**. Output votes are first accumulated inside region-local score buffers and only then merged, which is the main v4 step toward future parallel kernels.

### 3. Conservative bridge memories

A memory can optionally connect a primary and secondary region. The current gate is deliberately conservative because earlier eager bridge rules created too many harmful cross-region nodes.

### 4. Stable sensory anchoring

The v4 implementation keeps sensory bytes on a stable anchor path and lets regions emerge from overloaded memory subgraphs rather than repeatedly reassigning the raw byte alphabet when the region count changes.

### 5. Direct shrink test

The artifact now includes a dedicated hard-to-easy **elasticity probe** so runtime contraction is not only claimed in theory but measured in practice.

## Packaged protocol

The default reproducible artifact uses:

- **Bit sweeps:** 4 x 30k-byte prefix and drift runs on enwik8.
- **Ablations:** 4-bit prefix and drift runs.
- **Long stress:** 4 x 40k-byte contiguous prefix run.
- **Elasticity probe:** 60k real enwik8 bytes followed by a 60k low-entropy tail.

## Main empirical findings

### Best SBAN v4 results on the packaged enwik8 protocol

- Best **prefix** result: **sban_v4_4bit = 40.51%**
- Prefix **order-2** baseline: **39.46%**
- Best **drift** result: **sban_v4_6bit = 42.94%**
- Drift **order-2** baseline: **39.99%**

### Precision scaling trend

The strongest gains still happen in the move from **1-bit** into the low multi-bit range. Prefix peaks around **4-bit**, while drift is strongest near **5-bit / 6-bit**.

### Reputation-gating result

At 4 bits, removing reputation drops the default model by about **3.08 pp** on prefix and **3.20 pp** on drift. This remains the clearest evidence that local self-rating suppresses bad-habit consolidation.

### Elasticity result on the main protocol

Relative to the 4-bit **fixed-capacity** ablation, the default elastic model is ahead by about **0.17 pp** on prefix and **0.08 pp** on drift. The gain is modest, but it is positive on the main protocol.

### Elasticity probe result

On the dedicated hard-to-easy probe:

- the default 4-bit model grows its target from **2048** to **8192**,
- then shrinks to **4608**,
- while live short memories collapse from more than **4718** to **198**,
- and accuracy is **69.89%** versus **69.22%** for fixed capacity.

This is the strongest direct evidence that SBAN v4 can actually change its effective size during runtime.

## Comparison with the bundled v3 reference

- Best v4 prefix is **-0.05 pp** relative to the bundled v3 reference.
- Best v4 drift is **-0.11 pp** relative to v3.
- The v4 **4-bit** operating point is **-0.05 pp** on prefix and **-0.16 pp** on drift versus v3 4-bit.

This means v4 broadens the architecture significantly, but it does **not yet surpass v3 on raw top-1**.

## What the current system demonstrates

1. **Runtime self-improvement** on a real byte stream.
2. **Online pattern learning** without offline retraining.
3. **Dynamic size adaptation** through growth and shrink of the short-memory target.
4. A non-transformer sparse graph with **creation, promotion, demotion, and pruning** of structure.
5. A concrete scaffold for future **parallel region-lane execution**.

## Important limitations

1. v4 does **not yet beat v3** on the main enwik8 benchmark.
2. The current **bridge-memory** rule is not yet a clear win; on prefix the no-bridge ablation is slightly stronger.
3. The system can shrink its **target** and live memory count, but it does not yet compact the allocated region scaffold.
4. On hard enwik8 runs the target grows aggressively to the current maximum of **8192**.
5. Scores are still vote values rather than calibrated probabilities.
6. Synapses are still low-bit in logic but **not bit-packed in RAM**.

## Highest-value next steps

### Near term

- Improve bridge selection using region-specific error signals rather than only diversity and surprise.
- Add true **region compaction / merge** so structural footprint can shrink, not only live memories.
- Learn or meta-optimize the elasticity controller.
- Pack synapses and metadata more compactly.

### Mid term

- Build hierarchical multi-region stacks.
- Add explicit asynchronous or SIMD-friendly region kernels.
- Compare against stronger online baselines beyond order-2 Markov.

## Bottom line

SBAN v4 is now a **real Zig scientific artifact** for studying non-transformer online learning with structural plasticity, dynamic memory sizing, region-tagged sparse computation, and conservative bridge-memory scaffolding. The main enwik8 accuracy is still roughly at v3 level rather than above it, but the new artifact now demonstrates something v3 did not: **direct runtime growth and shrink of the model's effective memory budget**.
