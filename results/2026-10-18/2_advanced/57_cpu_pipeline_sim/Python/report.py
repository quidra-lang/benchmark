"""Integer-only ratio formatting and fixed-width pipeline row serialization."""

from math import gcd
from pathlib import Path


def decimal(numerator, denominator):
    scaled = (2 * numerator * 10000 + denominator) // (2 * denominator)
    return f"{scaled // 10000}.{scaled % 10000:04d}"


def percentage(numerator, denominator):
    if denominator == 0:
        return "-"
    scaled = (2 * numerator * 10000 + denominator) // (2 * denominator)
    return f"{scaled // 100}.{scaled % 100:02d}"


def reduced_fraction(numerator, denominator):
    divisor = gcd(numerator, denominator)
    return f"{numerator // divisor}/{denominator // divisor}"


def hexadecimal(value):
    return f"{value:08x}"


def register(value):
    return "-" if value is None else f"r{value}"


def cycle_heading(start, end):
    return "cycle" + " " * 18 + "".join(str(cycle % 10) for cycle in range(start, end + 1))


def diagram_row(number, pc, instruction_class, characters, annotation=""):
    identifier = "     -" if number is None else f"{number:6d}"
    return f"{identifier} {hexadecimal(pc)} {instruction_class:<6} {characters}{annotation}"


def join_parts(parts):
    lines = []
    for part in parts:
        if lines:
            lines.append("")
        lines.extend(part)
    return lines


def write_lines(name, lines):
    target = Path("output") / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines) + "\n", encoding="ascii")
