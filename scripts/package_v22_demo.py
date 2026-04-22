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
RESULTS_DIR = ROOT / "docs" / "results" / "v22"
OUTPUT_DIR = ROOT / "deliverables" / "v22" / "demo"


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
    return f"SBAN_v22_{platform}_demo"


def build_stage(binary_path: Path, platform: str, stage_root: Path) -> Path:
    bundle_root = stage_root / bundle_name(platform)
    if bundle_root.exists():
        shutil.rmtree(bundle_root)
    (bundle_root / "data").mkdir(parents=True, exist_ok=True)
    docs_dir = bundle_root / "docs"
    docs_dir.mkdir(parents=True, exist_ok=True)

    shipped_binary = "sban_v22.exe" if platform.startswith("windows") else "sban_v22"
    shutil.copy2(binary_path, bundle_root / shipped_binary)
    shutil.copy2(DATA_DIR / "sban_dialogue_seed_v22.txt", bundle_root / "data" / "sban_dialogue_seed_v22.txt")
    shutil.copy2(DATA_DIR / "sban_chat_eval_prompts_v22.txt", bundle_root / "data" / "sban_chat_eval_prompts_v22.txt")
    shutil.copy2(DATA_DIR / "sban_session_eval_v22.txt", bundle_root / "data" / "sban_session_eval_v22.txt")
    shutil.copy2(DEMO_DIR / "sample_prompts_v22.txt", bundle_root / "sample_prompts_v22.txt")

    if (ROOT / "SBAN_v22_EXECUTIVE_SUMMARY.md").exists():
        shutil.copy2(ROOT / "SBAN_v22_EXECUTIVE_SUMMARY.md", docs_dir / "SBAN_v22_EXECUTIVE_SUMMARY.md")
    if (ROOT / "docs" / "papers" / "SBAN_v22_follow_up_research_paper.pdf").exists():
        shutil.copy2(ROOT / "docs" / "papers" / "SBAN_v22_follow_up_research_paper.pdf", docs_dir / "SBAN_v22_follow_up_research_paper.pdf")

    for name in [
        "chat_demo_v22_recall.txt",
        "chat_demo_v22_uncertainty.txt",
        "chat_demo_v22_paraphrase.txt",
        "chat_session_eval_v22.txt",
        "accel_info_v22.txt",
    ]:
        source = RESULTS_DIR / name
        if source.exists():
            shutil.copy2(source, docs_dir / name)

    readme_text = """SBAN v22 newcomer demo

This bundle packages the SBAN v22 binary plus a starter script for a continuing grounded chat session.

Quick start:
- Windows: double-click SBAN_v22_Start.bat
- Linux: run ./SBAN_v22_Start.sh

What to ask first:
- what is SBAN v22
- how is v22 different from v21
- what is bridge memory
- compare SBAN to transformers in detail
- hi i am tom and i need help
- can you recall my name
- i live in london
- what city do i live in
- can you remember my role if i tell you
- what is 3 / 0

Runtime notes:
- the starter loop defaults to CPU mode because the grounded v22 corpus is small enough that CPU startup is usually faster
- use `sban_v22 accel-info seed_path=data/sban_dialogue_seed_v22.txt` to probe GPU availability
- use `backend=gpu` explicitly if you want to experiment with the OpenCL retrieval path

Important benchmark caveat:
The packaged numeric v22 benchmark remains separate from this demo and must still be described according to the release methodology documented in the main repository.
"""
    write_text(bundle_root / "README_FIRST.txt", readme_text)

    batch_text = """@echo off
setlocal
cd /d "%~dp0"
if exist session_v22.txt del /f /q session_v22.txt
echo SBAN v22 grounded continuing demo
echo Default backend: CPU for faster small-corpus startup.
echo Run "sban_v22.exe accel-info seed_path=data/sban_dialogue_seed_v22.txt" to inspect GPU support.
echo Press Enter on an empty line to exit.
echo.
:loop
set /p SBAN_PROMPT=You^>
if "%SBAN_PROMPT%"=="" goto end
echo.
sban_v22.exe chat-demo "%SBAN_PROMPT%" 160 seed_path=data/sban_dialogue_seed_v22.txt session_path=session_v22.txt backend=cpu
echo.
goto loop
:end
echo Demo finished.
pause
"""
    sh_text = """#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
rm -f session_v22.txt
echo "SBAN v22 grounded continuing demo"
echo "Default backend: CPU for faster small-corpus startup."
echo "Run './sban_v22 accel-info seed_path=data/sban_dialogue_seed_v22.txt' to inspect GPU support."
echo "Press Enter on an empty line to exit."
while true; do
  printf 'You> '
  IFS= read -r SBAN_PROMPT || exit 0
  if [ -z "$SBAN_PROMPT" ]; then
    exit 0
  fi
  echo
  ./sban_v22 chat-demo "$SBAN_PROMPT" 160 seed_path=data/sban_dialogue_seed_v22.txt session_path=session_v22.txt backend=cpu
  echo
done
"""
    write_text(bundle_root / "SBAN_v22_Start.bat", batch_text)
    write_text(bundle_root / "SBAN_v22_Start.sh", sh_text)
    if os.name != "nt":
        os.chmod(bundle_root / "SBAN_v22_Start.sh", 0o755)

    return bundle_root


def main() -> None:
    parser = argparse.ArgumentParser(description="Package the grounded continuing-session SBAN v22 demo bundle.")
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
