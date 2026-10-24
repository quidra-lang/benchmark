import math

from matrix import (
    column, copy_matrix, deflate, dot, identity, max_difference, multiply, normalize, orient,
)


MAX_SWEEPS = 100
STOP_FACTOR = 1e-22
COUNT_FACTOR = 1e-16
POWER_ITERATIONS = 1000
AGREEMENT_TOLERANCE = 0.000001


class EigenSystem:
    def __init__(self, values, vectors, sweeps):
        self.values = values
        self.vectors = vectors
        self.sweeps = sweeps


class PowerComponent:
    def __init__(self, value, vector, agreement):
        self.value = value
        self.vector = vector
        self.agreement = agreement


def off_diagonal(a):
    total = 0.0
    for p in range(len(a) - 1):
        for q in range(p + 1, len(a)):
            total += a[p][q] * a[p][q]
    return total


def rotate(a, v, p, q):
    if a[p][q] == 0:
        return
    theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
    t = 1 / (abs(theta) + math.sqrt(theta * theta + 1))
    if theta < 0:
        t = -t
    c = 1 / math.sqrt(t * t + 1)
    s = t * c
    for r in range(len(a)):
        if r != p and r != q:
            arp, arq = a[r][p], a[r][q]
            a[r][p] = a[p][r] = c * arp - s * arq
            a[r][q] = a[q][r] = s * arp + c * arq
    apq = a[p][q]
    a[p][p] -= t * apq
    a[q][q] += t * apq
    a[p][q] = a[q][p] = 0.0
    for row in v:
        vrp, vrq = row[p], row[q]
        row[p] = c * vrp - s * vrq
        row[q] = s * vrp + c * vrq


def sweep(a, v):
    for p in range(len(a) - 1):
        for q in range(p + 1, len(a)):
            rotate(a, v, p, q)


def jacobi(matrix):
    a = copy_matrix(matrix)
    v = identity(len(matrix))
    initial = off_diagonal(a)
    sweeps = 0
    if initial > 0:
        for number in range(1, MAX_SWEEPS + 1):
            sweep(a, v)
            remaining = off_diagonal(a)
            if sweeps == 0 and remaining < COUNT_FACTOR * initial:
                sweeps = number
            if remaining < STOP_FACTOR * initial:
                break
    order = sorted(range(len(a)), key=lambda k: (-a[k][k], k))
    values = [a[k][k] for k in order]
    vectors = [orient(normalize(column(v, k))) for k in order]
    return EigenSystem(values, vectors, sweeps)


def power_iteration(matrix, references):
    b = copy_matrix(matrix)
    components = []
    for reference in references:
        opposite = [-value for value in reference]
        x = [1.0] * len(b)
        agreement = None
        for step in range(1, POWER_ITERATIONS + 1):
            x = normalize(multiply(b, x))
            difference = min(max_difference(x, reference), max_difference(x, opposite))
            if agreement is None and difference < AGREEMENT_TOLERANCE:
                agreement = step
        value = dot(x, multiply(b, x))
        vector = orient(normalize(x))
        deflate(b, value, vector)
        components.append(PowerComponent(value, vector, agreement))
    return components
