"""Deterministic number and frequency lists and output paragraph layout."""

from collections import Counter
from pathlib import Path


def number_list(values):
    values = list(values)
    return ",".join(map(str, values)) if values else "-"


def frequency(values):
    counts = Counter(values)
    return ",".join(
        f"{key}:{counts[key]}" for key in sorted(counts)
    ) if counts else "-"


def record(**items):
    return " ".join(f"{name}={value}" for name, value in items.items())


def heading(job):
    return f"JOB {job['number']} {job['text']}"


def joining_paragraphs(paragraphs):
    return "\n\n".join("\n".join(lines) for lines in paragraphs)


def save_lines(filename, lines):
    target = Path("output") / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    text = "\n".join(lines)
    if lines:
        text += "\n"
    target.write_text(text, encoding="ascii")


def save_paragraphs(filename, paragraphs):
    text = joining_paragraphs(paragraphs)
    target = Path("output") / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text + "\n" if text else "", encoding="ascii")


def queen_board(columns):
    return [
        "." * (column - 1) + "Q" + "." * (len(columns) - column)
        for column in columns
    ]
