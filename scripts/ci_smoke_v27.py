#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "zig-out" / "bin" / ("zig_sban.exe" if os.name == "nt" else "zig_sban")

SEED = "data/sban_dialogue_seed_v27.txt"
OPEN_SEED = "data/sban_dialogue_open_seed_v27.txt"
SESSION_EVAL = "data/sban_session_eval_v27.txt"
OPEN_SESSION_EVAL = "data/sban_open_chat_session_eval_v27.txt"
BROAD_SESSION_EVAL = "data/sban_broad_chat_session_eval_v27.txt"


def run_text(args: list[str]) -> str:
    return subprocess.check_output(args, cwd=ROOT, text=True)


def run_chat(prompt: str, *, session_path: str | None = None) -> str:
    cmd = [
        str(BIN),
        "chat-demo",
        prompt,
        "220",
        "mode=free",
        "allow_generation=true",
        "backend=cpu",
        f"seed_path={SEED}",
        f"open_seed_path={OPEN_SEED}",
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
        ]
    )
    require_contains(session_eval, "passed=43", "main session eval")
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
        ]
    )
    require_contains(open_eval, "passed=66", "open session eval")
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
        ]
    )
    require_contains(broad_eval, "passed=63", "broad session eval")
    if "expect_pass=false" in broad_eval:
        raise AssertionError(broad_eval)

    overview = run_chat("what is SBAN v27")
    require_contains(overview, "conversational product release", "overview")

    bundle = run_chat("what files ship in the bundle")
    require_contains(bundle, "sban_v27_repo.zip", "bundle inventory")

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

    with tempfile.TemporaryDirectory() as tmp_dir:
        session_path = str(Path(tmp_dir) / "session_v27.txt")
        dog_store = run_chat("my dog is luna", session_path=session_path)
        require_contains(dog_store, "Luna", "dog store")
        dog_recall = run_chat("what is my dog name", session_path=session_path)
        require_contains(dog_recall, "Luna", "dog recall")
        project_store = run_chat("our project is nebula", session_path=session_path)
        require_contains(project_store, "nebula", "project store")
        project_recall = run_chat("what project are we on", session_path=session_path)
        require_contains(project_recall, "nebula", "project recall")

    print("SBAN v27 CI smoke passed")


if __name__ == "__main__":
    main()
