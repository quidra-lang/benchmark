"""Distances, OSPA, continuity and the required four-decimal notation."""

from math import sqrt

from association import minimum_matching
from matrix import total


def squared_distance(a, b):
    dx, dy = a[0] - b[0], a[1] - b[1]
    return dx * dx + dy * dy


def distance(a, b):
    return sqrt(squared_distance(a, b))


def ospa(first, second, cutoff):
    if not first and not second:
        return 0.0
    if not first or not second:
        return cutoff
    smaller, larger = (first, second) if len(first) <= len(second) else (second, first)
    costs = []
    for point in smaller:
        row = []
        for other in larger:
            clipped = min(cutoff, distance(point, other))
            row.append(clipped * clipped)
        costs.append(row)
    matches = minimum_matching(costs)
    cost = total(costs[row][column] for row, column in matches)
    return sqrt((cost + cutoff * cutoff * (len(larger) - len(smaller))) / len(larger))


def continuity(labels):
    covered = groups = swaps = 0
    previous_label = None
    previous_covered = False
    delay = None
    for offset, label in enumerate(labels):
        if label is None:
            previous_covered = False
            continue
        covered += 1
        if delay is None:
            delay = offset
        if not previous_covered:
            groups += 1
        if previous_label is not None and label != previous_label:
            swaps += 1
        previous_label = label
        previous_covered = True
    return {"covered": covered, "breaks": max(0, groups - 1), "swaps": swaps, "delay": delay}


def real(value):
    return "-" if value is None else format(value, "z.4f")
