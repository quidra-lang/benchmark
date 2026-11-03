"""Common evaluation, ordered folds, and exact output conventions."""


def sign(value):
    return 1 if value > 0 else -1


def folds(size, count):
    result = []
    for fold in range(count):
        training = [i for i in range(size) if i % count != fold]
        testing = [i for i in range(size) if i % count == fold]
        result.append((training, testing))
    return result


def correct_count(labels, values):
    return sum(sign(value) == label for label, value in zip(labels, values))


def binary_counts(labels, values):
    tp = fp = tn = fn = 0
    for label, value in zip(labels, values):
        prediction = sign(value)
        if label == 1:
            if prediction == 1:
                tp += 1
            else:
                fn += 1
        elif prediction == 1:
            fp += 1
        else:
            tn += 1
    return tp, fp, tn, fn


def auc(labels, values):
    positives = [i for i, label in enumerate(labels) if label == 1]
    negatives = [i for i, label in enumerate(labels) if label == -1]
    total = 0.0
    for positive in positives:
        for negative in negatives:
            if values[positive] > values[negative]:
                total += 1.0
            elif values[positive] == values[negative]:
                total += 0.5
    return total / (len(positives) * len(negatives))


def confusion_matrix(classes, predictions):
    matrix = [[0, 0, 0] for _ in range(3)]
    for actual, predicted in zip(classes, predictions):
        matrix[actual - 1][predicted - 1] += 1
    return matrix


def confusion_lines(matrix):
    lines = [" ".join(str(value) for value in row) for row in matrix]
    for index in range(3):
        column = sum(row[index] for row in matrix)
        row = sum(matrix[index])
        lines.append(
            f"class {index + 1} precision {ratio(matrix[index][index], column)} "
            f"recall {ratio(matrix[index][index], row)}"
        )
    return lines


def fixed(value, decimals=4):
    result = f"{value:.{decimals}f}"
    if result.startswith("-") and float(result) == 0:
        result = result[1:]
    return result


def ratio(numerator, denominator):
    return fixed(numerator / denominator) if denominator > 0 else "-"


def write_lines(path, lines):
    with open(path, "w", encoding="ascii", newline="\n") as destination:
        for line in lines:
            destination.write(line + "\n")
