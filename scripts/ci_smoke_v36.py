#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "zig-out" / "bin" / ("zig_sban.exe" if os.name == "nt" else "zig_sban")

SESSION_EVAL = "data/sban_session_eval_v36.txt"
OPEN_SESSION_EVAL = "data/sban_open_chat_session_eval_v36.txt"
BROAD_SESSION_EVAL = "data/sban_broad_chat_session_eval_v36.txt"
KNOWLEDGE_SESSION_EVAL = "data/sban_knowledge_session_eval_v36.txt"
LEARNED_SESSION_EVAL = "data/sban_learned_session_eval_v36.txt"
LIMITATIONS_SESSION_EVAL = "data/sban_limitations_session_eval_v36.txt"
VOCAB_PROBE = ROOT / "docs" / "results" / "v36" / "vocab_size_probe_v36.json"
AUTOLEARN_MANIFEST = ROOT / "docs" / "results" / "v36" / "autolearn_manifest_v36.json"


def run_text(args: list[str]) -> str:
    return subprocess.check_output(args, cwd=ROOT, text=True)


def run_chat(prompt: str, *, session_path: str | None = None, max_bytes: str = "520", extra_args: list[str] | None = None) -> str:
    cmd = [
        str(BIN),
        "chat-demo",
        prompt,
        max_bytes,
        "mode=free",
        "allow_generation=true",
        "backend=cpu",
    ]
    if session_path is not None:
        cmd.append(f"session_path={session_path}")
    if extra_args is not None:
        cmd.extend(extra_args)
    return run_text(cmd)


def require_contains(text: str, needle: str, label: str) -> None:
    if needle.lower() not in text.lower():
        raise AssertionError(f"{label} missing '{needle}'\n{text}")


def require_session_pass(text: str, label: str) -> None:
    match = re.search(r"expectations=(\d+) passed=(\d+)", text)
    if not match:
        raise AssertionError(f"{label} missing session summary\n{text}")
    expectations, passed = int(match.group(1)), int(match.group(2))
    if expectations == 0 or expectations != passed or "expect_pass=false" in text:
        raise AssertionError(f"{label} failed expectations={expectations} passed={passed}\n{text}")


