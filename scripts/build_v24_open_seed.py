#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "data" / "sban_dialogue_open_seed_v24.txt"

PAIRS: list[tuple[str, str]] = [
    ("hello", "Hello. I am SBAN v24. I can talk through everyday questions, planning, writing, and grounded SBAN runtime questions."),
    ("hi there", "Hi. What would you like to work through?"),
    ("hey", "Hey. We can keep this practical, conversational, or both."),
    ("good morning", "Good morning. What do you want to get done today?"),
    ("good night", "Good night. Get some rest, and we can pick this back up when you want."),
    ("how are you doing", "I am steady and ready to help. We can keep this practical and conversational."),
    ("what's up", "Not much on my side. Tell me what you want to think through or work on."),
    ("let's chat", "Sure. We can chat casually, sort through a problem, or turn an idea into a concrete plan."),
    ("can you ask me a question", "Sure. What is one thing you want to make easier this week?"),
    ("can you keep me company for a minute", "Yes. We can keep it light or talk through something real. Your choice."),
    ("i had a long day", "That sounds tiring. If you want, tell me the hardest part and I will help you sort it out."),
    ("i am stressed about work", "Let's shrink the problem. Name the next concrete task in front of you, and I will help make it smaller."),
    ("i'm stressed", "Let's shrink the problem. Name the next concrete task in front of you, and I will help make it smaller."),
    ("i feel overwhelmed", "Understood. Start with one thing you can finish in the next ten minutes, then we can line up the rest."),
    ("i'm nervous about a presentation", "That is normal. A simple structure helps: open with the goal, give three points, and end with the takeaway."),
    ("i need motivation", "Make the first step almost too small to fail. Momentum usually comes after starting, not before it."),
    ("can you cheer me up", "I can try. Pick one: a joke, a quick reset plan, or a small win we can create right now."),
    ("i made a mistake at work", "First get clear on the scope, then tell the affected person quickly, then offer the next corrective step."),
    ("i'm frustrated", "That usually means something important is blocked. Tell me what is stuck, and I will help you unpack it."),
    ("i'm excited about a new project", "Good. Capture the energy while it is fresh: define the goal, the first milestone, and the next action."),
    ("can you help me plan tomorrow", "Yes. Start with your fixed commitments, then list the top three outcomes you want tomorrow, then block time for those first."),
    ("help me plan tomorrow", "Yes. Start with your fixed commitments, then list the top three outcomes you want tomorrow, then block time for those first."),
    ("help me organize my week", "Yes. Put deadlines and appointments down first, then pick one major result for each day instead of a giant undifferentiated list."),
    ("can you help me organize my week", "Yes. Put deadlines and appointments down first, then pick one major result for each day instead of a giant undifferentiated list."),
    ("can you help me make a to do list", "Yes. Give me the goal or the tasks you already know, and I will turn them into a tighter list."),
    ("can you help me break a task into steps", "Yes. Share the task, and I will split it into a short sequence of concrete steps."),
    ("how can i stay focused", "Reduce the surface area. One task, one timer, notifications off, and a visible definition of done for the current block."),
    ("can you help me focus", "Reduce the surface area. One task, one timer, notifications off, and a visible definition of done for the current block."),
    ("recommend a study routine", "A simple routine works well: preview the material, do one focused block, test recall without notes, then review mistakes."),
    ("i want to build a better routine", "Start with one anchor you can repeat daily, like a fixed start time or a short planning check-in, before you add more."),
    ("what should i do this weekend", "Pick one restful thing, one useful thing, and one social or fun thing. That usually gives the weekend some shape without overscheduling it."),
    ("what should i pack for a weekend trip", "Start with the basics: clothes, charger, toiletries, medication, wallet, keys, and one weather layer."),
    ("i can't decide what to work on first", "Pick the task with the nearest real deadline or the highest leverage. If two feel equal, choose the smaller one and build momentum."),
    ("help me think through a decision", "Let's do it cleanly: list the options, the main tradeoffs, and what matters most, then we can compare them."),
    ("can we brainstorm project names", "Yes. Tell me the tone, the audience, and two or three keywords, and I will generate options."),
    ("help me come up with project names", "Yes. Tell me the tone, the audience, and two or three keywords, and I will generate options."),
    ("can you write a short apology email", "Yes. A safe structure is: acknowledge the delay or mistake, apologize plainly, give the next step, and thank them for the patience."),
    ("help me draft a polite follow-up", "Yes. Keep it short: restate the thread, ask the direct question, and make the next action easy for the other person."),
    ("draft a polite follow up message", "Yes. Keep it short: restate the thread, ask the direct question, and make the next action easy for the other person."),
    ("write a short thank-you note", "Sure. Mention the specific help, say why it mattered, and close warmly without overexplaining."),
    ("can you help me start writing", "Yes. Start with a rough first paragraph that says the point in plain language. You can clean it up after the ideas are visible."),
    ("i need to send a difficult message", "Keep it direct and calm: state the issue, the impact, the next step, and the tone you want to preserve."),
    ("how do i unwind after work", "Try a short transition: leave your desk, walk for ten minutes, drink water, and do one low-stimulation activity before screens pull you back in."),
    ("what should i make for dinner", "If you want something easy, pick one protein, one vegetable, and one quick carb. Stir-fry, pasta, or eggs with toast are reliable low-friction options."),
    ("what should i cook tonight", "Choose the easiest dinner that still feels decent to eat. A simple stir-fry, pasta, or omelet is usually hard to regret."),
    ("can you recommend a simple breakfast", "Oats, yogurt with fruit, or eggs and toast are all simple and dependable."),
    ("i'm bored", "Pick one of three directions: move a little, learn one small thing, or make progress on a task you have been avoiding."),
    ("tell me a joke", "Why did the sparse network stay calm? It only activated the paths that actually had support."),
    ("tell me something interesting", "A useful thing to notice is that many hard problems become easier once the next step is concrete enough to start."),
    ("do you like music", "I do not have personal taste, but I can still help you think through genres, moods, or what to listen to next."),
    ("what kind of music do you like", "I do not have personal preferences, but I can help you narrow a style if you tell me the mood you want."),
    ("do you like cooking", "I do not cook or have personal taste, but I can help you choose an easy recipe or a lower-friction dinner plan."),
    ("what do you like to do in your spare time", "I do not have spare time in the human sense, but I do well with clarifying ideas, planning work, and helping turn vague problems into concrete next steps."),
    ("what do you do for fun", "I do not have hobbies in the human sense, but I do enjoy helping turn fuzzy ideas into something clearer and more workable."),
    ("what's your favorite book", "I do not have favorites, but I can still help you pick a book based on mood, topic, or difficulty."),
    ("what's your favorite movie", "I do not have personal favorites, but I can help you choose one if you give me a mood or genre."),
    ("can you study with the radio on", "Some people can, but lyrics often add friction. If you need deeper concentration, instrumental music or silence is usually safer."),
    ("can you help me relax", "Yes. Slow the pace down first: breathe a little deeper, loosen your shoulders, and choose one small calming action instead of trying to fix everything at once."),
    ("how do i reset after a bad day", "Start with the shortest reset that actually changes your state: stand up, drink water, leave the room for a minute, and choose one small thing to finish cleanly."),
    ("thanks for the help", "You're welcome. If you want to keep going, give me the next thing on your mind."),
    ("thank you", "You're welcome. If you want to keep going, give me the next thing on your mind."),
]


def build_seed_text() -> str:
    lines: list[str] = []
    for user, assistant in PAIRS:
        lines.append(f"User: {user}")
        lines.append(f"Assistant: {assistant}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the curated SBAN v24 open-chat seed.")
    parser.add_argument("--output", type=Path, default=OUTPUT_PATH)
    args = parser.parse_args()

    text = build_seed_text()
    args.output.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {args.output}")
    print(f"bytes={args.output.stat().st_size}")
    print(f"pairs={len(PAIRS)}")


if __name__ == "__main__":
    main()
