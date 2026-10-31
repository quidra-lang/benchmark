"""Accumulator-tree and pairwise crossing counts."""


def positions(orders):
    return {vertex: position for layer in orders for position, vertex in enumerate(layer)}


def accumulator(segments, position, lower_size):
    capacity = 1
    while capacity < lower_size:
        capacity *= 2
    tree = [0] * (2 * capacity - 1)
    count = 0
    pairs = sorted((position[p], position[q]) for p, q, edge in segments)
    for _, lower in pairs:
        index = lower + capacity - 1
        tree[index] += 1
        while index > 0:
            if index % 2 == 1:
                count += tree[index + 1]
            index = (index - 1) // 2
            tree[index] += 1
    return count


def brute_force(segments, position):
    count = 0
    for index, (p1, q1, _) in enumerate(segments):
        for p2, q2, _ in segments[index + 1:]:
            if (position[p1] - position[p2]) * (position[q1] - position[q2]) < 0:
                count += 1
    return count


def gap_counts(gaps, orders):
    position = positions(orders)
    return [accumulator(segments, position, len(orders[index + 1]))
            for index, segments in enumerate(gaps)]


def total(gaps, orders):
    return sum(gap_counts(gaps, orders))


def local_cost(gaps, orders, layer):
    position = positions(orders)
    count = 0
    for gap in (layer - 1, layer):
        if 0 <= gap < len(gaps):
            count += accumulator(gaps[gap], position, len(orders[gap + 1]))
    return count


def adjacent_cost(first, second, upper, lower, position):
    count = 0
    for neighbors in (upper, lower):
        for a in neighbors[first]:
            for b in neighbors[second]:
                count += position[a] > position[b]
    return count
