"""Ordered error reductions and the metrics of one user's ranked list."""

from math import log2, sqrt


def sequential_sum(values):
    """Use ordinary additions, without Python's compensated float sum."""
    total = 0.0
    for value in values:
        total += value
    return total


def clip(prediction):
    if prediction < 1:
        return 1.0
    if prediction > 5:
        return 5.0
    return prediction


def rmse(errors):
    if not errors:
        return None
    return sqrt(sequential_sum(error * error for error in errors) / len(errors))


def mae(errors):
    if not errors:
        return None
    return sequential_sum(abs(error) for error in errors) / len(errors)


def training_rmse(training, predict):
    squared_error = 0.0
    for user, item, rating, timestamp in training:
        error = rating - predict(user, item)
        squared_error += error * error
    return sqrt(squared_error / len(training))


def rank_weight(rank):
    return 1 / log2(rank + 1)


def ranking_metrics(ranked, relevant, cutoff):
    hits = 0
    dcg = average_precision = reciprocal_rank = 0.0
    for rank, item in enumerate(ranked[:cutoff], 1):
        if item in relevant:
            hits += 1
            dcg += rank_weight(rank)
            average_precision += hits / rank
            if reciprocal_rank == 0:
                reciprocal_rank = 1 / rank
    ideal_hits = min(cutoff, len(relevant))
    ideal_dcg = sequential_sum(rank_weight(rank) for rank in range(1, ideal_hits + 1))
    return (
        hits,
        hits / len(relevant),
        dcg / ideal_dcg,
        average_precision / ideal_hits,
        reciprocal_rank,
    )
