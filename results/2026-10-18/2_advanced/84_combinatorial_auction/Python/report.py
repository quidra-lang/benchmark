"""Exact fraction and item-order bundle notation, and ASCII report writing."""

from fractions import Fraction
from pathlib import Path


def fraction(value):
    return str(Fraction(value))


def bundle(items, order):
    return "+".join(item for item in order if item in items) or "-"


def write_reports(reports):
    Path("output").mkdir(exist_ok=True)
    for name, lines in reports:
        with open("output/" + name, "w", encoding="ascii", newline="\n") as destination:
            for line in lines:
                destination.write(line + "\n")
