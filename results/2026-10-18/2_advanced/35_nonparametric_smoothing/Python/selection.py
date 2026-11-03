"""Ordered arithmetic and parameter-score selection for smoothing methods."""


def ordered_sum(values):
    total = 0.0
    for value in values:
        total += value
    return total


def cross_validation_score(observed, predicted):
    if any(value is None for value in predicted):
        return None
    return ordered_sum((y - estimate) * (y - estimate)
                       for y, estimate in zip(observed, predicted)) / len(observed)


def generalized_score(observed, fitted, edf):
    residual_square = ordered_sum((y - estimate) * (y - estimate)
                                  for y, estimate in zip(observed, fitted))
    factor = 1 - edf / len(observed)
    return residual_square / len(observed) / (factor * factor)


def choose_candidate(candidates):
    eligible = [index for index, item in enumerate(candidates)
                if item["score"] is not None]
    return min(eligible, key=lambda index: (candidates[index]["score"], index))
