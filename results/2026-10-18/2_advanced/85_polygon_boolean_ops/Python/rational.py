"""Exact rational coordinates, point arithmetic and prescribed notation."""

from fractions import Fraction


def divide(numerator, denominator):
    return Fraction(numerator) / Fraction(denominator)


def along(start, end, position):
    return (start[0] + position * (end[0] - start[0]),
            start[1] + position * (end[1] - start[1]))


def cross(origin, first, second):
    return ((first[0] - origin[0]) * (second[1] - origin[1])
            - (first[1] - origin[1]) * (second[0] - origin[0]))


def point_key(point):
    return point[1], point[0]


def fraction_text(value):
    value = Fraction(value)
    if value.denominator == 1:
        return str(value.numerator)
    return f"{value.numerator}/{value.denominator}"


def point_text(point):
    return f"({fraction_text(point[0])},{fraction_text(point[1])})"


def segment_text(first, second):
    return point_text(first) + "-" + point_text(second)


def real(value):
    return float(value.numerator) / float(value.denominator)
