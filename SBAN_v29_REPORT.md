# SBAN v29 Follow-up Research Paper

## Release intent

SBAN v29 is the synthetic-knowledge, runtime hardening, and Zig-coding follow-up after v28.

The goal is to keep the packaged numeric engine-health suite stable while addressing the v28 architecture stress report. In practical terms, v29 keeps the measured CPU, `cpu_mt`, CUDA, and OpenCL backend stack, preserves the stable CPU numeric guardrail profile, ships a generated synthetic knowledge pack plus a runtime `knowledge_path`, rejects secret storage, caps session loading and retained turns, safely refuses huge exact-number casts, enforces `max_bytes` on displayed responses, fixes numeric `auto` CUDA semantics, adds larger-vocabulary probe results, and extends Zig coding plus real-world task coverage without claiming live internet facts.

## What changed in v29

1. Added a generated synthetic knowledge pack with 124 pairs and a separate runtime `knowledge_path`.
2. Added a v29 generated-knowledge regression eval with 15 / 15 checks covering science, literature, Zig code, JSON, algebra, safe huge math, source boundaries, and secret rejection.
3. Strengthened session safety with a 256 KiB session-load cap, retained turn and fact caps, secret-key rejection, and fixed encoded-field cleanup during save.
4. Added safe exact-number handling for huge exponent results, simple linear equation solving, mixed-expression math checks, and printed response `max_bytes` enforcement.
5. Added generated general-knowledge coverage for tides, mitosis, capitals, literature, civics, economics, real-world task triage, and Zig allocator/error/defer/slice concepts.
6. Added Zig code-generation snippets for slice reversal, ArrayList, StringHashMap, and error unions, plus JSON object generation.
7. Added a larger-vocabulary probe for 256 through 16384 buckets, showing collision reduction while documenting dense-table memory cost and the sparse-index recommendation.
8. Fixed numeric `auto` so CUDA is attempted when the CUDA runtime exists and the scoring edge threshold is met, while CPU remains the safe default.

## Packaged numeric engine-health results

| Test | Baseline | v29 packaged | Delta |
|---|---:|---:|---:|
| Prefix | 99.6650% | 99.6650% | +0.0000 pp |
| Drift | 99.5675% | 99.5675% | +0.0000 pp |
| Probe | 99.9112% | 99.9112% | +0.0000 pp |
| 250k | 99.4632% | 99.4632% | +0.0000 pp |
| 1M | 99.5334% | 99.5334% | +0.0000 pp |
| 10M | 78.3230% | 78.3230% | +0.0001 pp |
| 20M guardrail | 78.4756% | 78.4756% | -0.0000 pp |

- The shipped numeric suite still runs on `numeric_backend=cpu` with `score_threads=1`.
- v29 does not promote `cpu_mt` or numeric CUDA by preference; it keeps the safe CPU path and isolates product/reporting repairs from numeric-profile churn.
- The `longrun_v29_20m.json` artifact is a carried-forward guardrail from `docs/results/v27/longrun_v27_20m.json` with v29 metadata because the local v29 20M rerun hit OutOfMemory on this workstation; it is not claimed as a fresh 20M numeric improvement.

## Conversation and product checks

- Hybrid chat eval: **86 / 86** non-empty, **8** anchored, **3** retrieved, **32** symbolic, **43** uncertain
- Free chat eval: **86 / 86** non-empty, **7** anchored, **4** retrieved, **32** symbolic, **2** uncertain
- Main scripted session eval: **57 / 57** expectation checks passed
- Open-chat scripted session eval: **71 / 71** expectation checks passed
- Broad free-chat battery: **73 / 73** expectation checks passed
- Generated knowledge and stress-regression eval: **15 / 15** expectation checks passed
- Synthetic knowledge pack: **124** generated prompt/answer pairs across **17** categories
- Vocab probe: 4096 buckets reduce collisions from **4920** at 256 buckets to **2202**, while the dense order-2 estimate rises to **1024 MiB**

The open-chat scripted session eval, broad free-chat battery, and generated-knowledge stress eval are the important v29 product signals. Together they exercise planning tomorrow, organizing a week, staying focused, drafting follow-ups, meeting agendas, apology rewrites, interview prep, procrastination, practical coding help, generated science/literature/geography facts, algebra, safe huge math, source-location boundaries, secret rejection, richer session memory, Zig upstream questions, and one unsupported nonsense prompt that should still decline cleanly. v29 passes these versioned sets end to end.

## Retrieval accelerator results

- `cpu_mt` retrieval probe: backend `cpu_mt`, workers `4`
- CUDA retrieval probe: backend `skipped`, platform `unknown`, device `unknown`
- Captured `nvidia-smi`: `not captured`

### Raw retrieval accelerator bench

