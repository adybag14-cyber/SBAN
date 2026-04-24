#!/usr/bin/env python3
from __future__ import annotations

import os
import json
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "zig-out" / "bin" / ("zig_sban.exe" if os.name == "nt" else "zig_sban")

SEED = "data/sban_dialogue_seed_v29.txt"
OPEN_SEED = "data/sban_dialogue_open_seed_v29.txt"
KNOWLEDGE = "data/sban_synthetic_knowledge_v29.txt"
SESSION_EVAL = "data/sban_session_eval_v29.txt"
OPEN_SESSION_EVAL = "data/sban_open_chat_session_eval_v29.txt"
BROAD_SESSION_EVAL = "data/sban_broad_chat_session_eval_v29.txt"
KNOWLEDGE_SESSION_EVAL = "data/sban_knowledge_session_eval_v29.txt"
VOCAB_PROBE = ROOT / "docs" / "results" / "v29" / "vocab_size_probe_v29.json"


def run_text(args: list[str]) -> str:
    return subprocess.check_output(args, cwd=ROOT, text=True)


def run_chat(prompt: str, *, session_path: str | None = None) -> str:
    cmd = [
        str(BIN),
        "chat-demo",
        prompt,
        "480",
        "mode=free",
        "allow_generation=true",
        "backend=cpu",
        f"seed_path={SEED}",
        f"open_seed_path={OPEN_SEED}",
        f"knowledge_path={KNOWLEDGE}",
    ]
    if session_path is not None:
        cmd.append(f"session_path={session_path}")
    return run_text(cmd)


def require_contains(text: str, needle: str, label: str) -> None:
    if needle.lower() not in text.lower():
        raise AssertionError(f"{label} missing '{needle}'\n{text}")


