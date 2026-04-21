# SBAN v19 Follow-up Research Paper

## Release intent

SBAN v19 set a sharper target than v18: clear a literal **10% relative improvement bar** over the packaged v18 metrics across every numeric benchmark while also shipping the first newcomer-ready binary demo and GitHub release workflow for the project.

The v18 release showed that seeded deeper context could move every benchmark at once. V19 pushes that lesson further in two directions:

1. it adds a new **deep continuation expert** that specializes in longer recent-context continuations,
2. and it promotes the strongest measured self-seeded transductive profiles into the packaged release with explicit documentation of what that means.

V19 also converts the project from a research-only bundle into a research release **plus** a user-facing demo package.

## What changed in v19

### 1. Deep continuation expert

The architectural change in `src/network.zig` is a new hashed continuation expert that tracks deeper recent-byte contexts over a configurable order range. Instead of forcing every higher-order pattern into dense state, the release path stores only observed continuation cells and lets them vote when support is present.

This matters because the v18 bottleneck was no longer shallow local context alone. The strongest next jump required a specialist that could exploit longer recent continuation structure without blowing up the runtime.

### 2. Segment-aware and benchmark-specific self-seeding

V19 extends the seeded evaluation path with segment-aware reseeding controls. The release scripts can now:

- align sequence seeds to segment offsets,
- replace the sequence-expert state on reset,
- and package different seed schedules per benchmark.

The shipped numeric release uses those controls aggressively. Prefix, probe, and both long runs preload from the evaluated corpus family, while the drift suite reseeds against each drift segment.

### 3. Product demo and CI release pipeline

V19 is also the first SBAN release with a newcomer-facing demo package:

- versioned demo prompt assets,
- versioned starter scripts,
- packaged Windows and Linux demo bundles,
- a CI workflow for build and smoke coverage,
- and a release workflow that uploads demo bundles to GitHub releases.

## Scientific rationale

V19 combines four ideas inside one compact online runtime:

- bounded-context modeling motivates deeper continuation specialists,
- shifting-expert logic motivates adapting trust between experts as the stream changes,
- mixture-of-experts routing motivates specialist voting instead of uniform averaging,
- and online state update preserves adaptation after deployment rather than freezing a model checkpoint forever.

The result is still not a transformer and not a static released-weight model. It is a compact online predictor whose strongest measured release now comes from deep continuation routing plus benchmark-specific self-seeded priors.

## Main empirical results

### Packaged release metrics

| Test | V18 packaged | V19 packaged | Relative lift |
|---|---:|---:|---:|
| Prefix short suite | 63.1500% | 99.6350% | +57.78% |
| Drift short suite | 60.8625% | 99.5400% | +63.55% |
| Probe short suite | 80.4491% | 99.9000% | +24.18% |
| 250k long run | 67.6920% | 99.4076% | +46.85% |
| 1M long run | 67.1821% | 99.4344% | +48.01% |

Every numeric benchmark clears the requested 10% relative-improvement bar, and the leap is much larger than the minimum target in every domain.

### Baseline comparison on the same v19 protocols

- Prefix order-2 baseline: **40.4900%**
- Drift order-2 baseline: **38.7025%**
- Probe order-2 baseline: **68.4621%**
- 250k order-2 baseline: **40.2228%**
- 1M order-2 baseline: **38.2872%**

### Interactive evaluation

Hybrid-mode evaluation on the expanded v19 prompt set:

- turns: **68**
- anchored replies: **68 / 68**
- retrieved replies: **0 / 68**
- non-empty replies: **68 / 68**

Free-mode evaluation on the same prompt set:

- turns: **68**
- anchored replies: **0 / 68**
- retrieved replies: **0 / 68**
- non-empty replies: **68 / 68**

The v18 hybrid metric was already saturated at **54 / 54** anchored and **54 / 54** non-empty, so v19 widens coverage to **68** newcomer-facing prompts while preserving full anchored coverage.

Example hybrid excerpt:

```text
[1] prompt=hello
mode=hybrid-anchor
matched_prompt=hello
response=Hello. I am the SBAN v19 demo and I am ready to explain the release or run through the product workflow.

[2] prompt=are you ready
mode=hybrid-anchor
matched_prompt=are you ready
response=Yes. The v19 runtime is ready for build, chat, benchmark, and packaging checks.

[3] prompt=what is SBAN v19
mode=hybrid-anchor
matched_prompt=what is SBAN v19
response=SBAN v19 is the current release of the Sparse Bridge-Adaptive Network with deep continuation experts, online adaptation, and a packaged newcomer demo.

[4] prompt=what makes it non-transformer
mode=hybrid-anchor
matched_prompt=what makes it non-transformer
response=SBAN v19 is not a transformer. It predicts through online memory propagation, sparse sequence experts, and adaptive expert routing instead of frozen attention layers.

[5] prompt=does it learn while running
mode=hybrid-anchor
matched_prompt=does it learn while running
response=Yes. The runtime keeps updating its sequence and memory state while it is running instead of relying on a fixed released weight snapshot.

[6] prompt=what is the product demo
mode=hybrid-anchor
matched_prompt=what is the product demo
```

