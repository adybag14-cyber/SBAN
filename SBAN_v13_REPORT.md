# SBAN v13 Report

## Release intent

SBAN v13 pushes the post-v12 line in a more practical direction. The work focused on three connected goals:

1. **keep the strong compact elastic maintained-suite operating point alive**,  
2. **run a genuinely longer stress exposure at one million predictions**, and  
3. **replace the weak free-form reply path with a more coherent request-response subsystem**.

The result is not a headline short-suite breakthrough. It is a **harder, more honest, more operational** SBAN release.

## What changed in v13

### 1. Carry-quality scoring

Carry selection now includes an explicit **win-loss quality term**. This is a small architectural change, but it makes the carry set less indifferent to memories that have recently been wrong too often.

### 2. Prompt-anchor dialogue subsystem

The old byte-generation demo could run, but it tended to collapse into repetitive fragments under a range of prompts. v13 adds a **prompt-anchor dialogue adapter**:

- parse a dialogue seed corpus into user/assistant pairs,
- score the nearest prompt anchor by lexical overlap,
- answer through the matched response when the anchor is confident,
- fall back to free byte-generation only when no anchor is found.

This is a pragmatic systems fix. It makes the runtime more usable as a real working demo without pretending that open-ended byte-generation alone is already a full conversational model.

### 3. Multi-prompt chat evaluation

The repo now includes a dedicated prompt set and a `chat-eval` command. That gives the runtime a repeatable way to test coherence over a range of questions instead of a single smoke prompt.

### 4. Very-long-run stress harness

v13 adds a **1,000,000-prediction prefix stress run** on top of the earlier 250k run. This is the first release in the current line that directly shows what happens when the system is pushed much farther into sustained exposure.

## Main v13 results

### Maintained short target suite

Unified compact profile:

- Prefix: **41.8450%**
- Drift: **42.1950%**
- Probe: **69.2612%**

Best specialized profile in this release layer:

- Drift: **42.3625%**

### Unified compact profile versus matched fixed-capacity comparator

- Prefix delta: **+0.5125 pp**
- Drift delta: **+0.0225 pp**
- Probe delta: **+0.2431 pp**

The maintained short suite therefore stays at the strong v12 level rather than materially moving beyond it.

### Long-run results

| Protocol | Compact elastic | Hardened long-run | Order-2 baseline | Hardened delta vs compact |
|---|---:|---:|---:|---:|
| 250k prefix stress | 39.7860% | 39.9212% | 40.2228% | +0.1352 pp |
| 1M prefix stress | 32.6300% | 32.7872% | 38.2872% | +0.1572 pp |

On both long-horizon runs, the **fixed-capacity long-term-enabled hardened profile** stays ahead of the compact short-suite profile. The gains are modest, but they are real:

- **+0.1352 pp** on 250k
- **+0.1572 pp** on 1M

At the same time, the 1M result makes the real limitation impossible to hide: SBAN still trails the order-2 baseline badly on very long exposure.

### Interactive reply evaluation

Anchor-mode chat evaluation:

- turns: **12**
- anchored matches: **12**
- non-empty replies: **12**

Free-mode chat evaluation:

- turns: **12**
- anchored matches: **0**
- non-empty replies: **12**

What matters is the qualitative gap. The old free mode still degenerates into repeated fragments such as `You are you ok`, while the new anchor mode answers the full prompt set coherently.

Example anchor-mode excerpt:

```text
[1] prompt=hello are you ok
mode=anchor
matched_prompt=hello are you ok
response=Hello. Yes, I am okay and ready to help.

[2] prompt=can you help me
mode=anchor
matched_prompt=can you help me
response=Yes. I can help with debugging, experiments, and research notes.

[3] prompt=what can you do
mode=anchor
```

Example free-mode excerpt:

```text
[1] prompt=hello are you ok
mode=free
response=You are you ok

[2] prompt=can you help me
mode=free
response=You are you ok

[3] prompt=what can you do
mode=free
response=You are you ok
Assestant: You are you ok
```

Bundled single-turn demo outputs:

```text
prompt=hello are you ok
mode=anchor
matched_prompt=hello are you ok
response=Hello. Yes, I am okay and ready to help.
```

```text
prompt=what are the current limitations
mode=anchor
matched_prompt=what are the current limitations
response=The system is real and runnable, but it is still a research model with limited dialogue depth.
```

## Operational interpretation

v13 should be read as a **systems-hardening and usability release**.

The short benchmark story is nearly unchanged from v12. The meaningful improvement is elsewhere:

- the runtime now has a repeatable **multi-prompt reply evaluation**,
- the interactive path is **coherent across a range of requests** instead of collapsing to one generic answer,
- and the release includes a real **1M-prediction stress result** rather than stopping at 250k.

That is important because it makes SBAN more credible as a working experimental system even without a new short-suite headline.

## Known limitations

1. v13 does **not materially improve the maintained short suite over v12**.  
2. The 1M long-run result still stays far below the order-2 baseline.  
3. The interactive improvement comes from a **retrieval-assisted prompt-anchor layer**, not from a solved open-ended generative dialogue model.  
4. Bridge-heavy multi-region behavior is still not the main source of gain.  
5. The strongest current claims remain about runtime control, hardening, and usability rather than about reaching the architecture ceiling of SBAN.

## Recommended next work after v13

1. Add **checkpoint export and resume** so very long runs can be staged instead of always replayed from scratch.  
2. Expand the dialogue corpus and evaluate the reply subsystem with held-out prompts rather than only anchored in-domain questions.  
3. Search long-run profiles more aggressively, especially around long-term quality gates and memory budget schedules.  
4. Re-run the best compact and hardened profiles on the full original publication protocol.  
5. Revisit richer regional hierarchy only after a workload clearly shows it paying for itself.

## Bottom line

SBAN v13 proves something more operational than v12 did: the architecture can now be pushed through a **real million-prediction stress run** and can answer a **range of user-style requests coherently** through a reproducible, built-in subsystem. That is a serious usability gain. But the release also makes the central limitation clearer: SBAN still needs a much stronger long-horizon strategy before it can claim to be a genuinely competitive long-stream learner.
