#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "docs" / "results" / "v18"
BIN = ROOT / "zig-out" / "bin" / ("zig_sban.exe" if os.name == "nt" else "zig_sban")

RELEASE_BITS = "4"
RELEASE_PROFILE = [
    "enable_long_term=false",
    "birth_margin=21",
    "min_parents_for_birth=4",
    "max_carry_memories=48",
    "max_hidden_per_hop=32",
    "propagation_depth=2",
    "birth_pressure_threshold_bonus=0",
    "birth_saturation_threshold_bonus=0",
    "birth_saturation_parent_boost=0",
    "hybrid_share_ppm=0",
    "hybrid_recent_drift_bonus=0",
    "recent_markov2_bonus_ppm=0",
    "burst_bonus_ppm=520",
    "markov1_bonus_ppm=340",
    "markov2_bonus_ppm=760",
    "markov3_bonus_ppm=1900",
    "markov4_bonus_ppm=2400",
    "markov5_bonus_ppm=2800",
    "hybrid_support_prior=0",
    "hybrid_evidence_prior=0",
    "hybrid_reward=28",
    "hybrid_penalty=6",
    "sequence_seed_path=data/enwik8",
    "sequence_seed_offset=60050",
    "sequence_seed_length=5000000",
]


def build_binary(zig_exe: str | None) -> None:
    subprocess.run([zig_exe or "zig", "build", "-Doptimize=ReleaseSafe"], cwd=ROOT, check=True)


def run_capture(cmd: list[str], output_path: Path) -> str:
    text = subprocess.check_output(cmd, cwd=ROOT, text=True)
    output_path.write_text(text, encoding="utf-8")
    return text


def run_eval(dataset: str, output_name: str, mode: str, seg_len: int, label: str) -> float:
    out_json = RESULTS / output_name
    cmd = [
        str(BIN),
        "eval-variant",
        str(ROOT / dataset),
        str(out_json),
        mode,
        RELEASE_BITS,
        "default",
        str(seg_len),
        "5000",
        "4096",
        f"label={label}",
        *RELEASE_PROFILE,
    ]
    started = time.time()
    subprocess.run(cmd, cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    elapsed = time.time() - started
    data = json.loads(out_json.read_text(encoding="utf-8"))
    model = data["models"][0]
    acc = 100.0 * model["total_correct"] / model["total_predictions"]
    print(f"{output_name}: {acc:.4f}% ({elapsed:.1f}s)")
    return acc


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the full SBAN v18 release suite.")
    parser.add_argument("--zig-exe", help="Path to zig or zig.exe used for the build step.")
    parser.add_argument("--skip-build", action="store_true", help="Reuse the existing zig-out binary.")
    args = parser.parse_args()

    RESULTS.mkdir(parents=True, exist_ok=True)

    if not args.skip_build:
        build_binary(args.zig_exe)

    if not BIN.exists():
        raise FileNotFoundError(f"missing runtime binary: {BIN}")

    run_eval("data/enwik8", "unified_prefix_v18_release.json", "prefix", 10_000, "sban_v18_release")
    run_eval("data/enwik8", "unified_drift_v18_release.json", "drift", 10_000, "sban_v18_release")
    run_eval("data/elastic_probe.bin", "unified_probe_v18_release.json", "prefix", 29_000, "sban_v18_release")
    run_eval("data/enwik8", "longrun_v18_250k.json", "prefix", 62_500, "sban_v18_release")
    run_eval("data/enwik8", "longrun_v18_1m.json", "prefix", 250_000, "sban_v18_release")

    run_capture(
        [str(BIN), "chat-demo", "what changed in v18", "128", "seed_path=data/sban_dialogue_seed_v18.txt"],
        RESULTS / "chat_demo_v18_changes.txt",
    )
    run_capture(
        [str(BIN), "chat-demo", "what profile shipped in v18", "128", "seed_path=data/sban_dialogue_seed_v18.txt"],
        RESULTS / "chat_demo_v18_profile.txt",
    )
    run_capture(
        [str(BIN), "chat-demo", "how strong is the one million run now", "128", "seed_path=data/sban_dialogue_seed_v18.txt"],
        RESULTS / "chat_demo_v18_longrun.txt",
    )
    run_capture(
        [str(BIN), "chat-eval", "data/sban_chat_eval_prompts_v18.txt", "seed_path=data/sban_dialogue_seed_v18.txt"],
        RESULTS / "chat_eval_v18_hybrid.txt",
    )
    run_capture(
        [str(BIN), "chat-eval", "data/sban_chat_eval_prompts_v18.txt", "mode=free", "seed_path=data/sban_dialogue_seed_v18.txt"],
        RESULTS / "chat_eval_v18_free.txt",
    )


if __name__ == "__main__":
    main()
