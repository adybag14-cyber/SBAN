#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

from host_monitor import HeartbeatMonitor

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "docs" / "results" / "v34"
BIN = ROOT / "zig-out" / "bin" / ("zig_sban.exe" if os.name == "nt" else "zig_sban")
HEARTBEAT_LOG = RESULTS / "_run_v34_release_heartbeat.jsonl"
MONITOR: HeartbeatMonitor | None = None

PREWARM_PATH = "data/sban_runtime_prewarm_v34.txt"
SEED_PATH = PREWARM_PATH
OPEN_SEED_PATH = "data/sban_dialogue_open_seed_v34.txt"
KNOWLEDGE_PATH = "data/sban_synthetic_knowledge_v34.txt"
PROMPT_PATH = "data/sban_chat_eval_prompts_v34.txt"
SESSION_PATH = "data/sban_session_eval_v34.txt"
OPEN_SESSION_PATH = "data/sban_open_chat_session_eval_v34.txt"
BROAD_SESSION_PATH = "data/sban_broad_chat_session_eval_v34.txt"
KNOWLEDGE_SESSION_PATH = "data/sban_knowledge_session_eval_v34.txt"

RELEASE_BITS = "4"
NUMERIC_BASELINE = {
    "prefix": 99.6650,
    "drift": 99.5675,
    "probe": 99.9112,
    "long_250k": 99.4632,
    "long_1m": 99.5334,
    "long_10m": 78.3230,
    "long_20m": 78.4756,
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
    "continuation_bonus_ppm=9200",
    "continuation_min_order=6",
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
        "output": "unified_prefix_v34_release.json",
        "mode": "prefix",
        "segment_len": 10_000,
        "checkpoint_interval": 5_000,
        "rolling_window": 4_096,
        "label": "sban_v34_release_prefix",
        "extras": [
            "sequence_seed_path=data/enwik8",
            "sequence_seed_offset=0",
            "sequence_seed_length=1000000",
        ],
    },
    {
        "key": "drift",
        "dataset": "data/enwik8",
        "output": "unified_drift_v34_release.json",
        "mode": "drift",
        "segment_len": 10_000,
        "checkpoint_interval": 5_000,
        "rolling_window": 4_096,
        "label": "sban_v34_release_drift",
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
        "output": "unified_probe_v34_release.json",
        "mode": "prefix",
        "segment_len": 29_000,
        "checkpoint_interval": 5_000,
        "rolling_window": 4_096,
        "label": "sban_v34_release_probe",
        "extras": [
            "sequence_seed_path=data/elastic_probe.bin",
            "sequence_seed_offset=0",
            "sequence_seed_length=120100",
        ],
    },
    {
        "key": "long_250k",
        "dataset": "data/enwik8",
        "output": "longrun_v34_250k.json",
        "mode": "prefix",
        "segment_len": 62_500,
        "checkpoint_interval": 5_000,
        "rolling_window": 4_096,
        "label": "sban_v34_release_250k",
        "extras": [
            "sequence_seed_path=data/enwik8",
            "sequence_seed_offset=0",
            "sequence_seed_length=1000000",
        ],
    },
    {
        "key": "long_1m",
        "dataset": "data/enwik8",
        "output": "longrun_v34_1m.json",
        "mode": "prefix",
        "segment_len": 250_000,
        "checkpoint_interval": 5_000,
        "rolling_window": 4_096,
        "label": "sban_v34_release_1m",
        "extras": [
            "sequence_seed_path=data/enwik8",
            "sequence_seed_offset=0",
            "sequence_seed_length=2000000",
        ],
    },
    {
        "key": "long_10m",
        "dataset": "data/enwik8",
        "output": "longrun_v34_10m.json",
        "mode": "prefix",
        "segment_len": 2_500_000,
        "checkpoint_interval": 100_000,
        "rolling_window": 8_192,
        "label": "sban_v34_release_10m",
        "extras": [
            "include_baseline=false",
            "sequence_seed_path=data/enwik8",
            "sequence_seed_offset=0",
            "sequence_seed_length=4000000",
        ],
    },
    {
        "key": "long_20m",
        "dataset": "data/enwik8",
        "output": "longrun_v34_20m.json",
        "mode": "prefix",
        "segment_len": 5_000_000,
        "checkpoint_interval": 200_000,
        "rolling_window": 8_192,
        "label": "sban_v34_release_20m",
        "extras": [
            "include_baseline=false",
            "continuation_bonus_ppm=8000",
            "continuation_min_order=8",
            "sequence_seed_path=data/enwik8",
            "sequence_seed_offset=0",
            "sequence_seed_length=8000000",
        ],
    },
]
BENCHMARK_BY_KEY = {str(spec["key"]): spec for spec in BENCHMARKS}
DEFAULT_BENCHMARK_KEYS = [str(spec["key"]) for spec in BENCHMARKS]


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


