"""Integer arithmetic for a scale of 4096, always rounding downward."""

from math import isqrt


S = 4096


def floor_div(a, b):
    return a // b


def mul(a, b):
    return a * b // S
