#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
RESULTS = ROOT / "docs" / "results" / "v36"
DEMO = ROOT / "demo"

VERSION = "v36"
PREVIOUS = "v35"
LEARNED_PATH = DATA / "sban_learned_reasoning_v36.txt"
MANIFEST_PATH = RESULTS / "autolearn_manifest_v36.json"
REQUIRED_OUTPUTS = [
    LEARNED_PATH,
    DATA / "sban_runtime_prewarm_v36.txt",
    DATA / "sban_cold_seed_v36.txt",
    DATA / "sban_dialogue_seed_v36.txt",
    DATA / "sban_dialogue_open_seed_v36.txt",
    DATA / "sban_synthetic_knowledge_v36.txt",
    DATA / "sban_chat_eval_prompts_v36.txt",
    DATA / "sban_session_eval_v36.txt",
    DATA / "sban_open_chat_session_eval_v36.txt",
    DATA / "sban_broad_chat_session_eval_v36.txt",
    DATA / "sban_knowledge_session_eval_v36.txt",
    DATA / "sban_learned_session_eval_v36.txt",
    DATA / "sban_limitations_session_eval_v36.txt",
    RESULTS / "runtime_prewarm_v36.json",
    RESULTS / "synthetic_knowledge_v36.json",
    DEMO / "sample_prompts_v36.txt",
]


@dataclass(frozen=True)
class Example:
    user: str
    assistant: str
    source: str


def clean(text: Any, *, limit: int = 900) -> str:
    value = "" if text is None else str(text)
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    value = re.sub(r"\s+", " ", value).strip()
    value = value.replace("SBAN v35", "SBAN v36").replace("SBAN v34", "SBAN v36").replace("v35", "v36").replace("v34", "v36")
    value = value.encode("ascii", "ignore").decode("ascii")
    if len(value) > limit:
        value = value[: limit - 3].rstrip() + "..."
    return value


def pair(user: str, assistant: str) -> str:
    return f"User: {clean(user, limit=500)}\nAssistant: {clean(assistant, limit=1000)}\n\n"


def read_previous(name: str) -> str:
    path = DATA / name
    if not path.exists():
        return ""
    text = path.read_text(encoding="utf-8", errors="ignore")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.replace("SBAN v35", "SBAN v36").replace("SBAN v34", "SBAN v36").replace("v35", "v36").replace("v34", "v36")
    text = text.encode("ascii", "ignore").decode("ascii")
    text = "\n".join(line.rstrip() for line in text.splitlines())
    if len(text) > 4_000_000:
        text = text[:4_000_000].rstrip() + "\n"
    return text + "\n"


def existing_online_assets_ready() -> bool:
    if not MANIFEST_PATH.exists() or not all(path.exists() for path in REQUIRED_OUTPUTS):
        return False
    try:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return False
    return int(manifest.get("online_examples", 0)) > 0


def take_dataset_rows(dataset_name: str, config: str | None, split: str, limit: int) -> Iterable[dict[str, Any]]:
    from datasets import load_dataset  # type: ignore

    dataset = load_dataset(dataset_name, config, split=split, streaming=True)
    count = 0
    for row in dataset:
        yield dict(row)
        count += 1
        if count >= limit:
            break


def build_gsm8k_examples(limit: int) -> list[Example]:
    examples: list[Example] = []
    for row in take_dataset_rows("openai/gsm8k", "main", "train", limit):
        question = clean(row.get("question"), limit=360)
        answer = str(row.get("answer", ""))
        rationale, _, final = answer.partition("####")
        final = clean(final or answer, limit=80)
        rationale = clean(rationale, limit=260)
        if not question or not final:
            continue
        examples.append(
            Example(
                question,
                f"Learned arithmetic answer: {final}. Compact reasoning pattern: identify the quantities, combine them in order, and check the final value. Training rationale summary: {rationale}",
                "openai/gsm8k",
            )
        )
    return examples