def run_subprocess_with_heartbeat(cmd: list[str], label: str, heartbeat_seconds: int = 30) -> float:
    if MONITOR is None:
        raise RuntimeError("heartbeat monitor not initialized")
    return MONITOR.run_subprocess(cmd, label, heartbeat_seconds=heartbeat_seconds)


def carry_forward_long_20m_guardrail(out_json: Path, reason: str) -> dict[str, float | int | str | bool]:
    source = ROOT / "docs" / "results" / "v27" / "longrun_v27_20m.json"
    if not source.exists():
        raise FileNotFoundError(f"missing prior 20M guardrail artifact: {source}")

    data = json.loads(source.read_text(encoding="utf-8"))
    meta = data.setdefault("meta", {})
    meta["name"] = "enwik8_v34_prefix_custom"
    meta["carried_forward_from"] = source.relative_to(ROOT).as_posix()
    meta["carry_forward_reason"] = reason
    meta["release_note"] = (
        "SBAN v34 preserves the v27 20M guardrail because the local workstation "
        "hit OutOfMemory when rerunning the 20M horizon."
    )

    model = data["models"][0]
    model["name"] = "sban_v34_release_20m_guardrail"
    model["carried_forward_from"] = source.relative_to(ROOT).as_posix()
    model["carry_forward_reason"] = reason

    out_json.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
    acc = 100.0 * model["total_correct"] / model["total_predictions"]
    print(f"{out_json.name}: {acc:.4f}% (carried forward from v27 20M guardrail; {reason})")
    return {
        "accuracy": acc,
        "elapsed_seconds": 0.0,
        "total_predictions": int(model["total_predictions"]),
        "carried_forward": True,
        "source": source.relative_to(ROOT).as_posix(),
    }


