"""Ordered threshold geometry and deterministic weak-classifier searches."""

from bisect import bisect_left
from math import sqrt


def ordered_sum(values):
    total = 0.0
    for value in values:
        total += value
    return total


class Stump:
    def __init__(self, feature, thresholds, values):
        self.feature = feature
        self.thresholds = tuple(thresholds)
        self.values = tuple(values)

    def __call__(self, values):
        index = bisect_left(self.thresholds, values[self.feature])
        return self.values[index]


class SearchSpace:
    def __init__(self, rows):
        self.rows = rows
        self.orders = []
        self.groups = []
        self.thresholds = []
        for feature in range(len(rows[0].values)):
            order = sorted(range(len(rows)), key=lambda i: rows[i].values[feature])
            groups = []
            distinct = []
            for index in order:
                value = rows[index].values[feature]
                if not distinct or value != distinct[-1]:
                    distinct.append(value)
                    groups.append([])
                groups[-1].append(index)
            thresholds = [distinct[0] - 1]
            thresholds.extend(
                (left + right) / 2
                for left, right in zip(distinct, distinct[1:])
            )
            self.orders.append(order)
            self.groups.append(groups)
            self.thresholds.append(thresholds)


def left_cumulative(groups, values):
    total = 0.0
    yield total
    for group in groups[:-1]:
        for index in group:
            total += values[index]
        yield total


def choose(candidates):
    """Apply the tolerance to the global minimum, never to a running winner."""
    minimum = min(candidate[0] for candidate in candidates)
    return next(candidate for candidate in candidates if candidate[0] <= minimum + 1e-9)


def discrete_search(space, labels, weights):
    positives = [weight if label == 1 else 0.0 for label, weight in zip(labels, weights)]
    negatives = [weight if label == -1 else 0.0 for label, weight in zip(labels, weights)]
    positive_total = ordered_sum(positives)
    negative_total = ordered_sum(negatives)
    candidates = []
    for feature, thresholds in enumerate(space.thresholds):
        left_positive = left_cumulative(space.groups[feature], positives)
        left_negative = left_cumulative(space.groups[feature], negatives)
        for threshold, positive, negative in zip(thresholds, left_positive, left_negative):
            candidates.append((positive + (negative_total - negative), feature, threshold, 1))
            candidates.append((negative + (positive_total - positive), feature, threshold, -1))
    return choose(candidates)


def regression_search(space, targets, weights):
    total_weight = ordered_sum(weights)
    products = [weight * target for weight, target in zip(weights, targets)]
    total_target = ordered_sum(products)
    total_square = ordered_sum(
        weight * target * target for weight, target in zip(weights, targets)
    )
    candidates = []
    for feature, thresholds in enumerate(space.thresholds):
        left_weights = left_cumulative(space.groups[feature], weights)
        left_targets = left_cumulative(space.groups[feature], products)
        for position, (threshold, left_weight, left_target) in enumerate(
            zip(thresholds, left_weights, left_targets)
        ):
            right_weight = total_weight - left_weight
            right_target = total_target - left_target
            right_value = right_target / right_weight
            if position == 0:
                left_value = 0.0
                gain = right_target * right_target / right_weight
            else:
                left_value = left_target / left_weight
                gain = (
                    left_target * left_target / left_weight
                    + right_target * right_target / right_weight
                )
            candidates.append(
                (total_square - gain, feature, threshold, left_value, right_value)
            )
    error, feature, threshold, left, right = choose(candidates)
    return Stump(feature, (threshold,), (left, right)), error


def multiclass_search(space, labels, weights, classes):
    total_weight = ordered_sum(weights)
    totals = [
        ordered_sum(weight for label, weight in zip(labels, weights) if label == klass)
        for klass in range(1, classes + 1)
    ]
    candidates = []
    for feature, thresholds in enumerate(space.thresholds):
        left = [0.0] * classes
        for position, threshold in enumerate(thresholds):
            if position:
                for index in space.groups[feature][position - 1]:
                    left[labels[index] - 1] += weights[index]
            right = [total - weight for total, weight in zip(totals, left)]
            left_class = max(range(classes), key=left.__getitem__)
            right_class = max(range(classes), key=right.__getitem__)
            error = total_weight - (left[left_class] + right[right_class])
            candidates.append((error, feature, threshold, left_class + 1, right_class + 1))
    error, feature, threshold, left, right = choose(candidates)
    return Stump(feature, (threshold,), (left, right)), error


def real_geometry(space, bins):
    count = len(space.rows)
    cuts = []
    assignments = []
    for feature, order in enumerate(space.orders):
        values = [space.rows[index].values[feature] for index in order]
        feature_cuts = []
        for bin_number in range(1, bins):
            rank = bin_number * count // bins
            feature_cuts.append((values[rank - 1] + values[rank]) / 2)
        cuts.append(feature_cuts)
        assignments.append([
            bisect_left(feature_cuts, row.values[feature]) for row in space.rows
        ])
    return cuts, assignments


def real_search(assignments, labels, weights, bins):
    candidates = []
    for feature, memberships in enumerate(assignments):
        positives = [0.0] * bins
        negatives = [0.0] * bins
        for label, weight, membership in zip(labels, weights, memberships):
            destination = positives if label == 1 else negatives
            destination[membership] += weight
        normalizer = 2 * ordered_sum(
            sqrt(positive * negative)
            for positive, negative in zip(positives, negatives)
        )
        candidates.append((normalizer, feature, positives, negatives))
    return choose(candidates)
