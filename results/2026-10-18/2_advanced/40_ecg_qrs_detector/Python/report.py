"""Exact integer rounding, decimal notation, reduced fractions and ratios."""

import math


def rdiv(numerator, denominator):
    """Round toward +infinity for exact halves, including negative values."""
    return (2 * numerator + denominator) // (2 * denominator)


def root(numerator, denominator):
    return (math.isqrt(40000 * numerator // denominator) + 1) // 2


def two(value):
    sign = "-" if value < 0 else ""
    magnitude = abs(value)
    return f"{sign}{magnitude // 100}.{magnitude % 100:02d}"


def four(value):
    return f"{value // 10000}.{value % 10000:04d}"


def fraction(numerator, denominator):
    divisor = math.gcd(numerator, denominator)
    return f"{numerator // divisor}/{denominator // divisor}"


def ratio(numerator, denominator):
    if denominator == 0:
        return f"{numerator}/0 none"
    percent = two(rdiv(10000 * numerator, denominator))
    return (
        f"{numerator}/{denominator} "
        f"reduced={fraction(numerator, denominator)} percent={percent}"
    )


def maybe_two(value):
    return "none" if value is None else two(value)


def scale(value, top, bottom, rows):
    return rdiv((top - value) * (rows - 1), top - bottom) if top > bottom else 0
