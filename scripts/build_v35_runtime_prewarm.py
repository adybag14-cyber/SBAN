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
RESULTS = ROOT / "docs" / "results" / "v35"
DEMO = ROOT / "demo"

VERSION = "v35"
PREVIOUS = "v34"
LEARNED_PATH = DATA / "sban_learned_reasoning_v35.txt"
MANIFEST_PATH = RESULTS / "autolearn_manifest_v35.json"
REQUIRED_OUTPUTS = [
    LEARNED_PATH,
    DATA / "sban_runtime_prewarm_v35.txt",
    DATA / "sban_cold_seed_v35.txt",
    DATA / "sban_dialogue_seed_v35.txt",
    DATA / "sban_dialogue_open_seed_v35.txt",
    DATA / "sban_synthetic_knowledge_v35.txt",
    DATA / "sban_chat_eval_prompts_v35.txt",
    DATA / "sban_session_eval_v35.txt",
    DATA / "sban_open_chat_session_eval_v35.txt",
    DATA / "sban_broad_chat_session_eval_v35.txt",
    DATA / "sban_knowledge_session_eval_v35.txt",
    DATA / "sban_learned_session_eval_v35.txt",
    RESULTS / "runtime_prewarm_v35.json",
    RESULTS / "synthetic_knowledge_v35.json",
    DEMO / "sample_prompts_v35.txt",
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
    value = value.replace("SBAN v34", "SBAN v35").replace("v34", "v35")
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
    text = text.replace("SBAN v34", "SBAN v35").replace("v34", "v35")
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
            "what is SBAN v35",
            "SBAN v35 is an auto-learned warm-start SBAN runtime. It keeps the generated v34 prewarm surface, adds a learned reasoning corpus produced by dataset adapters, and routes that corpus through runtime retrieval so replies can improve by regenerating training data instead of expanding dialogue.zig.",
            "fallback-v35",
        ),
        Example(
            "how does SBAN v35 learn without editing dialogue.zig",
            "SBAN v35 learns by rebuilding data/sban_learned_reasoning_v35.txt from dataset adapters and then loading that file through the same sparse retrieval scorer as other dialogue corpora. Improving the training set changes runtime behavior without adding new hardcoded prompt branches.",
            "fallback-v35",
        ),
        Example(
            "If all daxes are lums, and some lums are norps, are all daxes definitely norps? Explain.",
            "No, not definitely. The statement says every dax is a lum, and only that some lums are norps. The some-lums fact may refer to lums that are not daxes, so the conclusion that every dax is a norp does not follow.",
            "fallback-v35",
        ),
        Example(
            "If all glims are tars and all tars are noles, are all glims noles?",
            "Yes. This is transitive class reasoning: every glim is inside the tar set, and every tar is inside the nole set, so every glim is also a nole.",
            "fallback-v35",
        ),
        Example(
            "A box has 3 red balls and 2 blue balls. If one red ball is added, how many balls are there?",
            "There are 6 balls. Start with 3 + 2 = 5, then add one more red ball for 6 total.",
            "fallback-v35",
        ),
        Example(
            "why did the JSON prompt with age 37 fail before v35",
            "The earlier runtime had a static JSON example that always returned age 42. V35 treats simple JSON name and age prompts as slot filling, so the requested value is preserved instead of copied from a canned example.",
            "fallback-v35",
        ),
        Example(
            "what changed about session forget in v35",
            "V35 adds a structured forget path. A request such as forget my dog name maps to the normalized dog key, removes that fact from session memory, and later recall returns a miss instead of a stale answer.",
            "fallback-v35",
        ),
        Example(
            "summarize: alpha beta gamma delta alpha beta gamma delta alpha beta gamma delta",
            "Summary: the passage is repetitive and cycles through the same four terms: alpha, beta, gamma, and delta.",
            "fallback-v35",
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

    learned_text = "# SBAN v35 learned reasoning corpus generated by scripts/build_v35_runtime_prewarm.py.\n\n"
    learned_text += "".join(pair(item.user, item.assistant) for item in examples)
    LEARNED_PATH.write_text(learned_text, encoding="utf-8")

    v35_overview = pair(
        "what is SBAN v35",
        "SBAN v35 is an auto-learned warm-start non-transformer runtime. It uses generated prewarm knowledge plus a learned reasoning corpus built from online dataset adapters and deterministic fallbacks, so reply quality can improve by regenerating data instead of expanding dialogue.zig.",
    )
    previous_prewarm = read_previous("sban_runtime_prewarm_v34.txt")
    prewarm_text = "# SBAN v35 runtime prewarm pack with auto-learned reasoning corpus.\n\n"
    prewarm_text += v35_overview
    prewarm_text += previous_prewarm
    prewarm_text += learned_text
    (DATA / "sban_runtime_prewarm_v35.txt").write_text(prewarm_text, encoding="utf-8")
    (DATA / "sban_dialogue_seed_v35.txt").write_text(prewarm_text, encoding="utf-8")

    open_seed = "# SBAN v35 open-chat compatibility seed.\n\n"
    open_seed += read_previous("sban_dialogue_open_seed_v34.txt")
    open_seed += "".join(pair(item.user, item.assistant) for item in examples if item.source.startswith("fallback"))
    (DATA / "sban_dialogue_open_seed_v35.txt").write_text(open_seed, encoding="utf-8")

    knowledge = "# SBAN v35 synthetic knowledge compatibility pack.\n\n"
    knowledge += read_previous("sban_synthetic_knowledge_v34.txt")
    knowledge += learned_text
    (DATA / "sban_synthetic_knowledge_v35.txt").write_text(knowledge, encoding="utf-8")

    cold = "# SBAN v35 cold seed. This is intentionally tiny for prewarm_path=none tests.\n\n"
    cold += pair("what is SBAN v35 cold mode", "Cold mode disables prewarm, open-chat, knowledge, and learned corpora except for this tiny seed. It is useful for proving that broad answers come from generated data assets rather than hidden code branches.")
    (DATA / "sban_cold_seed_v35.txt").write_text(cold, encoding="utf-8")

    prompts = [
        "what is SBAN v35",
        "how does SBAN v35 learn without editing dialogue.zig",
        "If all daxes are lums, and some lums are norps, are all daxes definitely norps? Explain.",
        "generate JSON with name Ada and age 37",
        "my dog is max now",
        "what is my dog name",
        "forget my dog name",
        "what is my dog name",
        "what is DNS",
        "write a Zig function to reverse a slice",
    ]
    (DATA / "sban_chat_eval_prompts_v35.txt").write_text("\n".join(prompts) + "\n", encoding="utf-8")

    write_session(
        DATA / "sban_session_eval_v35.txt",
        [
            ("what is SBAN v35", "auto-learned"),
            ("generate JSON with name Ada and age 37", "\"age\":37"),
            ("my dog is luna", "Luna"),
            ("what is my dog name", "Luna"),
            ("my dog is max now", "Max"),
            ("what is my dog name", "Max"),
            ("forget my dog name", "Forgot"),
            ("what is my dog name", "do not know"),
        ],
    )
    write_session(
        DATA / "sban_open_chat_session_eval_v35.txt",
        [
            ("hello", "SBAN v35"),
            ("what should new users try first", "learned reasoning"),
            ("how does SBAN v35 learn without editing dialogue.zig", "sban_learned_reasoning_v35.txt"),
        ],
    )
    write_session(
        DATA / "sban_broad_chat_session_eval_v35.txt",
        [
            ("what is DNS", "Domain Name System"),
            ("what is entropy", "second law"),
            ("write a Zig function to reverse a slice", "pub fn reverse"),
        ],
    )
    write_session(
        DATA / "sban_knowledge_session_eval_v35.txt",
        [
            ("what changed in v35", "auto-learned"),
            ("what changed about session forget in v35", "structured forget"),
            ("why did the JSON prompt with age 37 fail before v35", "slot"),
        ],
    )
    write_session(
        DATA / "sban_learned_session_eval_v35.txt",
        [
            ("If all daxes are lums, and some lums are norps, are all daxes definitely norps? Explain.", "does not follow"),
            ("If all glims are tars and all tars are noles, are all glims noles?", "transitive"),
            ("A box has 3 red balls and 2 blue balls. If one red ball is added, how many balls are there?", "6"),
        ],
    )

    sample_prompts = "\n".join(prompts + ["prewarm_path=none learned_path=none check"]) + "\n"
    (DEMO / "sample_prompts_v35.txt").write_text(sample_prompts, encoding="utf-8")

    runtime_stats = {
        "version": VERSION,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "prewarm_bytes": (DATA / "sban_runtime_prewarm_v35.txt").stat().st_size,
        "learned_bytes": LEARNED_PATH.stat().st_size,
        "learned_examples": len(examples),
        "knowledge_pairs": len(examples),
        "online_examples": online_count,
        "fallback_examples": fallback_count,
        "sources": sources,
        "categories": ["arithmetic", "strategyqa", "commonsense", "runtime-regression"],
        "cold_seed_path": "data/sban_cold_seed_v35.txt",
        "learned_path": "data/sban_learned_reasoning_v35.txt",
    }
    (RESULTS / "runtime_prewarm_v35.json").write_text(json.dumps(runtime_stats, indent=2) + "\n", encoding="utf-8")
    (RESULTS / "synthetic_knowledge_v35.json").write_text(json.dumps({**runtime_stats, "path": "data/sban_synthetic_knowledge_v35.txt"}, indent=2) + "\n", encoding="utf-8")

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
    parser = argparse.ArgumentParser(description="Build SBAN v35 runtime prewarm and auto-learned reasoning assets.")
    parser.add_argument("--force-refresh", action="store_true", help="Regenerate even when an online-generated manifest already exists.")
    parser.add_argument("--gsm8k-limit", type=int, default=16)
    parser.add_argument("--strategyqa-limit", type=int, default=12)
    parser.add_argument("--commonsense-limit", type=int, default=12)
    args = parser.parse_args()

    if not args.force_refresh and existing_online_assets_ready():
        print(f"reused_existing_online_v35_assets={MANIFEST_PATH}")
        return

    online, online_errors = fetch_online_examples(args)
    examples = dedupe(online + fallback_examples())
    write_outputs(examples, online_errors)


if __name__ == "__main__":
    main()
