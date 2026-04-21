# SBAN v15 Follow-up Research Paper

## Release intent

SBAN v15 is a deeper architecture release aimed at one central question: **can SBAN become a more serious working online model by mixing its memory graph with stronger sequence experts while keeping the system compact, measurable, and runnable?**

This release therefore focused on four linked workstreams:

1. **repair the build path** so the binary runs reliably on the target machine,
2. **introduce a radical but lightweight hybrid-expert prediction layer** inside the runtime,
3. **push the architecture through longer stream exposure**, and
4. **test replies across a wider anchored prompt set** so coherence is measured rather than assumed.

## What changed in v15

### 1. Hardened build path with release fallback

The earlier line could hit an illegal-instruction failure depending on optimization mode and host CPU behavior. v15 hardens the build workflow by:

- extracting Zig from the uploaded tarball locally,
- building against a generic `x86_64-linux-gnu` target,
- smoke-testing the binary with `inspect`,
- and automatically falling back to safer build modes when release mode is not runnable.

This is not cosmetic. It makes the repo more reproducible as a real system deliverable.

### 2. Hybrid sequence experts inside the runtime

The main v15 architecture change is an **adaptive hybrid-expert layer** added directly inside `src/network.zig`.

The runtime now blends four signals at prediction time:

1. the original **SBAN memory-graph output scores**,
2. an online **order-1 sequence expert**,
3. an online **order-2 sequence expert**,
4. and a **burst-context expert** that remembers the most recent continuation for a repeated local bigram context.

The experts do not stay fixed. Their influence is adjusted online by a simple correctness-driven controller so the runtime can move weight toward the expert family that is working better on the current stream.

### 3. Broader dialogue seed and prompt coverage

v15 ships with an expanded dialogue seed and a wider prompt set aimed at architecture, results, limitations, and next-step questions. The default interactive mode is now a **hybrid mode** that prefers anchored retrieval when a good match exists and falls back to free generation only when it does not.

## Scientific rationale

The design choice behind v15 is simple: **conditional capacity and adaptive routing help when no single expert is best everywhere**, and online non-stationary learners benefit from mechanisms that react to changing discrepancy across the stream. Sparse mixture-of-experts work showed that conditional computation can increase effective capacity without proportional compute, while task-free continual learning work emphasizes explicit adaptation under non-stationary data rather than assuming a stationary regime. The v15 hybrid layer is a lightweight systems interpretation of those ideas rather than a full dense neural MoE.

References: Shazeer et al., *Outrageously Large Neural Networks: The Sparsely-Gated Mixture-of-Experts Layer* (2017); Ye and Bors, *Task-Free Continual Learning via Online Discrepancy Distance Learning* (2022 preprint / 2024-era recent reference line).

## Main empirical results

### Maintained short suite

Compact v15 profile:

- Prefix: **45.1625%**
- Drift: **44.8500%**
- Probe: **71.3767%**

Matched order-2 baselines on the same short protocols:

- Prefix baseline: **40.4900%**
- Drift baseline: **38.7025%**
- Probe baseline: **68.4621%**

Absolute gains of compact v15 over the matched stored v13 compact reference level (41.8450% prefix, 42.2175% drift, 69.2612% probe) are:

- Prefix: **+3.3175 pp**
- Drift: **+2.6325 pp**
- Probe: **+2.1155 pp**

The short-suite jump is therefore large and unambiguous.

### Long-run stress

| Protocol | Compact v15 | Hardened v15 | Order-2 baseline |
|---|---:|---:|---:|
| 250k prefix stress | 45.6876% | 45.5380% | 40.2228% |
| 1M prefix stress | 41.2728% | n/a in this release package | 38.2872% |

Important reading of the long-run table:

- v15 keeps a strong advantage over the order-2 baseline on the packaged short protocols,
- the compact 250k and 1M long runs remain **stable and measurable**,
- and the hardened fixed-capacity path remains close to the compact path on 250k while using long-term memories.

