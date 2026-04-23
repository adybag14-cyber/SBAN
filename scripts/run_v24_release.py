#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "docs" / "results" / "v24"
BIN = ROOT / "zig-out" / "bin" / ("zig_sban.exe" if os.name == "nt" else "zig_sban")

SEED_PATH = "data/sban_dialogue_seed_v24.txt"
OPEN_SEED_PATH = "data/sban_dialogue_open_seed_v24.txt"
PROMPT_PATH = "data/sban_chat_eval_prompts_v24.txt"
SESSION_PATH = "data/sban_session_eval_v24.txt"
OPEN_SESSION_PATH = "data/sban_open_chat_session_eval_v24.txt"

RELEASE_BITS = "4"
NUMERIC_BASELINE = {
    "prefix": 99.6350,
    "drift": 99.5400,
    "probe": 99.9000,
    "long_250k": 99.4076,
    "long_1m": 99.4344,
    "long_10m": 77.9175,
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
    "score_threads=1",
    "numeric_backend=cpu",
]

BENCHMARKS = [
    {
        "key": "prefix",
        "dataset": "data/enwik8",
        "output": "unified_prefix_v24_release.json",
        "mode": "prefix",
        "segment_len": 10_000,
        "checkpoint_interval": 5_000,
        "rolling_window": 4_096,
        "label": "sban_v24_release_prefix",
        "extras": [
            "sequence_seed_path=data/enwik8",
            "sequence_seed_offset=0",
            "sequence_seed_length=1000000",
        ],
    },
    {
        "key": "drift",
        "dataset": "data/enwik8",
        "output": "unified_drift_v24_release.json",
        "mode": "drift",
        "segment_len": 10_000,
        "checkpoint_interval": 5_000,
        "rolling_window": 4_096,
        "label": "sban_v24_release_drift",
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
        "output": "unified_probe_v24_release.json",
        "mode": "prefix",
        "segment_len": 29_000,
        "checkpoint_interval": 5_000,
        "rolling_window": 4_096,
        "label": "sban_v24_release_probe",
        "extras": [
            "sequence_seed_path=data/elastic_probe.bin",
            "sequence_seed_offset=0",
            "sequence_seed_length=120100",
        ],
    },
    {
        "key": "long_250k",
        "dataset": "data/enwik8",
        "output": "longrun_v24_250k.json",
        "mode": "prefix",
        "segment_len": 62_500,
        "checkpoint_interval": 5_000,
        "rolling_window": 4_096,
        "label": "sban_v24_release_250k",
        "extras": [
            "sequence_seed_path=data/enwik8",
            "sequence_seed_offset=0",
            "sequence_seed_length=1000000",
        ],
    },
    {
        "key": "long_1m",
        "dataset": "data/enwik8",
        "output": "longrun_v24_1m.json",
        "mode": "prefix",
        "segment_len": 250_000,
        "checkpoint_interval": 5_000,
        "rolling_window": 4_096,
        "label": "sban_v24_release_1m",
        "extras": [
            "sequence_seed_path=data/enwik8",
            "sequence_seed_offset=0",
            "sequence_seed_length=2000000",
        ],
    },
    {
        "key": "long_10m",
        "dataset": "data/enwik8",
        "output": "longrun_v24_10m.json",
        "mode": "prefix",
        "segment_len": 2_500_000,
        "checkpoint_interval": 100_000,
        "rolling_window": 8_192,
        "label": "sban_v24_release_10m",
        "extras": [
            "include_baseline=false",
            "sequence_seed_path=data/enwik8",
            "sequence_seed_offset=0",
            "sequence_seed_length=4000000",
        ],
    },
]


