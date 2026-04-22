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
RESULTS_DIR = ROOT / "docs" / "results" / "v21"
OUTPUT_DIR = ROOT / "deliverables" / "v21" / "demo"


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
    return f"SBAN_v21_{platform}_demo"


def build_stage(binary_path: Path, platform: str, stage_root: Path) -> Path:
    bundle_root = stage_root / bundle_name(platform)
    if bundle_root.exists():
        shutil.rmtree(bundle_root)
    (bundle_root / "data").mkdir(parents=True, exist_ok=True)
    docs_dir = bundle_root / "docs"
    docs_dir.mkdir(parents=True, exist_ok=True)

    shipped_binary = "sban_v21.exe" if platform.startswith("windows") else "sban_v21"
    shutil.copy2(binary_path, bundle_root / shipped_binary)
    shutil.copy2(DATA_DIR / "sban_dialogue_seed_v21.txt", bundle_root / "data" / "sban_dialogue_seed_v21.txt")
    shutil.copy2(DATA_DIR / "sban_chat_eval_prompts_v21.txt", bundle_root / "data" / "sban_chat_eval_prompts_v21.txt")
    shutil.copy2(DATA_DIR / "sban_session_eval_v21.txt", bundle_root / "data" / "sban_session_eval_v21.txt")
    shutil.copy2(DEMO_DIR / "sample_prompts_v21.txt", bundle_root / "sample_prompts_v21.txt")

    if (ROOT / "SBAN_v21_EXECUTIVE_SUMMARY.md").exists():
        shutil.copy2(ROOT / "SBAN_v21_EXECUTIVE_SUMMARY.md", docs_dir / "SBAN_v21_EXECUTIVE_SUMMARY.md")
    if (ROOT / "docs" / "papers" / "SBAN_v21_follow_up_research_paper.pdf").exists():
        shutil.copy2(ROOT / "docs" / "papers" / "SBAN_v21_follow_up_research_paper.pdf", docs_dir / "SBAN_v21_follow_up_research_paper.pdf")

    for name in [
        "chat_demo_v21_recall.txt",
        "chat_demo_v21_uncertainty.txt",
        "chat_demo_v21_version_guard.txt",
        "chat_session_eval_v21.txt",
        "accel_info_v21.txt",
    ]:
        source = RESULTS_DIR / name
        if source.exists():
            shutil.copy2(source, docs_dir / name)

    readme_text = """SBAN v21 newcomer demo

This bundle packages the SBAN v21 binary plus a starter script for a continuing grounded chat session.

Quick start:
- Windows: double-click SBAN_v21_Start.bat
- Linux: run ./SBAN_v21_Start.sh

What to ask first:
- what is SBAN v21
- explain sparse bridge-adaptive network architecture
- compare SBAN to transformers in detail
- hi i am tom and i need help
- can you recall my name
- my favorite color is blue
- what is my favorite color
- what is 3.5 + 1.2
- tell me a joke

Runtime notes:
- the chat demo defaults to the grounded v21 flow with session persistence
- GPU retrieval acceleration is used automatically when a compatible OpenCL backend is present
- CPU fallback is automatic when no GPU path is available

Important benchmark caveat:
The packaged numeric v21 benchmark remains separate from this demo and must still be described according to the release methodology documented in the main repository.
"""
    write_text(bundle_root / "README_FIRST.txt", readme_text)

    batch_text = """@echo off
setlocal
cd /d "%~dp0"
if exist session_v21.txt del /f /q session_v21.txt
echo SBAN v21 grounded continuing demo
echo GPU acceleration is used automatically when OpenCL is available.
echo Press Enter on an empty line to exit.
echo.
:loop
set /p SBAN_PROMPT=You^> 
if "%SBAN_PROMPT%"=="" goto end
echo.
sban_v21.exe chat-demo "%SBAN_PROMPT%" 160 seed_path=data/sban_dialogue_seed_v21.txt session_path=session_v21.txt backend=auto
echo.
goto loop
:end
echo Demo finished.
pause
"""
    sh_text = """#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
rm -f session_v21.txt
echo "SBAN v21 grounded continuing demo"
echo "GPU acceleration is used automatically when OpenCL is available."
echo "Press Enter on an empty line to exit."
while true; do
  printf 'You> '
  IFS= read -r SBAN_PROMPT || exit 0
  if [ -z "$SBAN_PROMPT" ]; then
    exit 0
  fi
  echo
  ./sban_v21 chat-demo "$SBAN_PROMPT" 160 seed_path=data/sban_dialogue_seed_v21.txt session_path=session_v21.txt backend=auto
  echo
done
"""
    write_text(bundle_root / "SBAN_v21_Start.bat", batch_text)
    write_text(bundle_root / "SBAN_v21_Start.sh", sh_text)
    if os.name != "nt":
        os.chmod(bundle_root / "SBAN_v21_Start.sh", 0o755)

    return bundle_root


def main() -> None:
    parser = argparse.ArgumentParser(description="Package the grounded continuing-session SBAN v21 demo bundle.")
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
