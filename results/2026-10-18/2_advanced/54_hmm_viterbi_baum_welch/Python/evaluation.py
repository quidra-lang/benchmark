"""Exact fractions, confusion statistics, and path comparison primitives."""

from math import gcd


def fraction(numerator, denominator):
    if denominator == 0:
        return "-"
    if denominator < 0:
        numerator = -numerator
        denominator = -denominator
    divisor = gcd(abs(numerator), denominator)
    return f"{numerator // divisor}/{denominator // divisor}"


def confusion_matrix(count):
    return [[0] * count for _ in range(count)]


def accumulate_confusion(matrix, truth, prediction):
    for actual, predicted in zip(truth, prediction):
        matrix[actual][predicted] += 1


def correct_count(truth, prediction):
    return sum(actual == predicted for actual, predicted in zip(truth, prediction))


def matrix_lines(states, matrix):
    width = max(len(str(value)) for row in matrix for value in row)
    lines = [" " + "".join(f" {state:>{width}}" for state in states)]
    for state, row in zip(states, matrix):
        lines.append(state + "".join(f" {value:>{width}}" for value in row))
    return lines


def metric_lines(states, matrix):
    count = len(states)
    rows = [sum(row) for row in matrix]
    columns = [sum(matrix[row][column] for row in range(count)) for column in range(count)]
    total = sum(rows)
    correct = sum(matrix[state][state] for state in range(count))
    expected = sum(rows[state] * columns[state] for state in range(count))
    lines = [
        f"ACCURACY {fraction(correct, total)}",
        f"KAPPA {fraction(total * correct - expected, total * total - expected)}",
    ]
    for state, name in enumerate(states):
        true_positive = matrix[state][state]
        precision = fraction(true_positive, columns[state])
        recall = fraction(true_positive, rows[state])
        f1 = fraction(2 * true_positive, columns[state] + rows[state])
        lines.append(f"STATE {name} precision {precision} recall {recall} f1 {f1}")
    return lines


def runs(path):
    if not path:
        return []
    result = []
    start = 1
    state = path[0]
    for position in range(1, len(path)):
        if path[position] != state:
            result.append((state, start, position))
            state = path[position]
            start = position + 1
    result.append((state, start, len(path)))
    return result


def regions_overlap(first, second):
    return first[0] <= second[1] and second[0] <= first[1]


def region_counts(predicted, truth):
    matched_predicted = sum(
        any(regions_overlap(region, other) for other in truth)
        for region in predicted
    )
    matched_truth = sum(
        any(regions_overlap(region, other) for other in predicted)
        for region in truth
    )
    return len(predicted), len(truth), matched_predicted, matched_truth


def boundaries(path):
    return [
        position + 1 for position in range(1, len(path))
        if path[position - 1] != path[position]
    ]


def boundary_counts(predicted_path, true_path, tolerance):
    predicted = boundaries(predicted_path)
    truth = boundaries(true_path)
    matched_predicted = sum(
        any(abs(position - other) <= tolerance for other in truth)
        for position in predicted
    )
    matched_truth = sum(
        any(abs(position - other) <= tolerance for other in predicted)
        for position in truth
    )
    return len(predicted), len(truth), matched_predicted, matched_truth
