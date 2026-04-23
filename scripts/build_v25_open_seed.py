#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE_SEED_PATH = ROOT / "data" / "sban_dialogue_open_seed_v24.txt"
OUTPUT_PATH = ROOT / "data" / "sban_dialogue_open_seed_v25.txt"

EXTRA_PAIRS: list[tuple[str, str]] = [
    ("help me write a meeting agenda", "A simple meeting agenda is: purpose, the two or three decisions that matter, key updates, blockers, and the next actions with owners."),
    ("can you make a meeting agenda", "A simple meeting agenda is: purpose, the two or three decisions that matter, key updates, blockers, and the next actions with owners."),
    ("draft a short apology to my manager", "A good apology draft is brief and direct: say what happened, apologize plainly, state the fix or next step, and avoid turning the message into a defense."),
    ("how do i say no politely", "A polite way to say no is to be clear, brief, and respectful: thank them, decline plainly, and if useful offer a smaller alternative or a later time instead of overexplaining."),
    ("help me prepare for an interview", "A solid interview prep loop is: review the role, pick three stories that show impact, practice a short introduction, prepare a few questions, and rehearse concise answers out loud."),
    ("i am procrastinating and need help", "Cut the startup cost down. Pick the smallest visible step, set a ten-minute timer, and stop negotiating with the task until that first block is done."),
    ("how can i stop doomscrolling", "Make the next action physical and small: put the phone out of reach, stand up, and switch to one deliberate alternative like a short walk, water, or a single focused task."),
    ("write a python function to reverse a string", "Yes. A direct Python version is: def reverse_string(text: str) -> str: return text[::-1]."),
    ("can you suggest a workout plan", "A simple starter workout plan is three full-body sessions each week: one squat or leg movement, one push movement, one pull movement, and a short walk or easy cardio block on the other days."),
    ("give me three birthday ideas", "Three easy birthday directions are: a small dinner with one signature activity, a low-friction outing like bowling or mini golf, or a relaxed home gathering with one themed game or movie anchor."),
    ("how do i boil eggs", "To boil eggs, cover them with cold water, bring the pot just to a boil, turn the heat off, cover it, wait about 10 to 12 minutes, and then cool the eggs in cold water."),
    ("recommend a movie for tonight", "Tell me the mood you want tonight, like funny, tense, comforting, or thoughtful, and I can narrow the movie choice instead of guessing badly."),
    ("what is ram versus storage", "RAM is short-term working memory that programs use while they are running. Storage is the longer-term place where files and installed software live when the power is off."),
    ("explain recursion simply", "Recursion is when a function solves a problem by calling a smaller version of itself until it reaches a simple base case that stops the chain."),
    ("what is photosynthesis", "Photosynthesis is the process plants use to turn light, water, and carbon dioxide into chemical energy and oxygen."),
    ("what is photosynthesis in simple terms", "Photosynthesis is how plants use sunlight to turn water and carbon dioxide into stored energy and oxygen."),
    ("who wrote pride and prejudice", "Pride and Prejudice was written by Jane Austen."),
    ("what is the capital of japan", "The capital of Japan is Tokyo."),
    ("what does cpu stand for", "CPU stands for central processing unit."),
    ("what does cpu mean", "CPU means central processing unit."),
    ("tell me a fun fact about octopuses", "A fun fact about octopuses is that they have three hearts and blue blood."),
    ("should i buy or rent", "That depends on how long you expect to stay, how stable your income is, the local prices, and how much flexibility matters to you."),
    ("what is the capital of peru", "The capital of Peru is Lima."),
    ("what is the capital of france", "The capital of France is Paris."),
    ("what is the capital of canada", "The capital of Canada is Ottawa."),
    ("who painted the mona lisa", "The Mona Lisa was painted by Leonardo da Vinci."),
    ("what is gravity", "Gravity is the force that pulls masses toward each other, which is why objects fall toward Earth."),
    ("what is dna", "DNA is the molecule that stores genetic instructions in living things."),
    ("what is dna in simple words", "DNA is the molecule that stores the instructions cells use to build and run living things."),
    ("what is photosynthesis used for", "Photosynthesis lets plants capture energy from sunlight and store it as chemical energy."),
    ("what is an atom", "An atom is the basic unit of matter made of a nucleus with electrons around it."),
    ("what is the internet", "The internet is a global network of connected computers and services that exchange data."),
    ("what is machine learning", "Machine learning is a way of building systems that learn patterns from data instead of following only fixed hand-written rules."),
    ("what is a function in python", "In Python, a function is a reusable block of code that takes input, does work, and can return a result."),
    ("how do i apologize professionally", "A professional apology is best when it is short, clear, and accountable: explain the issue briefly, apologize plainly, and state the next corrective step."),
    ("how do i write a meeting follow-up", "A good meeting follow-up names the main decision, the agreed actions, the owners, and any deadline that matters."),
    ("how do i study for an exam", "A practical exam routine is to review the outline, do one focused block, test recall without notes, and then review the mistakes instead of rereading everything."),
    ("how do i manage stress at work", "Start by shrinking the problem. Pick the next concrete task, reduce the number of open tabs or threads, and get one visible thing finished before you re-evaluate the bigger list."),
    ("how do i quit doom scrolling at night", "Make the next action physical and small: put the phone out of reach, stand up, and switch to one deliberate alternative like a short walk, water, or a single focused task."),
    ("give me some birthday plans", "Three easy birthday directions are: a small dinner with one signature activity, a low-friction outing like bowling or mini golf, or a relaxed home gathering with one themed game or movie anchor."),
    ("help me politely decline an invite", "A polite decline is clear and kind: thank them, say you cannot make it, and if you want to preserve warmth add a brief good wish or an alternative time."),
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
    return text.replace("SBAN v24", "SBAN v25").replace("v24", "v25").replace("V24", "V25")


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
        if len(question) < 10 or len(question) > 90:
            continue
        if len(answer) < 3 or len(answer) > 90:
            continue
        if not question.startswith(("what ", "who ", "where ", "when ", "which ", "how ")):
            continue
        if any(token in question for token in ("according to", "in what year", "how many ", "what did the term", "what was the name of")):
            continue
        if any(token in answer.lower() for token in ("http", "www.", "[", "]")):
            continue
        seen.add(question)
        pairs.append((question, answer))
        if len(pairs) >= limit:
            break
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
    parser = argparse.ArgumentParser(description="Build the expanded SBAN v25 open-chat seed.")
    parser.add_argument("--output", type=Path, default=OUTPUT_PATH)
    parser.add_argument("--squad-limit", type=int, default=160)
    parser.add_argument("--no-datasets", action="store_true")
    args = parser.parse_args()

    base_pairs = [(upgrade_release_text(user), upgrade_release_text(assistant)) for user, assistant in parse_seed_text(BASE_SEED_PATH.read_text(encoding="utf-8"))]
    all_pairs = list(base_pairs)
    all_pairs.extend(EXTRA_PAIRS)
    if not args.no_datasets:
        try:
            all_pairs.extend(load_squad_pairs(args.squad_limit))
        except Exception as exc:  # pragma: no cover - offline fallback
            print(f"warning=squad_load_failed detail={exc}")

    final_pairs = dedupe_pairs(all_pairs)
    text = build_seed_text(final_pairs)
    args.output.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {args.output}")
    print(f"bytes={args.output.stat().st_size}")
    print(f"pairs={len(final_pairs)}")


if __name__ == "__main__":
    main()
