"""Three-dimensional vectors whose components are fixed-point integers."""

from fixed_point import S, isqrt


def add(u, v):
    return tuple(a + b for a, b in zip(u, v))


def sub(u, v):
    return tuple(a - b for a, b in zip(u, v))


def neg(u):
    return tuple(-a for a in u)


def dot(u, v):
    return sum(a * b for a, b in zip(u, v)) // S


def sc(u, k):
    return tuple(a * k // S for a in u)


def length(u):
    return isqrt(sum(a * a for a in u))


def norm(u):
    magnitude = length(u)
    return tuple(a * S // magnitude for a in u)
