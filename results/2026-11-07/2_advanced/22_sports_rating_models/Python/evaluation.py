from fractions import Fraction
from math import exp, log


HALF = Fraction(1, 2)


def sigma(value):
    return 1 / (1 + exp(-value))


def fit_link(features, results, iterations):
    alpha = 0.0
    beta = 0.0
    for _ in range(iterations):
        g0 = g1 = h00 = h01 = h11 = 0.0
        for z, y in zip(features, results):
            p = sigma(alpha + beta * z)
            w = p * (1 - p)
            g0 += y - p
            g1 += (y - p) * z
            h00 += w
            h01 += w * z
            h11 += w * z * z
        det = h00 * h11 - h01 * h01
        alpha, beta = (
            alpha + (h11 * g0 - h01 * g1) / det,
            beta + (h00 * g1 - h01 * g0) / det,
        )
    return alpha, beta


def log_loss(p, y):
    if y == 1:
        return -log(p)
    if y == 0:
        return -log(1 - p)
    return -(log(p) / 2 + log(1 - p) / 2)


def brier_score(p, y):
    return (p - y) * (p - y)


def correctness(p, y):
    if y == HALF:
        return HALF
    if (p > 0.5 and y == 1) or (p < 0.5 and y == 0):
        return Fraction(1)
    return Fraction(0)


def average_ranks(values):
    ranks = []
    for value in values:
        greater = sum(1 for other in values if other > value)
        equal = sum(1 for other in values if other == value)
        ranks.append(greater + Fraction(equal + 1, 2))
    return ranks


def direction(first, second):
    if first > second:
        return 1
    if first < second:
        return -1
    return 0


def kendall_tau(first, second):
    count = len(first)
    concordant = 0
    discordant = 0
    for t in range(count):
        for u in range(t + 1, count):
            agreement = direction(first[t], first[u]) * direction(second[t], second[u])
            if agreement > 0:
                concordant += 1
            elif agreement < 0:
                discordant += 1
    return Fraction(concordant - discordant, count * (count - 1) // 2)


def spearman_rho(first, second):
    count = len(first)
    first_ranks = average_ranks(first)
    second_ranks = average_ranks(second)
    squares = Fraction(0)
    for first_rank, second_rank in zip(first_ranks, second_ranks):
        difference = first_rank - second_rank
        squares += difference * difference
    return 1 - 6 * squares / (count * (count * count - 1))
