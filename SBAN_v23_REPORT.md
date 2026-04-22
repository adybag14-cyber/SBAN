# SBAN v23 Follow-up Research Paper

## Release intent

SBAN v23 is the conversational repair release after v22.5.

The point of v23 is not another numeric leap. The release keeps the established numeric engine-health suite stable while repairing the actual product runtime: a real v23 chat seed, broader operational and hardware coverage, safer retrieval on paraphrases, stronger natural session memory, and a default free-chat loop that is no longer just hybrid retrieval with generation disabled.

## What changed in v23

1. Replaced the stale v22.5 dialogue asset with a real `data/sban_dialogue_seed_v23.txt` seed that knows the v23 starter files, artifact paths, release inventory, CUDA commands, backend comparisons, and roadmap stance.
2. Tightened retrieval with semantic guards so hardware prompts and artifact questions do not overmatch unrelated benchmark blurbs.
3. Broadened paraphrase coverage through new seed entries plus stronger lexical canonicalization for change, compare, launch, command, overview, bundle, path, and hardware wording.
4. Upgraded session memory extraction so natural phrases like `i am from london` and `i work in the sbx lab` are stored correctly instead of being misread as names or ignored.
5. Replaced the old unsafe-feeling free-chat fallback with constrained conversational synthesis for greetings, identity, thanks, light small talk, and other safe prompts.
6. Kept the real CUDA path, cpu-mt retrieval path, accelerator bench, and experimental numeric multithread probe from v22.5, and revalidated them after the local NVIDIA driver update.

## Numeric engine-health results

| Test | V22.5 baseline | V23 packaged | Delta |
|---|---:|---:|---:|
| Prefix | 99.6350% | 99.6350% | +0.0000 pp |
| Drift | 99.5400% | 99.5400% | +0.0000 pp |
| Probe | 99.9000% | 99.9000% | +0.0000 pp |
| 250k | 99.4076% | 99.4076% | +0.0000 pp |
| 1M | 99.4344% | 99.4344% | +0.0000 pp |
| 10M | 77.9175% | 77.9175% | +0.0000 pp |

- The shipped numeric suite still stays on `score_threads=1`.

## Chat and product results

- Hybrid chat eval: **42 / 42** non-empty, **17** anchored, **0** retrieved, **21** symbolic
- Free chat eval: **42 / 42** non-empty, **17** anchored, **0** retrieved, **21** symbolic
- Scripted session eval: **21 / 21** expectation checks passed

The free-chat path is the main user-facing improvement. It can now answer operational questions about files and commands, handle a few safe open-domain prompts, and keep more natural session facts without regressing into stale v22 paths.

## Accelerator results

- `cpu_mt` accel-info: backend `cpu_mt`, workers `4`
- CUDA accel-info: backend `cuda`, platform `NVIDIA CUDA`, device `NVIDIA GeForce RTX 2080 Super with Max-Q Design`
- Captured `nvidia-smi`: `NVIDIA GeForce RTX 2080 Super with Max-Q Design, 596.21`

### Raw retrieval accelerator bench

- CPU elapsed: **46.744s**
- `cpu_mt` elapsed: **46.255s** with speedup **1.0106x** vs CPU
- CUDA elapsed: **7.228s** with speedup **6.4667x** vs CPU

CUDA remains the preferred large-corpus retrieval accelerator on this NVIDIA system. The driver update did not break the CUDA probe or the raw accelerator path.

### Numeric backend probe

- 250k single-thread elapsed: **16.156s**
- 250k mt4 elapsed: **15.990s**
- 1M single-thread elapsed: **43.441s**
- 1M mt4 elapsed: **43.926s**

The multithreaded numeric path is still available for experiments, but it does not yet earn default release status.

## Concrete behavior

### Overview

```text
prompt=what is SBAN v23
mode=free-anchor
backend=cpu
matched_prompt=what is SBAN v23
response=SBAN v23 is the conversational repair release. It keeps the established numeric engine-health suite stable while shipping a real v23 chat seed, broader paraphrase coverage, safer hardware-aware retrieval, stronger natural session memory, and a default free-chat loop that behaves more like a calm collaborator than a scripted demo.
```

### Artifact path answer

```text
prompt=where is the v23 paper pdf
mode=operational-paper-path
backend=cpu
response=The v23 paper PDF is generated at docs/papers/SBAN_v23_follow_up_research_paper.pdf.
```

### CUDA command answer

```text
prompt=what command shows cuda support
mode=operational-cuda-command
backend=cpu
response=Use accel-info to confirm CUDA support: zig-out/bin/zig_sban accel-info seed_path=data/sban_dialogue_seed_v23.txt backend=cuda. If you want raw retrieval throughput after that, run accel-bench with backend=cuda against the versioned v23 bench assets.
```

### RTX support answer

```text
prompt=can this run on an rtx 4090
mode=operational-rtx-support
backend=cpu
response=Yes. NVIDIA RTX cards such as the RTX 4090 should use backend=cuda for the retrieval accelerator path. CPU remains the fallback, and OpenCL is still the generic GPU fallback when CUDA is unavailable.
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

V23 is the release where SBAN's chat runtime finally stops feeling like a narrowly seeded retrieval demo. It still does not pretend to have broad transformer-style world knowledge, but it now answers more of its own operational questions correctly, carries more natural session facts across turns, avoids obvious retrieval overmatches, and handles a useful slice of free conversation without losing its grounding discipline.