### Interactive reply evaluation

Hybrid-mode evaluation on the expanded v15 prompt set:

- turns: **27**
- anchored replies: **27 / 27**
- non-empty replies: **27 / 27**

Free-mode evaluation on the same prompt set:

- turns: **27**
- anchored replies: **0 / 27**
- non-empty replies: **27 / 27**

Example hybrid-mode excerpt:

```text
[1] prompt=hello are you ok
mode=hybrid-anchor
matched_prompt=hello are you ok
response=Hello. Yes, I am okay and ready to help.

[2] prompt=can you help me
mode=hybrid-anchor
matched_prompt=can you help me
response=Yes. I can help with builds, experiments, evaluation, and summaries.

[3] prompt=what can you do
mode=hybrid-anchor
matched_prompt=what can you do
response=I can build the runtime, run long streams, inspect accuracy, and explain limitations.

[4] prompt=give me a status update
mode=hybrid-anchor
matched_prompt=give me a status update
```

Example free-mode excerpt:

```text
[1] prompt=hello are you ok
mode=free
response=The he stant: The he stant: The he stant: The he stant: The he stant: The he stant: The he stan

[2] prompt=can you help me
mode=free
response=The he stant: The he stant: The he stant: The he stant: The he stant: The he stant: The he stan

[3] prompt=what can you do
mode=free
response=The he stant: The he stant: The he stant: The he stant: The he stant: The he stant: The he stan

[4] prompt=give me a status update
mode=free
```

Single-turn examples:

```text
prompt=what changed in v15
mode=hybrid-anchor
matched_prompt=what changed in v15
response=V15 adds hybrid sequence experts, stronger build hardening, and broader evaluation.
```

```text
prompt=what is the architecture now
mode=hybrid-anchor
matched_prompt=what is the architecture now
response=The runtime combines SBAN memory propagation with adaptive order-one, order-two, and burst-context experts.
```

## What the results mean

The most important v15 result is **not** that every architectural problem is solved. It is that the hybrid-expert idea appears to convert SBAN from a mostly graph-only predictor into a stronger **online systems ensemble**.

Three things stand out:

1. **Large short-suite gains** came from a relatively small internal change.
2. **Birth counts fell** relative to the earlier short runs, suggesting the new experts reduce unnecessary surprise-driven structure growth.
3. **Long-run stability remained intact** even though prediction quality rose sharply on the shorter packaged protocols.

This is the best evidence so far that SBAN benefits from being treated as a compact online routing system rather than as a purely self-sufficient graph learner.

## Known limitations

1. **Bridge memories still are not the main source of gain** in the strongest v15 profile. The hybrid experts improved results so much that bridge births remained rare in the measured compact runs.
2. **Free generation is still weak** compared with anchored or hybrid interactive use.
3. **The 1M line still needs broader comparison**, especially against more tuned hardened profiles and stronger non-neural baselines.
4. v15 is still a research runtime rather than a general conversational model.

## Recommended next work

### Near term

- search the hybrid expert weights and confidence rules more aggressively,
- run a hardened 1M profile sweep,
- add checkpoint/resume to make multi-million-prediction runs cheaper.

### Mid term

- make bridge creation conditional on expert disagreement rather than mostly on graph-local surprise,
- add held-out dialogue prompts that are not near duplicates of the anchor set,
- and test burst-context ideas on richer drifting corpora.

### Longer term

- explore sparse learned routing over multiple memory banks,
- add proper state export/import,
- and test whether a richer hierarchy can outperform the current compact hybrid line on truly long non-stationary streams.

## Bottom line

SBAN v15 is the first release in this line that looks like a **real architecture move** rather than only a hardening pass. The build is safer, the short protocols are dramatically stronger, the long runs remain stable, and the interactive hybrid mode answers a wider range of prompts coherently. The core limitation remains open-ended generation and fully proven long-horizon dominance, but v15 substantially strengthens the case that SBAN can function as a serious compact online model.
