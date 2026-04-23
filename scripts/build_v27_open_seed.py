#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE_SEED_PATH = ROOT / "data" / "sban_dialogue_open_seed_v26.txt"
OUTPUT_PATH = ROOT / "data" / "sban_dialogue_open_seed_v27.txt"
DEFAULT_ZIG_ZIP = Path.home() / "Downloads" / "zig-upstream-9b177a7d2125.zip"

EXTRA_PAIRS: list[tuple[str, str]] = [
    ("how is your day going", "I am steady and ready to help. We can keep things practical, conversational, and honest about what I know."),
    ("how do i make coffee taste better", "If coffee tastes flat or harsh, the fastest fixes are usually fresher beans, a cleaner grinder, and adjusting the grind. If it tastes bitter, go a bit coarser or shorten the brew. If it tastes sour, grind a bit finer or increase extraction slightly."),
    ("explain inflation simply", "Inflation means prices rise over time, so the same amount of money buys less than it used to. Mild inflation is normal, but high inflation makes everyday costs and planning harder."),
    ("what is a black hole", "A black hole is a region where gravity is so strong that once something crosses the event horizon, it cannot escape. You can think of it as matter packed so densely that spacetime is bent extremely hard around it."),
    ("what is dns", "DNS stands for Domain Name System. It translates human-readable names like example.com into the IP addresses computers use to reach the right server."),
    ("tcp vs udp", "TCP emphasizes reliable ordered delivery: it retries lost data and keeps packets in sequence. UDP is simpler and faster but does not guarantee delivery or order, which is why it fits low-latency uses like streaming, voice, or games."),
    ("explain pointers in c simply", "In C, a pointer is a variable that stores a memory address. Instead of holding the value itself, it points to where the value lives, which is why pointers matter for arrays, dynamic memory, and passing data by reference."),
    ("write a short linkedin summary for a researcher", "Researcher focused on turning complex technical questions into measurable results. I work across experiments, analysis, and implementation, with an emphasis on clear reasoning, reproducible evaluation, and building systems that hold up outside the happy path."),
    ("write a python class for a stack", "A simple Python stack class is: class Stack: def __init__(self): self._items = []; def push(self, item): self._items.append(item); def pop(self): if not self._items: raise IndexError('pop from empty stack'); return self._items.pop(); def peek(self): if not self._items: raise IndexError('peek from empty stack'); return self._items[-1]; def is_empty(self): return not self._items."),
    ("how do i reverse a list in python", "In Python, reverse a list in place with items.reverse(). If you want a reversed copy instead, use items[::-1]."),
    ("write javascript debounce function", "A compact JavaScript debounce helper is: function debounce(fn, delay) { let timer = null; return (...args) => { clearTimeout(timer); timer = setTimeout(() => fn(...args), delay); }; }."),
    ("write sql to count users per country", "A simple SQL answer is: SELECT country, COUNT(*) AS user_count FROM users GROUP BY country ORDER BY user_count DESC."),
    ("what is json", "JSON stands for JavaScript Object Notation. It is a text format for structured data built from objects, arrays, strings, numbers, booleans, and null."),
    ("what is a hash map", "A hash map stores key-value pairs and uses a hash function to decide where keys should live internally, which is why lookups are often close to constant time on average."),
    ("what is garbage collection in programming", "Garbage collection is a runtime system that automatically finds memory the program no longer uses and reclaims it, so developers do not have to free every object manually."),
    ("difference between stack and heap memory", "Stack memory usually holds short-lived call-frame data such as local variables, while heap memory is the larger pool used for data that needs to live beyond one function call."),
    ("what is kubernetes in plain english", "Kubernetes is a system for running and managing containers across multiple machines. In plain English, it helps deploy applications, keep them running, and scale them without handling each server by hand."),
    ("what is oauth", "OAuth is a way to let one application access another service on your behalf without handing over your password directly. It is the pattern behind many sign-in and delegated API-access flows."),
    ("what is mutex in programming", "A mutex is a mutual-exclusion lock. It lets one thread enter a critical section at a time so shared data does not get modified concurrently in unsafe ways."),
    ("explain compound interest simply", "Compound interest means you earn interest on the original amount and on the interest already added, so the growth snowballs over time."),
    ("what causes the seasons on earth", "The seasons are caused mainly by Earth's axial tilt, not by Earth simply being closer to or farther from the Sun."),
    ("who painted starry night", "Vincent van Gogh painted The Starry Night."),
    ("give me three easy lunch ideas", "Three easy lunch ideas are a wrap with salad and sauce, rice with roasted vegetables and a fried egg, or tomato soup with a grilled cheese or tuna melt."),
    ("tell me a joke about databases", "Why did the database admin leave the party early? Too many bad joins and not enough committed relationships."),
    ("rewrite this professionally: sorry i was late", "A more professional rewrite is: I apologize for arriving late. Thank you for your patience."),
    ("make a haiku about rain", "Rain taps at the glass. City lights blur into mist. Evening slows its pace."),
    ("plan a relaxed weekend in london", "A relaxed weekend in London could be a slow morning walk and coffee, one museum or gallery, lunch in a neighborhood you enjoy, a park break, and one easy evening anchor."),
    ("my dog is luna", "Noted. Your dog's name is Luna, and I will remember that for this session."),
    ("what is my dog name", "Your dog's name is Luna."),
    ("our project is nebula", "Noted. Your project is nebula, and I will remember that for this session."),
    ("what project are we on", "Your project is nebula."),
    ("tomorrow i have a dentist appointment", "Noted. Tomorrow you have a dentist appointment, and I will remember that for this session."),
    ("what do i have tomorrow", "Tomorrow you have a dentist appointment."),
    ("what is binary search", "Binary search finds a target in a sorted list by repeatedly checking the middle element and cutting the remaining search space in half."),
    ("what is big o of binary search", "Binary search runs in O(log n) time because each step halves the remaining search space."),
    ("what is http 404", "HTTP 404 means Not Found. The server was reached, but it could not find the resource at that path."),
    ("what is sql join", "A SQL join combines rows from two tables based on a related key, such as matching users.id with orders.user_id."),
    ("what is a queue data structure", "A queue is a first-in, first-out data structure. The earliest item added is the earliest item removed."),
    ("stack vs queue", "A stack is last-in, first-out, while a queue is first-in, first-out. Stacks fit backtracking and nested calls; queues fit scheduling and breadth-first work."),
    ("what is a linked list", "A linked list is a sequence of nodes where each node points to the next one, which makes insertion cheap in the middle when you already have the right pointer."),
    ("what is a memory leak", "A memory leak happens when a program allocates memory and then loses the ability to free or reuse it, so memory usage keeps growing unnecessarily."),
    ("what is unit testing", "Unit testing means checking small isolated pieces of code, such as one function or one module, to confirm they behave as expected."),
    ("what is an api", "An API is an application programming interface: a defined way for one piece of software to call into another piece of software."),
    ("what is git rebase", "Git rebase rewrites a branch so its commits are replayed on top of a new base, which gives a cleaner linear history but changes commit identities."),
    ("how do i write a concise project update", "A concise project update usually has four parts: what changed, what is blocked, what comes next, and what decision or help you need from the reader."),
    ("what is a black hole in simple terms", "A black hole is an object so dense that gravity becomes extremely strong around it. Once something crosses the event horizon, it cannot get back out."),
    ("what is tcp", "TCP is a transport protocol that focuses on reliable ordered delivery. It makes sure data arrives, retries missing pieces, and preserves sequence."),
    ("what is udp", "UDP is a transport protocol that sends packets without guaranteeing delivery or order. It is simpler and often lower-latency than TCP."),
    ("what is dns in simple terms", "DNS is the internet's address book. It turns names like ziglang.org into the numeric IP addresses computers use."),
    ("how do i make better coffee at home", "The biggest home coffee wins are fresh beans, consistent grinding, clean equipment, and adjusting grind size to taste. Bitter usually means too much extraction; sour usually means too little."),
    ("what is a black hole made of", "A black hole forms when matter collapses so densely that gravity dominates the region around it. The defining feature is not a normal surface but the event horizon and the mass packed inside it."),
    ("how is tcp different from udp", "TCP retries lost data and preserves order, which makes it reliable. UDP skips that overhead, so it is lighter and faster but does not guarantee delivery or ordering."),
    ("what is inflation in simple terms", "Inflation means the general level of prices goes up over time, so money loses some purchasing power."),
    ("what does a pointer do in c", "A pointer in C stores a memory address. That lets code refer to data indirectly, share access to the same value, and work with dynamic memory."),
    ("write a short bio for a researcher", "Researcher with a focus on rigorous experimentation, clear analysis, and building systems that hold up outside the happy path."),
    ("how do i explain complex work on linkedin", "Keep it outcome-first: say what you work on, what problems you solve, and what makes your approach distinctive. Avoid turning the summary into a full resume."),
    ("what is zig", "Zig is a general-purpose programming language and toolchain focused on robust, optimal, and reusable software."),
    ("what does std.arraylist do in zig", "In Zig upstream, std/array_list.zig implements ArrayList and related managed and unmanaged growable contiguous arrays."),
    ("what does std.hashmap do in zig", "In Zig upstream, std/hash_map.zig implements generic hash maps, including helpers such as StringHashMap for string keys."),
    ("what does std.mem.allocator do in zig", "In Zig upstream, the allocator interface is the standard way to request, resize, and free memory in a controlled explicit way."),
    ("what does zig std do", "The Zig README says `zig std` opens the standard library documentation in a browser tab."),
    ("what are the two main pieces of a zig installation", "The Zig README says a Zig installation is composed of two things: the Zig executable and the lib directory."),
    ("how do you build zig from source", "The upstream Zig README says the standard source build is the normal CMake flow: create a build directory, run cmake, and then make install."),
    ("how do you build zig without llvm", "The upstream Zig README says you can compile bootstrap.c with a C compiler, run the resulting bootstrap executable, and produce a zig2 stage2 compiler without LLVM extensions."),
]

