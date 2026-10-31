import math


DISTANCE_TYPES = ("euclidean", "manhattan", "correlation")


def sequential_sum(values):
    total = 0.0
    for value in values:
        total += value
    return total


def squared_distance(u, w):
    return sequential_sum((a - b) * (a - b) for a, b in zip(u, w))


def feature_statistics(rows):
    count = len(rows)
    means = []
    deviations = []
    for f in range(len(rows[0])):
        column = [row[f] for row in rows]
        mean = sequential_sum(column) / count
        variance = sequential_sum((value - mean) * (value - mean) for value in column) / (count - 1)
        means.append(mean)
        deviations.append(math.sqrt(variance))
    return means, deviations


def standardize(rows, means, deviations):
    return [
        [(value - mean) / deviation for value, mean, deviation in zip(row, means, deviations)]
        for row in rows
    ]


def correlation_distance(u, w):
    mean_u = sequential_sum(u) / len(u)
    mean_w = sequential_sum(w) / len(w)
    centered_u = [value - mean_u for value in u]
    centered_w = [value - mean_w for value in w]
    cross = sequential_sum(a * b for a, b in zip(centered_u, centered_w))
    spread = sequential_sum(a * a for a in centered_u) * sequential_sum(b * b for b in centered_w)
    return 1 - cross / math.sqrt(spread)


def distance(u, w, kind):
    if kind == "euclidean":
        return math.sqrt(squared_distance(u, w))
    if kind == "manhattan":
        return sequential_sum(abs(a - b) for a, b in zip(u, w))
    return correlation_distance(u, w)


def distance_matrix(vectors, kind):
    count = len(vectors)
    matrix = [[0.0] * count for _ in range(count)]
    for i in range(count):
        for j in range(i + 1, count):
            value = distance(vectors[i], vectors[j], kind)
            matrix[i][j] = value
            matrix[j][i] = value
    return matrix
