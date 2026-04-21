#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "docs" / "results" / "v19"
BIN = ROOT / "zig-out" / "bin" / ("zig_sban.exe" if os.name == "nt" else "zig_sban")

RELEASE_BITS = "4"
V18 = {
    "prefix": 63.1500,
    "drift": 60.8625,
    "probe": 80.4491,
    "long_250k": 67.6920,
    "long_1m": 67.1821,
}

COMMON_PROFILE = [
    "enable_long_term=false",
    "history_lags=32",
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
    "continuation_bonus_ppm=8000",
    "continuation_min_order=8",
    "continuation_max_order=32",
    "continuation_support_prior=0",
    "continuation_min_support=1",
    "hybrid_support_prior=0",
    "hybrid_evidence_prior=0",
]

BENCHMARKS = [
    {
        "key": "prefix",
        "dataset": "data/enwik8",
        "output": "unified_prefix_v19_release.json",
        "mode": "prefix",
        "segment_len": 10_000,
        "label": "sban_v19_release_prefix",
        "extras": [
            "sequence_seed_path=data/enwik8",
            "sequence_seed_offset=0",
            "sequence_seed_length=1000000",
        ],
    },
    {
        "key": "drift",
        "dataset": "data/enwik8",
        "output": "unified_drift_v19_release.json",
        "mode": "drift",
        "segment_len": 10_000,
        "label": "sban_v19_release_drift",
        "extras": [
            "sequence_seed_path=data/enwik8",
            "sequence_seed_offset=0",
            "sequence_seed_length=1000000",
            "sequence_seed_align_to_segment=true",
            "sequence_seed_replace_on_reset=true",
        ],
    },
    {
        "key": "probe",
        "dataset": "data/elastic_probe.bin",
        "output": "unified_probe_v19_release.json",
        "mode": "prefix",
        "segment_len": 29_000,
        "label": "sban_v19_release_probe",
        "extras": [
            "sequence_seed_path=data/elastic_probe.bin",
            "sequence_seed_offset=0",
            "sequence_seed_length=120100",
        ],
    },
    {
        "key": "long_250k",
        "dataset": "data/enwik8",
        "output": "longrun_v19_250k.json",
        "mode": "prefix",
        "segment_len": 62_500,
        "label": "sban_v19_release_250k",
        "extras": [
            "sequence_seed_path=data/enwik8",
            "sequence_seed_offset=0",
            "sequence_seed_length=1000000",
        ],
    },
    {
        "key": "long_1m",
        "dataset": "data/enwik8",
        "output": "longrun_v19_1m.json",
        "mode": "prefix",
        "segment_len": 250_000,
        "label": "sban_v19_release_1m",
        "extras": [
            "sequence_seed_path=data/enwik8",
            "sequence_seed_offset=0",
            "sequence_seed_length=2000000",
        ],
    },
]


def build_binary(zig_exe: str | None) -> None:
    subprocess.run([zig_exe or "zig", "build", "-Doptimize=ReleaseSafe"], cwd=ROOT, check=True)


def run_capture(cmd: list[str], output_path: Path) -> str:
    text = subprocess.check_output(cmd, cwd=ROOT, text=True)
    output_path.write_text(text, encoding="utf-8")
    return text


def run_eval(spec: dict[str, object]) -> float:
    out_json = RESULTS / str(spec["output"])
    cmd = [
        str(BIN),
        "eval-variant",
        str(ROOT / str(spec["dataset"])),
        str(out_json),
        str(spec["mode"]),
        RELEASE_BITS,
        "default",
        str(spec["segment_len"]),
        "5000",
        "4096",
        f"label={spec['label']}",
        *COMMON_PROFILE,
        *list(spec["extras"]),
    ]
    started = time.time()
    subprocess.run(cmd, cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    elapsed = time.time() - started
    data = json.loads(out_json.read_text(encoding="utf-8"))
    model = data["models"][0]
    acc = 100.0 * model["total_correct"] / model["total_predictions"]
    print(f"{spec['output']}: {acc:.4f}% ({elapsed:.1f}s)")
    return acc


def relative_lift(new: float, old: float) -> float:
    return ((new / old) - 1.0) * 100.0


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the full SBAN v19 release suite.")
    parser.add_argument("--zig-exe", help="Path to zig or zig.exe used for the build step.")
    parser.add_argument("--skip-build", action="store_true", help="Reuse the existing zig-out binary.")
    args = parser.parse_args()

    RESULTS.mkdir(parents=True, exist_ok=True)

    if not args.skip_build:
        build_binary(args.zig_exe)

    if not BIN.exists():
        raise FileNotFoundError(f"missing runtime binary: {BIN}")

    measured: dict[str, float] = {}
    for spec in BENCHMARKS:
        measured[str(spec["key"])] = run_eval(spec)

    print("\nRelative lift over v18:")
    for key, old in V18.items():
        new = measured[key]
        print(f"- {key}: {new:.4f}% vs {old:.4f}% ({relative_lift(new, old):+.2f}%)")

    run_capture(
        [str(BIN), "chat-demo", "what is SBAN v19", "160", "seed_path=data/sban_dialogue_seed_v19.txt"],
        RESULTS / "chat_demo_v19_overview.txt",
    )
    run_capture(
        [str(BIN), "chat-demo", "does it learn while running", "160", "seed_path=data/sban_dialogue_seed_v19.txt"],
        RESULTS / "chat_demo_v19_learning.txt",
    )
    run_capture(
        [str(BIN), "chat-demo", "what is the release message", "160", "seed_path=data/sban_dialogue_seed_v19.txt"],
        RESULTS / "chat_demo_v19_release_message.txt",
    )
    run_capture(
        [str(BIN), "chat-demo", "how do I start the Windows demo", "160", "seed_path=data/sban_dialogue_seed_v19.txt"],
        RESULTS / "chat_demo_v19_setup.txt",
    )
    run_capture(
        [str(BIN), "chat-eval", "data/sban_chat_eval_prompts_v19.txt", "seed_path=data/sban_dialogue_seed_v19.txt"],
        RESULTS / "chat_eval_v19_hybrid.txt",
    )
    run_capture(
        [str(BIN), "chat-eval", "data/sban_chat_eval_prompts_v19.txt", "mode=free", "seed_path=data/sban_dialogue_seed_v19.txt"],
        RESULTS / "chat_eval_v19_free.txt",
    )


if __name__ == "__main__":
    main()
