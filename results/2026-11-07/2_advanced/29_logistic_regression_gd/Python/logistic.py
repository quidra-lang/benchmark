import math


def score(weights, vector):
    total = 0.0
    for weight, component in zip(weights, vector):
        total += weight * component
    return total


def probability(u):
    if u >= 0:
        return 1.0 / (1.0 + math.exp(-u))
    e = math.exp(u)
    return e / (1.0 + e)


def loss(u, target):
    return max(u, 0.0) - target * u + math.log(1.0 + math.exp(-abs(u)))


def average_loss(weights, vectors, targets):
    total = 0.0
    for vector, target in zip(vectors, targets):
        total += loss(score(weights, vector), target)
    return total / len(vectors)


def penalty(weights):
    total = 0.0
    for weight in weights[1:]:
        total += weight * weight
    return total


def objective(weights, vectors, targets, lam):
    return average_loss(weights, vectors, targets) + lam * penalty(weights) / 2


def gradient(weights, vectors, targets, lam):
    size = len(weights)
    totals = [0.0] * size
    for vector, target in zip(vectors, targets):
        error = probability(score(weights, vector)) - target
        for j in range(size):
            totals[j] += error * vector[j]
    count = len(vectors)
    result = [totals[0] / count]
    for j in range(1, size):
        result.append(totals[j] / count + lam * weights[j])
    return result


def hessian(weights, vectors, lam):
    size = len(weights)
    totals = [[0.0] * size for _ in range(size)]
    for vector in vectors:
        pi = probability(score(weights, vector))
        variance = pi * (1.0 - pi)
        for j in range(size):
            row = totals[j]
            for k in range(j + 1):
                row[k] += variance * vector[j] * vector[k]
    count = len(vectors)
    matrix = [[0.0] * size for _ in range(size)]
    for j in range(size):
        for k in range(j + 1):
            value = totals[j][k] / count
            if j == k and j >= 1:
                value += lam
            matrix[j][k] = value
            matrix[k][j] = value
    return matrix
