import math

from matrix import dot, sequential_sum


def column_means(rows):
    return [sequential_sum(row[j] for row in rows) / len(rows) for j in range(len(rows[0]))]


def covariance_matrix(rows, means):
    size = len(means)
    deviations = [[row[j] - means[j] for j in range(size)] for row in rows]
    covariance = [[0.0] * size for _ in range(size)]
    for j in range(size):
        for k in range(j, size):
            products = sequential_sum(deviation[j] * deviation[k] for deviation in deviations)
            covariance[j][k] = covariance[k][j] = products / (len(rows) - 1)
    return covariance


def standard_deviations(covariance):
    return [math.sqrt(covariance[j][j]) for j in range(len(covariance))]


def correlation_matrix(covariance, deviations):
    size = len(covariance)
    return [
        [1.0 if j == k else covariance[j][k] / (deviations[j] * deviations[k]) for k in range(size)]
        for j in range(size)
    ]


def standardize(values, means, scales):
    return [
        0.0 if value is None else (value - mean) / scale
        for value, mean, scale in zip(values, means, scales)
    ]


def component_scores(z, vectors):
    return [dot(z, vector) for vector in vectors]


def residuals(z, scores, vectors, count):
    return [
        z[j] - sequential_sum(scores[k] * vectors[k][j] for k in range(count))
        for j in range(len(z))
    ]


def hotelling_t2(scores, eigenvalues, count):
    return sequential_sum(scores[k] * scores[k] / eigenvalues[k] for k in range(count))
