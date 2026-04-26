#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
DEMO_DIR = ROOT / "demo"
RESULTS_DIR = ROOT / "docs" / "results" / "v36"
OUTPUT_DIR = ROOT / "deliverables" / "v36" / "demo"


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def zip_tree(source_dir: Path, output_zip: Path) -> None:
    output_zip.parent.mkdir(parents=True, exist_ok=True)
    if output_zip.exists():
        output_zip.unlink()
    with zipfile.ZipFile(output_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for path in sorted(source_dir.rglob("*")):
            if path.is_dir():
                continue
            zf.write(path, path.relative_to(source_dir).as_posix())


def bundle_name(platform: str) -> str:
    return f"SBAN_v36_{platform}_demo"


def build_stage(binary_path: Path, platform: str, stage_root: Path) -> Path:
    bundle_root = stage_root / bundle_name(platform)
    if bundle_root.exists():
        shutil.rmtree(bundle_root)
    (bundle_root / "data").mkdir(parents=True, exist_ok=True)
    docs_dir = bundle_root / "docs"
    docs_dir.mkdir(parents=True, exist_ok=True)

    shipped_binary = "sban_v36.exe" if platform.startswith("windows") else "sban_v36"
    shutil.copy2(binary_path, bundle_root / shipped_binary)
    shutil.copy2(DATA_DIR / "sban_runtime_prewarm_v36.txt", bundle_root / "data" / "sban_runtime_prewarm_v36.txt")
    shutil.copy2(DATA_DIR / "sban_learned_reasoning_v36.txt", bundle_root / "data" / "sban_learned_reasoning_v36.txt")
    shutil.copy2(DATA_DIR / "sban_cold_seed_v36.txt", bundle_root / "data" / "sban_cold_seed_v36.txt")
    shutil.copy2(DATA_DIR / "sban_dialogue_seed_v36.txt", bundle_root / "data" / "sban_dialogue_seed_v36.txt")
    shutil.copy2(DATA_DIR / "sban_dialogue_open_seed_v36.txt", bundle_root / "data" / "sban_dialogue_open_seed_v36.txt")
    shutil.copy2(DATA_DIR / "sban_synthetic_knowledge_v36.txt", bundle_root / "data" / "sban_synthetic_knowledge_v36.txt")
    shutil.copy2(DATA_DIR / "sban_chat_eval_prompts_v36.txt", bundle_root / "data" / "sban_chat_eval_prompts_v36.txt")
    shutil.copy2(DATA_DIR / "sban_session_eval_v36.txt", bundle_root / "data" / "sban_session_eval_v36.txt")
    shutil.copy2(DATA_DIR / "sban_open_chat_session_eval_v36.txt", bundle_root / "data" / "sban_open_chat_session_eval_v36.txt")
    shutil.copy2(DATA_DIR / "sban_broad_chat_session_eval_v36.txt", bundle_root / "data" / "sban_broad_chat_session_eval_v36.txt")
    shutil.copy2(DATA_DIR / "sban_knowledge_session_eval_v36.txt", bundle_root / "data" / "sban_knowledge_session_eval_v36.txt")
    shutil.copy2(DATA_DIR / "sban_learned_session_eval_v36.txt", bundle_root / "data" / "sban_learned_session_eval_v36.txt")
    shutil.copy2(DATA_DIR / "sban_limitations_session_eval_v36.txt", bundle_root / "data" / "sban_limitations_session_eval_v36.txt")
    shutil.copy2(DEMO_DIR / "sample_prompts_v36.txt", bundle_root / "sample_prompts_v36.txt")

    if (ROOT / "SBAN_v36_EXECUTIVE_SUMMARY.md").exists():
        shutil.copy2(ROOT / "SBAN_v36_EXECUTIVE_SUMMARY.md", docs_dir / "SBAN_v36_EXECUTIVE_SUMMARY.md")
    if (ROOT / "docs" / "papers" / "SBAN_v36_follow_up_research_paper.pdf").exists():
        shutil.copy2(ROOT / "docs" / "papers" / "SBAN_v36_follow_up_research_paper.pdf", docs_dir / "SBAN_v36_follow_up_research_paper.pdf")

    for name in [
        "chat_demo_v36_overview.txt",
        "chat_demo_v36_autolearn.txt",
        "chat_demo_v36_learned_syllogism.txt",
        "chat_demo_v36_json_slots.txt",
        "chat_demo_v36_bundle.txt",
        "chat_demo_v36_paper.txt",
        "chat_demo_v36_cuda_command.txt",
        "chat_demo_v36_rtx.txt",
        "chat_demo_v36_memory_capability.txt",
        "chat_demo_v36_planning.txt",
        "chat_demo_v36_weekend.txt",
        "chat_demo_v36_zig_hashmap.txt",
        "chat_demo_v36_quantified_logic.txt",
        "chat_demo_v36_quadratic.txt",
        "chat_demo_v36_word_problem.txt",
        "chat_demo_v36_rust_server.txt",
        "chat_demo_v36_uncertainty.txt",
        "chat_session_eval_v36.txt",
        "open_chat_session_eval_v36.txt",
        "broad_chat_session_eval_v36.txt",
        "knowledge_session_eval_v36.txt",
        "learned_session_eval_v36.txt",
        "limitations_session_eval_v36.txt",
        "runtime_prewarm_v36.json",
        "synthetic_knowledge_v36.json",
        "autolearn_manifest_v36.json",
        "vocab_size_probe_v36.json",
        "accel_info_v36_cuda.txt",
        "numeric_accel_info_v36_cuda.txt",
        "accel_bench_v36.json",
        "numeric_backend_v36.json",
        "nvidia_smi_v36.txt",
    ]:
        source = RESULTS_DIR / name
        if source.exists():
            shutil.copy2(source, docs_dir / name)

    readme_text = """SBAN v36 newcomer demo

This bundle packages the SBAN v36 binary plus a starter script for a continuing chat session. The runtime loads the generated v36 prewarm pack and learned reasoning corpus by default, so the starter loop does not need separate seed, open-seed, knowledge-path, or learned-path arguments.

Quick start:
- Windows: double-click SBAN_v36_Start.bat
- Linux: run ./SBAN_v36_Start.sh

What to ask first:
- what is SBAN v36
- how does SBAN v36 learn without editing dialogue.zig
- If all daxes are lums, and some lums are norps, are all daxes definitely norps? Explain.
- what is DNS
- what is entropy
- what does defer do in Zig
- write Python BFS for a graph
- how do I triage an outage
- what files ship in the bundle
- what command shows cuda support
- can this run on an rtx 4090
- hi i am tom and i need help
- can you recall my name
- our team is atlas
- what team am i on
- i am from london
- where am i from
- my dog is luna
- what is my dog name
- my cat is io
- what is my cat name
- our project is nebula
- what project are we on
- remember that my launch date is tuesday
- when is my launch date
- can you help me plan tomorrow
- what should i do this weekend
- calculate 2^10
- translate hello to spanish
- summarize: SBAN v36 fixes stale labels and tightens eval matching
- what is json
- where is std.hashmap implemented in zig upstream
- what causes tides
- what is mitosis
- who wrote pride and prejudice
- write a zig function to reverse a slice
- If no blickets are wugs and all glims are blickets, can any glim be a wug?
- solve x^2 = 4
- Sam has 14 apples, gives away 5, then buys 8. How many apples does Sam have?
- write a Rust async HTTP server
- generate JSON with name and age
- generate JSON with name Ada and age 37
- generate JSON with name Jane Doe and age 0
- forget my dog name
- solve 3x + 5 = 20
- calculate 2^1000

Runtime notes:
- the starter loop uses backend=auto with the generated v36 runtime prewarm pack and learned reasoning corpus loaded by default
- regenerate data/sban_learned_reasoning_v36.txt with scripts/build_v36_runtime_prewarm.py to improve learned replies from dataset adapters without editing dialogue.zig
- the default chat loop is free mode with safe conversational composition enabled
- use `sban_v36 accel-info backend=cuda` to probe NVIDIA CUDA retrieval support
- use `sban_v36 numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1` to probe the numeric CUDA backend
- use `backend=cpu_mt threads=4` or `backend=cuda` explicitly when you want to override the hybrid retrieval path

Important product note:
SBAN v36 promotes the generated runtime prewarm pack and learned reasoning corpus to the default chat surface, fixes exact JSON slot preservation and session forget semantics, adds wider Zig/Rust and real-world task coverage, and probes larger vocabularies through 65,536 buckets. It is still a bounded static/offline runtime unless you supply refreshed knowledge; it should answer near-miss prompts with supported reasoning paths and reserve hard boundaries for live-current facts or missing external sources.
"""
    write_text(bundle_root / "README_FIRST.txt", readme_text)

    batch_text = """@echo off
setlocal
cd /d "%~dp0"
if exist session_v36.txt del /f /q session_v36.txt
echo SBAN v36 continuing demo
echo Default backend: auto. The bundled chat loop loads the v36 runtime prewarm pack and learned reasoning corpus by default.
echo Run "sban_v36.exe accel-info backend=cuda" to inspect NVIDIA CUDA support.
echo Run "sban_v36.exe numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1" to inspect the numeric CUDA backend.
echo Press Enter on an empty line to exit.
echo.
:loop
set /p SBAN_PROMPT=You^>
if "%SBAN_PROMPT%"=="" goto end
echo.
sban_v36.exe chat-demo "%SBAN_PROMPT%" 220 session_path=session_v36.txt backend=auto mode=free allow_generation=true
echo.
goto loop
:end
echo Demo finished.
pause
"""
    sh_text = """#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
rm -f session_v36.txt
echo "SBAN v36 continuing demo"
echo "Default backend: auto. The bundled chat loop loads the v36 runtime prewarm pack and learned reasoning corpus by default."
echo "Run './sban_v36 accel-info backend=cuda' to inspect NVIDIA CUDA support."
echo "Run './sban_v36 numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1' to inspect the numeric CUDA backend."
echo "Press Enter on an empty line to exit."
while true; do
  printf 'You> '
  IFS= read -r SBAN_PROMPT || exit 0
  if [ -z "$SBAN_PROMPT" ]; then
    exit 0
  fi
  echo
  ./sban_v36 chat-demo "$SBAN_PROMPT" 220 session_path=session_v36.txt backend=auto mode=free allow_generation=true
  echo
done
"""
    write_text(bundle_root / "SBAN_v36_Start.bat", batch_text)
    write_text(bundle_root / "SBAN_v36_Start.sh", sh_text)
    if os.name != "nt":
        os.chmod(bundle_root / "SBAN_v36_Start.sh", 0o755)

    return bundle_root


def main() -> None:
    parser = argparse.ArgumentParser(description="Package the SBAN v36 conversational demo bundle.")
    parser.add_argument("--binary", required=True, help="Path to the built zig_sban binary.")
    parser.add_argument("--platform", required=True, help="Platform label such as windows_x86_64 or linux_x86_64.")
    parser.add_argument("--output-dir", default=str(OUTPUT_DIR), help="Directory that receives the packaged archive.")
    args = parser.parse_args()

    binary_path = Path(args.binary).resolve()
    if not binary_path.exists():
        raise FileNotFoundError(binary_path)

    output_dir = Path(args.output_dir).resolve()
    stage_root = output_dir / "_stage"
    bundle_root = build_stage(binary_path, args.platform, stage_root)
    archive_path = output_dir / f"{bundle_root.name}.zip"
    zip_tree(bundle_root, archive_path)
    shutil.rmtree(stage_root, ignore_errors=True)
    print(archive_path)


if __name__ == "__main__":
    main()
