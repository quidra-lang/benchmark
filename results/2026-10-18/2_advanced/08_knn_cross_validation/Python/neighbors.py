from math import sqrt


WEIGHT_OFFSET = 0.000000001


class Tally:
    def __init__(self, label):
        self.label = label
        self.count = 0
        self.distance_sum = 0.0
        self.weight_sum = 0.0


class Vote:
    def __init__(self, label, share, runner_up, runner_share):
        self.label = label
        self.share = share
        self.runner_up = runner_up
        self.runner_share = runner_share


def squared_euclidean(a, b):
    total = 0.0
    for x, y in zip(a, b):
        difference = x - y
        total += difference * difference
    return total


def manhattan(a, b):
    total = 0.0
    for x, y in zip(a, b):
        total += abs(x - y)
    return total


def chebyshev(a, b):
    largest = 0.0
    for x, y in zip(a, b):
        difference = abs(x - y)
        if difference > largest:
            largest = difference
    return largest


def cosine(a, b):
    dot = 0.0
    squares_a = 0.0
    squares_b = 0.0
    for x, y in zip(a, b):
        dot += x * y
        squares_a += x * x
        squares_b += y * y
    norm_a = sqrt(squares_a)
    norm_b = sqrt(squares_b)
    if norm_a == 0 or norm_b == 0:
        return 1.0
    return 1 - dot / (norm_a * norm_b)


METRICS = {
    "squared_euclidean": squared_euclidean,
    "manhattan": manhattan,
    "chebyshev": chebyshev,
    "cosine": cosine,
}


def distance(a, b, metric):
    return METRICS[metric](a, b)


def sort_neighbors(neighbors):
    return sorted(neighbors, key=lambda neighbor: (neighbor[0], neighbor[1].ident))


def neighbor_order(query, references, metric):
    measure = METRICS[metric]
    return sort_neighbors([(measure(query, vector), row) for vector, row in references])


def vote(nearest, weighting):
    tallies = {}
    weight_total = 0.0
    for gap, row in nearest:
        weight = 1 / (gap + WEIGHT_OFFSET)
        if row.label not in tallies:
            tallies[row.label] = Tally(row.label)
        tally = tallies[row.label]
        tally.count += 1
        tally.distance_sum += gap
        tally.weight_sum += weight
        weight_total += weight
    if weighting == "uniform":
        ranked = sorted(
            tallies.values(),
            key=lambda tally: (-tally.count, tally.distance_sum, tally.label),
        )
        shares = [tally.count / len(nearest) for tally in ranked]
    else:
        ranked = sorted(
            tallies.values(),
            key=lambda tally: (-tally.weight_sum, tally.distance_sum, tally.label),
        )
        shares = [tally.weight_sum / weight_total for tally in ranked]
    if len(ranked) == 1:
        return Vote(ranked[0].label, shares[0], None, 0.0)
    return Vote(ranked[0].label, shares[0], ranked[1].label, shares[1])


def estimate(nearest, weighting):
    if weighting == "uniform":
        total = 0.0
        for _, row in nearest:
            total += row.target
        return total / len(nearest)
    weighted = 0.0
    weights = 0.0
    for gap, row in nearest:
        weight = 1 / (gap + WEIGHT_OFFSET)
        weighted += weight * row.target
        weights += weight
    return weighted / weights