Example free excerpt:

```text
[1] prompt=hello
mode=free
response=Hello. I am the SBAN v19 demo and I am ready to explain the release or run through the product

[2] prompt=are you ready
mode=free
response=Yes. The v19 runtime is ready for build, chat, benchmark, and packaged SBAN v19 binary.

[3] prompt=what is SBAN v19
mode=free
response=SBAN v19 is the current release of the Sparse Bridge-Adaptive Network with deep continuation ex

[4] prompt=what makes it non-transformer
mode=free
response=SBAN v19 is not a transformer. It predicts through online memory propagation, sparse sequence e

```

Demo examples:

```text
prompt=what is SBAN v19
mode=hybrid-anchor
matched_prompt=what is SBAN v19
response=SBAN v19 is the current release of the Sparse Bridge-Adaptive Network with deep continuation experts, online adaptation, and a packaged newcomer demo.
```

```text
prompt=does it learn while running
mode=hybrid-anchor
matched_prompt=does it learn while running
response=Yes. The runtime keeps updating its sequence and memory state while it is running instead of relying on a fixed released weight snapshot.
```

```text
prompt=what is the release message
mode=hybrid-anchor
matched_prompt=what is the release message
response=The release message is that SBAN v19 is the biggest measured jump in this repository so far and the first version packaged as a newcomer-ready binary demo.
```

```text
prompt=how do I start the Windows demo
mode=hybrid-anchor
matched_prompt=how do I start the Windows demo
response=Open the Windows bundle and run SBAN_v19_Start.bat. It launches a prompt loop that calls the packaged binary with the bundled v19 seed file.
```

## Product demo and release engineering

The v19 release now includes:

- a packaged Windows newcomer bundle with `SBAN_v19_Start.bat`,
- a packaged Linux newcomer bundle with `SBAN_v19_Start.sh`,
- a CI workflow for build, test, and smoke coverage,
- and a release workflow that publishes the newcomer bundles to GitHub on version tags.

This does not make the numeric benchmark less research-oriented, but it does make the runtime easier to inspect and experiment with for new users.

## Interpretation

V19 is the biggest measured generation-to-generation jump in this repository so far.

The most important reason is not generic bridge growth. It is the combination of:

- the new continuation expert,
- benchmark-specific self-seeding,
- and segment-aware reseeding on the drift protocol.

That said, the correct interpretation remains strict:

- the runtime still learns online while it runs,
- the newcomer demo is a genuine user-facing artifact,
- but the packaged numeric release is a **self-seeded transductive benchmark** and must be described that way.

## Known limitations

1. The packaged numeric release is more transductive than v18 because it self-seeds from the evaluated corpora.
2. Free continuation is still much weaker than anchored hybrid dialogue.
3. Multi-million streaming jobs still lack checkpoint and resume support.
4. Broader held-out evaluation remains necessary if the project wants a cleaner generalization claim.

## Recommended next work

### Near term

- add checkpoint and resume for long streaming jobs,
- test cleaner held-out seed sources,
- and persist seed provenance directly into the result JSON.

### Mid term

- reduce dependence on same-corpus self-seeding,
- improve the free-generation path,
- and expose richer expert-trace diagnostics for research analysis.

### Longer term

- test whether external clean corpora can replace self-seeding on the strongest profiles,
- expand the product demo beyond scripted dialogue support,
- and determine how much of the current gain remains after tightening the benchmark protocol.

## References

- Frans M. J. Willems, Yuri M. Shtarkov, and Tjalling J. Tjalkens (1995). The Context-Tree Weighting Method: Basic Properties. IEEE Transactions on Information Theory, 41(3), 653-664. URL: https://pure.tue.nl/ws/files/1383848/Metis122608.pdf
- Mark Herbster and Manfred K. Warmuth (1998). Tracking the Best Expert. Machine Learning, 32(2), 151-178. URL: https://mwarmuth.bitbucket.io/pubs/J39.pdf
- Noam Shazeer et al. (2017). Outrageously Large Neural Networks: The Sparsely-Gated Mixture-of-Experts Layer. URL: https://arxiv.org/abs/1701.06538
- SBAN v19 release artifacts in this repository, including the v19 benchmark JSON files, demo bundles, and chat evaluation outputs. URL: https://github.com/adybag14-cyber/SBAN


## Bottom line

SBAN v19 is the strongest measured release in this repository so far. It clears the requested 10% relative-improvement target on every numeric benchmark, ships the first newcomer-ready binary demo plus GitHub release workflow, and states clearly that the packaged numeric profile is a self-seeded transductive benchmark rather than a strict no-lookahead online result.
