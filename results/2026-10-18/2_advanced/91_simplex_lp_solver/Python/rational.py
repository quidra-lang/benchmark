"""Exact fractions, input numerals, and the specified decimal display."""

import re
from fractions import Fraction


def read_number(word, signed=False):
    pattern = r"-?[0-9]+(?:\.[0-9]+|/[0-9]+)?" if signed else r"[0-9]+(?:\.[0-9]+|/[0-9]+)?"
    if re.fullmatch(pattern, word) is None:
        return None
    if "/" in word and int(word.split("/")[1]) == 0:
        return None
    return Fraction(word)


def floor(value):
    return value.numerator // value.denominator


def ceil(value):
    return -((-value.numerator) // value.denominator)


def approximate(value):
    scaled = floor(abs(value) * 1000000 + Fraction(1, 2))
    sign = "-" if value < 0 and scaled else ""
    return f"{sign}{scaled // 1000000}.{scaled % 1000000:06d}"


def endpoint(value, lower):
    return ("-inf" if lower else "inf") if value is None else str(value)