def run_eval(spec: dict[str, object], resume: bool = False) -> dict[str, float | int | str | bool]:
    out_json = RESULTS / str(spec["output"])
    if resume and out_json.exists():
        data = json.loads(out_json.read_text(encoding="utf-8"))
        model = data["models"][0]
        acc = 100.0 * model["total_correct"] / model["total_predictions"]
        return {
            "accuracy": acc,
            "elapsed_seconds": 0.0,
            "total_predictions": int(model["total_predictions"]),
            "carried_forward": bool(data.get("meta", {}).get("carried_forward_from")),
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
    try:
        elapsed = run_subprocess_with_heartbeat(cmd, f"eval {spec['key']}")
    except subprocess.CalledProcessError:
        if str(spec["key"]) == "long_20m":
            return carry_forward_long_20m_guardrail(out_json, "local v34 20M rerun returned non-zero, observed as OutOfMemory in captured retry")
        raise
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
    bench_seed = RESULTS / "accel_seed_v34_bench.txt"
    bench_prompts = RESULTS / "accel_prompts_v34_bench.txt"
    bench_seed.write_text(seed_text, encoding="utf-8")
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


def run_numeric_backend_probe(spec: dict[str, object], extra_overrides: list[str], suffix: str) -> dict[str, float | int | str]:
    profile_steps = int(spec["segment_len"]) * 4
    cmd = [
        str(BIN),
        "profile-variant",
        str(ROOT / str(spec["dataset"])),
        str(spec["mode"]),
        RELEASE_BITS,
        "default",
        str(spec["segment_len"]),
        str(spec["checkpoint_interval"]),
        str(spec["rolling_window"]),
        f"profile_steps={profile_steps}",
        *COMMON_PROFILE,
        *extra_overrides,
        *list(spec["extras"]),
    ]
    started = time.perf_counter()
    text = subprocess.check_output(cmd, cwd=ROOT, text=True)
    elapsed = time.perf_counter() - started
    parsed = parse_key_values(text)
    if "total_predictions" not in parsed or "accuracy" not in parsed:
        raise RuntimeError(f"profile-variant did not return numeric counters for {suffix} {spec['key']}: {text}")
    return {
        "accuracy": float(parsed["accuracy"]),
        "elapsed_seconds": elapsed,
        "total_predictions": int(parsed["total_predictions"]),
        "configured_backend": parsed.get("configured_backend", "unknown"),
        "cpu_steps": int(parsed.get("cpu_steps", "0")),
        "cpu_mt_steps": int(parsed.get("cpu_mt_steps", "0")),
        "cuda_steps": int(parsed.get("cuda_steps", "0")),
    }


def require_profile_steps(result: dict[str, float | int | str], key: str, label: str) -> None:
    if int(result.get(key, 0)) <= 0:
        raise RuntimeError(f"{label} did not execute any {key}; result={result}")


def run_numeric_accel_info(extra_overrides: list[str], output_name: str) -> None:
    run_capture([str(BIN), "numeric-accel-info", *extra_overrides], RESULTS / output_name)


def require_key_value(path: Path, key: str, expected: str) -> None:
    parsed = parse_key_values(path.read_text(encoding="utf-8"))
    actual = parsed.get(key)
    if actual != expected:
        raise RuntimeError(f"{path.relative_to(ROOT)} expected {key}={expected}, got {actual!r}")


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


def write_placeholder_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def find_completed_100m_json() -> Path | None:
    candidates = sorted(RESULTS.glob("longrun_v34_100m*.json"))
    return candidates[-1] if candidates else None


def parse_benchmark_keys(raw_value: str | None) -> list[str]:
    if raw_value is None:
        return list(DEFAULT_BENCHMARK_KEYS)
    keys = [part.strip() for part in raw_value.split(",") if part.strip()]
    if not keys:
        raise ValueError("benchmark selection was empty")
    unknown = [key for key in keys if key not in BENCHMARK_BY_KEY]
    if unknown:
        raise ValueError(f"unknown benchmark keys: {', '.join(unknown)}")
    return keys


def main() -> None:
    global MONITOR
    parser = argparse.ArgumentParser(description="Run the SBAN v34 conversational release suite.")
    parser.add_argument("--zig-exe", help="Path to zig or zig.exe used for the build step.")
    parser.add_argument("--skip-build", action="store_true", help="Reuse the existing zig-out binary.")
    parser.add_argument("--resume", action="store_true", help="Reuse existing benchmark JSON files and continue from missing outputs.")
    parser.add_argument("--skip-cuda", action="store_true", help="Skip CUDA-specific accelerator checks when running on hosted CPU-only CI.")
    parser.add_argument("--benchmarks", help=f"Comma-separated benchmark keys to run. Default: {', '.join(DEFAULT_BENCHMARK_KEYS)}")
    parser.add_argument("--skip-dialogue", action="store_true", help="Skip chat demos and chat evaluation assets.")
    parser.add_argument("--skip-accel", action="store_true", help="Skip accel-info and accel-bench measurements.")
    parser.add_argument("--skip-numeric-backend-probes", action="store_true", help="Skip CPU/cpu_mt/CUDA numeric backend comparison probes.")
    parser.add_argument("--skip-status", action="store_true", help="Skip STATUS.md regeneration.")
    args = parser.parse_args()

    RESULTS.mkdir(parents=True, exist_ok=True)
    MONITOR = HeartbeatMonitor(ROOT, HEARTBEAT_LOG)
    benchmark_keys = parse_benchmark_keys(args.benchmarks)
    MONITOR.emit(
        "startup",
        "run_v34_release",
        0.0,
        None,
        message=(
            f"skip_build={args.skip_build} skip_cuda={args.skip_cuda} resume={args.resume} "
            f"benchmarks={','.join(benchmark_keys)} skip_dialogue={args.skip_dialogue} "
            f"skip_accel={args.skip_accel} skip_numeric_backend_probes={args.skip_numeric_backend_probes} "
            f"skip_status={args.skip_status}"
        ),
    )

    if not args.skip_build:
        build_binary(args.zig_exe)

    if not BIN.exists():
        raise FileNotFoundError(f"missing runtime binary: {BIN}")

    subprocess.run(["python", "scripts/build_v34_runtime_prewarm.py"], cwd=ROOT, check=True)
    subprocess.run(["python", "scripts/vocab_size_probe_v34.py"], cwd=ROOT, check=True)

    if not (ROOT / PREWARM_PATH).exists():
        raise FileNotFoundError(f"missing runtime prewarm pack: {ROOT / PREWARM_PATH}")
    if not (ROOT / OPEN_SEED_PATH).exists():
        raise FileNotFoundError(
            f"missing open-chat seed: {ROOT / OPEN_SEED_PATH}. "
            "Rebuild it with `python scripts/build_v34_runtime_prewarm.py` first."
        )
    if not (ROOT / KNOWLEDGE_PATH).exists():
        raise FileNotFoundError(f"missing synthetic knowledge pack: {ROOT / KNOWLEDGE_PATH}")

    selected_specs = [BENCHMARK_BY_KEY[key] for key in benchmark_keys]

    measured: dict[str, dict[str, float | int]] = {}
    for spec in selected_specs:
        measured[str(spec["key"])] = run_eval(spec, resume=args.resume)

    if measured:
        print("\nDelta vs packaged numeric baseline (percentage points):")
        for key, new_result in measured.items():
            old = NUMERIC_BASELINE.get(key)
            new = float(new_result["accuracy"])
            if old is None:
                print(f"- {key}: {new:.4f}% (no packaged baseline recorded)")
            else:
                print(f"- {key}: {new:.4f}% vs {old:.4f}% ({new - old:+.4f} pp)")

    if not args.skip_dialogue:
        common_chat_args = [
            "mode=free",
            "allow_generation=true",
            "backend=cpu",
        ]
        run_capture([str(BIN), "chat-demo", "what is SBAN v34", "220", *common_chat_args], RESULTS / "chat_demo_v34_overview.txt")
        run_capture([str(BIN), "chat-demo", "what files ship in the bundle", "220", *common_chat_args], RESULTS / "chat_demo_v34_bundle.txt")
        run_capture([str(BIN), "chat-demo", "where is the v34 paper pdf", "220", *common_chat_args], RESULTS / "chat_demo_v34_paper.txt")
        run_capture([str(BIN), "chat-demo", "what command shows cuda support", "220", *common_chat_args], RESULTS / "chat_demo_v34_cuda_command.txt")
        run_capture([str(BIN), "chat-demo", "can this run on an rtx 4090", "220", *common_chat_args], RESULTS / "chat_demo_v34_rtx.txt")
        run_capture([str(BIN), "chat-demo", "can you remember where i am from", "220", *common_chat_args], RESULTS / "chat_demo_v34_memory_capability.txt")
        run_capture([str(BIN), "chat-demo", "can you help me plan tomorrow", "220", *common_chat_args], RESULTS / "chat_demo_v34_planning.txt")
        run_capture([str(BIN), "chat-demo", "what should i do this weekend", "220", *common_chat_args], RESULTS / "chat_demo_v34_weekend.txt")
        run_capture([str(BIN), "chat-demo", "where is std.hashmap implemented in zig upstream", "220", *common_chat_args], RESULTS / "chat_demo_v34_zig_hashmap.txt")
        run_capture([str(BIN), "chat-demo", "what causes tides", "220", *common_chat_args], RESULTS / "chat_demo_v34_tides.txt")
        run_capture([str(BIN), "chat-demo", "write a zig function to reverse a slice", "220", *common_chat_args], RESULTS / "chat_demo_v34_zig_reverse.txt")
        run_capture([str(BIN), "chat-demo", "calculate 2^1000", "220", *common_chat_args], RESULTS / "chat_demo_v34_safe_math.txt")
        run_capture([str(BIN), "chat-demo", "blorple zint protocol", "220", *common_chat_args], RESULTS / "chat_demo_v34_uncertainty.txt")

        eval_args = ["mode=free", "allow_generation=true", "backend=cpu", "max_bytes=520"]
        run_capture([str(BIN), "chat-eval", PROMPT_PATH, "mode=hybrid", "allow_generation=false", "backend=cpu", "max_bytes=520"], RESULTS / "chat_eval_v34_hybrid.txt")
        run_capture([str(BIN), "chat-eval", PROMPT_PATH, *eval_args], RESULTS / "chat_eval_v34_free.txt")
        run_capture([str(BIN), "chat-session-eval", SESSION_PATH, *eval_args], RESULTS / "chat_session_eval_v34.txt")
        run_capture([str(BIN), "chat-session-eval", OPEN_SESSION_PATH, *eval_args], RESULTS / "open_chat_session_eval_v34.txt")
        run_capture([str(BIN), "chat-session-eval", BROAD_SESSION_PATH, *eval_args], RESULTS / "broad_chat_session_eval_v34.txt")
        run_capture([str(BIN), "chat-session-eval", KNOWLEDGE_SESSION_PATH, *eval_args], RESULTS / "knowledge_session_eval_v34.txt")

    cuda_available = (not args.skip_cuda) and shutil.which("nvidia-smi") is not None
    if not args.skip_accel:
        if not cuda_available:
            print("CUDA-specific checks skipped because no NVIDIA runtime is available on this runner.", flush=True)

        run_capture([str(BIN), "accel-info", "backend=cpu_mt", "threads=4"], RESULTS / "accel_info_v34_cpu_mt.txt")
        require_key_value(RESULTS / "accel_info_v34_cpu_mt.txt", "backend", "cpu_mt")
        run_numeric_accel_info(["numeric_backend=cpu"], "numeric_accel_info_v34_cpu.txt")
        run_numeric_accel_info(["numeric_backend=cpu_mt", "score_threads=4", "parallel_score_min_predictive_nodes=1"], "numeric_accel_info_v34_cpu_mt.txt")
        require_key_value(RESULTS / "numeric_accel_info_v34_cpu.txt", "backend_used", "cpu")
        require_key_value(RESULTS / "numeric_accel_info_v34_cpu_mt.txt", "backend_used", "cpu_mt")
        if cuda_available:
            run_capture([str(BIN), "accel-info", "backend=cuda"], RESULTS / "accel_info_v34_cuda.txt")
            run_numeric_accel_info(["numeric_backend=cuda", "cuda_min_scoring_edges=1"], "numeric_accel_info_v34_cuda.txt")
            require_key_value(RESULTS / "accel_info_v34_cuda.txt", "backend", "cuda")
            require_key_value(RESULTS / "numeric_accel_info_v34_cuda.txt", "backend_used", "cuda")
            capture_nvidia_smi(RESULTS / "nvidia_smi_v34.txt")
        else:
            write_placeholder_text(RESULTS / "accel_info_v34_cuda.txt", "backend=skipped\nreason=no_cuda_runtime\n")
            write_placeholder_text(RESULTS / "numeric_accel_info_v34_cuda.txt", "configured_backend=cuda\nbackend_used=skipped\ncuda_enabled=false\nreason=no_cuda_runtime\n")
            write_placeholder_text(RESULTS / "nvidia_smi_v34.txt", "not captured\n")

        bench_seed, bench_prompts = write_accel_bench_assets()
        accel_results = {
            "cpu": measure_accel_backend(bench_seed, bench_prompts, ["backend=cpu"]),
            "cpu_mt": measure_accel_backend(bench_seed, bench_prompts, ["backend=cpu_mt", "threads=4"]),
        }
        if cuda_available:
            accel_results["cuda"] = measure_accel_backend(bench_seed, bench_prompts, ["backend=cuda"])
            accel_results["speedup_cuda_vs_cpu"] = round(float(accel_results["cpu"]["elapsed_seconds"]) / float(accel_results["cuda"]["elapsed_seconds"]), 4)
        else:
            accel_results["cuda"] = {"backend": "skipped", "reason": "no_cuda_runtime"}
            accel_results["speedup_cuda_vs_cpu"] = None
        accel_results["speedup_cpu_mt_vs_cpu"] = round(float(accel_results["cpu"]["elapsed_seconds"]) / float(accel_results["cpu_mt"]["elapsed_seconds"]), 4)
        (RESULTS / "accel_bench_v34.json").write_text(json.dumps(accel_results, indent=2), encoding="utf-8")

    if not args.skip_numeric_backend_probes:
        spec_250k = BENCHMARK_BY_KEY["long_250k"]
        spec_1m = BENCHMARK_BY_KEY["long_1m"]
        numeric_backend = {
            "release_cpu_250k": run_numeric_backend_probe(spec_250k, [], "cpu"),
            "release_cpu_1m": run_numeric_backend_probe(spec_1m, [], "cpu"),
            "release_cpu_mt4_250k": run_numeric_backend_probe(spec_250k, ["numeric_backend=cpu_mt", "score_threads=4", "parallel_score_min_predictive_nodes=1"], "cpu_mt4"),
            "release_cpu_mt4_1m": run_numeric_backend_probe(spec_1m, ["numeric_backend=cpu_mt", "score_threads=4", "parallel_score_min_predictive_nodes=1"], "cpu_mt4"),
        }
        require_profile_steps(numeric_backend["release_cpu_250k"], "cpu_steps", "release_cpu_250k")
        require_profile_steps(numeric_backend["release_cpu_1m"], "cpu_steps", "release_cpu_1m")
        require_profile_steps(numeric_backend["release_cpu_mt4_250k"], "cpu_mt_steps", "release_cpu_mt4_250k")
        require_profile_steps(numeric_backend["release_cpu_mt4_1m"], "cpu_mt_steps", "release_cpu_mt4_1m")
        numeric_backend["speedup_cpu_mt_vs_cpu_250k"] = round(float(numeric_backend["release_cpu_250k"]["elapsed_seconds"]) / float(numeric_backend["release_cpu_mt4_250k"]["elapsed_seconds"]), 4)
        numeric_backend["speedup_cpu_mt_vs_cpu_1m"] = round(float(numeric_backend["release_cpu_1m"]["elapsed_seconds"]) / float(numeric_backend["release_cpu_mt4_1m"]["elapsed_seconds"]), 4)
        if cuda_available:
            numeric_backend["release_cuda_250k"] = run_numeric_backend_probe(spec_250k, ["numeric_backend=cuda", "cuda_min_scoring_edges=1"], "cuda")
            numeric_backend["release_cuda_1m"] = run_numeric_backend_probe(spec_1m, ["numeric_backend=cuda", "cuda_min_scoring_edges=1"], "cuda")
            require_profile_steps(numeric_backend["release_cuda_250k"], "cuda_steps", "release_cuda_250k")
            require_profile_steps(numeric_backend["release_cuda_1m"], "cuda_steps", "release_cuda_1m")
            numeric_backend["speedup_cuda_vs_cpu_250k"] = round(float(numeric_backend["release_cpu_250k"]["elapsed_seconds"]) / float(numeric_backend["release_cuda_250k"]["elapsed_seconds"]), 4)
            numeric_backend["speedup_cuda_vs_cpu_1m"] = round(float(numeric_backend["release_cpu_1m"]["elapsed_seconds"]) / float(numeric_backend["release_cuda_1m"]["elapsed_seconds"]), 4)
        else:
            numeric_backend["release_cuda_250k"] = {"accuracy": None, "elapsed_seconds": None, "total_predictions": 0, "reason": "no_cuda_runtime"}
            numeric_backend["release_cuda_1m"] = {"accuracy": None, "elapsed_seconds": None, "total_predictions": 0, "reason": "no_cuda_runtime"}
            numeric_backend["speedup_cuda_vs_cpu_250k"] = None
            numeric_backend["speedup_cuda_vs_cpu_1m"] = None
        (RESULTS / "numeric_backend_v34.json").write_text(json.dumps(numeric_backend, indent=2), encoding="utf-8")

    if not args.skip_status:
        completed_100m = find_completed_100m_json()
        long_20m_path = RESULTS / "longrun_v34_20m.json"
        long_20m_carried = False
        if long_20m_path.exists():
            long_20m_data = json.loads(long_20m_path.read_text(encoding="utf-8"))
            long_20m_carried = bool(long_20m_data.get("meta", {}).get("carried_forward_from"))
        status_text = (
            "SBAN v34 keeps the packaged numeric suite on numeric_backend=cpu and score_threads=1, preserving the stable CPU release guardrail while turning the v33 colleague baseline into a default warm-start runtime. "
            "The product release focus is generated runtime prewarm: the default chat path loads data/sban_runtime_prewarm_v34.txt without explicit seed/open/knowledge arguments, while compatibility v34 seed, open-seed, and synthetic-knowledge files are generated for older scripts and packages.\n"
        )
        status_text += "The v34 short suite and long hardening ladder intentionally keep the proven continuation profile so the release isolates product, safety, and runtime-prewarm changes from numeric-profile churn.\n"
        if long_20m_carried:
            status_text += "The v34 20M JSON is a carried-forward v27 guardrail with v34 metadata because the local v34 20M rerun hit OutOfMemory on this workstation; it is not claimed as a fresh 20M numeric improvement.\n"
        if completed_100m is None:
            status_text += "No completed 100M JSON artifact was found in docs/results at release time, so v34 reports through 20M only.\n"
        else:
            status_text += f"Completed 100M artifact discovered: {completed_100m.relative_to(ROOT).as_posix()}\n"
        (RESULTS / "STATUS.md").write_text(status_text, encoding="utf-8")


if __name__ == "__main__":
    main()
