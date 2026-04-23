# SBAN v24 Follow-up Research Paper

## Release intent

SBAN v24 is the conversational product release after v23.5.

The goal is to keep the packaged numeric engine-health suite locked to the proven CPU baseline while repairing the broader user-facing limitation that earlier releases were still too narrow in free chat. In practical terms, v24 keeps the measured CPU, `cpu_mt`, CUDA, and OpenCL backend stack, but ships a real v24 grounded seed, a separate v24 open-chat seed, broader operational answers, stronger session-memory behavior, and a free-chat surface that can handle a much wider set of ordinary prompts without drifting into stale release blurbs or blanket decline behavior.

## What changed in v24

1. Replaced the stale version-mixed chat seed with a real v24 grounded seed that reflects the current release, current starter files, current artifact paths, and current backend commands.
2. Added a separate curated v24 open-chat seed so broader casual conversation is supported without inheriting unsafe human-persona answers from raw dialogue data.
3. Tightened retrieval and operational routing so bundle inventory, paper or report paths, CUDA commands, RTX prompts, and roadmap prompts no longer overmatch each other.
4. Kept the continuing-session persistence and memory safety work, but improved the user-facing memory behavior around capability questions and natural fact storage.
5. Added a versioned open-chat scripted session evaluation so broader free chat is measured directly instead of being inferred from the grounded prompt set.
6. Re-ran the full numeric guardrail suite plus the backend probes and retrieval accelerator bench after the NVIDIA driver update.

## Packaged numeric engine-health results

| Test | Baseline | V24 packaged | Delta |
|---|---:|---:|---:|
| Prefix | 99.6350% | 99.6350% | +0.0000 pp |
| Drift | 99.5400% | 99.5400% | +0.0000 pp |
| Probe | 99.9000% | 99.9000% | +0.0000 pp |
| 250k | 99.4076% | 99.4076% | +0.0000 pp |
| 1M | 99.4344% | 99.4344% | +0.0000 pp |
| 10M | 77.9175% | 77.9175% | +0.0000 pp |

- The shipped numeric suite still runs on `numeric_backend=cpu` with `score_threads=1`.
- That preserves the original regression baseline while the newer backends remain measured explicitly rather than promoted by preference.

## Conversation and product checks

- Hybrid chat eval: **51 / 51** non-empty, **20** anchored, **0** retrieved, **25** symbolic, **6** uncertain
- Free chat eval: **51 / 51** non-empty, **20** anchored, **0** retrieved, **25** symbolic, **1** uncertain
- Main scripted session eval: **27 / 27** expectation checks passed
- Open-chat scripted session eval: **21 / 21** expectation checks passed

The open-chat scripted session eval is the important new product signal. It exercises ordinary prompts such as planning tomorrow, organizing a week, staying focused, drafting a follow-up, brainstorming names, handling stress, weekend planning, cooking questions, casual preference boundaries, session memory, and one unsupported factual question that should still decline cleanly. V24 passes that versioned open-chat set end to end.

## Retrieval accelerator results

- `cpu_mt` retrieval probe: backend `cpu_mt`, workers `4`
- CUDA retrieval probe: backend `cuda`, platform `NVIDIA CUDA`, device `NVIDIA GeForce RTX 2080 Super with Max-Q Design`
- Captured `nvidia-smi`: `NVIDIA GeForce RTX 2080 Super with Max-Q Design, 596.21`

### Raw retrieval accelerator bench

- CPU elapsed: **71.851s**
- `cpu_mt` elapsed: **86.765s** with speedup **0.8281x** vs CPU
- CUDA elapsed: **9.281s** with speedup **7.7416x** vs CPU

CUDA remains the preferred large-corpus retrieval accelerator on this NVIDIA system.

## Numeric backend results

- Numeric CPU probe: configured `cpu`, used `cpu`
- Numeric `cpu_mt` probe: configured `cpu_mt`, used `cpu_mt`
- Numeric CUDA probe: configured `cuda`, used `cuda`, CUDA enabled `true`, device `NVIDIA GeForce RTX 2080 Super with Max-Q Design`

