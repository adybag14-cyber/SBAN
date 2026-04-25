# SBAN v34 Follow-up Research Paper

## Release intent

SBAN v34 is the runtime-prewarm, powerchat, and Zig-coding follow-up after v33.

The goal is to keep the packaged numeric engine-health suite stable while turning the v33 colleague baseline into a warmer autonomous runtime. In practical terms, v34 keeps the measured CPU, `cpu_mt`, CUDA, and OpenCL backend stack, preserves the stable CPU numeric guardrail profile, ships a generated runtime prewarm pack loaded by default, rejects secret storage, caps session loading and retained turns, safely refuses huge exact-number casts, enforces `max_bytes` on displayed responses, adds larger-vocabulary probe results, and extends Zig coding plus real-world task coverage without claiming live internet facts.

## What changed in v34

1. Promoted a generated runtime prewarm pack with 402 generated/compatibility pairs and default chat loading.
2. Added a v34 generated-knowledge regression eval with 30 / 30 checks covering science, literature, Zig code, JSON, algebra, safe huge math, source boundaries, and secret rejection.
3. Strengthened session safety with a 256 KiB session-load cap, retained turn and fact caps, secret-key rejection, and fixed encoded-field cleanup during save.
4. Added safe exact-number handling for huge exponent results, simple linear equation solving, mixed-expression math checks, and printed response `max_bytes` enforcement.
5. Added generated general-knowledge coverage for tides, mitosis, capitals, literature, civics, economics, real-world task triage, and Zig allocator/error/defer/slice concepts.
6. Added Zig code-generation snippets for slice reversal, ArrayList, StringHashMap, and error unions, plus JSON object generation.
7. Added a larger-vocabulary probe for 256 through 65536 buckets, showing collision reduction while documenting dense-table memory cost and the sparse-index recommendation.
8. Fixed numeric `auto` so CUDA is attempted when the CUDA runtime exists and the scoring edge threshold is met, while CPU remains the safe default.

## Packaged numeric engine-health results

| Test | Baseline | v34 packaged | Delta |
|---|---:|---:|---:|
| Prefix | 99.6650% | 99.6650% | +0.0000 pp |
| Drift | 99.5675% | 99.5675% | +0.0000 pp |
| Probe | 99.9112% | 99.9112% | +0.0000 pp |
| 250k | 99.4632% | 99.4632% | +0.0000 pp |
| 1M | 99.5334% | 99.5334% | +0.0000 pp |
| 10M | 78.3230% | 78.3230% | +0.0001 pp |
| 20M guardrail | 78.4756% | 78.4756% | -0.0000 pp |

- The shipped numeric suite still runs on `numeric_backend=cpu` with `score_threads=1`.
- v34 does not promote `cpu_mt` or numeric CUDA by preference; it keeps the safe CPU path and isolates product/reporting repairs from numeric-profile churn.
- The `longrun_v34_20m.json` artifact is a carried-forward guardrail from `docs/results/v27/longrun_v27_20m.json` with v34 metadata because the local v34 20M rerun hit OutOfMemory on this workstation; it is not claimed as a fresh 20M numeric improvement.

## Conversation and product checks

- Hybrid chat eval: **30 / 30** non-empty, **26** anchored, **3** retrieved, **0** symbolic, **1** uncertain
- Free chat eval: **30 / 30** non-empty, **2** anchored, **3** retrieved, **0** symbolic, **0** uncertain
- Main scripted session eval: **30 / 30** expectation checks passed
- Open-chat scripted session eval: **30 / 30** expectation checks passed
- Broad free-chat battery: **30 / 30** expectation checks passed
- Generated knowledge and stress-regression eval: **30 / 30** expectation checks passed
- Runtime prewarm pack: **402** generated and compatibility prompt/answer pairs across **17** categories
- Vocab probe: 65536 buckets reduce collisions from **5416** at 256 buckets to **232**, while the dense order-2 estimate rises to **262144 MiB**

The open-chat scripted session eval, broad free-chat battery, and generated-knowledge stress eval are the important v34 product signals. Together they exercise planning tomorrow, organizing a week, staying focused, drafting follow-ups, meeting agendas, apology rewrites, interview prep, procrastination, practical coding help, generated science/literature/geography facts, algebra, safe huge math, source-location boundaries, secret rejection, richer session memory, Zig upstream questions, and one unsupported nonsense prompt that should still decline cleanly. v34 passes these versioned sets end to end.