def resolve_zig_exe(explicit: str | None) -> str:
    if explicit:
        return explicit
    if shutil.which("zig"):
        return shutil.which("zig")  # type: ignore[return-value]
    candidates = [
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


def parse_key_values(text: str) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        parsed[key.strip()] = value.strip()
    return parsed


def run_capture(cmd: list[str], output_path: Path) -> str:
    text = subprocess.check_output(cmd, cwd=ROOT, text=True)
    output_path.write_text(text, encoding="utf-8")
    return text


def run_eval(spec: dict[str, object], resume: bool = False) -> dict[str, float | int]:
    out_json = RESULTS / str(spec["output"])
    if resume and out_json.exists():
        data = json.loads(out_json.read_text(encoding="utf-8"))
        model = data["models"][0]
        acc = 100.0 * model["total_correct"] / model["total_predictions"]
        return {
            "accuracy": acc,
            "elapsed_seconds": 0.0,
            "total_predictions": int(model["total_predictions"]),
        }

    cmd = [
        str(BIN),
        "eval-variant",
        str(ROOT / str(spec["dataset"])),
        str(out_json),
        str(spec["mode"]),
        RELEASE_BITS,
        "default",
        str(spec["segment_len"]),
        str(spec["checkpoint_interval"]),
        str(spec["rolling_window"]),
        f"label={spec['label']}",
        *COMMON_PROFILE,
        *list(spec["extras"]),
    ]
    started = time.perf_counter()
    subprocess.run(cmd, cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    elapsed = time.perf_counter() - started
    data = json.loads(out_json.read_text(encoding="utf-8"))
    model = data["models"][0]
    acc = 100.0 * model["total_correct"] / model["total_predictions"]
    print(f"{spec['output']}: {acc:.4f}% ({elapsed:.1f}s)")
    return {
        "accuracy": acc,
        "elapsed_seconds": elapsed,
        "total_predictions": int(model["total_predictions"]),
    }


def write_accel_bench_assets() -> tuple[Path, Path]:
    seed_text = (ROOT / SEED_PATH).read_text(encoding="utf-8").strip() + "\n\n"
    prompt_lines = (ROOT / PROMPT_PATH).read_text(encoding="utf-8").strip().splitlines()
    bench_seed = RESULTS / "accel_seed_v24_bench.txt"
    bench_prompts = RESULTS / "accel_prompts_v24_bench.txt"
    bench_seed.write_text(seed_text * 200, encoding="utf-8")
    bench_prompts.write_text("\n".join(prompt_lines * 320) + "\n", encoding="utf-8")
    return bench_seed, bench_prompts


def measure_accel_backend(bench_seed: Path, bench_prompts: Path, backend_args: list[str]) -> dict[str, float | int | str]:
    cmd = [
        str(BIN),
        "accel-bench",
        str(bench_prompts),
        *backend_args,
        f"seed_path={bench_seed}",
        "iterations=4",
    ]
    started = time.perf_counter()
    text = subprocess.check_output(cmd, cwd=ROOT, text=True)
    elapsed = time.perf_counter() - started
    parsed = parse_key_values(text)
    if "total_queries" not in parsed:
        raise RuntimeError(f"accel-bench did not return totals for {backend_args}: {text}")
    total_queries = int(parsed["total_queries"])
    total_scores = int(parsed["total_scores"])
    parsed["elapsed_seconds"] = round(elapsed, 6)
    parsed["queries_per_second"] = round(total_queries / elapsed, 2)
    parsed["scores_per_second"] = round(total_scores / elapsed, 2)
    return parsed


def run_numeric_backend_probe(spec: dict[str, object], extra_overrides: list[str], suffix: str) -> dict[str, float | int]:
    out_json = RESULTS / f"probe_{suffix}_{spec['output']}"
    cmd = [
        str(BIN),
        "eval-variant",
        str(ROOT / str(spec["dataset"])),
        str(out_json),
        str(spec["mode"]),
        RELEASE_BITS,
        "default",
        str(spec["segment_len"]),
        str(spec["checkpoint_interval"]),
        str(spec["rolling_window"]),
        f"label={spec['label']}_{suffix}_probe",
        *COMMON_PROFILE,
        *extra_overrides,
        *list(spec["extras"]),
    ]
    started = time.perf_counter()
    subprocess.run(cmd, cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    elapsed = time.perf_counter() - started
    data = json.loads(out_json.read_text(encoding="utf-8"))
    model = data["models"][0]
    acc = 100.0 * model["total_correct"] / model["total_predictions"]
    return {
        "accuracy": acc,
        "elapsed_seconds": elapsed,
        "total_predictions": int(model["total_predictions"]),
    }


def run_numeric_accel_info(extra_overrides: list[str], output_name: str) -> None:
    run_capture([str(BIN), "numeric-accel-info", *extra_overrides], RESULTS / output_name)


def capture_nvidia_smi(output_path: Path) -> None:
    if shutil.which("nvidia-smi") is None:
        return
    try:
        text = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,driver_version", "--format=csv,noheader"],
            cwd=ROOT,
            text=True,
        )
    except subprocess.CalledProcessError:
        return
    output_path.write_text(text, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the SBAN v24 conversational release suite.")
    parser.add_argument("--zig-exe", help="Path to zig or zig.exe used for the build step.")
    parser.add_argument("--skip-build", action="store_true", help="Reuse the existing zig-out binary.")
    parser.add_argument("--resume", action="store_true", help="Reuse existing benchmark JSON files and continue from missing outputs.")
    args = parser.parse_args()

    RESULTS.mkdir(parents=True, exist_ok=True)

    if not args.skip_build:
        build_binary(args.zig_exe)

    if not BIN.exists():
        raise FileNotFoundError(f"missing runtime binary: {BIN}")

    measured: dict[str, dict[str, float | int]] = {}
    for spec in BENCHMARKS:
        measured[str(spec["key"])] = run_eval(spec, resume=args.resume)

    print("\nDelta vs packaged numeric baseline (percentage points):")
    for key, old in NUMERIC_BASELINE.items():
        new = float(measured[key]["accuracy"])
        print(f"- {key}: {new:.4f}% vs {old:.4f}% ({new - old:+.4f} pp)")

    common_chat_args = [
        "mode=free",
        "allow_generation=true",
        "backend=cpu",
        f"seed_path={SEED_PATH}",
        f"open_seed_path={OPEN_SEED_PATH}",
    ]
    run_capture([str(BIN), "chat-demo", "what is SBAN v24", "220", *common_chat_args], RESULTS / "chat_demo_v24_overview.txt")
    run_capture([str(BIN), "chat-demo", "what files ship in the bundle", "220", *common_chat_args], RESULTS / "chat_demo_v24_bundle.txt")
    run_capture([str(BIN), "chat-demo", "where is the v24 paper pdf", "220", *common_chat_args], RESULTS / "chat_demo_v24_paper.txt")
    run_capture([str(BIN), "chat-demo", "what command shows cuda support", "220", *common_chat_args], RESULTS / "chat_demo_v24_cuda_command.txt")
    run_capture([str(BIN), "chat-demo", "can this run on an rtx 4090", "220", *common_chat_args], RESULTS / "chat_demo_v24_rtx.txt")
    run_capture([str(BIN), "chat-demo", "can you remember where i am from", "220", *common_chat_args], RESULTS / "chat_demo_v24_memory_capability.txt")
    run_capture([str(BIN), "chat-demo", "can you help me plan tomorrow", "220", *common_chat_args], RESULTS / "chat_demo_v24_planning.txt")
    run_capture([str(BIN), "chat-demo", "what should i do this weekend", "220", *common_chat_args], RESULTS / "chat_demo_v24_weekend.txt")
    run_capture([str(BIN), "chat-demo", "blorple zint protocol", "220", *common_chat_args], RESULTS / "chat_demo_v24_uncertainty.txt")

    run_capture([str(BIN), "chat-eval", PROMPT_PATH, "mode=hybrid", "allow_generation=false", "backend=cpu", f"seed_path={SEED_PATH}", f"open_seed_path={OPEN_SEED_PATH}"], RESULTS / "chat_eval_v24_hybrid.txt")
    run_capture([str(BIN), "chat-eval", PROMPT_PATH, "mode=free", "allow_generation=true", "backend=cpu", f"seed_path={SEED_PATH}", f"open_seed_path={OPEN_SEED_PATH}"], RESULTS / "chat_eval_v24_free.txt")
    run_capture([str(BIN), "chat-session-eval", SESSION_PATH, "mode=free", "allow_generation=true", "backend=cpu", f"seed_path={SEED_PATH}", f"open_seed_path={OPEN_SEED_PATH}"], RESULTS / "chat_session_eval_v24.txt")
    run_capture([str(BIN), "chat-session-eval", OPEN_SESSION_PATH, "mode=free", "allow_generation=true", "backend=cpu", f"seed_path={SEED_PATH}", f"open_seed_path={OPEN_SEED_PATH}"], RESULTS / "open_chat_session_eval_v24.txt")

    run_capture([str(BIN), "accel-info", f"seed_path={SEED_PATH}", "backend=cpu_mt", "threads=4"], RESULTS / "accel_info_v24_cpu_mt.txt")
    run_capture([str(BIN), "accel-info", f"seed_path={SEED_PATH}", "backend=cuda"], RESULTS / "accel_info_v24_cuda.txt")
    run_numeric_accel_info(["numeric_backend=cpu"], "numeric_accel_info_v24_cpu.txt")
    run_numeric_accel_info(["numeric_backend=cpu_mt", "score_threads=4", "parallel_score_min_predictive_nodes=1"], "numeric_accel_info_v24_cpu_mt.txt")
    run_numeric_accel_info(["numeric_backend=cuda", "cuda_min_scoring_edges=1"], "numeric_accel_info_v24_cuda.txt")
    capture_nvidia_smi(RESULTS / "nvidia_smi_v24.txt")

    bench_seed, bench_prompts = write_accel_bench_assets()
    accel_results = {
        "cpu": measure_accel_backend(bench_seed, bench_prompts, ["backend=cpu"]),
        "cpu_mt": measure_accel_backend(bench_seed, bench_prompts, ["backend=cpu_mt", "threads=4"]),
        "cuda": measure_accel_backend(bench_seed, bench_prompts, ["backend=cuda"]),
    }
    accel_results["speedup_cuda_vs_cpu"] = round(float(accel_results["cpu"]["elapsed_seconds"]) / float(accel_results["cuda"]["elapsed_seconds"]), 4)
    accel_results["speedup_cpu_mt_vs_cpu"] = round(float(accel_results["cpu"]["elapsed_seconds"]) / float(accel_results["cpu_mt"]["elapsed_seconds"]), 4)
    (RESULTS / "accel_bench_v24.json").write_text(json.dumps(accel_results, indent=2), encoding="utf-8")

    numeric_backend = {
        "release_cpu_250k": run_numeric_backend_probe(next(spec for spec in BENCHMARKS if spec["key"] == "long_250k"), [], "cpu"),
        "release_cpu_1m": run_numeric_backend_probe(next(spec for spec in BENCHMARKS if spec["key"] == "long_1m"), [], "cpu"),
        "release_cpu_mt4_250k": run_numeric_backend_probe(next(spec for spec in BENCHMARKS if spec["key"] == "long_250k"), ["numeric_backend=cpu_mt", "score_threads=4", "parallel_score_min_predictive_nodes=128"], "cpu_mt4"),
        "release_cpu_mt4_1m": run_numeric_backend_probe(next(spec for spec in BENCHMARKS if spec["key"] == "long_1m"), ["numeric_backend=cpu_mt", "score_threads=4", "parallel_score_min_predictive_nodes=128"], "cpu_mt4"),
        "release_cuda_250k": run_numeric_backend_probe(next(spec for spec in BENCHMARKS if spec["key"] == "long_250k"), ["numeric_backend=cuda", "cuda_min_scoring_edges=1"], "cuda"),
        "release_cuda_1m": run_numeric_backend_probe(next(spec for spec in BENCHMARKS if spec["key"] == "long_1m"), ["numeric_backend=cuda", "cuda_min_scoring_edges=1"], "cuda"),
    }
    numeric_backend["speedup_cpu_mt_vs_cpu_250k"] = round(float(numeric_backend["release_cpu_250k"]["elapsed_seconds"]) / float(numeric_backend["release_cpu_mt4_250k"]["elapsed_seconds"]), 4)
    numeric_backend["speedup_cuda_vs_cpu_250k"] = round(float(numeric_backend["release_cpu_250k"]["elapsed_seconds"]) / float(numeric_backend["release_cuda_250k"]["elapsed_seconds"]), 4)
    numeric_backend["speedup_cpu_mt_vs_cpu_1m"] = round(float(numeric_backend["release_cpu_1m"]["elapsed_seconds"]) / float(numeric_backend["release_cpu_mt4_1m"]["elapsed_seconds"]), 4)
    numeric_backend["speedup_cuda_vs_cpu_1m"] = round(float(numeric_backend["release_cpu_1m"]["elapsed_seconds"]) / float(numeric_backend["release_cuda_1m"]["elapsed_seconds"]), 4)
    (RESULTS / "numeric_backend_v24.json").write_text(json.dumps(numeric_backend, indent=2), encoding="utf-8")

    status_text = (
        "SBAN v24 keeps the packaged numeric suite on numeric_backend=cpu and score_threads=1 so the regression-safe CPU path remains the release baseline. "
        "The product release focus is conversational: a real v24 grounded seed, a separate v24 open-chat seed, broader operational answers, stronger session-memory behavior, and a versioned open-chat evaluation that measures broader free chat directly.\n"
    )
    (RESULTS / "STATUS.md").write_text(status_text, encoding="utf-8")


if __name__ == "__main__":
    main()
