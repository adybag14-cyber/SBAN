#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path

from host_monitor import HeartbeatMonitor

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "docs" / "results" / "v28"
BIN = ROOT / "zig-out" / "bin" / ("zig_sban.exe" if os.name == "nt" else "zig_sban")
HEARTBEAT_LOG = RESULTS / "_run_v28_100m_ci_heartbeat.jsonl"
MONITOR: HeartbeatMonitor | None = None

RELEASE_BITS = "4"
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


def resolve_zig_exe(explicit: str | None) -> str:
    if explicit:
        return explicit
    if shutil.which("zig"):
        return shutil.which("zig")  # type: ignore[return-value]
    candidates = [
        Path.home() / "Downloads" / "zig-x86_64-windows-0.17.0-dev.87+9b177a7d2" / "zig-x86_64-windows-0.17.0-dev.87+9b177a7d2" / "zig.exe",
        Path.home() / "Documents" / "toolchains" / "zig-0.17.0-dev.87" / "zig-x86_64-windows-0.17.0-dev.87+9b177a7d2" / "zig.exe",
        Path.home() / "tools" / "zig-x86_64-windows-0.17.0-dev.87+9b177a7d2" / "zig.exe",
        Path.home() / "work" / "zig-0.17.0-dev.87" / "zig-x86_64-windows-0.17.0-dev.87+9b177a7d2" / "zig.exe",
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    raise FileNotFoundError("zig not found on PATH and no known local toolchain candidate exists")


def build_binary(zig_exe: str | None) -> None:
    subprocess.run([resolve_zig_exe(zig_exe), "build", "-Doptimize=ReleaseFast"], cwd=ROOT, check=True)


def run_subprocess_with_heartbeat(cmd: list[str], label: str, heartbeat_seconds: int = 30) -> float:
    if MONITOR is None:
        raise RuntimeError("heartbeat monitor not initialized")
    return MONITOR.run_subprocess(cmd, label, heartbeat_seconds=heartbeat_seconds)


def run_eval(output_name: str, extra_overrides: list[str]) -> dict[str, float | int | str]:
    out_json = RESULTS / output_name
    cmd = [
        str(BIN),
        "eval-variant",
        str(ROOT / "data" / "enwik8"),
        str(out_json),
        "prefix",
        RELEASE_BITS,
        "default",
        "24999999",
        "1000000",
        "16384",
        "label=sban_v28_ci_100m",
        *COMMON_PROFILE,
        *extra_overrides,
        "include_baseline=false",
        "markov4_bonus_ppm=0",
        "markov5_bonus_ppm=0",
        "continuation_bonus_ppm=0",
        "continuation_min_order=0",
        "continuation_max_order=0",
        "sequence_seed_path=data/enwik8",
        "sequence_seed_offset=0",
        "sequence_seed_length=8000000",
    ]
    elapsed = run_subprocess_with_heartbeat(cmd, "v28 100m ci")
    data = json.loads(out_json.read_text(encoding="utf-8"))
    model = data["models"][0]
    acc = 100.0 * model["total_correct"] / model["total_predictions"]
    return {
        "output": output_name,
        "accuracy": round(acc, 4),
        "elapsed_seconds": round(elapsed, 6),
        "total_predictions": int(model["total_predictions"]),
    }


def main() -> None:
    global MONITOR
    parser = argparse.ArgumentParser(description="Run the SBAN v28 near-100M hardening attempt on CI.")
    parser.add_argument("--zig-exe", help="Path to zig or zig.exe used for the build step.")
    parser.add_argument("--skip-build", action="store_true", help="Reuse the existing zig-out binary.")
    parser.add_argument("--numeric-backend", default="cpu", choices=["cpu", "cpu_mt"], help="Numeric backend for the 100M attempt.")
    parser.add_argument("--score-threads", type=int, default=1, help="score_threads override when numeric-backend=cpu_mt.")
    args = parser.parse_args()

    RESULTS.mkdir(parents=True, exist_ok=True)
    MONITOR = HeartbeatMonitor(ROOT, HEARTBEAT_LOG)
    status_path = RESULTS / "longrun_v28_100m_ci_status.txt"
    summary_path = RESULTS / "longrun_v28_100m_ci_summary.json"
    MONITOR.emit(
        "startup",
        "run_v28_100m_ci",
        0.0,
        None,
        message=f"skip_build={args.skip_build} numeric_backend={args.numeric_backend} score_threads={args.score_threads}",
    )

    if not args.skip_build:
        build_binary(args.zig_exe)

    if not BIN.exists():
        raise FileNotFoundError(f"missing runtime binary: {BIN}")

    overrides = [f"numeric_backend={args.numeric_backend}"]
    if args.numeric_backend == "cpu_mt":
        overrides.extend([f"score_threads={args.score_threads}", "parallel_score_min_predictive_nodes=128"])
        output_name = "longrun_v28_100m_ci_cpu_mt.json"
    else:
        overrides.append("score_threads=1")
        output_name = "longrun_v28_100m_ci_cpu.json"

    status_path.write_text(
        f"started=true\noutput={output_name}\nnumeric_backend={args.numeric_backend}\nscore_threads={args.score_threads}\n",
        encoding="utf-8",
    )
    result = run_eval(output_name, overrides)
    status_path.write_text(
        "started=true\ncompleted=true\n"
        f"output={result['output']}\n"
        f"accuracy={result['accuracy']}\n"
        f"elapsed_seconds={result['elapsed_seconds']}\n"
        f"total_predictions={result['total_predictions']}\n"
        f"numeric_backend={args.numeric_backend}\n"
        f"score_threads={args.score_threads}\n",
        encoding="utf-8",
    )
    summary_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