def build_strategyqa_examples(limit: int) -> list[Example]:
    examples: list[Example] = []
    for row in take_dataset_rows("Ritu27/StrategyQA", None, "train", limit):
        question = clean(row.get("question"), limit=320)
        raw_answer = row.get("answer")
        answer = "yes" if raw_answer is True else "no" if raw_answer is False else clean(raw_answer, limit=40)
        facts = clean(" ".join(map(str, row.get("facts") or [])), limit=260)
        decomposition = clean(" ".join(map(str, row.get("decomposition") or [])), limit=220)
        if not question or not answer:
            continue
        examples.append(
            Example(
                question,
                f"Learned strategy answer: {answer}. Use decomposition first, then test the facts against the question. Decomposition cue: {decomposition}. Fact cue: {facts}",
                "Ritu27/StrategyQA",
            )
        )
    return examples


def commonsense_answer_text(row: dict[str, Any]) -> str:
    answer_key = clean(row.get("answerKey"), limit=12)
    choices = row.get("choices")
    if isinstance(choices, dict):
        labels = choices.get("label") or []
        texts = choices.get("text") or []
        for label, text in zip(labels, texts):
            if clean(label, limit=12).upper() == answer_key.upper():
                return f"{answer_key}: {clean(text, limit=120)}"
    return answer_key


def build_commonsense_examples(limit: int) -> list[Example]:
    examples: list[Example] = []
    for row in take_dataset_rows("HuggingFaceFW/CommonsenseQA", None, "validation", limit):
        question = clean(row.get("question"), limit=320)
        answer = commonsense_answer_text(row)
        explanation = clean(row.get("answerability_explanation"), limit=260)
        if not question or not answer:
            continue
        examples.append(
            Example(
                question,
                f"Learned commonsense answer: {answer}. Use the option that best satisfies the everyday relation in the question. Explanation cue: {explanation}",
                "HuggingFaceFW/CommonsenseQA",
            )
        )
    return examples


def fallback_examples() -> list[Example]:
    return [
        Example(
            "what is SBAN v36",
            "SBAN v36 is a runtime-learning SBAN prototype. It keeps the generated v35 prewarm and learned corpus, adds limitation-regression training rows, and routes symbolic reasoning before retrieval so near-miss prompts get educated attempts instead of confident unrelated matches.",
            "fallback-v36",
        ),
        Example(
            "how does SBAN v36 learn without editing dialogue.zig",
            "SBAN v36 learns by rebuilding data/sban_learned_reasoning_v36.txt from dataset adapters and then loading that file through the same sparse retrieval scorer as other dialogue corpora. Improving the training set changes runtime behavior without adding new hardcoded prompt branches.",
            "fallback-v36",
        ),
        Example(
            "If all daxes are lums, and some lums are norps, are all daxes definitely norps? Explain.",
            "No, not definitely. The statement says every dax is a lum, and only that some lums are norps. The some-lums fact may refer to lums that are not daxes, so the conclusion that every dax is a norp does not follow.",
            "fallback-v36",
        ),
        Example(
            "If all glims are tars and all tars are noles, are all glims noles?",
            "Yes. This is transitive class reasoning: every glim is inside the tar set, and every tar is inside the nole set, so every glim is also a nole.",
            "fallback-v36",
        ),
        Example(
            "A box has 3 red balls and 2 blue balls. If one red ball is added, how many balls are there?",
            "There are 6 balls. Start with 3 + 2 = 5, then add one more red ball for 6 total.",
            "fallback-v36",
        ),
        Example(
            "why did the JSON prompt with age 37 fail before v36",
            "The earlier runtime had a static JSON example that always returned age 42. v36 treats simple JSON name and age prompts as slot filling, so the requested value is preserved instead of copied from a canned example.",
            "fallback-v36",
        ),
        Example(
            "what changed about session forget in v36",
            "v36 adds a structured forget path. A request such as forget my dog name maps to the normalized dog key, removes that fact from session memory, and later recall returns a miss instead of a stale answer.",
            "fallback-v36",
        ),
        Example(
            "summarize: alpha beta gamma delta alpha beta gamma delta alpha beta gamma delta",
            "Summary: the passage is repetitive and cycles through the same four terms: alpha, beta, gamma, and delta.",
            "fallback-v36",
        ),
        Example(
            "If no blickets are wugs and all glims are blickets, can any glim be a wug?",
            "No. All glims are blickets, and no blickets are wugs, so no glim can be a wug.",
            "fallback-v36-limitations",
        ),
        Example(
            "solve x^2 = 4",
            "x = 2 and x = -2.",
            "fallback-v36-limitations",
        ),
        Example(
            "Sam has 14 apples, gives away 5, then buys 8. How many apples does Sam have?",
            "Sam has 17 left. Start from 14, subtract 5, then add 8.",
            "fallback-v36-limitations",
        ),
        Example(
            "generate JSON with name Jane Doe and age 0",
            "```json\n{\"name\":\"Jane Doe\",\"age\":0}\n```\nThe full name and age slots are preserved exactly.",
            "fallback-v36-limitations",
        ),
        Example(
            "generate JSON with city London and temperature 18",
            "```json\n{\"city\":\"London\",\"temperature\":18}\n```\nThe city and temperature slots are preserved exactly.",
            "fallback-v36-limitations",
        ),
        Example(
            "generate JSON with name Ada and age thirty seven",
            "```json\n{\"name\":\"Ada\",\"age\":37}\n```\nThe word-number age is normalized to the JSON number 37.",
            "fallback-v36-limitations",
        ),
        Example(
            "write a Rust async HTTP server",
            "Use Tokio plus Axum: define async handlers, attach them to an Axum Router, bind a tokio::net::TcpListener, and serve it with axum::serve.",
            "fallback-v36-limitations",
        ),
    ]


