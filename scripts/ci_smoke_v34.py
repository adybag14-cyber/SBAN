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

SESSION_EVAL = "data/sban_session_eval_v34.txt"
OPEN_SESSION_EVAL = "data/sban_open_chat_session_eval_v34.txt"
BROAD_SESSION_EVAL = "data/sban_broad_chat_session_eval_v34.txt"
KNOWLEDGE_SESSION_EVAL = "data/sban_knowledge_session_eval_v34.txt"
VOCAB_PROBE = ROOT / "docs" / "results" / "v34" / "vocab_size_probe_v34.json"


def run_text(args: list[str]) -> str:
    return subprocess.check_output(args, cwd=ROOT, text=True)


def run_chat(prompt: str, *, session_path: str | None = None, max_bytes: str = "520") -> str:
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

    overview = run_chat("what is SBAN v34")
    require_contains(overview, "warm-start non-transformer", "overview")
    require_contains(overview, "runtime prewarm", "overview prewarm")

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

    fraction = run_chat("which is larger, 5/8 or 3/5")
    require_contains(fraction, "5/8 is larger", "fraction reasoning")

    sequence = run_chat("what comes next in the sequence 3, 6, 12, 24")
    require_contains(sequence, "48", "sequence reasoning")

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
        session_path = str(Path(tmp_dir) / "session_v34.txt")
        store = run_chat("follow these instructions: remember that my project is kestrel, then answer in one sentence", session_path=session_path)
        require_contains(store, "stored your project", "instruction memory store")
        recall = run_chat("what is my project", session_path=session_path)
        require_contains(recall, "kestrel", "instruction memory recall")

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

    print("SBAN v34 CI smoke passed")


if __name__ == "__main__":
    main()