### Numeric backend timing matrix

| Run | CPU | `cpu_mt` | CUDA |
|---|---:|---:|---:|
| 250k elapsed | 21.825s | 19.225s | 76.214s |
| 1M elapsed | 46.805s | 46.081s | 275.225s |

- 250k `cpu_mt` speedup vs CPU: **1.1353x**
- 250k CUDA speedup vs CPU: **0.2864x**
- 1M `cpu_mt` speedup vs CPU: **1.0157x**
- 1M CUDA speedup vs CPU: **0.1701x**

These numbers still decide whether the accelerated numeric backends deserve promotion. V24 keeps the old CPU fallback as the packaged default unless the measured end-to-end suite actually wins.

## Concrete runtime behavior

### Overview answer

```text
prompt=what is SBAN v24
mode=free-anchor
backend=cpu
matched_prompt=what is SBAN v24
response=SBAN v24 is the conversational product release after v23.5. It keeps the numeric engine-health suite stable, preserves the measured CPU and GPU backend stack, and upgrades the shipped chat surface so free mode is broader, less brittle, and more useful for ordinary conversation.
```

### Bundle inventory answer

```text
prompt=what files ship in the bundle
mode=operational-bundle
backend=cpu
response=The v24 release bundle ships the executive summary at SBAN_v24_EXECUTIVE_SUMMARY.md, the report at SBAN_v24_REPORT.md, the paper PDF at docs/papers/SBAN_v24_follow_up_research_paper.pdf, the repo archive at deliverables/v24/SBAN_v24_repo.zip, and demo bundles at deliverables/v24/demo/SBAN_v24_windows_x86_64_demo.zip and deliverables/v24/demo/SBAN_v24_linux_x86_64_demo.zip.
```

### Artifact path answer

```text
prompt=where is the v24 paper pdf
mode=operational-paper-path
backend=cpu
response=The v24 paper PDF is generated at docs/papers/SBAN_v24_follow_up_research_paper.pdf.
```

### CUDA command answer

```text
prompt=what command shows cuda support
mode=operational-cuda-command
backend=cpu
response=Use accel-info to confirm the grounded retrieval CUDA path: zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v24.txt backend=cuda. To confirm the new numeric CUDA path, run zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1. If you want raw retrieval throughput after that, run accel-bench with backend=cuda against the versioned v24 bench assets.
```

### Session-memory capability answer

```text
prompt=can you remember where i am from
mode=session-memory-capability
backend=cpu
response=Yes. Tell me where you live or where you are from, and I will remember it for this session.
```

### Planning answer

```text
prompt=can you help me plan tomorrow
mode=free-composed
backend=cpu
response=Yes. Start with the fixed commitments, then pick the top few outcomes that matter most, and block time for those before the smaller tasks spread everywhere.
```

### Weekend planning answer

```text
prompt=what should i do this weekend
mode=free-open-retrieved
backend=cpu
matched_prompt=what should i do this weekend
response=Pick one restful thing, one useful thing, and one social or fun thing. That usually gives the weekend some shape without overscheduling it.
```

### Unsupported factual prompt still declines cleanly

```text
prompt=blorple zint protocol
mode=uncertain
backend=cpu
response=I am not sure yet. I can handle grounded SBAN questions, remembered session facts, short math, everyday planning, writing help, and a wider set of casual prompts, but I still should not improvise beyond that.
```

## Interpretation

V24 is a product release with a strict trust boundary: keep the numeric baseline honest, keep the backend claims measured, and make the default chat loop materially more useful without pretending it is a broad general knowledge model. The important architectural result is not just that SBAN answers its own artifact questions correctly now; it is that the release ships a broader conversational surface, versioned conversational evaluations, and a calmer free-chat path that still declines unsupported factual prompts instead of hallucinating.