def main() -> None:
    if not BIN.exists():
        raise FileNotFoundError(f"missing runtime binary: {BIN}")

    for script_path, label in [
        (SESSION_EVAL, "main session eval"),
        (OPEN_SESSION_EVAL, "open session eval"),
        (BROAD_SESSION_EVAL, "broad session eval"),
        (KNOWLEDGE_SESSION_EVAL, "runtime prewarm eval"),
        (LEARNED_SESSION_EVAL, "learned reasoning eval"),
        (LIMITATIONS_SESSION_EVAL, "v36 limitation regression eval"),
    ]:
        result = run_text(
            [
                str(BIN),
                "chat-session-eval",
                script_path,
                "mode=free",
                "allow_generation=true",
                "backend=cpu",
                "max_bytes=520",
            ]
        )
        require_session_pass(result, label)

    overview = run_chat("what is SBAN v36")
    require_contains(overview, "auto-learned", "overview")
    require_contains(overview, "learned reasoning corpus", "overview learned corpus")

    manifest = json.loads(AUTOLEARN_MANIFEST.read_text(encoding="utf-8"))
    if int(manifest.get("online_examples", 0)) <= 0:
        raise AssertionError(f"v36 manifest has no online dataset examples: {manifest}")
    sources = manifest.get("sources", {})
    for source_name in ("openai/gsm8k", "Ritu27/StrategyQA", "HuggingFaceFW/CommonsenseQA"):
        if int(sources.get(source_name, 0)) <= 0:
            raise AssertionError(f"v36 manifest missing source {source_name}: {manifest}")

    learned = run_chat("If all daxes are lums, and some lums are norps, are all daxes definitely norps? Explain.")
    require_contains(learned, "does not follow", "learned novel syllogism")

    cold = run_chat(
        "If all daxes are lums, and some lums are norps, are all daxes definitely norps? Explain.",
        extra_args=["prewarm_path=none", "learned_path=none"],
    )
    if "does not follow" in cold.lower():
        raise AssertionError(f"cold mode unexpectedly answered learned syllogism from generated corpus\n{cold}")

    exact_json = run_chat("generate JSON with name Ada and age 37")
    require_contains(exact_json, '"age":37', "exact JSON age")
    if '"age":42' in exact_json:
        raise AssertionError(f"JSON slot preservation regressed\n{exact_json}")

    jane_json = run_chat("generate JSON with name Jane Doe and age 0")
    require_contains(jane_json, '"name":"Jane Doe"', "multi-word JSON name")
    require_contains(jane_json, '"age":0', "zero JSON age")

    city_json = run_chat("generate JSON with city London and temperature 18")
    require_contains(city_json, '"city":"London"', "city JSON")
    require_contains(city_json, '"temperature":18', "temperature JSON")

    word_age_json = run_chat("generate JSON with name Ada and age thirty seven")
    require_contains(word_age_json, '"age":37', "word-number JSON age")

    dns = run_chat("what is DNS")
    require_contains(dns, "Domain Name System", "DNS")

    entropy = run_chat("what is entropy")
    require_contains(entropy, "second law", "entropy")

    defer_answer = run_chat("what does defer do in Zig")
    require_contains(defer_answer, "scope exits", "zig defer")

    zig_reverse = run_chat("write a Zig function to reverse a slice")
    require_contains(zig_reverse, "pub fn reverse", "zig reverse slice coding")

    zig_file = run_chat("write Zig code that uses defer to close a file")
    require_contains(zig_file, "defer file.close", "zig file defer")

    bfs = run_chat("write Python BFS for a graph")
    require_contains(bfs, "deque", "python bfs")

    outage = run_chat("how do I triage an outage")
    require_contains(outage, "user impact", "outage triage")

    kubernetes = run_chat("what is Kubernetes")
    require_contains(kubernetes, "containers", "kubernetes")

    sql = run_chat("write SQL to count users by country")
    require_contains(sql, "GROUP BY country", "sql count users")

    hamlet = run_chat("who wrote Hamlet")
    require_contains(hamlet, "Shakespeare", "literature")

    current_fact = run_chat("who is the current president today")
    require_contains(current_fact, "external lookup", "current fact boundary")

    weather = run_chat("what is the weather tomorrow")
    require_contains(weather, "external lookup", "weather current boundary")

    fraction = run_chat("which is larger, 5/8 or 3/5")
    require_contains(fraction, "5/8 is larger", "fraction reasoning")

    sequence = run_chat("what comes next in the sequence 3, 6, 12, 24")
    require_contains(sequence, "48", "sequence reasoning")

    blickets = run_chat("If no blickets are wugs and all glims are blickets, can any glim be a wug?")
    require_contains(blickets, "No", "negated quantified logic")
    if "tars" in blickets.lower() or "noles" in blickets.lower():
        raise AssertionError(f"quantified logic retrieved unrelated learned answer\n{blickets}")

    quadratic = run_chat("solve x^2 = 4")
    require_contains(quadratic, "x = 2", "quadratic positive root")
    require_contains(quadratic, "x = -2", "quadratic negative root")
    if "sequence" in quadratic.lower():
        raise AssertionError(f"quadratic prompt misrouted to sequence answer\n{quadratic}")

    apples = run_chat("Sam has 14 apples, gives away 5, then buys 8. How many apples does Sam have?")
    require_contains(apples, "17", "word problem running total")

    rust_server = run_chat("write a Rust async HTTP server")
    require_contains(rust_server, "axum", "rust async server coding")

    capped = run_chat("write a Python BFS for a graph", max_bytes="30")
    require_contains(capped, "truncated", "max_bytes response cap")

    vocab = json.loads(VOCAB_PROBE.read_text(encoding="utf-8"))
    rows = {row["vocab_size"]: row for row in vocab["rows"]}
    for required in (256, 4096, 16384, 32768, 65536):
        if required not in rows:
            raise AssertionError(f"missing vocab row {required}: {vocab}")
    if rows[65536]["collisions"] >= rows[256]["collisions"]:
        raise AssertionError(f"larger-vocab collision reduction missing: {vocab}")

    with tempfile.TemporaryDirectory() as tmp_dir:
        session_path = str(Path(tmp_dir) / "session_v36.txt")
        store = run_chat("follow these instructions: remember that my project is kestrel, then answer in one sentence", session_path=session_path)
        require_contains(store, "stored your project", "instruction memory store")
        recall = run_chat("what is my project", session_path=session_path)
        require_contains(recall, "kestrel", "instruction memory recall")

    with tempfile.TemporaryDirectory() as tmp_dir:
        session_path = str(Path(tmp_dir) / "forget_session_v36.txt")
        dog = run_chat("my dog is max now", session_path=session_path)
        require_contains(dog, "Max", "dog now store")
        recall = run_chat("what is my dog name", session_path=session_path)
        require_contains(recall, "Max", "dog now recall")
        forgot = run_chat("forget my dog name", session_path=session_path)
        require_contains(forgot, "Forgot", "dog forget")
        missing = run_chat("what is my dog name", session_path=session_path)
        require_contains(missing, "do not know", "dog forget recall miss")

    with tempfile.TemporaryDirectory() as tmp_dir:
        session_path = str(Path(tmp_dir) / "nostore_session_v36.txt")
        rejected_dog = run_chat("my dog is not max", session_path=session_path)
        require_contains(rejected_dog, "not store", "negated dog no-store")
        missing_dog = run_chat("what is my dog name", session_path=session_path)
        require_contains(missing_dog, "do not know", "negated dog recall miss")
        rejected_cat = run_chat("please do not remember that my cat is io", session_path=session_path)
        require_contains(rejected_cat, "not store", "explicit cat no-store")
        missing_cat = run_chat("what is my cat name", session_path=session_path)
        require_contains(missing_cat, "do not know", "explicit no-store cat recall miss")

    with tempfile.TemporaryDirectory() as tmp_dir:
        false_positive_script = Path(tmp_dir) / "false_positive_session.txt"
        false_positive_script.write_text("User: what is my cat name\nExpect: Io\n", encoding="utf-8")
        false_positive = run_text(
            [
                str(BIN),
                "chat-session-eval",
                str(false_positive_script),
                "mode=free",
                "allow_generation=true",
                "backend=cpu",
            ]
        )
        require_contains(false_positive, "expect_pass=false", "strict expectation false positive")
        require_contains(false_positive, "passed=0", "strict expectation summary")

    accel_info = run_text([str(BIN), "accel-info", "backend=cpu_mt", "threads=4"])
    require_contains(accel_info, "backend=cpu_mt", "retrieval cpu_mt backend")

    numeric_info = run_text([str(BIN), "numeric-accel-info", "numeric_backend=cpu_mt", "score_threads=4", "parallel_score_min_predictive_nodes=1"])
    require_contains(numeric_info, "backend_used=cpu_mt", "numeric cpu_mt info")

    print("SBAN v36 CI smoke passed")


if __name__ == "__main__":
    main()