ZIG_HINTS: list[tuple[str, str, str]] = [
    ("README.md", "what is zig upstream", "The upstream Zig README describes Zig as a general-purpose programming language and toolchain for maintaining robust, optimal, and reusable software."),
    ("README.md", "how do i build zig from source", "The upstream Zig README describes the standard source build as the normal CMake process: create a build directory, run cmake, and then make install."),
    ("README.md", "what does zig std do", "The upstream Zig README says `zig std` opens the standard library documentation in a browser tab."),
    ("README.md", "what are the two main pieces of a zig installation", "The upstream Zig README says a Zig installation is composed of the Zig executable and the lib directory."),
    ("build.zig", "what file drives the zig source build", "In the upstream Zig source tree, build.zig is the top-level Zig build script in the repository root."),
    ("lib/std/array_list.zig", "where is std.arraylist implemented in zig upstream", "In the upstream Zig source tree, ArrayList lives in lib/std/array_list.zig."),
    ("lib/std/array_list.zig", "what does std.arraylist do in zig upstream", "In the upstream Zig source tree, lib/std/array_list.zig implements ArrayList and related growable contiguous arrays."),
    ("lib/std/hash_map.zig", "where is std.hashmap implemented in zig upstream", "In the upstream Zig source tree, the generic hash map implementation lives in lib/std/hash_map.zig."),
    ("lib/std/hash_map.zig", "what does std.hashmap do in zig upstream", "In the upstream Zig source tree, lib/std/hash_map.zig implements generic hash maps and helpers such as StringHashMap."),
    ("lib/std/mem.zig", "what does std.mem do in zig upstream", "In the upstream Zig source tree, std.mem collects memory utilities such as allocators, slices, copying helpers, and byte-level operations."),
    ("lib/std/fmt.zig", "what does std.fmt do in zig upstream", "In the upstream Zig source tree, std.fmt provides formatting helpers for printing, parsing, and structured string building."),
    ("lib/std/json.zig", "what does std.json do in zig upstream", "In the upstream Zig source tree, std.json provides JSON parsing and writing utilities."),
    ("lib/std/process/Child.zig", "what does std.process.child do in zig upstream", "In the upstream Zig source tree, std/process/Child.zig implements child-process spawning and management."),
    ("lib/std/net.zig", "what does std.net do in zig upstream", "In the upstream Zig source tree, std.net provides networking helpers such as address handling and socket-related utilities."),
    ("lib/std/http.zig", "what does std.http do in zig upstream", "In the upstream Zig source tree, std.http provides HTTP-related types and utilities."),
    ("lib/std/Thread.zig", "what does std.thread do in zig upstream", "In the upstream Zig source tree, std/Thread.zig provides thread creation and related concurrency helpers."),
    ("lib/std/testing.zig", "what does std.testing do in zig upstream", "In the upstream Zig source tree, std.testing contains test helpers and utilities used across the standard library."),
    ("doc/langref/hello.zig", "where is the zig hello world langref example", "In the upstream Zig tree, one Hello World language reference example lives at doc/langref/hello.zig."),
    ("doc/langref/print.zig", "where is the zig print langref example", "In the upstream Zig tree, a printing example lives at doc/langref/print.zig."),
    ("doc/langref/test_allocator.zig", "where is a zig allocator example in the langref", "In the upstream Zig tree, one allocator example lives at doc/langref/test_allocator.zig."),
]


