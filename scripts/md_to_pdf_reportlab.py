#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import Paragraph, Preformatted, SimpleDocTemplate, Spacer


def apply_inline_markup(text: str) -> str:
    escaped = html.escape(text)
    escaped = re.sub(r"`([^`]+)`", r"<font name='Courier'>\1</font>", escaped)
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", escaped)
    escaped = re.sub(r"\*([^*]+)\*", r"<i>\1</i>", escaped)
    return escaped


def build_story(markdown_text: str):
    styles = getSampleStyleSheet()
    styles.add(
        ParagraphStyle(
            name="BodySBAN",
            parent=styles["BodyText"],
            fontName="Helvetica",
            fontSize=10.5,
            leading=14,
            alignment=TA_LEFT,
            spaceAfter=6,
        )
    )
    styles.add(
        ParagraphStyle(
            name="BulletSBAN",
            parent=styles["BodySBAN"],
            leftIndent=14,
            firstLineIndent=-10,
        )
    )
    styles.add(
        ParagraphStyle(
            name="CodeSBAN",
            parent=styles["Code"],
            fontName="Courier",
            fontSize=8.5,
            leading=10,
            backColor=colors.whitesmoke,
            borderColor=colors.lightgrey,
            borderWidth=0.5,
            borderPadding=6,
            borderRadius=2,
            spaceAfter=8,
        )
    )

    story = []
    in_code = False
    code_lines: list[str] = []

    for raw_line in markdown_text.splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()

        if stripped.startswith("```"):
            if in_code:
                story.append(Preformatted("\n".join(code_lines), styles["CodeSBAN"]))
                code_lines = []
                in_code = False
            else:
                in_code = True
            continue

        if in_code:
            code_lines.append(line)
            continue

        if not stripped:
            story.append(Spacer(1, 0.10 * inch))
            continue

        if stripped.startswith("# "):
            story.append(Paragraph(apply_inline_markup(stripped[2:]), styles["Title"]))
            continue
        if stripped.startswith("## "):
            story.append(Paragraph(apply_inline_markup(stripped[3:]), styles["Heading2"]))
            continue
        if stripped.startswith("### "):
            story.append(Paragraph(apply_inline_markup(stripped[4:]), styles["Heading3"]))
            continue
        if stripped.startswith("- "):
            story.append(Paragraph(f"&#8226; {apply_inline_markup(stripped[2:])}", styles["BulletSBAN"]))
            continue
        if re.match(r"^\d+\.\s", stripped):
            story.append(Paragraph(apply_inline_markup(stripped), styles["BulletSBAN"]))
            continue

        story.append(Paragraph(apply_inline_markup(stripped), styles["BodySBAN"]))

    if code_lines:
        story.append(Preformatted("\n".join(code_lines), styles["CodeSBAN"]))

    return story


def render_markdown_to_pdf(input_path: Path, output_path: Path) -> None:
    story = build_story(input_path.read_text(encoding="utf-8"))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(output_path),
        pagesize=A4,
        leftMargin=0.75 * inch,
        rightMargin=0.75 * inch,
        topMargin=0.75 * inch,
        bottomMargin=0.75 * inch,
        title=input_path.stem,
    )
    doc.build(story)


def main() -> None:
    parser = argparse.ArgumentParser(description="Render lightweight Markdown to PDF with ReportLab.")
    parser.add_argument("input_path")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    render_markdown_to_pdf(Path(args.input_path), Path(args.output))


if __name__ == "__main__":
    main()
