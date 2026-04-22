# SBAN v20

SBAN v20 is the current research release of the Sparse Bridge-Adaptive Network runtime. This iteration keeps the packaged numeric engine-health suite near the v19 baseline while shifting the main release focus toward real usability: stronger free chat, continuing multi-turn sessions, and simple unseen-prompt robustness.

## Headline v20 results

- Prefix: stable against the v19 packaged baseline
- Drift: stable against the v19 packaged baseline
- Probe: stable against the v19 packaged baseline
- 250k long run: stable against the v19 packaged baseline
- 1M long run: stable against the v19 packaged baseline
- Hybrid chat eval: expanded v20 prompt set with full non-empty coverage
- Free chat eval: expanded v20 prompt set with grounded retrieval plus symbolic support
- Session eval: scripted multi-turn recall and arithmetic checks

The numeric suite is still the engine-health check. The main v20 product claim is that the newcomer demo now supports continuing sessions instead of acting like a fresh one-shot prompt on every turn.

## Important benchmark caveat

The packaged v20 numeric release remains **self-seeded and transductive**. It uses benchmark-specific sequence seeding directly from the evaluated corpora and should not be described as a strict no-lookahead online compression result.

That caveat applies to the numeric benchmark.

The continuing-session demo is a separate user-facing artifact built on the same runtime.

## What changed in v20

- added transcript-backed continuing chat through `session_path`
- added lightweight symbolic handling for name recall, short arithmetic, and newcomer help prompts
- added `chat-session-eval` for honest multi-turn evaluation
- broadened the v20 prompt assets around usability instead of only release Q&A
- updated the newcomer demo bundle so the packaged starter scripts preserve one session across turns
- updated the SBAN research skill and release references for future continuation work

## Build

If `zig` is already on `PATH`:

```bash
zig build -Doptimize=ReleaseSafe
```

If you want to use a local Zig executable path on Windows:

```bash
python scripts/run_v20_release.py --zig-exe C:\path\to\zig.exe
```

## Try the v20 demo from source

After building:

```bash
zig-out/bin/zig_sban chat-demo "what is SBAN v20" 160 seed_path=data/sban_dialogue_seed_v20.txt
```

To keep a continuing session:

```bash
zig-out/bin/zig_sban chat-demo "hi im tom" 160 mode=free seed_path=data/sban_dialogue_seed_v20.txt session_path=session_v20.txt
zig-out/bin/zig_sban chat-demo "can you recall my name" 160 mode=free seed_path=data/sban_dialogue_seed_v20.txt session_path=session_v20.txt
```

The packaged newcomer bundles generated for releases use the same `session_path` flow behind `SBAN_v20_Start.bat` and `SBAN_v20_Start.sh`.

## Run the v20 release suite

With `zig` on `PATH`:

```bash
python scripts/run_v20_release.py
```

Reuse an existing build:

```bash
python scripts/run_v20_release.py --skip-build
```

This writes the packaged release artifacts to `docs/results/v20/`.

## Generate the v20 paper, summary, demo bundle, and repo zip

```bash
python scripts/make_v20_deliverables.py
```

This generates:

- `SBAN_v20_REPORT.md`
- `SBAN_v20_EXECUTIVE_SUMMARY.md`
- `docs/papers/SBAN_v20_follow_up_research_paper.pdf`
- `deliverables/v20/`
- `deliverables/v20/SBAN_v20_repo.zip`
- `deliverables/v20/demo/SBAN_v20_windows_x86_64_demo.zip`

## Package only the newcomer demo bundle

```bash
python scripts/package_v20_demo.py --binary zig-out/bin/zig_sban.exe --platform windows_x86_64
```

## GitHub automation

- `.github/workflows/ci.yml` builds and tests SBAN v20 on Windows and Ubuntu and runs smoke checks for the continuing chat surface
- `.github/workflows/release.yml` builds the packaged Windows and Linux continuing-session bundles and uploads them to tagged GitHub releases

## Main files

- `src/network.zig`
- `src/config.zig`
- `src/experiment.zig`
- `src/main.zig`
- `scripts/run_v20_release.py`
- `scripts/make_v20_deliverables.py`
- `scripts/package_v20_demo.py`
- `references/release_profiles.md`
- `docs/results/v20/`
- `data/sban_dialogue_seed_v20.txt`
- `data/sban_chat_eval_prompts_v20.txt`
- `data/sban_session_eval_v20.txt`
- `demo/`
- `skills/sban-research/SKILL.md`

## Bottom line

SBAN v20 is the usability release. It keeps the strong packaged runtime core from v19 while making the architecture much easier to try as an actual continuing chat demo. The reporting requirement remains the same: keep the numeric caveat explicit and separate that benchmark story from the user-facing session demo.
