"""Real AdaBoost, Gentle AdaBoost, and LogitBoost training."""

from math import exp, log

from adaboost import Model, Round
from stumps import (
    SearchSpace, Stump, ordered_sum, real_geometry, real_search, regression_search,
)


def update_weights(rows, weights, stump):
    updated = [
        weight * exp(-row.label * stump(row.values))
        for row, weight in zip(rows, weights)
    ]
    normalizer = ordered_sum(updated)
    return [weight / normalizer for weight in updated]


def train_real(rows, max_rounds, bins, smoothing, convergence):
    space = SearchSpace(rows)
    cuts, assignments = real_geometry(space, bins)
    labels = [row.label for row in rows]
    weights = [1 / len(rows)] * len(rows)
    rounds = []
    bound = 1.0
    stop = "completed"
    for _ in range(max_rounds):
        normalizer, feature, positives, negatives = real_search(
            assignments, labels, weights, bins
        )
        if normalizer >= 1 - convergence:
            stop = "converged"
            break
        values = [
            0.5 * log((positive + smoothing) / (negative + smoothing))
            for positive, negative in zip(positives, negatives)
        ]
        stump = Stump(feature, cuts[feature], values)
        bound *= normalizer
        rounds.append(Round(stump, tuple(weights), z=normalizer, bound=bound))
        weights = update_weights(rows, weights, stump)
    return Model(rounds, stop, cuts)


def train_gentle(rows, max_rounds):
    space = SearchSpace(rows)
    targets = [row.label for row in rows]
    weights = [1 / len(rows)] * len(rows)
    rounds = []
    for _ in range(max_rounds):
        stump, error = regression_search(space, targets, weights)
        rounds.append(Round(stump, tuple(weights), error=error))
        weights = update_weights(rows, weights, stump)
    return Model(rounds, "completed")


def train_logit(rows, max_rounds, clip):
    space = SearchSpace(rows)
    targets = [1 if row.label == 1 else 0 for row in rows]
    scores = [0.0] * len(rows)
    probabilities = [0.5] * len(rows)
    rounds = []
    for _ in range(max_rounds):
        working_weights = []
        responses = []
        for target, probability in zip(targets, probabilities):
            weight = probability * (1 - probability)
            response = (target - probability) / weight
            if response > clip:
                response = clip
            elif response < -clip:
                response = -clip
            working_weights.append(weight)
            responses.append(response)
        normalizer = ordered_sum(working_weights)
        weights = [weight / normalizer for weight in working_weights]
        fitted, error = regression_search(space, responses, weights)
        stump = Stump(
            fitted.feature, fitted.thresholds,
            (fitted.values[0] / 2, fitted.values[1] / 2),
        )
        for index, row in enumerate(rows):
            scores[index] += stump(row.values)
            probabilities[index] = 1 / (1 + exp(-2 * scores[index]))
        loss = ordered_sum(
            log(1 + exp(-2 * row.label * score))
            for row, score in zip(rows, scores)
        ) / len(rows)
        rounds.append(Round(stump, tuple(weights), error=error, loss=loss))
    return Model(rounds, "completed")
