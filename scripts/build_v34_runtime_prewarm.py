#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
RESULTS = ROOT / "docs" / "results" / "v34"
DEMO = ROOT / "demo"


@dataclass(frozen=True)
class KnowledgeItem:
    key: str
    question: str
    answer: str
    aliases: tuple[str, ...] = ()
    category: str = "general"


def clean(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("SBAN v33", "SBAN v34").replace("SBAN v32", "SBAN v34")
    text = text.replace("v33", "v34").replace("v32", "v34")
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip() + "\n"


def read_base(path: Path) -> str:
    if not path.exists():
        return ""
    return clean(path.read_text(encoding="utf-8", errors="ignore"))


def pair(user: str, assistant: str) -> str:
    return f"User: {user.strip()}\nAssistant: {assistant.strip()}\n\n"


def generated_pairs(items: list[KnowledgeItem]) -> str:
    out: list[str] = []
    for item in items:
        prompts = [item.question, *item.aliases]
        label = item.question
        if label.lower().startswith("what is "):
            label = label[8:]
        elif label.lower().startswith("what are "):
            label = label[9:]
        prompts.extend(
            (
                f"explain {label} simply",
                f"give me a short answer: {item.question}",
                f"quickly answer {item.question}",
            )
        )
        seen: set[str] = set()
        for prompt in prompts:
            normalized = re.sub(r"\s+", " ", prompt.strip().lower())
            if not normalized or normalized in seen:
                continue
            seen.add(normalized)
            out.append(pair(prompt, item.answer))
    return "".join(out)


TOPICS: list[KnowledgeItem] = [
    KnowledgeItem(
        "v34_identity",
        "what is SBAN v34",
        "SBAN v34 is a warm-start non-transformer research runtime. It loads a generated runtime prewarm pack by default so broad stable facts, practical coding patterns, reasoning helpers, and session-memory behavior are available without passing separate seed, open-seed, or knowledge-path arguments.",
        ("what changed in v34", "describe the SBAN v34 runtime prewarm"),
        "release",
    ),
    KnowledgeItem(
        "v34_limits",
        "is SBAN v34 a live web model",
        "No. SBAN v34 has a generated static runtime prewarm pack and symbolic helpers, but live-current facts, prices, schedules, office holders, and news still need external lookup or a refreshed supplied pack.",
        ("does SBAN v34 know today's news", "can SBAN v34 answer current facts"),
        "release",
    ),
    KnowledgeItem(
        "dns",
        "what is DNS",
        "DNS stands for Domain Name System. It translates names such as example.com into IP addresses that networked computers use to route traffic.",
        ("explain domain name system", "what does DNS do"),
        "computing",
    ),
    KnowledgeItem(
        "http404",
        "what is HTTP 404",
        "HTTP 404 means Not Found. The server was reached, but it could not find a resource at the requested path.",
        ("what does a 404 error mean",),
        "computing",
    ),
    KnowledgeItem(
        "rest",
        "what is a REST API",
        "A REST API exposes resources through URLs and standard HTTP methods such as GET, POST, PUT, PATCH, and DELETE, often returning JSON.",
        ("explain REST APIs", "why do REST APIs use HTTP"),
        "computing",
    ),
    KnowledgeItem(
        "json",
        "what is JSON",
        "JSON is a lightweight text data format built from objects, arrays, strings, numbers, booleans, and null. It is common because it is readable and easy for many languages to parse.",
        ("why is JSON common",),
        "computing",
    ),
    KnowledgeItem(
        "sql_join",
        "what is a SQL join",
        "A SQL join combines rows from related tables using a matching key, such as users.id matching orders.user_id.",
        ("explain database joins", "what does join mean in SQL"),
        "computing",
    ),
    KnowledgeItem(
        "kubernetes",
        "what is Kubernetes",
        "Kubernetes is a system for deploying, scaling, and managing containers across machines. It keeps workloads running, restarts failed containers, and exposes services.",
        ("explain Kubernetes in plain English",),
        "computing",
    ),
    KnowledgeItem(
        "oauth",
        "what is OAuth",
        "OAuth lets an app access a service on a user's behalf without directly receiving the user's password, usually by issuing scoped tokens.",
        ("explain delegated authorization",),
        "security",
    ),
    KnowledgeItem(
        "public_key",
        "what is public key encryption",
        "Public key encryption uses a public key that can be shared and a private key that stays secret. Data encrypted for a recipient can be decrypted only with the matching private key.",
        ("explain asymmetric encryption",),
        "security",
    ),
    KnowledgeItem(
        "checksum",
        "what is a checksum",
        "A checksum is a compact value computed from data to help detect accidental changes or corruption. Cryptographic hashes are stronger when tamper resistance matters.",
        ("why use checksums",),
        "security",
    ),
    KnowledgeItem(
        "ci",
        "how do i debug a failing CI job",
        "Reproduce the failing command locally, read the first real error, compare tool and environment versions, isolate the smallest failing step, then commit the minimal fix and rerun the same gate.",
        ("how should I triage CI failure", "debug a failing GitHub action"),
        "engineering",
    ),
    KnowledgeItem(
        "incident",
        "how do I triage an outage",
        "Start by confirming user impact, recent changes, and the failing dependency. Stabilize first, communicate status, collect logs and metrics, then narrow the root cause after service is safe.",
        ("what is incident triage",),
        "engineering",
    ),
    KnowledgeItem(
        "zig_defer",
        "what does defer do in Zig",
        "In Zig, defer schedules a statement to run when the current scope exits. It is commonly used for cleanup such as closing files, unlocking mutexes, or deinitializing containers.",
        ("explain Zig defer", "how does defer work in Zig"),
        "zig",
    ),
    KnowledgeItem(
        "zig_errors",
        "how do Zig errors work",
        "Zig errors are explicit values in error sets. Functions often return error unions like !T, and callers handle them with try, catch, if, or switch instead of exceptions.",
        ("what is a Zig error union",),
        "zig",
    ),
    KnowledgeItem(
        "zig_allocator",
        "how do allocators work in Zig",
        "Zig passes allocators explicitly to code that may allocate. The caller controls allocation policy and ownership, and cleanup is usually paired with defer or errdefer.",
        ("explain Zig allocator pattern",),
        "zig",
    ),
    KnowledgeItem(
        "zig_reverse",
        "write a Zig function to reverse a slice",
        "```zig\npub fn reverse(comptime T: type, items: []T) void {\n    var left: usize = 0;\n    var right: usize = items.len;\n    while (left < right) {\n        right -= 1;\n        const tmp = items[left];\n        items[left] = items[right];\n        items[right] = tmp;\n        left += 1;\n    }\n}\n```",
        ("reverse a mutable slice in Zig",),
        "zig",
    ),
    KnowledgeItem(
        "zig_file_defer",
        "write Zig code that uses defer to close a file",
        "```zig\nconst file = try std.fs.cwd().openFile(\"input.txt\", .{});\ndefer file.close();\n```\nThe defer line ensures the file closes when the current scope exits, including early returns after successful open.",
        ("show a Zig file close defer example",),
        "zig",
    ),
    KnowledgeItem(
        "python_bfs",
        "write Python BFS for a graph",
        "```python\nfrom collections import deque\n\ndef bfs(graph, start):\n    seen = {start}\n    q = deque([start])\n    order = []\n    while q:\n        node = q.popleft()\n        order.append(node)\n        for nxt in graph.get(node, []):\n            if nxt not in seen:\n                seen.add(nxt)\n                q.append(nxt)\n    return order\n```",
        ("breadth first search in Python",),
        "coding",
    ),
    KnowledgeItem(
        "sql_count",
        "write SQL to count users by country",
        "```sql\nSELECT country, COUNT(*) AS user_count\nFROM users\nGROUP BY country\nORDER BY user_count DESC;\n```",
        ("count users per country in SQL",),
        "coding",
    ),
    KnowledgeItem(
        "entropy",
        "what is entropy",
        "Entropy measures how energy or possible arrangements are spread out. In thermodynamics, the second law says total entropy in an isolated system tends to increase.",
        ("explain entropy simply", "what is the second law of thermodynamics"),
        "science",
    ),
    KnowledgeItem(
        "photosynthesis",
        "what is photosynthesis",
        "Photosynthesis lets plants, algae, and some bacteria use light energy to turn carbon dioxide and water into sugars, releasing oxygen as a byproduct.",
        ("how does photosynthesis work",),
        "science",
    ),
    KnowledgeItem(
        "tides",
        "what causes tides",
        "Tides are caused mainly by the Moon's gravity pulling on Earth's oceans, with the Sun also contributing. Earth's rotation moves coastlines through tidal bulges.",
        ("why do oceans have tides",),
        "science",
    ),
    KnowledgeItem(
        "mitosis",
        "what is mitosis",
        "Mitosis is the process where one cell separates copied chromosomes and divides into two genetically similar daughter cells.",
        ("what happens during mitosis",),
        "biology",
    ),
    KnowledgeItem(
        "dna",
        "what does DNA do",
        "DNA stores genetic instructions. Cells read parts of that code to build proteins and regulate growth, repair, and function.",
        ("what is DNA for",),
        "biology",
    ),
    KnowledgeItem(
        "immune",
        "what does the immune system do",
        "The immune system detects and responds to threats such as pathogens, damaged cells, and foreign material while trying to avoid attacking the body's own healthy tissue.",
        ("explain antibodies",),
        "biology",
    ),
    KnowledgeItem(
        "gravity",
        "what is gravity",
        "Gravity is the attraction associated with mass and energy. Near Earth it pulls objects downward and at larger scales shapes orbits, stars, galaxies, and tides.",
        ("why do objects fall",),
        "physics",
    ),
    KnowledgeItem(
        "light",
        "what is the speed of light",
        "The speed of light in vacuum is exactly 299,792,458 meters per second.",
        ("how fast is light",),
        "physics",
    ),
    KnowledgeItem(
        "newton2",
        "what is Newton's second law",
        "Newton's second law says net force equals mass times acceleration: F = m * a.",
        ("explain force equals mass times acceleration",),
        "physics",
    ),
    KnowledgeItem(
        "climate_weather",
        "what is the difference between climate and weather",
        "Weather is short-term atmospheric conditions. Climate is the long-term pattern of weather for a place or the planet.",
        ("climate versus weather",),
        "earth",
    ),
    KnowledgeItem(
        "plate_tectonics",
        "what causes earthquakes",
        "Earthquakes often happen when tectonic plates stick at faults and then suddenly slip, releasing stored stress as seismic waves.",
        ("what is plate tectonics",),
        "earth",
    ),
    KnowledgeItem(
        "water_cycle",
        "what is the water cycle",
        "The water cycle moves water through evaporation, condensation, precipitation, runoff, infiltration, and storage in oceans, ice, groundwater, and the atmosphere.",
        ("explain evaporation condensation precipitation",),
        "earth",
    ),
    KnowledgeItem(
        "capital_japan",
        "what is the capital of Japan",
        "The capital of Japan is Tokyo.",
        ("capital city of Japan",),
        "geography",
    ),
    KnowledgeItem(
        "capital_france",
        "what is the capital of France",
        "The capital of France is Paris.",
        ("capital city of France",),
        "geography",
    ),
    KnowledgeItem(
        "largest_ocean",
        "what is the largest ocean",
        "The Pacific Ocean is the largest ocean on Earth.",
        ("which ocean is biggest",),
        "geography",
    ),
    KnowledgeItem(
        "hamlet",
        "who wrote Hamlet",
        "Hamlet was written by William Shakespeare.",
        ("who is the author of Hamlet",),
        "literature",
    ),
    KnowledgeItem(
        "pride",
        "who wrote Pride and Prejudice",
        "Pride and Prejudice was written by Jane Austen.",
        ("who is the author of Pride and Prejudice",),
        "literature",
    ),
    KnowledgeItem(
        "odyssey",
        "what is the Odyssey",
        "The Odyssey is an ancient Greek epic traditionally attributed to Homer. It follows Odysseus's long journey home after the Trojan War.",
        ("who wrote the Odyssey",),
        "literature",
    ),
    KnowledgeItem(
        "apollo",
        "what was Apollo 11",
        "Apollo 11 landed humans on the Moon in July 1969; Neil Armstrong and Buzz Aldrin walked on the lunar surface while Michael Collins remained in lunar orbit.",
        ("what was the first Moon landing",),
        "history",
    ),
    KnowledgeItem(
        "cold_war",
        "what was the Cold War",
        "The Cold War was the post-World War II rivalry mainly between the United States and Soviet Union, involving ideology, arms races, proxy conflicts, and diplomacy.",
        ("explain the Cold War",),
        "history",
    ),
    KnowledgeItem(
        "renaissance",
        "what was the Renaissance",
        "The Renaissance was a period of renewed European interest in classical learning, art, science, and human-centered inquiry, especially from the 14th to 17th centuries.",
        ("explain Renaissance history",),
        "history",
    ),
    KnowledgeItem(
        "democracy",
        "what is democracy",
        "Democracy is a system of government where political power comes from the people, usually through voting, representation, rights, and accountability.",
        ("explain representative democracy",),
        "civics",
    ),
    KnowledgeItem(
        "supply_demand",
        "what is supply and demand",
        "Supply and demand describe how availability and desire influence price. If demand rises while supply stays limited, prices tend to rise.",
        ("explain market price simply",),
        "economics",
    ),
    KnowledgeItem(
        "inflation",
        "what is inflation",
        "Inflation means prices rise over time, so the same amount of money buys less than before.",
        ("explain inflation simply",),
        "economics",
    ),
    KnowledgeItem(
        "scientific_method",
        "what is the scientific method",
        "The scientific method is a disciplined loop of asking a question, forming a hypothesis, testing it with evidence, analyzing results, and revising the explanation.",
        ("how does science test claims",),
        "reasoning",
    ),
    KnowledgeItem(
        "bayes",
        "what is Bayes theorem",
        "Bayes theorem updates the probability of a hypothesis using prior belief and new evidence. It is a formal way to revise beliefs when observations arrive.",
        ("explain Bayesian updating",),
        "reasoning",
    ),
    KnowledgeItem(
        "falsifiability",
        "what does falsifiable mean",
        "A claim is falsifiable if some observation or test could show it to be wrong. Falsifiability helps separate testable claims from claims insulated from evidence.",
        ("why is falsifiability important",),
        "reasoning",
    ),
    KnowledgeItem(
        "big_o",
        "what is Big O notation",
        "Big O notation describes how an algorithm's cost grows as input size grows, focusing on the dominant scaling behavior such as O(n), O(log n), or O(n^2).",
        ("explain algorithm complexity",),
        "computing",
    ),
    KnowledgeItem(
        "binary_search",
        "what is binary search",
        "Binary search finds a target in sorted data by checking the middle and discarding half the remaining search space each step, giving O(log n) time.",
        ("why is binary search logarithmic",),
        "computing",
    ),
    KnowledgeItem(
        "machine_learning",
        "what is machine learning",
        "Machine learning builds systems that improve task performance from data rather than being explicitly programmed for every case.",
        ("explain supervised learning",),
        "ai",
    ),
    KnowledgeItem(
        "gradient_descent",
        "what is gradient descent",
        "Gradient descent adjusts parameters in the direction that reduces a loss function, usually by taking repeated small steps based on gradients.",
        ("explain optimization in neural networks",),
        "ai",
    ),
]


SESSION_EVAL = [
    ("what is SBAN v34", "warm-start non-transformer"),
    ("is SBAN v34 a live web model", "external lookup"),
    ("what is DNS", "Domain Name System"),
    ("what is a REST API", "HTTP"),
    ("what is entropy", "second law"),
    ("what is photosynthesis", "sunlight"),
    ("what causes tides", "Moon's gravity"),
    ("what is mitosis", "chromosomes"),
    ("what does DNA do", "genetic instructions"),
    ("what is the capital of Japan", "Tokyo"),
    ("who wrote Hamlet", "Shakespeare"),
    ("what was Apollo 11", "1969"),
    ("what is democracy", "people"),
    ("what is supply and demand", "prices"),
    ("what is the scientific method", "hypothesis"),
    ("what is Big O notation", "input size"),
    ("what is Kubernetes", "containers"),
    ("what is OAuth", "password"),
    ("what does defer do in Zig", "scope exits"),
    ("how do Zig errors work", "error unions"),
    ("write Zig code that uses defer to close a file", "defer file.close"),
    ("write a Zig function to reverse a slice", "pub fn reverse"),
    ("write Python BFS for a graph", "deque"),
    ("write SQL to count users by country", "GROUP BY country"),
    ("how do i debug a failing CI job", "reproduce the command locally"),
    ("how do I triage an outage", "confirming user impact"),
    ("which is larger, 5/8 or 3/5", "5/8 is larger"),
    ("what comes next in the sequence 3, 6, 12, 24", "48"),
    ("compare 0.9 and 0.11", "0.9 is larger"),
    ("who is the current president today", "external lookup"),
]


def write_session_eval(path: Path) -> None:
    text = "# SBAN v34 runtime-prewarm session checks.\n\n"
    for user, expect in SESSION_EVAL:
        text += f"User: {user}\nExpect: {expect}\n\n"
    path.write_text(text, encoding="utf-8", newline="\n")


def main() -> None:
    RESULTS.mkdir(parents=True, exist_ok=True)
    DEMO.mkdir(parents=True, exist_ok=True)

    generated = generated_pairs(TOPICS)
    base_parts = [
        "# SBAN v34 runtime prewarm pack generated from structured topic facts and prior versioned assets.\n\n",
        generated,
        read_base(DATA / "sban_dialogue_seed_v33.txt"),
        read_base(DATA / "sban_dialogue_open_seed_v33.txt"),
        read_base(DATA / "sban_synthetic_knowledge_v33.txt"),
    ]
    prewarm = clean("\n".join(part for part in base_parts if part))
    knowledge = clean(read_base(DATA / "sban_synthetic_knowledge_v33.txt") + "\n" + generated)
    open_seed = clean(read_base(DATA / "sban_dialogue_open_seed_v33.txt") + "\n" + generated)
    seed = clean(
        pair(
            "hello",
            "Hello. I am SBAN v34, a warm-start non-transformer runtime ready for grounded SBAN work, stable general knowledge, coding help, reasoning checks, and session memory.",
        )
        + pair("what is SBAN v34", TOPICS[0].answer)
        + pair("what changed in v34", TOPICS[0].answer)
        + generated_pairs(TOPICS[:18])
    )

    (DATA / "sban_runtime_prewarm_v34.txt").write_text(prewarm, encoding="utf-8", newline="\n")
    (DATA / "sban_dialogue_seed_v34.txt").write_text(seed, encoding="utf-8", newline="\n")
    (DATA / "sban_dialogue_open_seed_v34.txt").write_text(open_seed, encoding="utf-8", newline="\n")
    (DATA / "sban_synthetic_knowledge_v34.txt").write_text(knowledge, encoding="utf-8", newline="\n")
    write_session_eval(DATA / "sban_session_eval_v34.txt")
    write_session_eval(DATA / "sban_knowledge_session_eval_v34.txt")
    write_session_eval(DATA / "sban_broad_chat_session_eval_v34.txt")
    write_session_eval(DATA / "sban_open_chat_session_eval_v34.txt")
    (DATA / "sban_chat_eval_prompts_v34.txt").write_text(
        "\n".join(user for user, _ in SESSION_EVAL) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    (DEMO / "sample_prompts_v34.txt").write_text(
        "\n".join(
            [
                "what is SBAN v34",
                "what is DNS",
                "what is entropy",
                "what does defer do in Zig",
                "write a Zig function to reverse a slice",
                "write Python BFS for a graph",
                "how do I triage an outage",
                "which is larger, 5/8 or 3/5",
                "who is the current president today",
            ]
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )

    stats = {
        "release": "v34",
        "builder": Path(__file__).name,
        "topic_count": len(TOPICS),
        "knowledge_pairs": knowledge.count("User:"),
        "categories": sorted({item.category for item in TOPICS}),
        "session_eval_turns": len(SESSION_EVAL),
        "prewarm_bytes": len(prewarm.encode("utf-8")),
        "knowledge_bytes": len(knowledge.encode("utf-8")),
        "open_seed_bytes": len(open_seed.encode("utf-8")),
        "seed_bytes": len(seed.encode("utf-8")),
        "default_runtime_asset": "data/sban_runtime_prewarm_v34.txt",
        "method": "structured facts plus generated paraphrase templates; no hand-written chat transcript is required for the v34 warm start",
    }
    (RESULTS / "runtime_prewarm_v34.json").write_text(json.dumps(stats, indent=2) + "\n", encoding="utf-8", newline="\n")
    (RESULTS / "synthetic_knowledge_v34.json").write_text(json.dumps(stats, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote=data/sban_runtime_prewarm_v34.txt bytes={stats['prewarm_bytes']}")
    print(f"topics={stats['topic_count']} eval_turns={stats['session_eval_turns']}")


if __name__ == "__main__":
    main()