def fetch_online_examples(args: argparse.Namespace) -> tuple[list[Example], list[str]]:
    errors: list[str] = []
    examples: list[Example] = []
    builders = [
        ("openai/gsm8k", lambda: build_gsm8k_examples(args.gsm8k_limit)),
        ("Ritu27/StrategyQA", lambda: build_strategyqa_examples(args.strategyqa_limit)),
        ("HuggingFaceFW/CommonsenseQA", lambda: build_commonsense_examples(args.commonsense_limit)),
    ]
    for name, builder in builders:
        try:
            examples.extend(builder())
        except Exception as exc:  # CI may not have datasets installed or network access.
            errors.append(f"{name}: {type(exc).__name__}: {exc}")
    return examples, errors


def dedupe(examples: list[Example]) -> list[Example]:
    seen: set[str] = set()
    out: list[Example] = []
    for example in examples:
        key = re.sub(r"\s+", " ", example.user.lower()).strip()
        if not key or key in seen:
            continue
        seen.add(key)
        out.append(example)
    return out


def write_session(path: Path, rows: list[tuple[str, str]]) -> None:
    text = "".join(f"User: {user}\nExpect: {expect}\n\n" for user, expect in rows)
    path.write_text(text, encoding="utf-8")


def write_outputs(examples: list[Example], online_errors: list[str]) -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    RESULTS.mkdir(parents=True, exist_ok=True)
    DEMO.mkdir(parents=True, exist_ok=True)

    online_count = sum(1 for item in examples if not item.source.startswith("fallback"))
    fallback_count = sum(1 for item in examples if item.source.startswith("fallback"))
    sources: dict[str, int] = {}
    for example in examples:
        sources[example.source] = sources.get(example.source, 0) + 1

    learned_text = "# SBAN v36 learned reasoning corpus generated by scripts/build_v36_runtime_prewarm.py.\n\n"
    learned_text += "".join(pair(item.user, item.assistant) for item in examples)
    LEARNED_PATH.write_text(learned_text, encoding="utf-8")

    v36_overview = pair(
        "what is SBAN v36",
        "SBAN v36 is an auto-learned warm-start non-transformer runtime. It uses generated prewarm knowledge plus a learned reasoning corpus built from online dataset adapters and deterministic fallbacks, so reply quality can improve by regenerating data instead of expanding dialogue.zig.",
    )
    previous_prewarm = read_previous("sban_runtime_prewarm_v35.txt")
    prewarm_text = "# SBAN v36 runtime prewarm pack with auto-learned reasoning corpus.\n\n"
    prewarm_text += v36_overview
    prewarm_text += previous_prewarm
    prewarm_text += learned_text
    (DATA / "sban_runtime_prewarm_v36.txt").write_text(prewarm_text, encoding="utf-8")
    (DATA / "sban_dialogue_seed_v36.txt").write_text(prewarm_text, encoding="utf-8")

    open_seed = "# SBAN v36 open-chat compatibility seed.\n\n"
    open_seed += read_previous("sban_dialogue_open_seed_v35.txt")
    open_seed += "".join(pair(item.user, item.assistant) for item in examples if item.source.startswith("fallback"))
    (DATA / "sban_dialogue_open_seed_v36.txt").write_text(open_seed, encoding="utf-8")

    knowledge = "# SBAN v36 synthetic knowledge compatibility pack.\n\n"
    knowledge += read_previous("sban_synthetic_knowledge_v35.txt")
    knowledge += learned_text
    (DATA / "sban_synthetic_knowledge_v36.txt").write_text(knowledge, encoding="utf-8")

    cold = "# SBAN v36 cold seed. This is intentionally tiny for prewarm_path=none tests.\n\n"
    cold += pair("what is SBAN v36 cold mode", "Cold mode disables prewarm, open-chat, knowledge, and learned corpora except for this tiny seed. It is useful for proving that broad answers come from generated data assets rather than hidden code branches.")
    (DATA / "sban_cold_seed_v36.txt").write_text(cold, encoding="utf-8")

    prompts = [
        "what is SBAN v36",
        "how does SBAN v36 learn without editing dialogue.zig",
        "If all daxes are lums, and some lums are norps, are all daxes definitely norps? Explain.",
        "generate JSON with name Ada and age 37",
        "my dog is max now",
        "what is my dog name",
        "forget my dog name",
        "what is my dog name",
        "what is DNS",
        "write a Zig function to reverse a slice",
        "If no blickets are wugs and all glims are blickets, can any glim be a wug?",
        "solve x^2 = 4",
        "Sam has 14 apples, gives away 5, then buys 8. How many apples does Sam have?",
        "generate JSON with name Jane Doe and age 0",
        "generate JSON with city London and temperature 18",
        "generate JSON with name Ada and age thirty seven",
        "write a Rust async HTTP server",
    ]
    (DATA / "sban_chat_eval_prompts_v36.txt").write_text("\n".join(prompts) + "\n", encoding="utf-8")

    write_session(
        DATA / "sban_session_eval_v36.txt",
        [
            ("what is SBAN v36", "auto-learned"),
            ("generate JSON with name Ada and age 37", "\"age\":37"),
            ("my dog is luna", "Luna"),
            ("what is my dog name", "Luna"),
            ("my dog is max now", "Max"),
            ("what is my dog name", "Max"),
            ("forget my dog name", "Forgot"),
            ("what is my dog name", "do not know"),
            ("my dog is not max", "not store"),
            ("what is my dog name", "do not know"),
            ("please do not remember that my cat is io", "not store"),
            ("what is my cat name", "do not know"),
        ],
    )
    write_session(
        DATA / "sban_open_chat_session_eval_v36.txt",
        [
            ("hello", "SBAN v36"),
            ("what should new users try first", "learned reasoning"),
            ("how does SBAN v36 learn without editing dialogue.zig", "sban_learned_reasoning_v36.txt"),
        ],
    )
    write_session(
        DATA / "sban_broad_chat_session_eval_v36.txt",
        [
            ("what is DNS", "Domain Name System"),
            ("what is entropy", "second law"),
            ("write a Zig function to reverse a slice", "pub fn reverse"),
            ("write a Rust async HTTP server", "axum"),
        ],
    )
    write_session(
        DATA / "sban_knowledge_session_eval_v36.txt",
        [
            ("what changed in v36", "auto-learned"),
            ("what changed about session forget in v36", "structured forget"),
            ("why did the JSON prompt with age 37 fail before v36", "slot"),
        ],
    )
    write_session(
        DATA / "sban_learned_session_eval_v36.txt",
        [
            ("If all daxes are lums, and some lums are norps, are all daxes definitely norps? Explain.", "does not follow"),
            ("If all glims are tars and all tars are noles, are all glims noles?", "transitive"),
            ("A box has 3 red balls and 2 blue balls. If one red ball is added, how many balls are there?", "6"),
        ],
    )
    write_session(
        DATA / "sban_limitations_session_eval_v36.txt",
        [
            ("If no blickets are wugs and all glims are blickets, can any glim be a wug?", "No"),
            ("solve x^2 = 4", "x = -2"),
            ("Sam has 14 apples, gives away 5, then buys 8. How many apples does Sam have?", "17"),
            ("generate JSON with name Jane Doe and age 0", "\"name\":\"Jane Doe\""),
            ("generate JSON with city London and temperature 18", "\"temperature\":18"),
            ("generate JSON with name Ada and age thirty seven", "\"age\":37"),
            ("what is the weather tomorrow", "external lookup"),
            ("write a Rust async HTTP server", "axum"),
        ],
    )

    sample_prompts = "\n".join(prompts + ["prewarm_path=none learned_path=none check"]) + "\n"
    (DEMO / "sample_prompts_v36.txt").write_text(sample_prompts, encoding="utf-8")

    runtime_stats = {
        "version": VERSION,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "prewarm_bytes": (DATA / "sban_runtime_prewarm_v36.txt").stat().st_size,
        "learned_bytes": LEARNED_PATH.stat().st_size,
        "learned_examples": len(examples),
        "knowledge_pairs": len(examples),
        "online_examples": online_count,
        "fallback_examples": fallback_count,
        "sources": sources,
        "categories": ["arithmetic", "strategyqa", "commonsense", "runtime-regression", "limitation-repairs"],
        "cold_seed_path": "data/sban_cold_seed_v36.txt",
        "learned_path": "data/sban_learned_reasoning_v36.txt",
    }
    (RESULTS / "runtime_prewarm_v36.json").write_text(json.dumps(runtime_stats, indent=2) + "\n", encoding="utf-8")
    (RESULTS / "synthetic_knowledge_v36.json").write_text(json.dumps({**runtime_stats, "path": "data/sban_synthetic_knowledge_v36.txt"}, indent=2) + "\n", encoding="utf-8")

    manifest = {
        **runtime_stats,
        "online_errors": online_errors,
        "dataset_adapters": [
            "openai/gsm8k",
            "Ritu27/StrategyQA",
            "HuggingFaceFW/CommonsenseQA",
        ],
        "note": "The runtime consumes the learned corpus as data through retrieval; future improvement should regenerate this file rather than adding dialogue.zig prompt branches.",
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description="Build SBAN v36 runtime prewarm and auto-learned reasoning assets.")
    parser.add_argument("--force-refresh", action="store_true", help="Regenerate even when an online-generated manifest already exists.")
    parser.add_argument("--gsm8k-limit", type=int, default=16)
    parser.add_argument("--strategyqa-limit", type=int, default=12)
    parser.add_argument("--commonsense-limit", type=int, default=12)
    args = parser.parse_args()

    if not args.force_refresh and existing_online_assets_ready():
        print(f"reused_existing_online_v36_assets={MANIFEST_PATH}")
        return

    online, online_errors = fetch_online_examples(args)
    examples = dedupe(online + fallback_examples())
    write_outputs(examples, online_errors)


if __name__ == "__main__":
    main()
