# SBAN v20 Follow-up Research Paper

## Release intent

SBAN v20 deliberately changes the optimization target.

The v19 release already pushed the packaged numeric suite close to saturation under a self-seeded transductive protocol. Chasing another artificial numeric jump would not have improved the real product surface much. V20 therefore keeps the exact same numeric health suite as an engine check and redirects the generation effort toward three user-facing behaviors:

1. stronger free chat mode,
2. continuing multi-turn memory without requiring a fresh chat,
3. and basic robustness on short unseen prompts such as `what is 2 + 2`.

The design constraint is strict: hold the v19 numeric baseline within roughly **plus or minus one percentage point** while making the newcomer demo actually usable as a continuing session.

## What changed in v20

### 1. Persistent session transcripts

The v20 CLI adds a continuing-session path through `session_path`. Each turn can reload the prior transcript, answer with the current runtime, and append the new turn back to disk. This keeps the product demo simple while providing stable cross-turn continuity for packaged starter scripts.

### 2. Lightweight symbolic support for practical prompts

V20 adds targeted symbolic handling for the cases where v19 was weakest:

- name capture from user introductions such as `hi im tom`,
- name recall prompts such as `can you recall my name`,
- short arithmetic expressions such as `2 + 2`,
- and newcomer help prompts.

This is intentionally narrow. The point is not to claim broad open-domain reasoning. The point is to make the product surface behave reliably on the first prompts a new user will actually try.

### 3. Honest session evaluation

V19 reported one-shot chat coverage. V20 adds a scripted `chat-session-eval` path so the release can measure multi-turn recall and short robustness checks directly instead of implying that a one-shot prompt list captures session behavior.

### 4. Continuing-session demo packaging

The v20 starter scripts now keep a single session file alive for the duration of the demo. That means the packaged newcomer flow can demonstrate continuity and recall out of the box.

## Scientific rationale

V20 treats the numeric suite as a health metric for the runtime core and shifts innovation into the orchestration layer around that core. This is a pragmatic research move:

- preserve the strong engine profile that already works,
- avoid perturbing the saturated release path without evidence,
- and make the architecture easier to inspect as a real interactive system.

The result is still an online non-transformer runtime. It keeps adapting while it runs, but the user-facing behavior is now less dependent on exact anchored prompts.

## Main empirical results

### Numeric engine-health suite

| Test | V19 packaged | V20 packaged | Delta |
|---|---:|---:|---:|
| Prefix short suite | 99.6350% | 99.6350% | +0.0000 pp |
| Drift short suite | 99.5400% | 99.5400% | +0.0000 pp |
| Probe short suite | 99.9000% | 99.9000% | +0.0000 pp |
| 250k long run | 99.4076% | 99.4076% | +0.0000 pp |
| 1M long run | 99.4344% | 99.4344% | +0.0000 pp |

The numeric v20 release stays on top of the v19 baseline without sacrificing the core release profile.

### Baseline comparison on the same v20 protocols

- Prefix order-2 baseline: **40.4900%**
- Drift order-2 baseline: **38.7025%**
- Probe order-2 baseline: **68.4621%**
- 250k order-2 baseline: **40.2228%**
- 1M order-2 baseline: **38.2872%**

### One-shot chat evaluation

Hybrid-mode evaluation on the v20 prompt set:

- turns: **53**
- anchored replies: **48 / 53**
- retrieved replies: **0 / 53**
- symbolic replies: **5 / 53**
- non-empty replies: **53 / 53**

Free-mode evaluation on the same prompt set:

- turns: **53**
- anchored replies: **0 / 53**
- retrieved replies: **48 / 53**
- symbolic replies: **5 / 53**
- non-empty replies: **53 / 53**

### Multi-turn session evaluation

The scripted free-mode session evaluation records:

- turns: **6**
- symbolic replies: **4 / 6**
- non-empty replies: **6 / 6**
- expectation checks passed: **6 / 6**

Example hybrid excerpt:

```text
[1] prompt=hello
mode=hybrid-anchor
matched_prompt=hello
response=Hello. I am the SBAN v20 demo and I am ready for a continuing session, release questions, and quick reasoning checks.

[2] prompt=are you ready
mode=hybrid-anchor
matched_prompt=are you ready
response=Yes. The v20 runtime is ready for build, chat, benchmark, and packaging checks.

[3] prompt=what is SBAN v20
mode=hybrid-anchor
matched_prompt=what is SBAN v20
response=SBAN v20 is the current SBAN release focused on real usability. It keeps the numeric health suite near the v19 baseline while improving free chat, session memory, and simple unseen-prompt robustness.

[4] prompt=what changed in v20
mode=hybrid-anchor
matched_prompt=what changed in v20
response=V20 adds persistent session transcripts, symbolic recall for user facts like names, simple arithmetic handling, a session evaluation path, and a newcomer demo that keeps talking without restarting from scratch.

[5] prompt=what makes it non-transformer
mode=hybrid-anchor
matched_prompt=what makes it non-transformer
response=SBAN v20 is not a transformer. It predicts through online memory propagation, sparse sequence experts, and adaptive routing instead of frozen attention layers.
```

