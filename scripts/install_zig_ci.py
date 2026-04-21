#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import tarfile
import urllib.request
import zipfile
from pathlib import Path

INDEX_URL = "https://ziglang.org/download/index.json"


def detect_platform_key() -> str:
    system = platform.system().lower()
    machine = platform.machine().lower()
    if machine in {"amd64", "x86_64", "x64"}:
        arch = "x86_64"
    elif machine in {"arm64", "aarch64"}:
        arch = "aarch64"
    else:
        raise RuntimeError(f"unsupported architecture: {machine}")

    if system == "windows":
        return f"{arch}-windows"
    if system == "linux":
        return f"{arch}-linux"
    if system == "darwin":
        return f"{arch}-macos"
    raise RuntimeError(f"unsupported operating system: {system}")


def fetch_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.load(response)


def download_file(url: str, destination: Path) -> None:
    with urllib.request.urlopen(url, timeout=300) as response, destination.open("wb") as fh:
        shutil.copyfileobj(response, fh)


def flatten_output_dir(output_dir: Path) -> None:
    children = list(output_dir.iterdir())
    if len(children) != 1 or not children[0].is_dir():
        return
    nested = children[0]
    for item in nested.iterdir():
        shutil.move(str(item), output_dir / item.name)
    nested.rmdir()


def append_github_path(path: Path) -> None:
    github_path = os.environ.get("GITHUB_PATH")
    if not github_path:
        return
    with open(github_path, "a", encoding="utf-8") as fh:
        fh.write(str(path.resolve()) + os.linesep)


def main() -> None:
    parser = argparse.ArgumentParser(description="Install Zig for CI from the official Zig download index.")
    parser.add_argument("--version", default="master", help="Version key from https://ziglang.org/download/index.json")
    parser.add_argument("--output-dir", required=True, help="Directory to receive the extracted Zig toolchain")
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    platform_key = detect_platform_key()
    index = fetch_json(INDEX_URL)
    if args.version not in index:
        raise KeyError(f"version {args.version!r} not found in Zig index")
    version_entry = index[args.version]
    platform_entry = version_entry.get(platform_key)
    if not platform_entry:
        raise KeyError(f"platform {platform_key!r} not present for version {args.version!r}")

    archive_url = platform_entry.get("tarball") or platform_entry.get("zip")
    if not archive_url:
        raise KeyError(f"missing archive URL for {args.version!r} on {platform_key!r}")

    archive_name = archive_url.rsplit("/", 1)[-1]
    archive_path = output_dir / archive_name
    download_file(archive_url, archive_path)

    if archive_name.endswith(".zip"):
        with zipfile.ZipFile(archive_path) as zf:
            zf.extractall(output_dir)
    elif archive_name.endswith(".tar.xz"):
        with tarfile.open(archive_path, "r:xz") as tf:
            tf.extractall(output_dir)
    else:
        raise RuntimeError(f"unsupported archive type: {archive_name}")

    archive_path.unlink()
    flatten_output_dir(output_dir)
    append_github_path(output_dir)

    zig_path = output_dir / ("zig.exe" if platform.system().lower() == "windows" else "zig")
    print(zig_path)


if __name__ == "__main__":
    main()
