"""Formatting and small evaluation primitives shared by the reports."""

from pathlib import Path


def number(value, decimals=4):
    result = f"{value:.{decimals}f}"
    if result.startswith("-") and float(result) == 0.0:
        return result[1:]
    return result


def ratio(numerator, denominator):
    return number(numerator / denominator) if denominator > 0 else "-"


def prediction(score):
    return 1 if score > 0 else -1


def auc(rows, scores):
    positives = [score for row, score in zip(rows, scores) if row.label == 1]
    negatives = [score for row, score in zip(rows, scores) if row.label == -1]
    wins = 0
    ties = 0
    for positive in positives:
        for negative in negatives:
            if positive > negative:
                wins += 1
            elif positive == negative:
                ties += 1
    return 2 * wins + ties, 2 * len(positives) * len(negatives)


def confusion(rows, predictions, classes):
    matrix = [[0] * classes for _ in range(classes)]
    for row, predicted in zip(rows, predictions):
        matrix[row.label - 1][predicted - 1] += 1
    return matrix


def count_at_most(margins, threshold):
    return sum(margin <= threshold for margin in margins)


def write_lines(path, lines):
    with Path(path).open("w", encoding="ascii", newline="\n") as destination:
        for line in lines:
            destination.write(line)
            destination.write("\n")
