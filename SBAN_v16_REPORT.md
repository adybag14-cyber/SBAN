# SBAN v16 Follow-up Research Paper

## Release intent

SBAN v16 is a systems-focused release aimed at a harder question than v15: **can SBAN preserve its stronger short-suite behavior while becoming more adaptive on truly long non-stationary streams?**

The core v16 decision was to treat the v15 hybrid design as incomplete rather than final. v15 already showed that a compact mixture of online experts could materially improve prediction quality, but its expert weights were still effectively global. That is not ideal when the stream changes regime over time.

Accordingly, v16 targeted four linked workstreams:

1. preserve the v15 short-suite profile rather than regress it,
2. add a new **recent-context specialist** for regime shifts,
3. test the new routing on longer streams where drift actually matters,
4. and improve the reply path with broader v16 prompt coverage and support retrieval.

## What changed in v16

### 1. Regime-aware recent-context expert

The main v16 architecture change is a new **bounded recent order-two expert** inside `src/network.zig`.

The runtime now maintains:

- the original SBAN memory-graph score path,
- an online order-1 expert,
- an online order-2 expert over the full stream,
- a burst-context expert,
- and a new **recent-context order-2 expert** backed by a sliding window.

This new expert keeps only a bounded recent transition history. Its purpose is not to dominate everywhere. It exists to react faster when the stream changes local regime and the older global counts become a worse guide.

### 2. Shared online expert adaptation

V15 already adapted expert weights. V16 adds a stronger **shared mixing rule** so the expert weights can move toward whichever specialist is currently working, while still pulling back toward a common center instead of drifting into a brittle winner-take-all state.

### 3. Safer chat fallback behavior

The v16 dialogue path still prefers anchored matches, but now includes a related-prompt retrieval fallback before pure free generation. On the bundled prompt set the anchors remained strong enough that retrieval was rarely needed, but the system path is now more robust than the v15 all-or-nothing split.

## Scientific rationale

The v16 design is guided by three compatible research ideas:

- sparse conditional computation and mixture-of-experts improve effective capacity when no single expert is uniformly best,
- drifting environments benefit from ensembles that can reweight, add, or track specialists over time,
- and adaptive-regret / fixed-share style online methods are specifically motivated by settings where the best expert changes across intervals.

V16 is therefore not trying to become a neural MoE. Instead, it uses those ideas to build a more regime-aware **online systems ensemble** inside the SBAN runtime.

## Main empirical results

### Short-suite preservation profile

Compact v16 short profile:

- Prefix: **45.1625%**
- Drift: **44.8500%**
- Probe: **71.3767%**

Order-2 baselines on the same short protocols:

- Prefix baseline: **40.4900%**
- Drift baseline: **38.7025%**
- Probe baseline: **68.4621%**

Relative to v15, the short profile is intentionally **held stable rather than aggressively retuned**:

- Prefix delta vs v15: **+0.0000 pp**
- Drift delta vs v15: **+0.0000 pp**
- Probe delta vs v15: **+0.0000 pp**

This matters because the new recent-context expert did not improve the short packaged protocol when forced on all the time. The measured v16 decision was therefore to keep the v15-equivalent short profile and specialize the new expert to longer-horizon runs.

### Long-run results


| Protocol | V16 profile | Order-2 baseline | Delta |
|---|---:|---:|---:|
| 250k prefix stress | 46.1572% | 40.2228% | +0.4696 pp vs v15 250k |
| 1M prefix stress | 43.2688% | 38.2872% | +1.9960 pp vs v15 1M compact |

The 250k result is the clearest completed v16 gain: **46.1572%**, up from the v15-equivalent **45.6876%**, while also using fewer births and fewer final live memories.

The longest completed v16 stress line packaged here is the **1M** run at **43.2688%** against an order-2 baseline of **38.2872%**.


### Interactive reply evaluation

Hybrid-mode evaluation on the expanded v16 prompt set:

- turns: **36**
- anchored replies: **36 / 36**
- retrieved replies: **0 / 36**
- non-empty replies: **36 / 36**

Free-mode evaluation on the same prompt set:

- turns: **36**
- anchored replies: **0 / 36**
- retrieved replies: **0 / 36**
- non-empty replies: **36 / 36**

Example hybrid excerpt:

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
response=The build is running, the evaluation is active, and the latest checks are recorded.

```

Example free excerpt:

```text
[1] prompt=hello are you ok
mode=free
response=what stant: what stant: what stant: what stant: what stant: what stant: what stant: what stant:

[2] prompt=can you help me
mode=free
response=what stant: what stant: what stant: what stant: what stant: what stant: what stant: what stant:

[3] prompt=what can you do
mode=free
response=what stant: what stant: what stant: what stant: what stant: what stant: what stant: what stant:

```

Single-turn examples:

```text
prompt=what changed in v16
mode=hybrid-anchor
matched_prompt=what changed in v16
response=V16 adds regime-aware routing, a recent-context expert, and stronger chat fallback behavior.
```

```text
prompt=explain the new routing logic
mode=hybrid-anchor
matched_prompt=can you explain the hybrid experts
response=The hybrid experts blend SBAN scores with online Markov, burst-context, and recent-context signals and learn which one to trust.
```

```text
prompt=how do you respond when the prompt is only loosely related
mode=hybrid-anchor
matched_prompt=can you summarize the project
response=The project is building a compact online learner that can adapt, measure, and answer short requests.
```

## Interpretation

The v16 lesson is more specific than the v15 lesson.

- **Global hybrid experts were enough to lift the short suite in v15.**
- **Recent-window specialists become useful once the stream is long enough for regime mismatch to matter.**
- **Trying to force the recent specialist into every profile is counterproductive.**

That is why the final v16 release uses two distinct operating ideas:

1. a **short-suite preservation profile** that keeps the v15-equivalent compact behavior,
2. a **long-run regime-aware profile** that turns on the recent expert and shared expert mixing where it actually earns its keep.

This split is a real architectural result, not a marketing one. It tells us where the new specialist helps and where it should stay out of the way.

## Known limitations

1. The recent expert is beneficial on longer streams, but it does **not** improve the packaged short-suite when always enabled.
2. Hybrid and anchored chat remain stronger than pure free generation.
3. Bridge memories are still not the main driver of the best measured gains.
4. V16 is a stronger working online model, but it is still a research runtime rather than a finished general conversational system.

## Recommended next work

### Near term

- search separate short-run and long-run profiles more systematically,
- add checkpoint/resume for multi-million-prediction jobs,
- and record explicit expert-weight traces across the stream.

### Mid term

- make bridge creation conditional on expert disagreement and interval error,
- add a real regime detector instead of only a sliding recent window,
- and test longer held-out drifting corpora beyond the packaged enwik8 protocols.

### Longer term

- combine multiple recent windows rather than a single fixed one,
- add serialization and resume support,
- and explore whether bridge structure can become a true routing substrate instead of mostly a supporting mechanism.

## Bottom line

SBAN v16 is a real architectural improvement in long-horizon online adaptation. It preserves the strong v15 short profile, improves the completed 250k long run to **46.1572%**, and broadens the hybrid reply path with a larger anchored prompt set and related-prompt fallback. The strongest completed long-horizon evidence in this packaging pass is the 250k gain to **46.1572%** together with the completed **1M** stress line at **43.2688%**.
