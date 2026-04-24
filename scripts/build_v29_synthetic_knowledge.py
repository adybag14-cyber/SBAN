#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE_OPEN_SEED = ROOT / "data" / "sban_dialogue_open_seed_v28.txt"
OPEN_OUTPUT = ROOT / "data" / "sban_dialogue_open_seed_v29.txt"
KNOWLEDGE_OUTPUT = ROOT / "data" / "sban_synthetic_knowledge_v29.txt"
STATS_OUTPUT = ROOT / "docs" / "results" / "v29" / "synthetic_knowledge_v29.json"


@dataclass(frozen=True)
class KnowledgeFact:
    topic: str
    aliases: tuple[str, ...]
    answer: str
    category: str


FACTS: tuple[KnowledgeFact, ...] = (
    KnowledgeFact("tides", ("what causes tides", "why do oceans have tides", "explain tides simply"), "Tides are caused mainly by the Moon's gravity pulling on Earth's oceans, with the Sun also contributing. Earth's rotation moves coastlines through those tidal bulges, which is why many places see high and low tides each day.", "science"),
    KnowledgeFact("mitosis", ("what is mitosis", "explain mitosis simply", "what happens during mitosis"), "Mitosis is the process where one cell divides its copied chromosomes into two matching sets, then splits into two genetically similar daughter cells.", "biology"),
    KnowledgeFact("dna", ("what does dna do", "what is dna for", "explain dna simply"), "DNA stores genetic instructions. Cells read parts of that code to build proteins and regulate how living things grow, repair themselves, and function.", "biology"),
    KnowledgeFact("photosynthesis", ("what is photosynthesis", "how does photosynthesis work", "explain photosynthesis"), "Photosynthesis lets plants, algae, and some bacteria use light energy to turn carbon dioxide and water into sugars, releasing oxygen as a byproduct.", "biology"),
    KnowledgeFact("conservation of energy", ("what is conservation of energy", "explain conservation of energy", "does energy disappear"), "Conservation of energy means energy is not created or destroyed in a closed system; it changes form or moves between objects.", "physics"),
    KnowledgeFact("gravity", ("what is gravity", "explain gravity simply", "why do objects fall"), "Gravity is the attraction between masses. Near Earth it pulls objects toward the planet, and on larger scales it shapes orbits, stars, galaxies, and tides.", "physics"),
    KnowledgeFact("plate tectonics", ("what causes earthquakes", "what is plate tectonics", "why do earthquakes happen"), "Earthquakes often happen when tectonic plates stick at faults and then suddenly slip, releasing stored stress as seismic waves.", "earth science"),
    KnowledgeFact("water cycle", ("what is the water cycle", "explain evaporation condensation precipitation", "how does water cycle work"), "The water cycle moves water through evaporation, condensation into clouds, precipitation, runoff, and storage in oceans, ice, soil, and groundwater.", "earth science"),
    KnowledgeFact("capital france", ("what is the capital of france", "capital city of france", "which city is france's capital"), "Paris is the capital of France.", "geography"),
    KnowledgeFact("capital japan", ("what is the capital of japan", "capital city of japan", "which city is japan's capital"), "Tokyo is the capital of Japan.", "geography"),
    KnowledgeFact("pride and prejudice", ("who wrote pride and prejudice", "author of pride and prejudice", "who is jane austen"), "Jane Austen wrote Pride and Prejudice.", "literature"),
    KnowledgeFact("hamlet", ("who wrote hamlet", "author of hamlet", "what is hamlet"), "William Shakespeare wrote Hamlet.", "literature"),
    KnowledgeFact("supply and demand", ("what is supply and demand", "explain supply and demand", "why do prices change with supply"), "Supply and demand describes how prices tend to rise when demand is high or supply is scarce, and fall when supply is abundant or demand weakens.", "economics"),
    KnowledgeFact("inflation", ("what is inflation", "explain inflation", "why does money buy less"), "Inflation is a broad rise in prices over time, which reduces purchasing power because the same amount of money buys less.", "economics"),
    KnowledgeFact("democracy", ("what is democracy", "explain democracy simply", "what does democratic government mean"), "Democracy is a system of government where people have political power, usually through voting, representation, civil rights, and public accountability.", "civics"),
    KnowledgeFact("scientific method", ("what is the scientific method", "explain hypothesis experiment evidence", "how do scientists test ideas"), "The scientific method is a disciplined loop: ask a question, form a hypothesis, test it with evidence, analyze results, and revise the explanation when needed.", "reasoning"),
    KnowledgeFact("binary search", ("what is binary search", "big o of binary search", "why is binary search logarithmic"), "Binary search finds an item in sorted data by halving the remaining search space each step, so its time complexity is O(log n).", "computing"),
    KnowledgeFact("hash map", ("what is a hash map", "how does a hash map work", "why are hash maps fast"), "A hash map stores key-value pairs by hashing each key to choose where it should live, giving average-case constant-time lookup when collisions are controlled.", "computing"),
    KnowledgeFact("http status", ("what does http 404 mean", "what is a 404 error", "explain http 500 vs 404"), "HTTP 404 means the server was reached but the requested resource was not found. HTTP 500 means the server hit an internal error.", "computing"),
    KnowledgeFact("tls", ("what is tls", "what does https encrypt", "explain tls simply"), "TLS is the protocol behind HTTPS. It authenticates the server, negotiates keys, and encrypts traffic so observers cannot easily read or alter it.", "computing"),
    KnowledgeFact("git rebase", ("what is git rebase", "explain git rebase", "rebase versus merge"), "Git rebase replays commits on top of a new base, creating a linear history. Merge preserves the branch join explicitly with a merge commit.", "software"),
    KnowledgeFact("zig allocator", ("how do allocators work in zig", "why does zig pass allocators", "explain zig allocator"), "Zig makes allocation explicit. Code that may allocate usually receives an allocator, uses it to create or resize memory, and releases owned memory with matching deinit or free calls.", "zig"),
    KnowledgeFact("zig errors", ("how do zig errors work", "what is a zig error union", "explain try in zig"), "Zig error unions carry either a value or an error. `try` returns early on an error and unwraps the value otherwise, making error paths explicit.", "zig"),
    KnowledgeFact("zig defer", ("what does defer do in zig", "explain defer in zig", "when should i use defer in zig"), "`defer` in Zig schedules cleanup for the end of the current scope, which makes ownership and resource release easier to audit.", "zig"),
    KnowledgeFact("zig slices", ("what is a zig slice", "explain slices in zig", "zig slice versus array"), "A Zig slice is a pointer plus a length. It views contiguous memory without owning it by itself, while an array has a compile-time known length.", "zig"),
    KnowledgeFact("debug ci", ("how do i debug a failing ci job", "what should i check when ci fails", "triage a failing github actions run"), "For a failing CI job, read the first real error, reproduce the command locally, isolate whether it is environment or code, make the smallest fix, then rerun the narrow check before the full suite.", "real-world task"),
    KnowledgeFact("incident response", ("how do i triage a production incident", "what are incident response steps", "handle an outage checklist"), "A practical incident response loop is: stabilize users first, assign roles, capture timeline, identify the blast radius, mitigate, communicate status, then do a blameless follow-up with corrective actions.", "real-world task"),
    KnowledgeFact("bug report", ("how do i write a useful bug report", "what should a bug report include", "make a bug report template"), "A useful bug report includes expected behavior, actual behavior, reproduction steps, environment, relevant logs or screenshots, severity, and the smallest known failing case.", "real-world task"),
    KnowledgeFact("acceptance criteria", ("write acceptance criteria", "what are good acceptance criteria", "how do i define done for a feature"), "Good acceptance criteria are observable and testable: given the starting state, when the user acts, then the system shows a specific result, including important error and edge cases.", "real-world task"),
    KnowledgeFact("project plan", ("how do i plan a small software project", "make a project plan", "software project planning steps"), "A small software project plan should name the outcome, users, constraints, milestones, risks, validation checks, and the next concrete task that moves the project forward.", "real-world task"),
)

