"""Exact text formatting and ASCII, LF-terminated output files."""

from math import gcd
from pathlib import Path


def fraction(numerator, denominator):
    divisor = gcd(numerator, denominator)
    return f"{numerator // divisor}/{denominator // divisor}"


def ids(values):
    text = " ".join(map(str, values))
    return text if text else "-"


def distances(values):
    text = " ".join(f"{identifier}:{distance}" for identifier, distance in values)
    return text if text else "-"


def write_lines(path, lines):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as destination:
        for line in lines:
            destination.write(line)
            destination.write("\n")
