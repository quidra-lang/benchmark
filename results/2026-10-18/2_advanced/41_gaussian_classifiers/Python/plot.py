"""Output formatting, map geometry, and ASCII file writing."""

from math import floor
from pathlib import Path

from evaluation import reduced_fraction


def real(value):
    result = f"{value:.4f}"
    return "0.0000" if result == "-0.0000" else result


def reals(values):
    return " ".join(real(value) for value in values)


def fraction_text(value):
    if value is None:
        return "-"
    numerator, denominator = value
    return f"{numerator}/{denominator} {real(numerator / denominator)}"


def ratio_text(numerator, denominator):
    return fraction_text(reduced_fraction(numerator, denominator))


def frame(grid):
    border = "+" + "-" * len(grid[0]) + "+"
    return [border, *("|" + "".join(row) + "|" for row in grid), border]


def cell(value, low, high, size):
    return floor((value - low) / (high - low) * (size - 1) + 0.5)


def join_sections(sections):
    lines = []
    for section in sections:
        if lines:
            lines.append("")
        lines.extend(section)
    return lines


def write_lines(path, lines):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as destination:
        for line in lines:
            destination.write(line + "\n")