CODING_TEMPLATES: tuple[tuple[str, str, str], ...] = (
    ("zig reverse slice", "write a zig function to reverse a slice", "A compact Zig in-place reverse function is:\n```zig\npub fn reverse(comptime T: type, items: []T) void {\n    var left: usize = 0;\n    var right: usize = items.len;\n    while (left < right) {\n        right -= 1;\n        const tmp = items[left];\n        items[left] = items[right];\n        items[right] = tmp;\n        left += 1;\n    }\n}\n```"),
    ("zig arraylist", "show a zig arraylist example", "A minimal Zig ArrayList example is:\n```zig\nvar list = std.ArrayList(u8).empty;\ndefer list.deinit(allocator);\ntry list.append(allocator, 42);\n```"),
    ("zig error union", "write zig code using an error union", "A small Zig error-union example is:\n```zig\nconst ParseError = error{Empty};\nfn firstByte(input: []const u8) ParseError!u8 {\n    if (input.len == 0) return error.Empty;\n    return input[0];\n}\n```"),
    ("json object", "generate json with name and age", "```json\n{\"name\":\"Ada\",\"age\":42}\n```"),
)


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip())


def upgrade_release_text(text: str) -> str:
    return text.replace("SBAN v28", "SBAN v29").replace("v28", "v29").replace("V28", "V29")


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


