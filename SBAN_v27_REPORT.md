# SBAN v27 Follow-up Research Paper

## Release intent

SBAN v27 is the product and free-chat follow-up after v26.

The goal is twofold: push the packaged numeric engine-health suite forward without leaving the safe CPU release path, and make the shipped free-chat surface meaningfully broader on ordinary prompts that previously fell to uncertainty or bad overmatches. In practical terms, v27 keeps the measured CPU, `cpu_mt`, CUDA, and OpenCL backend stack, upgrades the release CPU profile with a stronger continuation setting, ships a real v27 grounded seed plus a larger v27 open-chat seed, broadens operational answers, strengthens natural session memory around project, pet, and tomorrow-style facts, and extends the free-chat surface so common coding, explanation, writing, and planning prompts resolve deterministically instead of drifting.

## What changed in v27

1. Upgraded the packaged CPU numeric release profile with a stronger continuation configuration that improved prefix, drift, probe, 250k, 1M, and 10M while keeping `numeric_backend=cpu` and `score_threads=1` as the shipped fallback path.
2. Shipped a real v27 grounded seed that reflects the current release, starter files, artifact paths, and backend commands.
3. Rebuilt the separate v27 open-chat seed from the v26 base plus broader curated practical prompts and a larger filtered factoid slice.
4. Extended deterministic free-chat support for common coding prompts, practical explanations, professional rewrites, short creative writing, lunch and weekend planning, and safe light-humor prompts.
5. Strengthened natural session memory around project, dog-name, and tomorrow-style facts without regressing earlier location, team, lab, and role behavior.
6. Re-ran the full numeric guardrail suite, the broader conversational batteries, and the measured backend probes and retrieval accelerator bench on the current NVIDIA stack.

## Packaged numeric engine-health results

| Test | Baseline | v27 packaged | Delta |
|---|---:|---:|---:|
| Prefix | 99.6350% | 99.6650% | +0.0300 pp |
| Drift | 99.5400% | 99.5675% | +0.0275 pp |
| Probe | 99.9000% | 99.9112% | +0.0112 pp |
| 250k | 99.4076% | 99.4632% | +0.0556 pp |
| 1M | 99.4344% | 99.5334% | +0.0990 pp |
| 10M | 77.9175% | 78.3230% | +0.4055 pp |
| 20M | n/a | 78.4756% | new |

- The shipped numeric suite still runs on `numeric_backend=cpu` with `score_threads=1`.
- v27 does not promote `cpu_mt` or numeric CUDA by preference; it keeps the safe CPU path while improving that path's actual release profile.
- v27 also extends the hardening ladder to a measured 20M run on the same guarded CPU release path, but that 20M point intentionally falls back to the older bounded continuation setting after the stronger short-suite profile hit `OutOfMemory` at that horizon on this workstation.

## Conversation and product checks

- Hybrid chat eval: **72 / 72** non-empty, **8** anchored, **2** retrieved, **25** symbolic, **37** uncertain
- Free chat eval: **72 / 72** non-empty, **7** anchored, **4** retrieved, **25** symbolic, **2** uncertain
- Main scripted session eval: **43 / 43** expectation checks passed
- Open-chat scripted session eval: **66 / 66** expectation checks passed
- Broad free-chat battery: **63 / 63** expectation checks passed

The open-chat scripted session eval and the broad free-chat battery are the important v27 product signals. Together they exercise planning tomorrow, organizing a week, staying focused, drafting follow-ups, meeting agendas, apology rewrites, interview prep, procrastination, doomscrolling, practical coding help, everyday explanations, light factual prompts, short math, richer session memory, Zig upstream questions, and one unsupported nonsense prompt that should still decline cleanly. v27 passes both versioned sets end to end.

## Retrieval accelerator results

- `cpu_mt` retrieval probe: backend `cpu_mt`, workers `4`
- CUDA retrieval probe: backend `cuda`, platform `NVIDIA CUDA`, device `NVIDIA GeForce RTX 2080 Super with Max-Q Design`
- Captured `nvidia-smi`: `NVIDIA GeForce RTX 2080 Super with Max-Q Design, 596.21`

### Raw retrieval accelerator bench