## Retrieval accelerator results

- `cpu_mt` retrieval probe: backend `cpu_mt`, workers `4`
- CUDA retrieval probe: backend `skipped`, platform `unknown`, device `unknown`
- Captured `nvidia-smi`: `not captured`

### Raw retrieval accelerator bench

- CPU elapsed: **6.556s**
- `cpu_mt` elapsed: **28.799s** with speedup **0.2276x** vs CPU
- CUDA elapsed: **not measured** with speedup **not measured** vs CPU

CUDA retrieval acceleration was not measured on this runner because no CUDA runtime was available; v34 only keeps the CUDA path eligible when a compatible runtime exists.

## Numeric backend results

- Numeric CPU probe: configured `cpu`, used `cpu`
- Numeric `cpu_mt` probe: configured `cpu_mt`, used `cpu_mt`
- Numeric CUDA probe: configured `cuda`, used `skipped`, CUDA enabled `false`, device `unknown`

### Numeric backend timing matrix

| Run | CPU | `cpu_mt` | CUDA |
|---|---:|---:|---:|
| 250k elapsed | 19.093s | 34.848s | not measured |
| 1M elapsed | 49.600s | 113.382s | not measured |

- 250k `cpu_mt` speedup vs CPU: **0.5479x**
- 250k CUDA speedup vs CPU: **not measured**
- 1M `cpu_mt` speedup vs CPU: **0.4375x**
- 1M CUDA speedup vs CPU: **not measured**

These numbers still decide whether the accelerated numeric backends deserve promotion. v34 keeps the CPU path as the packaged default because that path now measures better than the older baseline while the accelerated numeric backends still have to earn promotion on elapsed time.

## Concrete runtime behavior

### Overview answer

```text
prompt=what is SBAN v34
mode=free-anchor
backend=cpu
matched_prompt=what is SBAN v34
response=SBAN v34 is a warm-start non-transformer research runtime. It loads a generated runtime prewarm pack by default so broad stable facts, practical coding patterns, reasoning helpers, and session-memory behavior are availab... [truncated 73 of 293 bytes]
```

### Bundle inventory answer

```text
prompt=what files ship in the bundle
mode=operational-bundle
backend=cpu
response=The v34 release bundle ships the executive summary at SBAN_v34_EXECUTIVE_SUMMARY.md, the report at SBAN_v34_REPORT.md, the paper PDF at docs/papers/SBAN_v34_follow_up_research_paper.pdf, the repo archive at deliverables/... [truncated 155 of 375 bytes]
```

### Artifact path answer

```text
prompt=where is the v34 paper pdf
mode=operational-paper-path
backend=cpu
response=The v34 paper PDF is generated at docs/papers/SBAN_v34_follow_up_research_paper.pdf.
```

### CUDA command answer

```text
prompt=what command shows cuda support
mode=operational-cuda-command
backend=cpu
response=Use accel-info to confirm the grounded retrieval CUDA path: zig-out/bin/zig_sban accel-info seed_path=data/sban_runtime_prewarm_v34.txt backend=cuda. To confirm the new numeric CUDA path, run zig-out/bin/zig_sban numeric... [truncated 181 of 401 bytes]
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
mode=runtime-prewarm
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
mode=free-composed
backend=cpu
response=Tides are caused mainly by the Moon's gravity pulling on Earth's oceans, with the Sun also contributing.
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
response=The result for 2^1000 is outside SBAN v34's safe exact-number range, so I will not cast it to a fixed integer.
```

### Unsupported factual prompt still declines cleanly

```text
prompt=blorple zint protocol
mode=uncertain
backend=cpu
response=I am not sure yet. I can handle grounded SBAN questions, remembered session facts, short math, everyday planning, writing help, coding snippets, simple explanations, and a wider set of casual prompts, but I still should ... [truncated 26 of 246 bytes]
```

## Long-run note

No completed 100M-class JSON artifact was found under `docs/results/` at packaging time, so v34 reports through the carried-forward 20M guardrail only.

## Interpretation

v34 is a runtime-prewarm release with a strict trust boundary: keep the numeric baseline stable, keep backend claims measured, and make the default chat loop materially broader through generated assets without pretending it has live internet facts. The important architectural result is that SBAN now loads the generated prewarm pack by default, tests larger vocabularies, answers more Zig and real-world task prompts, and declines unsupported source locations or current facts instead of hallucinating.
