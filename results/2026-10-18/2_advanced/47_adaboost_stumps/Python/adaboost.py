"""Discrete AdaBoost and SAMME, including their stopping rules."""

from collections import namedtuple
from math import exp, log

from stumps import SearchSpace, Stump, discrete_search, multiclass_search, ordered_sum


Round = namedtuple(
    "Round", "stump weights error alpha polarity z bound loss",
    defaults=((), None, None, None, None, None, None),
)
Model = namedtuple("Model", "rounds stop cuts", defaults=(None,))


def train_discrete(rows, max_rounds, weights=None, shrinkage=1.0, space=None):
    if space is None:
        space = SearchSpace(rows)
    labels = [row.label for row in rows]
    weights = [1 / len(rows)] * len(rows) if weights is None else list(weights)
    rounds = []
    bound = 1.0
    stop = "completed"
    for _ in range(max_rounds):
        error, feature, threshold, polarity = discrete_search(space, labels, weights)
        if error >= 0.5:
            stop = "weak"
            break
        alpha = 1.0 if error <= 1e-10 else shrinkage * (0.5 * log((1 - error) / error))
        stump = Stump(feature, (threshold,), (-polarity * alpha, polarity * alpha))
        before = tuple(weights)
        updated = []
        for row, weight in zip(rows, weights):
            decision = polarity if row.values[feature] > threshold else -polarity
            factor = exp(-alpha) if decision == row.label else exp(alpha)
            updated.append(weight * factor if weight else 0.0)
        normalizer = ordered_sum(updated)
        weights = [weight / normalizer for weight in updated]
        bound *= normalizer
        rounds.append(Round(
            stump, before, error=error, alpha=alpha, polarity=polarity,
            z=normalizer, bound=bound,
        ))
        if error <= 1e-10:
            stop = "perfect"
            break
    return Model(rounds, stop)


def train_samme(rows, max_rounds, classes):
    space = SearchSpace(rows)
    labels = [row.label for row in rows]
    weights = [1 / len(rows)] * len(rows)
    rounds = []
    stop = "completed"
    for _ in range(max_rounds):
        stump, error = multiclass_search(space, labels, weights, classes)
        if error >= (classes - 1) / classes:
            stop = "weak"
            break
        alpha = 1.0 if error <= 1e-10 else log((1 - error) / error) + log(classes - 1)
        updated = [
            weight * exp(alpha) if stump(row.values) != row.label else weight
            for row, weight in zip(rows, weights)
        ]
        normalizer = ordered_sum(updated)
        weights = [weight / normalizer for weight in updated]
        rounds.append(Round(stump, error=error, alpha=alpha))
        if error <= 1e-10:
            stop = "perfect"
            break
    return Model(rounds, stop)