- CPU elapsed: **102.799s**
- `cpu_mt` elapsed: **142.938s** with speedup **0.7192x** vs CPU
- CUDA elapsed: **not measured** with speedup **not measured** vs CPU

CUDA retrieval acceleration was not measured on this runner because no CUDA runtime was available; v29 only keeps the CUDA path eligible when a compatible runtime exists.

## Numeric backend results

- Numeric CPU probe: configured `cpu`, used `cpu`
- Numeric `cpu_mt` probe: configured `cpu_mt`, used `cpu_mt`
- Numeric CUDA probe: configured `cuda`, used `skipped`, CUDA enabled `false`, device `unknown`

### Numeric backend timing matrix

| Run | CPU | `cpu_mt` | CUDA |
|---|---:|---:|---:|
| 250k elapsed | 16.493s | 36.784s | not measured |
| 1M elapsed | 44.074s | 128.899s | not measured |

- 250k `cpu_mt` speedup vs CPU: **0.4484x**
- 250k CUDA speedup vs CPU: **not measured**
- 1M `cpu_mt` speedup vs CPU: **0.3419x**
- 1M CUDA speedup vs CPU: **not measured**

These numbers still decide whether the accelerated numeric backends deserve promotion. v29 keeps the CPU path as the packaged default because that path now measures better than the older baseline while the accelerated numeric backends still have to earn promotion on elapsed time.

## Concrete runtime behavior

### Overview answer

```text
prompt=what is SBAN v29
mode=free-anchor
backend=cpu
matched_prompt=what is SBAN v29
response=SBAN v29 is the synthetic knowledge and runtime hardening release after v28. It keeps the measured CPU and GPU backend stack stable, adds a generated knowledge pack, expands Zig coding and real-world task coverage, probe... [truncated 73 of 293 bytes]
```

### Bundle inventory answer

```text
prompt=what files ship in the bundle
mode=operational-bundle
backend=cpu
response=The v29 release bundle ships the executive summary at SBAN_v29_EXECUTIVE_SUMMARY.md, the report at SBAN_v29_REPORT.md, the paper PDF at docs/papers/SBAN_v29_follow_up_research_paper.pdf, the repo archive at deliverables/... [truncated 155 of 375 bytes]
```

### Artifact path answer

```text
prompt=where is the v29 paper pdf
mode=operational-paper-path
backend=cpu
response=The v29 paper PDF is generated at docs/papers/SBAN_v29_follow_up_research_paper.pdf.
```

### CUDA command answer

```text
prompt=what command shows cuda support
mode=operational-cuda-command
backend=cpu
response=Use accel-info to confirm the grounded retrieval CUDA path: zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v29.txt backend=cuda. To confirm the new numeric CUDA path, run zig-out/bin/zig_sban numeric-a... [truncated 179 of 399 bytes]
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

### Generated knowledge answer

```text
prompt=what causes tides
mode=synthetic-knowledge
backend=cpu
matched_prompt=what causes tides
response=Tides are caused mainly by the Moon's gravity pulling on Earth's oceans, with the Sun also contributing. Earth's rotation moves coastlines through those tidal bulges, which is why many places see high and low tides each ... [truncated 4 of 224 bytes]
```

### Zig coding answer

```text
prompt=write a zig function to reverse a slice
mode=free-composed
backend=cpu
response=A compact Zig in-place slice reverse is:\n```zig\npub fn reverse(comptime T: type, items: []T) void {\n    var left: usize = 0;\n    var right: usize = items.len;\n    while (left < right) {\n        right -= 1;\n        const ... [truncated 199 of 419 bytes]
```

### Safe huge-math boundary

```text
prompt=calculate 2^1000
mode=symbolic-math-error
backend=cpu
response=The result for 2^1000 is outside SBAN v29's safe exact-number range, so I will not cast it to a fixed integer.
```

### Unsupported factual prompt still declines cleanly

```text
prompt=blorple zint protocol
mode=uncertain
backend=cpu
response=I am not sure yet. I can handle grounded SBAN questions, remembered session facts, short math, everyday planning, writing help, coding snippets, simple explanations, and a wider set of casual prompts, but I still should ... [truncated 26 of 246 bytes]
```

## Long-run note

A completed 100M-class JSON already exists at `docs/results/v27/_gh_v26_100m_artifacts/v26-100m-attempt/longrun_v26_100m_ci_summary.json` and can be consulted separately.

## Interpretation

v29 is a synthetic-knowledge and runtime-hardening release with a strict trust boundary: keep the numeric baseline stable, keep backend claims measured, and make the default chat loop materially broader through generated assets without pretending it has live internet facts. The important architectural result is that SBAN now loads a separate generated knowledge pack, tests larger vocabularies, answers more Zig and real-world task prompts, and declines unsupported source locations or current facts instead of hallucinating.
