"""Render exact named values, number lists, frequency lists, and paragraphs."""

from collections import Counter
from pathlib import Path


def named(**items):
    return " ".join(f"{key}={value}" for key, value in items.items())


def number_list(values):
    values = list(values)
    return ",".join(map(str, values)) if values else "-"


def frequency(values):
    counts = Counter(values)
    return ",".join(f"{key}:{counts[key]}" for key in sorted(counts)) if counts else "-"


def heading(job):
    return f"JOB {job['number']} {job['text']}"


def save_lines(filename, lines):
    target = Path("output") / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines) + "\n" if lines else "", encoding="ascii")


def save_paragraphs(filename, paragraphs):
    content = "\n\n".join("\n".join(lines) for lines in paragraphs)
    target = Path("output") / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content + "\n" if content else "", encoding="ascii")


def queens_board(columns):
    n = len(columns)
    return ["." * (column - 1) + "Q" + "." * (n - column)
            for column in columns]
