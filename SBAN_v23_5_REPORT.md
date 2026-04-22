# SBAN v23.5 Follow-up Research Paper

## Release intent

SBAN v23.5 is the technical backend upgrade after v23.

The goal is to keep the packaged numeric engine-health suite locked to the proven CPU baseline while extending measured CUDA support deeper into the runtime. In practical terms, v23.5 keeps the v23 conversational surface, preserves the regression-safe `numeric_backend=cpu` release profile, adds a real numeric CUDA backend for `eval-variant` experimentation, exposes a `numeric-accel-info` probe command, and measures CPU versus `cpu_mt` versus CUDA on both the dialogue retrieval path and the numeric scoring path.

## What changed in v23.5

1. Added a numeric scoring backend selector in `src/network.zig` so the runtime can choose `cpu`, `cpu_mt`, or `cuda` for predictive output scoring without changing the learning semantics.
2. Added a dedicated sparse numeric CUDA kernel in `src/numeric_cuda.zig` and kept CPU fallback automatic when CUDA is unavailable or not selected.
3. Preserved the original single-thread CPU path as the packaged release baseline and regression reference.
4. Added `numeric-accel-info` in `src/main.zig` so the numeric path can report whether it actually sees and uses the requested backend.
5. Re-versioned the shipped dialogue assets and demo bundle to `v23.5` so the release no longer reports stale v23 file names.
6. Re-ran the original numeric suite, the v23 conversation checks, the dialogue retrieval accelerator bench, and a new numeric backend comparison matrix after the local NVIDIA driver update.

## Packaged numeric engine-health results

| Test | Baseline | V23.5 packaged | Delta |
|---|---:|---:|---:|
| Prefix | 99.6350% | 99.6350% | +0.0000 pp |
| Drift | 99.5400% | 99.5400% | +0.0000 pp |
| Probe | 99.9000% | 99.9000% | +0.0000 pp |
| 250k | 99.4076% | 99.4076% | +0.0000 pp |
| 1M | 99.4344% | 99.4344% | +0.0000 pp |
| 10M | 77.9175% | 77.9175% | +0.0000 pp |

- The shipped numeric suite still runs on `numeric_backend=cpu` with `score_threads=1`.
- That preserves the original regression baseline while the newer backends are measured separately.

## Conversation and product checks

- Hybrid chat eval: **47 / 47** non-empty, **21** anchored, **0** retrieved, **22** symbolic
- Free chat eval: **47 / 47** non-empty, **21** anchored, **0** retrieved, **22** symbolic
- Scripted session eval: **23 / 23** expectation checks passed

The v23 conversational surface stayed intact while being re-versioned to `v23.5`. The product runtime still answers operational artifact questions, hardware prompts, session-memory prompts, and safe small-talk prompts without regressing into stale paths.

## Retrieval accelerator results

- `cpu_mt` retrieval probe: backend `cpu_mt`, workers `4`
- CUDA retrieval probe: backend `cuda`, platform `NVIDIA CUDA`, device `NVIDIA GeForce RTX 2080 Super with Max-Q Design`
- Captured `nvidia-smi`: `NVIDIA GeForce RTX 2080 Super with Max-Q Design, 596.21`

### Raw retrieval accelerator bench

- CPU elapsed: **49.912s**
- `cpu_mt` elapsed: **53.987s** with speedup **0.9245x** vs CPU
- CUDA elapsed: **8.005s** with speedup **6.2352x** vs CPU

CUDA remains the preferred large-corpus retrieval accelerator on this NVIDIA system.

## Numeric backend results

- Numeric CPU probe: configured `cpu`, used `cpu`
- Numeric `cpu_mt` probe: configured `cpu_mt`, used `cpu_mt`
- Numeric CUDA probe: configured `cuda`, used `cuda`, CUDA enabled `true`, device `NVIDIA GeForce RTX 2080 Super with Max-Q Design`

### Numeric backend timing matrix

| Run | CPU | `cpu_mt` | CUDA |
|---|---:|---:|---:|
| 250k elapsed | 15.956s | 16.031s | 42.959s |
| 1M elapsed | 43.316s | 43.043s | 150.642s |

- 250k `cpu_mt` speedup vs CPU: **0.9953x**
- 250k CUDA speedup vs CPU: **0.3714x**
- 1M `cpu_mt` speedup vs CPU: **1.0064x**
- 1M CUDA speedup vs CPU: **0.2875x**

These numbers decide whether the accelerated numeric backends deserve promotion. The release keeps the old CPU fallback as the default unless the measured end-to-end suite actually wins.

## Concrete runtime behavior

### Overview answer

```text
prompt=what is SBAN v23.5
mode=free-anchor
backend=cpu
matched_prompt=what is SBAN v23.5
response=SBAN v23.5 is the technical backend follow-up to v23. It keeps the established numeric engine-health suite on the proven CPU fallback, preserves the grounded v23 chat surface, and extends CUDA into the numeric output-scoring path so eval-variant can compare CPU, cpu-mt, and RTX-backed scoring honestly.
```

### Artifact path answer

```text
prompt=where is the v23.5 paper pdf
mode=operational-paper-path
backend=cpu
response=The v23.5 paper PDF is generated at docs/papers/SBAN_v23_5_follow_up_research_paper.pdf.
```

### CUDA command answer

```text
prompt=what command shows cuda support
mode=operational-cuda-command
backend=cpu
response=Use accel-info to confirm the grounded retrieval CUDA path: zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v23_5.txt backend=cuda. To confirm the new numeric CUDA path, run zig-out/bin/zig_sban numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1. If you want raw retrieval throughput after that, run accel-bench with backend=cuda against the versioned v23.5 bench assets.
```

### RTX support answer

```text
prompt=can this run on an rtx 4090
mode=operational-rtx-support
backend=cpu
response=Yes. NVIDIA RTX cards such as the RTX 4090 should use backend=cuda for the retrieval accelerator path, and v23.5 also exposes numeric_backend=cuda for eval-variant experimentation. CPU remains the fallback, and OpenCL is still the generic GPU fallback when CUDA is unavailable.
```

### Open-domain joke answer

```text
prompt=tell me a joke
mode=free-composed
backend=cpu
response=Why did the sparse network stay calm? It only activated the paths that actually had support.
```

### Noise prompt still declines cleanly

```text
prompt=blorple zint protocol
mode=uncertain
backend=cpu
response=I am not sure yet. I answer when I have grounded support, a remembered session fact, or a safe conversational rule for the prompt.
```

## Interpretation

V23.5 is a backend release with a strict trust boundary: keep the conversation surface stable, keep the numeric baseline honest, and only promote acceleration where the measurements prove it. The important architectural result is that CUDA is no longer confined to dialogue retrieval; it now reaches the numeric output-scoring stack too, while the original CPU path remains intact as the safe default.