def parse_seed_text(text: str) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    current_user: str | None = None
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("User:"):
            current_user = line[5:].strip()
        elif line.startswith("Assistant:") and current_user:
            pairs.append((current_user, line[10:].strip()))
            current_user = None
    return pairs


def normalize_text(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


def upgrade_release_text(text: str) -> str:
    return (
        text.replace("SBAN v26", "SBAN v27")
        .replace("SBAN v25", "SBAN v27")
        .replace("v26", "v27")
        .replace("v25", "v27")
        .replace("V26", "V27")
        .replace("V25", "V27")
        .replace("after v26", "after v27")
        .replace("after v25", "after v27")
    )


def clean_answer(text: str) -> str:
    cleaned = re.sub(r"\s+", " ", text.strip())
    cleaned = cleaned.replace(" ,", ",").replace(" .", ".")
    if cleaned and cleaned[-1] not in ".!?":
        cleaned += "."
    return cleaned


def load_squad_pairs(limit: int) -> list[tuple[str, str]]:
    from datasets import load_dataset

    dataset = load_dataset("squad", split="train")
    pairs: list[tuple[str, str]] = []
    seen: set[str] = set()
    for row in dataset:
        question = normalize_text(row["question"])
        answers = row["answers"]["text"]
        if not answers:
            continue
        answer = clean_answer(str(answers[0]))
        if question in seen:
            continue
        if len(question) < 10 or len(question) > 96:
            continue
        if len(answer) < 3 or len(answer) > 140:
            continue
        if not question.startswith(("what ", "who ", "where ", "when ", "which ", "how ", "why ")):
            continue
        if any(token in question for token in ("according to", "in what year", "what was the name of", "how many ")):
            continue
        if any(token in answer.lower() for token in ("http", "www.", "[", "]")):
            continue
        seen.add(question)
        pairs.append((question, answer))
        if len(pairs) >= limit:
            break
    return pairs


def resolve_zip_member(names: list[str], suffix: str) -> str | None:
    suffix = suffix.replace("\\", "/").lower()
    for name in names:
        if name.lower().endswith(suffix):
            return name
    return None


def load_zig_pairs(zip_path: Path) -> list[tuple[str, str]]:
    if not zip_path.exists():
        return []
    pairs: list[tuple[str, str]] = []
    with zipfile.ZipFile(zip_path) as archive:
        names = archive.namelist()
        for suffix, question, answer in ZIG_HINTS:
            if resolve_zip_member(names, suffix):
                pairs.append((question, answer))
    return pairs


def dedupe_pairs(pairs: list[tuple[str, str]]) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    seen: set[str] = set()
    for user, assistant in pairs:
        key = normalize_text(user)
        if not key or key in seen:
            continue
        seen.add(key)
        out.append((user.strip(), clean_answer(assistant)))
    return out


def build_seed_text(pairs: list[tuple[str, str]]) -> str:
    lines: list[str] = []
    for user, assistant in pairs:
        lines.append(f"User: {user}")
        lines.append(f"Assistant: {assistant}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the expanded SBAN v27 open-chat seed.")
    parser.add_argument("--output", type=Path, default=OUTPUT_PATH)
    parser.add_argument("--squad-limit", type=int, default=1800)
    parser.add_argument("--zig-zip", type=Path, default=DEFAULT_ZIG_ZIP)
    parser.add_argument("--no-datasets", action="store_true")
    parser.add_argument("--no-zig-zip", action="store_true")
    args = parser.parse_args()

    base_pairs = [
        (upgrade_release_text(user), upgrade_release_text(assistant))
        for user, assistant in parse_seed_text(BASE_SEED_PATH.read_text(encoding="utf-8"))
    ]
    all_pairs = list(base_pairs)
    all_pairs.extend(EXTRA_PAIRS)
    if not args.no_datasets:
        try:
            all_pairs.extend(load_squad_pairs(args.squad_limit))
        except Exception as exc:  # pragma: no cover - offline fallback
            print(f"warning=squad_load_failed detail={exc}")
    if not args.no_zig_zip:
        all_pairs.extend(load_zig_pairs(args.zig_zip))

    final_pairs = dedupe_pairs(all_pairs)
    text = build_seed_text(final_pairs)
    args.output.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {args.output}")
    print(f"bytes={args.output.stat().st_size}")
    print(f"pairs={len(final_pairs)}")


if __name__ == "__main__":
    main()
