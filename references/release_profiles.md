# SBAN Release Profiles

## Current Baseline for v29 Work

Use the packaged v28 release as the product baseline when testing or extending v29, and keep the v27-derived numeric guardrail profile stable unless the benchmark JSONs prove a better profile end to end.

### Packaged Numeric Guardrail Metrics

- Prefix: `99.6650%`
- Drift: `99.5675%`
- Probe: `99.9112%`
- 250k: `99.4632%`
- 1M: `99.5334%`
- 10M: `78.3230%`
- 20M: `78.4756%`

## v29 Target

The v29 research and product goal is **synthetic offline knowledge, safer autonomous runtime behavior, larger-vocabulary evidence, practical Zig coding capability, and stable numeric guardrails**:

- preserve the packaged CPU short-suite and hardening metrics while keeping `numeric_backend=cpu` and `score_threads=1` as the release default
- ship a real v29 grounded seed, a separate v29 open-chat seed, and a generated synthetic knowledge pack loaded through `knowledge_path`
- generate knowledge coverage rather than manually writing conversation transcripts for the new capability surface
- cover science, literature, geography, civics, economics, real-world task triage, and Zig allocator/error/defer/slice concepts in the generated pack
- add a dedicated generated-knowledge regression eval that includes general facts, Zig code, JSON, algebra, safe huge math, source boundaries, and secret rejection
- test larger vocabulary sizes from 256 through 16384 buckets and document the dense-table cost before changing the core byte-vocab architecture
- refuse exact-number math results outside the safe cast range instead of overflowing
- enforce displayed response `max_bytes` on generated, retrieved, and deterministic answers
- cap session file loading, retained facts, and retained turns, and reject API keys, tokens, passwords, and private credentials from persisted memory
- keep operational answers exact for starter files, artifact paths, bundle inventory, backend commands, and hardware support questions
- keep source-location support bounded to indexed or shipped source assets, and decline unsupported source-tree questions instead of inventing paths
- fix numeric `auto` so CUDA is attempted when the CUDA runtime is present and the scoring threshold is met
- keep CPU fallback automatic and keep accelerated numeric paths opt-in until measured wins justify promotion
- only report a `100M` point when a completed JSON artifact actually exists

## v29 Release Commands

Run the measured suite:

```bash
python scripts/run_v29_release.py
```

Generate the packaged report, summary, PDF, demo bundle, and repo zip:

```bash
python scripts/make_v29_deliverables.py
```

Package the newcomer demo directly:

```bash
python scripts/package_v29_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

Rebuild the shipped generated knowledge pack and vocabulary probe:

```bash
python scripts/build_v29_synthetic_knowledge.py
python scripts/vocab_size_probe_v29.py
```

## Packaged Numeric Profile

The packaged v29 numeric core keeps the safe single-thread CPU release stance and reuses the stable continuation profile so product, safety, and generated-knowledge repairs are isolated from numeric-profile churn.

Common network overrides:

- bits: `4`
- `enable_long_term=false`
- `history_lags=32`
- `birth_margin=21`
- `min_parents_for_birth=4`
- `max_carry_memories=48`
- `max_hidden_per_hop=32`
- `propagation_depth=2`
- `birth_pressure_threshold_bonus=0`
- `birth_saturation_threshold_bonus=0`
- `birth_saturation_parent_boost=0`
- `hybrid_share_ppm=0`
- `hybrid_recent_drift_bonus=0`
- `recent_markov2_bonus_ppm=0`
- `burst_bonus_ppm=520`
- `markov1_bonus_ppm=340`
- `markov2_bonus_ppm=760`
- `markov3_bonus_ppm=1900`
- `markov4_bonus_ppm=2400`
- `markov5_bonus_ppm=2800`
- `continuation_bonus_ppm=9200`
- `continuation_min_order=6`
- `continuation_max_order=32`
- `continuation_support_prior=0`
- `continuation_min_support=1`
- `hybrid_support_prior=0`
- `hybrid_evidence_prior=0`
- `score_threads=1`
- `numeric_backend=cpu`

Hardening additions:

- 10M run: `segment_len=2500000`, `checkpoint_interval=100000`, `sequence_seed_length=4000000`, `include_baseline=false`
- 20M run: `segment_len=5000000`, `checkpoint_interval=200000`, `sequence_seed_length=8000000`, `include_baseline=false`, plus bounded continuation overrides `continuation_bonus_ppm=8000` and `continuation_min_order=8`

The short suite and 10M run use the stronger continuation profile. The 20M run may be carried forward as a guardrail artifact if the local workstation cannot rerun that horizon; when that happens the status and report must say so plainly.

## v29 Dialogue and Product Profile

- default grounded seed: `data/sban_dialogue_seed_v29.txt`
- default open-chat seed: `data/sban_dialogue_open_seed_v29.txt`
- default generated knowledge pack: `data/sban_synthetic_knowledge_v29.txt`
- generated knowledge builder: `scripts/build_v29_synthetic_knowledge.py`
- larger-vocabulary probe: `scripts/vocab_size_probe_v29.py`
- grounded prompt eval asset: `data/sban_chat_eval_prompts_v29.txt`
- main session eval asset: `data/sban_session_eval_v29.txt`
- open-chat scripted session eval asset: `data/sban_open_chat_session_eval_v29.txt`
- broad free-chat battery: `data/sban_broad_chat_session_eval_v29.txt`
- generated knowledge and stress-regression eval: `data/sban_knowledge_session_eval_v29.txt`
- default product stance: grounded answers for SBAN-domain prompts, exact operational answers when the runtime knows its own files or commands, broader free chat through deterministic composition plus the v29 open seed and generated knowledge pack, explicit static-boundary messaging for current facts, honest uncertainty otherwise
- session persistence: encoded structured `SBAN_SESSION_V29` format with v28 compatibility, a 256 KiB load cap, retained fact/turn caps, and secret rejection
- default chat mode: free mode with safe conversational composition and `knowledge_path` loading enabled
- acceleration: CPU by default for numeric release checks, `backend=auto` for the newcomer chat loop, optional `cpu_mt`, direct CUDA on NVIDIA, OpenCL fallback through `backend=gpu`, and a numeric backend selector (`numeric_backend=cpu|cpu_mt|cuda|auto`) for `eval-variant`

## Interpretation Guardrails

- The numeric benchmark story and the conversational usability story are separate and should stay separate.
- The short numeric suite remains the baseline guardrail; the 10M and 20M runs are hardening extensions.
- GPU support is real and validated, and CUDA is the preferred large-corpus retrieval accelerator on NVIDIA hardware.
- Treat dialogue retrieval CUDA and numeric CUDA as separate claims. Measure both directly.
- The packaged numeric release still stays on CPU until accelerated numeric runs prove a dependable end-to-end win.
- Treat the generated knowledge pack as an offline/runtime-updatable asset, not as proof of live current knowledge.
- Treat the larger-vocabulary probe as architecture evidence. Do not switch the dense core vocab size until the memory cost is addressed by a sparse index or redesigned tables.
- Preserve the trustworthiness gains. Do not loosen retrieval thresholds in a way that turns uncertainty failures back into plausible-but-wrong blurbs.
- Prefer direct operational answers for artifact paths, starter files, bundle inventory, and backend commands when the runtime can know them exactly.
- Treat the open-chat, broad-chat, and generated-knowledge evaluations as real release gates. If the shipped conversational surface broadens, prove it with the versioned eval assets instead of hand-picked one-off demos.
- A completed hosted `100M` CPU artifact can be cited as an additional hardening datapoint, but it is not the packaged v29 release gate unless the JSON exists under `docs/results/`.