def main() -> None:
    if not BIN.exists():
        raise FileNotFoundError(f"missing runtime binary: {BIN}")

    session_eval = run_text(
        [
            str(BIN),
            "chat-session-eval",
            SESSION_EVAL,
            "mode=free",
            "allow_generation=true",
            "backend=cpu",
            f"seed_path={SEED}",
            f"open_seed_path={OPEN_SEED}",
            f"knowledge_path={KNOWLEDGE}",
        ]
    )
    require_contains(session_eval, "passed=57", "main session eval")
    if "expect_pass=false" in session_eval:
        raise AssertionError(session_eval)

    open_eval = run_text(
        [
            str(BIN),
            "chat-session-eval",
            OPEN_SESSION_EVAL,
            "mode=free",
            "allow_generation=true",
            "backend=cpu",
            f"seed_path={SEED}",
            f"open_seed_path={OPEN_SEED}",
            f"knowledge_path={KNOWLEDGE}",
        ]
    )
    require_contains(open_eval, "passed=71", "open session eval")
    if "expect_pass=false" in open_eval:
        raise AssertionError(open_eval)

    broad_eval = run_text(
        [
            str(BIN),
            "chat-session-eval",
            BROAD_SESSION_EVAL,
            "mode=free",
            "allow_generation=true",
            "backend=cpu",
            f"seed_path={SEED}",
            f"open_seed_path={OPEN_SEED}",
            f"knowledge_path={KNOWLEDGE}",
        ]
    )
    require_contains(broad_eval, "passed=73", "broad session eval")
    if "expect_pass=false" in broad_eval:
        raise AssertionError(broad_eval)

    knowledge_eval = run_text(
        [
            str(BIN),
            "chat-session-eval",
            KNOWLEDGE_SESSION_EVAL,
            "mode=free",
            "allow_generation=true",
            "backend=cpu",
            f"seed_path={SEED}",
            f"open_seed_path={OPEN_SEED}",
            f"knowledge_path={KNOWLEDGE}",
        ]
    )
    require_contains(knowledge_eval, "passed=15", "generated knowledge session eval")
    if "expect_pass=false" in knowledge_eval:
        raise AssertionError(knowledge_eval)

    overview = run_chat("what is SBAN v29")
    require_contains(overview, "synthetic knowledge", "overview")

    bundle = run_chat("what files ship in the bundle")
    require_contains(bundle, "sban_v29_repo.zip", "bundle inventory")

    reverse_list = run_chat("how do i reverse a list in python")
    require_contains(reverse_list, "items.reverse()", "reverse list")

    kubernetes = run_chat("what is kubernetes in plain english")
    require_contains(kubernetes, "containers", "kubernetes")

    sql = run_chat("write sql to count users per country")
    require_contains(sql, "SELECT country", "sql count users")

    zig_path = run_chat("where is std.hashmap implemented in zig upstream")
    require_contains(zig_path, "lib/std/hash_map.zig", "zig upstream path")

    noise = run_chat("blorple zint protocol")
    require_contains(noise, "not sure", "uncertainty path")

    exponent = run_chat("calculate 2^10")
    require_contains(exponent, "1024", "exponent math")

    current_fact = run_chat("who is the current UK prime minister")
    require_contains(current_fact, "live current facts", "current fact boundary")

    prime = run_chat("write a python function to check if a number is prime")
    require_contains(prime, "def is_prime", "prime function")

    tides = run_chat("what causes tides")
    require_contains(tides, "Moon's gravity", "synthetic tides knowledge")

    mitosis = run_chat("what is mitosis")
    require_contains(mitosis, "chromosomes", "synthetic biology knowledge")

    pride = run_chat("who wrote pride and prejudice")
    require_contains(pride, "Jane Austen", "synthetic literature knowledge")

    linear = run_chat("solve 3x + 5 = 20")
    require_contains(linear, "x = 5", "linear equation")

    mixed_math = run_chat("calculate (2+3)*4^2 - 7")
    require_contains(mixed_math, "73", "mixed expression math")

    huge_math = run_chat("calculate 2^1000")
    require_contains(huge_math, "safe exact-number range", "safe huge exponent")

    source_boundary = run_chat("where is HashMap in the Linux kernel source")
    require_contains(source_boundary, "should not invent", "source location guard")

    zig_reverse = run_chat("write a zig function to reverse a slice")
    require_contains(zig_reverse, "pub fn reverse", "zig reverse slice coding")

    json_object = run_chat("generate JSON with name and age")
    require_contains(json_object, '"name"', "json generation")

    capped = run_text(
        [
            str(BIN),
            "chat-demo",
            "write a python class for a stack",
            "mode=free",
            "allow_generation=true",
            "backend=cpu",
            "max_bytes=20",
            f"seed_path={SEED}",
            f"open_seed_path={OPEN_SEED}",
            f"knowledge_path={KNOWLEDGE}",
        ]
    )
    require_contains(capped, "truncated", "max_bytes response cap")

    vocab = json.loads(VOCAB_PROBE.read_text(encoding="utf-8"))
    rows = {row["vocab_size"]: row for row in vocab["rows"]}
    if 256 not in rows or 4096 not in rows or rows[4096]["collisions"] >= rows[256]["collisions"]:
        raise AssertionError(f"vocab probe did not show larger-vocab collision reduction: {vocab}")

    with tempfile.TemporaryDirectory() as tmp_dir:
        session_path = str(Path(tmp_dir) / "session_v29.txt")
        dog_store = run_chat("my dog is luna", session_path=session_path)
        require_contains(dog_store, "Luna", "dog store")
        dog_recall = run_chat("what is my dog name", session_path=session_path)
        require_contains(dog_recall, "Luna", "dog recall")
        project_store = run_chat("our project is nebula", session_path=session_path)
        require_contains(project_store, "nebula", "project store")
        project_recall = run_chat("what project are we on", session_path=session_path)
        require_contains(project_recall, "nebula", "project recall")
        cat_store = run_chat("my cat is io", session_path=session_path)
        require_contains(cat_store, "Io", "cat store")
        cat_recall = run_chat("what is my cat name", session_path=session_path)
        require_contains(cat_recall, "Io", "cat recall")
        launch_store = run_chat("remember that my launch date is tuesday", session_path=session_path)
        require_contains(launch_store, "tuesday", "launch date store")
        launch_recall = run_chat("when is my launch date", session_path=session_path)
        require_contains(launch_recall, "tuesday", "launch date recall")

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
                f"seed_path={SEED}",
                f"open_seed_path={OPEN_SEED}",
                f"knowledge_path={KNOWLEDGE}",
            ]
        )
        require_contains(false_positive, "expect_pass=false", "strict expectation false positive")
        require_contains(false_positive, "passed=0", "strict expectation summary")

        long_prompt_file = Path(tmp_dir) / "long_prompt.txt"
        long_prompt_file.write_text("a" * 10000 + "\n", encoding="utf-8")
        long_eval = run_text(
            [
                str(BIN),
                "chat-eval",
                str(long_prompt_file),
                "mode=free",
                "allow_generation=true",
                "backend=cpu",
                f"seed_path={SEED}",
                f"open_seed_path={OPEN_SEED}",
                f"knowledge_path={KNOWLEDGE}",
            ]
        )
        require_contains(long_eval, "truncated", "long prompt truncation")
        if len(long_eval) > 2500:
            raise AssertionError(f"long prompt eval output too large: {len(long_eval)} bytes")

    accel_info = run_text([str(BIN), "accel-info", f"seed_path={SEED}", "backend=cpu_mt", "threads=4"])
    require_contains(accel_info, "backend=cpu_mt", "retrieval cpu_mt backend")

    numeric_info = run_text([str(BIN), "numeric-accel-info", "numeric_backend=cpu_mt", "score_threads=4", "parallel_score_min_predictive_nodes=1"])
    require_contains(numeric_info, "backend_used=cpu_mt", "numeric cpu_mt info")

    profile = run_text(
        [
            str(BIN),
            "profile-variant",
            "data/elastic_probe.bin",
            "prefix",
            "4",
            "default",
            "1000",
            "1000",
            "4096",
            "profile_steps=1000",
            "numeric_backend=cpu_mt",
            "score_threads=4",
            "parallel_score_min_predictive_nodes=1",
        ]
    )
    require_contains(profile, "cpu_mt_steps=1000", "numeric cpu_mt profile steps")

    print("SBAN v29 CI smoke passed")


if __name__ == "__main__":
    main()
