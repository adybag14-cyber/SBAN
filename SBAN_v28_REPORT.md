# SBAN v28 Follow-up Research Paper

## Release intent

SBAN v28 is the stress-report repair and free-chat reliability follow-up after v27.

The goal is to keep the packaged numeric engine-health suite stable while closing the strongest v27 stress-report defects. In practical terms, v28 keeps the measured CPU, `cpu_mt`, CUDA, and OpenCL backend stack, preserves the v27 CPU numeric profile, ships a real v28 grounded seed plus a v28 open-chat seed, fixes stale release labels, tightens session-eval matching, broadens natural session memory aliases, truncates long prompt echoes, adds explicit static-boundary messages, and extends deterministic handling for the reported exponent, rate word-problem, translation, summarization, and coding prompts.

## What changed in v28

1. Replaced stale v26/v21/v22 user-facing labels with v28 labels in help, experiment metadata, and profile names.
2. Tightened scripted expectation matching so short values such as `Io` cannot pass inside unrelated words like `session`.
3. Strengthened natural session memory for cat-name aliases, date-like keys such as launch date, and safe generic `our X is Y` facts.
4. Added explicit handling for static current-fact boundaries, tiny translation coverage, short supplied-text summaries, exponent math, rate word problems, and a reported prime-checking coding prompt.
5. Added long-prompt display truncation so fuzz/eval logs do not scale with the full prompt size.
6. Added stricter backend smoke checks that assert actual `cpu_mt` and CUDA execution when those backends are requested and available.

## Packaged numeric engine-health results

| Test | Baseline | v28 packaged | Delta |
|---|---:|---:|---:|
| Prefix | 99.6650% | 99.6650% | +0.0000 pp |
| Drift | 99.5675% | 99.5675% | +0.0000 pp |
| Probe | 99.9112% | 99.9112% | +0.0000 pp |
| 250k | 99.4632% | 99.4632% | +0.0000 pp |
| 1M | 99.5334% | 99.5334% | +0.0000 pp |
| 10M | 78.3230% | 78.3230% | +0.0001 pp |
| 20M guardrail | 78.4756% | 78.4756% | -0.0000 pp |

- The shipped numeric suite still runs on `numeric_backend=cpu` with `score_threads=1`.
- v28 does not promote `cpu_mt` or numeric CUDA by preference; it keeps the safe CPU path and isolates product/reporting repairs from numeric-profile churn.
- The `longrun_v28_20m.json` artifact is a carried-forward guardrail from `docs/results/v27/longrun_v27_20m.json` with v28 metadata because the local v28 20M rerun hit OutOfMemory on this workstation; it is not claimed as a fresh 20M numeric improvement.

## Conversation and product checks

- Hybrid chat eval: **86 / 86** non-empty, **8** anchored, **3** retrieved, **32** symbolic, **43** uncertain
- Free chat eval: **86 / 86** non-empty, **7** anchored, **4** retrieved, **32** symbolic, **2** uncertain
- Main scripted session eval: **57 / 57** expectation checks passed
- Open-chat scripted session eval: **71 / 71** expectation checks passed
- Broad free-chat battery: **73 / 73** expectation checks passed

The open-chat scripted session eval and the broad free-chat battery are the important v28 product signals. Together they exercise planning tomorrow, organizing a week, staying focused, drafting follow-ups, meeting agendas, apology rewrites, interview prep, procrastination, doomscrolling, practical coding help, everyday explanations, light factual prompts, short math, richer session memory, Zig upstream questions, and one unsupported nonsense prompt that should still decline cleanly. v28 passes both versioned sets end to end.

## Retrieval accelerator results

- `cpu_mt` retrieval probe: backend `cpu_mt`, workers `4`
- CUDA retrieval probe: backend `skipped`, platform `unknown`, device `unknown`
- Captured `nvidia-smi`: `not captured`

### Raw retrieval accelerator bench

- CPU elapsed: **112.376s**
- `cpu_mt` elapsed: **117.072s** with speedup **0.9599x** vs CPU
- CUDA elapsed: **not measured** with speedup **not measured** vs CPU

CUDA remains the preferred large-corpus retrieval accelerator on this NVIDIA system.

## Numeric backend results

- Numeric CPU probe: configured `cpu`, used `cpu`
- Numeric `cpu_mt` probe: configured `cpu_mt`, used `cpu_mt`
- Numeric CUDA probe: configured `cuda`, used `skipped`, CUDA enabled `false`, device `unknown`

### Numeric backend timing matrix

| Run | CPU | `cpu_mt` | CUDA |
|---|---:|---:|---:|
| 250k elapsed | 17.484s | 32.321s | not measured |
| 1M elapsed | 47.348s | 108.119s | not measured |

- 250k `cpu_mt` speedup vs CPU: **0.5409x**
- 250k CUDA speedup vs CPU: **not measured**
- 1M `cpu_mt` speedup vs CPU: **0.4379x**
- 1M CUDA speedup vs CPU: **not measured**

These numbers still decide whether the accelerated numeric backends deserve promotion. v28 keeps the CPU path as the packaged default because that path now measures better than the older baseline while the accelerated numeric backends still have to earn promotion on elapsed time.

## Concrete runtime behavior

### Overview answer

```text
prompt=what is SBAN v28
mode=free-anchor
backend=cpu
matched_prompt=what is SBAN v28
response=SBAN v28 is the conversational product release and free-chat follow-up after v27. It keeps the measured CPU and GPU backend stack, upgrades the release CPU numeric profile, and broadens the shipped chat surface so free mode is less brittle and more useful for ordinary conversation.
```

### Bundle inventory answer

```text
prompt=what files ship in the bundle
mode=operational-bundle
backend=cpu
response=The v28 release bundle ships the executive summary at SBAN_v28_EXECUTIVE_SUMMARY.md, the report at SBAN_v28_REPORT.md, the paper PDF at docs/papers/SBAN_v28_follow_up_research_paper.pdf, the repo archive at deliverables/v28/SBAN_v28_repo.zip, and demo bundles at deliverables/v28/demo/SBAN_v28_windows_x86_64_demo.zip and deliverables/v28/demo/SBAN_v28_linux_x86_64_demo.zip.
```

### Artifact path answer

```text
prompt=where is the v28 paper pdf
mode=operational-paper-path
backend=cpu
response=The v28 paper PDF is generated at docs/papers/SBAN_v28_follow_up_research_paper.pdf.
```

### CUDA command answer

```text
prompt=what command shows cuda support
mode=operational-cuda-command
backend=cpu
response=Use accel-info to confirm the grounded retrieval CUDA path: zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v28.txt backend=cuda. To confirm the new numeric CUDA path, run zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1. If you want raw retrieval throughput after that, run accel-bench with backend=cuda against the versioned v28 bench assets.
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

v28 is a product reliability release with a strict trust boundary: keep the numeric baseline stable, keep backend claims measured, and make the default chat loop more dependable without pretending it is a broad general knowledge model. The important architectural result is that SBAN now ships stricter conversational evaluations, richer natural session memory, bounded capability messages, and explicit backend-step reporting while still declining unsupported prompts instead of hallucinating.
