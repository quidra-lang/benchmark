"""Exact evaluation ratios, paired comparisons, and the required generator."""

from math import gcd

from linalg import ordered_sum


def reduced_fraction(numerator, denominator):
    if denominator == 0:
        return None
    divisor = gcd(abs(numerator), denominator)
    return numerator // divisor, denominator // divisor


def sum_fractions(values):
    numerator, denominator = 0, 1
    for next_numerator, next_denominator in values:
        numerator, denominator = reduced_fraction(
            numerator * next_denominator + next_numerator * denominator,
            denominator * next_denominator,
        )
    return numerator, denominator


def confusion_matrix(actual, predictions, class_count):
    matrix = [[0] * class_count for _ in range(class_count)]
    for expected, predicted in zip(actual, predictions):
        matrix[expected][predicted] += 1
    return matrix


def measures(actual, predictions, class_count):
    matrix = confusion_matrix(actual, predictions, class_count)
    support = [sum(row) for row in matrix]
    predicted_counts = [sum(row[k] for row in matrix) for k in range(class_count)]
    correct = sum(matrix[k][k] for k in range(class_count))
    count = len(actual)
    recalls = [reduced_fraction(matrix[k][k], support[k]) for k in range(class_count)]
    precisions = [
        reduced_fraction(matrix[k][k], predicted_counts[k]) for k in range(class_count)
    ]
    f1 = [
        reduced_fraction(2 * matrix[k][k], support[k] + predicted_counts[k])
        for k in range(class_count)
    ]
    recall_numerator, recall_denominator = sum_fractions(recalls)
    expected = sum(support[k] * predicted_counts[k] for k in range(class_count))
    macro_f1 = ordered_sum(
        (2 * matrix[k][k]) / (support[k] + predicted_counts[k])
        for k in range(class_count)
    ) / class_count
    return {
        "matrix": matrix,
        "support": support,
        "correct": correct,
        "accuracy": reduced_fraction(correct, count),
        "balanced_accuracy": reduced_fraction(recall_numerator, recall_denominator * class_count),
        "kappa": reduced_fraction(count * correct - expected, count * count - expected),
        "recall": recalls,
        "precision": precisions,
        "f1": f1,
        "macro_f1": macro_f1,
    }


def mcnemar(actual, predictions_a, predictions_b):
    b01 = 0
    b10 = 0
    for expected, predicted_a, predicted_b in zip(actual, predictions_a, predictions_b):
        correct_a = predicted_a == expected
        correct_b = predicted_b == expected
        if correct_a and not correct_b:
            b01 += 1
        elif correct_b and not correct_a:
            b10 += 1
    if b01 == b10:
        chi2 = 0.0
    else:
        difference = abs(b01 - b10) - 1
        chi2 = (difference * difference) / (b01 + b10)
    return b01, b10, chi2, chi2 > 3.841


class RandomGenerator:
    def __init__(self, seed):
        self.state = seed

    def draw(self):
        self.state = (48271 * self.state) % 2147483647
        return self.state