- CPU elapsed: **85.351s**
- `cpu_mt` elapsed: **82.891s** with speedup **1.0297x** vs CPU
- CUDA elapsed: **12.091s** with speedup **7.0590x** vs CPU

CUDA remains the preferred large-corpus retrieval accelerator on this NVIDIA system.

## Numeric backend results

- Numeric CPU probe: configured `cpu`, used `cpu`
- Numeric `cpu_mt` probe: configured `cpu_mt`, used `cpu_mt`
- Numeric CUDA probe: configured `cuda`, used `cuda`, CUDA enabled `true`, device `NVIDIA GeForce RTX 2080 Super with Max-Q Design`

### Numeric backend timing matrix

| Run | CPU | `cpu_mt` | CUDA |
|---|---:|---:|---:|
| 250k elapsed | 20.420s | 20.323s | 70.822s |
| 1M elapsed | 45.548s | 45.550s | 257.874s |

- 250k `cpu_mt` speedup vs CPU: **1.0048x**
- 250k CUDA speedup vs CPU: **0.2883x**
- 1M `cpu_mt` speedup vs CPU: **1.0000x**
- 1M CUDA speedup vs CPU: **0.1766x**

These numbers still decide whether the accelerated numeric backends deserve promotion. v27 keeps the CPU path as the packaged default because that path now measures better than the older baseline while the accelerated numeric backends still have to earn promotion on elapsed time.

## Concrete runtime behavior

### Overview answer

```text
prompt=what is SBAN v27
mode=free-anchor
backend=cpu
matched_prompt=what is SBAN v27
response=SBAN v27 is the conversational product release and free-chat follow-up after v26. It keeps the measured CPU and GPU backend stack, upgrades the release CPU numeric profile, and broadens the shipped chat surface so free mode is less brittle and more useful for ordinary conversation.
```

### Bundle inventory answer

```text
prompt=what files ship in the bundle
mode=operational-bundle
backend=cpu
response=The v27 release bundle ships the executive summary at SBAN_v27_EXECUTIVE_SUMMARY.md, the report at SBAN_v27_REPORT.md, the paper PDF at docs/papers/SBAN_v27_follow_up_research_paper.pdf, the repo archive at deliverables/v27/SBAN_v27_repo.zip, and demo bundles at deliverables/v27/demo/SBAN_v27_windows_x86_64_demo.zip and deliverables/v27/demo/SBAN_v27_linux_x86_64_demo.zip.
```

### Artifact path answer

```text
prompt=where is the v27 paper pdf
mode=operational-paper-path
backend=cpu
response=The v27 paper PDF is generated at docs/papers/SBAN_v27_follow_up_research_paper.pdf.
```

### CUDA command answer

```text
prompt=what command shows cuda support
mode=operational-cuda-command
backend=cpu
response=Use accel-info to confirm the grounded retrieval CUDA path: zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v27.txt backend=cuda. To confirm the new numeric CUDA path, run zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1. If you want raw retrieval throughput after that, run accel-bench with backend=cuda against the versioned v27 bench assets.
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

### Zig upstream path answer

```text
prompt=where is std.hashmap implemented in zig upstream
mode=free-composed
backend=cpu
response=In the upstream Zig source tree, the generic hash map implementation lives in lib/std/hash_map.zig.
```

### Unsupported factual prompt still declines cleanly

```text
prompt=blorple zint protocol
mode=uncertain
backend=cpu
response=I am not sure yet. I can handle grounded SBAN questions, remembered session facts, short math, everyday planning, writing help, coding snippets, simple explanations, and a wider set of casual prompts, but I still should not improvise beyond that.
```

## Long-run note

A completed 100M-class JSON already exists at `docs/results/v27/_gh_v26_100m_artifacts/v26-100m-attempt/longrun_v26_100m_ci_summary.json` and can be consulted separately.

## Interpretation

v27 is a product release with a strict trust boundary: improve the numeric baseline honestly, keep the backend claims measured, and make the default chat loop materially more useful without pretending it is a broad general knowledge model. The important architectural result is that SBAN now ships a broader conversational surface, versioned conversational evaluations, richer natural session memory, and a measurably stronger CPU numeric profile, while still declining unsupported prompts instead of hallucinating.
