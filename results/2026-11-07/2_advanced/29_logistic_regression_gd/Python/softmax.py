import math

from logistic import score


CHECKPOINT_INTERVAL = 100


def shifted_scores(weights, vector):
    scores = [score(row, vector) for row in weights]
    top = max(scores)
    return [value - top for value in scores]


def exponential_total(shifted):
    total = 0.0
    for value in shifted:
        total += math.exp(value)
    return total


def probabilities(weights, vector):
    shifted = shifted_scores(weights, vector)
    total = exponential_total(shifted)
    return [math.exp(value) / total for value in shifted]


def predicted_class(class_probabilities):
    return class_probabilities.index(max(class_probabilities))


def loss(weights, vector, label):
    shifted = shifted_scores(weights, vector)
    return math.log(exponential_total(shifted)) - shifted[label]


def average_loss(weights, vectors, labels):
    total = 0.0
    for vector, label in zip(vectors, labels):
        total += loss(weights, vector, label)
    return total / len(vectors)


def penalty(weights):
    total = 0.0
    for row in weights:
        for weight in row[1:]:
            total += weight * weight
    return total


def objective(weights, vectors, labels, lam):
    return average_loss(weights, vectors, labels) + lam * penalty(weights) / 2


def gradient(weights, vectors, labels, lam):
    classes = len(weights)
    size = len(weights[0])
    totals = [[0.0] * size for _ in range(classes)]
    for vector, label in zip(vectors, labels):
        class_probabilities = probabilities(weights, vector)
        for k in range(classes):
            error = class_probabilities[k] - (1.0 if label == k else 0.0)
            row = totals[k]
            for j in range(size):
                row[j] += error * vector[j]
    count = len(vectors)
    result = []
    for k in range(classes):
        row = [totals[k][0] / count]
        for j in range(1, size):
            row.append(totals[k][j] / count + lam * weights[k][j])
        result.append(row)
    return result


def train(vectors, labels, classes, lam, rate, iterations):
    weights = [[0.0] * len(vectors[0]) for _ in range(classes)]
    checkpoints = [(0, weights)]
    for t in range(1, iterations + 1):
        direction = gradient(weights, vectors, labels, lam)
        weights = [
            [weight - rate * step for weight, step in zip(row, steps)]
            for row, steps in zip(weights, direction)
        ]
        if t % CHECKPOINT_INTERVAL == 0:
            checkpoints.append((t, weights))
    return checkpoints
