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
RESULTS_DIR = ROOT / "docs" / "results" / "v23_5"
OUTPUT_DIR = ROOT / "deliverables" / "v23_5" / "demo"


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
    return f"SBAN_v23_5_{platform}_demo"


def build_stage(binary_path: Path, platform: str, stage_root: Path) -> Path:
    bundle_root = stage_root / bundle_name(platform)
    if bundle_root.exists():
        shutil.rmtree(bundle_root)
    (bundle_root / "data").mkdir(parents=True, exist_ok=True)
    docs_dir = bundle_root / "docs"
    docs_dir.mkdir(parents=True, exist_ok=True)

    shipped_binary = "sban_v23_5.exe" if platform.startswith("windows") else "sban_v23_5"
    shutil.copy2(binary_path, bundle_root / shipped_binary)
    shutil.copy2(DATA_DIR / "sban_dialogue_seed_v23_5.txt", bundle_root / "data" / "sban_dialogue_seed_v23_5.txt")
    shutil.copy2(DATA_DIR / "sban_chat_eval_prompts_v23_5.txt", bundle_root / "data" / "sban_chat_eval_prompts_v23_5.txt")
    shutil.copy2(DATA_DIR / "sban_session_eval_v23_5.txt", bundle_root / "data" / "sban_session_eval_v23_5.txt")
    shutil.copy2(DEMO_DIR / "sample_prompts_v23_5.txt", bundle_root / "sample_prompts_v23_5.txt")

    if (ROOT / "SBAN_v23_5_EXECUTIVE_SUMMARY.md").exists():
        shutil.copy2(ROOT / "SBAN_v23_5_EXECUTIVE_SUMMARY.md", docs_dir / "SBAN_v23_5_EXECUTIVE_SUMMARY.md")
    if (ROOT / "docs" / "papers" / "SBAN_v23_5_follow_up_research_paper.pdf").exists():
        shutil.copy2(ROOT / "docs" / "papers" / "SBAN_v23_5_follow_up_research_paper.pdf", docs_dir / "SBAN_v23_5_follow_up_research_paper.pdf")

    for name in [
        "chat_demo_v23_5_overview.txt",
        "chat_demo_v23_5_paper.txt",
        "chat_demo_v23_5_cuda_command.txt",
        "chat_demo_v23_5_rtx.txt",
        "chat_demo_v23_5_joke.txt",
        "chat_session_eval_v23_5.txt",
        "accel_info_v23_5_cuda.txt",
        "numeric_accel_info_v23_5_cuda.txt",
        "accel_bench_v23_5.json",
        "numeric_backend_v23_5.json",
        "nvidia_smi_v23_5.txt",
    ]:
        source = RESULTS_DIR / name
        if source.exists():
            shutil.copy2(source, docs_dir / name)

    readme_text = """SBAN v23.5 newcomer demo

This bundle packages the SBAN v23.5 binary plus a starter script for a continuing grounded chat session with the real v23.5 dialogue seed.

Quick start:
- Windows: double-click SBAN_v23_5_Start.bat
- Linux: run ./SBAN_v23_5_Start.sh

What to ask first:
- what is SBAN v23.5
- what command shows cuda support
- what command shows numeric cuda support
- what is the windows starter file called
- where is the v23.5 paper pdf
- can this run on an rtx 4090
- hi i am tom and i need help
- can you recall my name
- tell me a joke

Runtime notes:
- the starter loop defaults to CPU for the bundled grounded corpus
- the default chat loop is free mode with safe conversational composition enabled
- use `sban_v23_5 accel-info seed_path=data/sban_dialogue_seed_v23_5.txt backend=cuda` to probe NVIDIA CUDA retrieval support
- use `sban_v23_5 numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1` to probe the numeric CUDA backend
- use `backend=cpu_mt threads=4` or `backend=cuda` explicitly when you want to experiment with the accelerated retrieval paths

Important benchmark note:
The packaged numeric v23.5 suite still stays on the proven single-thread CPU release profile. The release adds experimental numeric cpu_mt and CUDA backends, but they are not the shipped default unless the measured release-profile timings earn that promotion.
"""
    write_text(bundle_root / "README_FIRST.txt", readme_text)

    batch_text = """@echo off
setlocal
cd /d "%~dp0"
if exist session_v23_5.txt del /f /q session_v23_5.txt
echo SBAN v23.5 continuing demo
echo Default backend: CPU for the bundled grounded corpus.
echo Run "sban_v23_5.exe accel-info seed_path=data/sban_dialogue_seed_v23_5.txt backend=cuda" to inspect NVIDIA CUDA support.
echo Run "sban_v23_5.exe numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1" to inspect the numeric CUDA backend.
echo Press Enter on an empty line to exit.
echo.
:loop
set /p SBAN_PROMPT=You^>
if "%SBAN_PROMPT%"=="" goto end
echo.
sban_v23_5.exe chat-demo "%SBAN_PROMPT%" 180 seed_path=data/sban_dialogue_seed_v23_5.txt session_path=session_v23_5.txt backend=cpu mode=free allow_generation=true
echo.
goto loop
:end
echo Demo finished.
pause
"""
    sh_text = """#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
rm -f session_v23_5.txt
echo "SBAN v23.5 continuing demo"
echo "Default backend: CPU for the bundled grounded corpus."
echo "Run './sban_v23_5 accel-info seed_path=data/sban_dialogue_seed_v23_5.txt backend=cuda' to inspect NVIDIA CUDA support."
echo "Run './sban_v23_5 numeric-accel-info numeric_backend=cuda cuda_min_scoring_edges=1' to inspect the numeric CUDA backend."
echo "Press Enter on an empty line to exit."
while true; do
  printf 'You> '
  IFS= read -r SBAN_PROMPT || exit 0
  if [ -z "$SBAN_PROMPT" ]; then
    exit 0
  fi
  echo
  ./sban_v23_5 chat-demo "$SBAN_PROMPT" 180 seed_path=data/sban_dialogue_seed_v23_5.txt session_path=session_v23_5.txt backend=cpu mode=free allow_generation=true
  echo
done
"""
    write_text(bundle_root / "SBAN_v23_5_Start.bat", batch_text)
    write_text(bundle_root / "SBAN_v23_5_Start.sh", sh_text)
    if os.name != "nt":
        os.chmod(bundle_root / "SBAN_v23_5_Start.sh", 0o755)

    return bundle_root


def main() -> None:
    parser = argparse.ArgumentParser(description="Package the grounded SBAN v23.5 demo bundle.")
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
