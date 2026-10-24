from math import gcd


def orient(p, q, r):
    return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])


def d2(p, q):
    return (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2


def dot(o, p, q):
    return (p[0] - o[0]) * (q[0] - o[0]) + (p[1] - o[1]) * (q[1] - o[1])


def incircle(a, b, c, d):
    ax, ay = a[0] - d[0], a[1] - d[1]
    bx, by = b[0] - d[0], b[1] - d[1]
    cx, cy = c[0] - d[0], c[1] - d[1]
    aa, bb, cc = ax * ax + ay * ay, bx * bx + by * by, cx * cx + cy * cy
    return ax * (by * cc - bb * cy) - ay * (bx * cc - bb * cx) + aa * (bx * cy - by * cx)


def circumcenter(a, b, c):
    bx, by = b[0] - a[0], b[1] - a[1]
    cx, cy = c[0] - a[0], c[1] - a[1]
    bb, cc = bx * bx + by * by, cx * cx + cy * cy
    denominator = 2 * (bx * cy - by * cx)
    x = a[0] * denominator + cy * bb - by * cc
    y = a[1] * denominator + bx * cc - cx * bb
    return x, y, denominator


def fraction(n, d):
    common = gcd(n, d)
    n, d = n // common, d // common
    return str(n) if d == 1 else f"{n}/{d}"


def reduce_direction(dx, dy):
    common = gcd(abs(dx), abs(dy))
    return dx // common, dy // common
