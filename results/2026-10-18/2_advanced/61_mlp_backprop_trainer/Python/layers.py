"""MLP hidden nonlinearities, score functions, losses and output deltas."""

import math


def hidden_activation(kind, value):
    if kind == "TANH":
        return math.tanh(value)
    if kind == "SIGMOID":
        return 1.0 / (1.0 + math.exp(-value))
    return value if value > 0 else 0.0


def hidden_derivative(kind, z, activated):
    if kind == "TANH":
        return 1 - activated * activated
    if kind == "SIGMOID":
        return activated * (1 - activated)
    return 1.0 if z > 0 else 0.0


def output_scores(kind, z, label):
    count = len(z)
    if kind == "SOFTMAX":
        maximum = max(z)
        terms = [math.exp(value - maximum) for value in z]
        total = sum(terms)
        scores = [value / total for value in terms]
        loss = math.log(total) - (z[label] - maximum)
        error = [
            value - (1.0 if k == label else 0.0)
            for k, value in enumerate(scores)
        ]
        return scores, loss, error
    scores = [1 / (1 + math.exp(-value)) for value in z]
    error = []
    loss = 0.0
    for k, value in enumerate(scores):
        target = 1.0 if k == label else 0.0
        residual = value - target
        loss += residual * residual
        error.append(2 * residual * value * (1 - value) / count)
    return scores, loss / count, error


def weighted_pre_activation(weights, biases, activation):
    result = []
    for row, bias in zip(weights, biases):
        weighted = sum(
            coefficient * input_value
            for coefficient, input_value in zip(row, activation)
        )
        result.append(weighted + bias)
    return result


def backward_sum(weights, output_error):
    return [
        sum(row[column] * error
            for row, error in zip(weights, output_error))
        for column in range(len(weights[0]))
    ]