Example free excerpt:

```text
[1] prompt=hello
mode=free-retrieved
matched_prompt=hello
response=Hello. I am the SBAN v20 demo and I am ready for a continuing session, release questions, and quick reasoning checks.

[2] prompt=are you ready
mode=free-retrieved
matched_prompt=are you ready
response=Yes. The v20 runtime is ready for build, chat, benchmark, and packaging checks.

[3] prompt=what is SBAN v20
mode=free-retrieved
matched_prompt=what is SBAN v20
response=SBAN v20 is the current SBAN release focused on real usability. It keeps the numeric health suite near the v19 baseline while improving free chat, session memory, and simple unseen-prompt robustness.

[4] prompt=what changed in v20
mode=free-retrieved
matched_prompt=what changed in v20
response=V20 adds persistent session transcripts, symbolic recall for user facts like names, simple arithmetic handling, a session evaluation path, and a newcomer demo that keeps talking without restarting from scratch.

[5] prompt=what makes it non-transformer
mode=free-retrieved
matched_prompt=what makes it non-transformer
response=SBAN v20 is not a transformer. It predicts through online memory propagation, sparse sequence experts, and adaptive routing instead of frozen attention layers.
```

Example session excerpt:

```text
[1] prompt=hi im tom
mode=session-memory
response=Hi Tom. I will remember your name for this session.

expect_contains=remember your name
expect_pass=true

[2] prompt=can you recall my name
mode=session-recall
response=Your name is Tom.

expect_contains=Tom
expect_pass=true

[3] prompt=what is 2 + 2
mode=symbolic-math
response=2 + 2 = 4.

expect_contains=4
expect_pass=true

[4] prompt=what changed in v20
mode=free-retrieved
matched_prompt=what changed in v20
response=V20 adds persistent session transcripts, symbolic recall for user facts like names, simple arithmetic handling, a session evaluation path, and a newcomer demo that keeps talking without restarting from scratch.

expect_contains=session
expect_pass=true

[5] prompt=help
mode=symbolic-help
response=I can answer release questions, continue a session, remember facts you tell me in this chat, and handle simple arithmetic prompts.
```

## Demo examples

```text
prompt=what is SBAN v20
mode=hybrid-anchor
matched_prompt=what is SBAN v20
response=SBAN v20 is the current SBAN release focused on real usability. It keeps the numeric health suite near the v19 baseline while improving free chat, session memory, and simple unseen-prompt robustness.
```

```text
prompt=how do sessions work
mode=free-retrieved
matched_prompt=how do sessions work
response=The v20 demo can persist a plain-text session transcript through session_path, so each new turn reloads the prior conversation and keeps continuity without starting from an empty chat.
```

```text
prompt=what is 2 + 2
mode=symbolic-math
response=2 + 2 = 4.
```

```text
prompt=hi im tom
mode=session-memory
response=Hi Tom. I will remember your name for this session.

prompt=can you recall my name
mode=session-recall
response=Your name is Tom.
```

```text
prompt=how do I start the Windows demo
mode=hybrid-anchor
matched_prompt=how do I start the Windows demo
response=Open the Windows bundle and run SBAN_v20_Start.bat. It launches a prompt loop that reuses one v20 session transcript so the chat keeps context across turns.
```

## Interpretation

V20 is not the biggest numeric leap in the repository. That is intentional. It is the release where SBAN becomes much easier to use without collapsing the core benchmark behavior.

The key empirical statement is:

- the numeric engine-health suite stays essentially flat relative to v19,
- free chat becomes materially more reliable on newcomer prompts,
- session continuity is now directly supported and directly measured,
- and the product demo finally shows memory and simple robustness instead of only anchored question answering.

## Known limitations

1. The packaged numeric benchmark still uses a self-seeded transductive profile and must be described that way.
2. The symbolic helpers are narrow by design and do not replace broad open-domain reasoning.
3. Session continuity is transcript-backed rather than a long-lived process resident memory server.
4. Broader held-out and adversarial evaluation is still needed.

## Recommended next work

- broaden the session-memory schema beyond names and simple helpers,
- add checkpoint and resume for longer streaming workloads,
- tighten the free-generation path further on truly unseen prompts,
- and reduce dependence on same-corpus self-seeding for the numeric release.

## References

- Frans M. J. Willems, Yuri M. Shtarkov, and Tjalling J. Tjalkens (1995). The Context-Tree Weighting Method: Basic Properties. IEEE Transactions on Information Theory, 41(3), 653-664. URL: https://pure.tue.nl/ws/files/1383848/Metis122608.pdf
- Mark Herbster and Manfred K. Warmuth (1998). Tracking the Best Expert. Machine Learning, 32(2), 151-178. URL: https://mwarmuth.bitbucket.io/pubs/J39.pdf
- SBAN v20 release artifacts in this repository, including the v20 benchmark JSON files, continuing-session demo bundles, and chat evaluation outputs. URL: https://github.com/adybag14-cyber/SBAN


## Bottom line

SBAN v20 is the release that turns the architecture from a strong but rigid demo into a more usable continuing-session product surface while keeping the packaged engine-health suite stable.