def build_synthetic_pairs() -> list[tuple[str, str, str]]:
    pairs: list[tuple[str, str, str]] = []
    for fact in FACTS:
        for alias in fact.aliases:
            pairs.append((alias, fact.answer, fact.category))
        pairs.append((f"give me a short {fact.topic} explanation", fact.answer, fact.category))
    for category, prompt, answer in CODING_TEMPLATES:
        pairs.append((prompt, answer, category))
    return pairs


def dedupe_pairs(pairs: list[tuple[str, str]]) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    seen: set[str] = set()
    for user, assistant in pairs:
        key = normalize(user).lower()
        if not key or key in seen:
            continue
        seen.add(key)
        out.append((normalize(user), normalize(assistant)))
    return out


def render_pairs(pairs: list[tuple[str, str]]) -> str:
    lines: list[str] = []
    for user, assistant in pairs:
        lines.append(f"User: {user}")
        lines.append(f"Assistant: {assistant}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Build generated SBAN v29 synthetic knowledge assets.")
    parser.add_argument("--base-open-seed", type=Path, default=BASE_OPEN_SEED)
    parser.add_argument("--open-output", type=Path, default=OPEN_OUTPUT)
    parser.add_argument("--knowledge-output", type=Path, default=KNOWLEDGE_OUTPUT)
    parser.add_argument("--stats-output", type=Path, default=STATS_OUTPUT)
    args = parser.parse_args()

    base_pairs = parse_seed_text(args.base_open_seed.read_text(encoding="utf-8"))
    upgraded_base = [(upgrade_release_text(user), upgrade_release_text(assistant)) for user, assistant in base_pairs]
    synthetic = build_synthetic_pairs()
    synthetic_pairs = [(user, answer) for user, answer, _category in synthetic]

    args.open_output.parent.mkdir(parents=True, exist_ok=True)
    args.knowledge_output.parent.mkdir(parents=True, exist_ok=True)
    args.stats_output.parent.mkdir(parents=True, exist_ok=True)
    args.open_output.write_text(render_pairs(dedupe_pairs(upgraded_base + synthetic_pairs)), encoding="utf-8", newline="\n")
    args.knowledge_output.write_text(render_pairs(dedupe_pairs(synthetic_pairs)), encoding="utf-8", newline="\n")

    by_category: dict[str, int] = {}
    for _user, _answer, category in synthetic:
        by_category[category] = by_category.get(category, 0) + 1
    args.stats_output.write_text(
        json.dumps(
            {
                "release": "v29",
                "method": "generated from structured facts and coding templates, not handwritten conversation transcripts",
                "knowledge_pairs": len(dedupe_pairs(synthetic_pairs)),
                "open_seed_pairs": len(dedupe_pairs(upgraded_base + synthetic_pairs)),
                "categories": by_category,
                "outputs": {
                    "knowledge": str(args.knowledge_output.relative_to(ROOT)),
                    "open_seed": str(args.open_output.relative_to(ROOT)),
                },
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(f"knowledge_pairs={len(dedupe_pairs(synthetic_pairs))}")
    print(f"open_seed_pairs={len(dedupe_pairs(upgraded_base + synthetic_pairs))}")
    print(f"wrote={args.knowledge_output}")


if __name__ == "__main__":
    main()
