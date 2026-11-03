"""Mini-batch SGD, momentum, Adam and staircase learning-rate decay."""

import math


def initialize(run, count):
    return {
        "momentum": [0.0] * count,
        "first": [0.0] * count, "second": [0.0] * count,
        "power1": 1.0, "power2": 1.0,
    }


def epoch_rate(run, epoch, step, gamma):
    rate = run["rate"]
    for _ in range((epoch - 1) // step):
        rate *= gamma
    return rate


def update(theta, grad, state, run, learning_rate):
    optimizer = run["optimizer"]
    if optimizer == "SGD":
        for index, value in enumerate(grad):
            theta[index] -= learning_rate * value
        return
    if optimizer == "MOMENTUM":
        mu = run["extra"][0]
        for index, value in enumerate(grad):
            velocity = mu * state["momentum"][index] + value
            state["momentum"][index] = velocity
            theta[index] -= learning_rate * velocity
        return
    beta1, beta2, epsilon = run["extra"]
    state["power1"] *= beta1
    state["power2"] *= beta2
    for index, value in enumerate(grad):
        first = beta1 * state["first"][index] + (1 - beta1) * value
        second = beta2 * state["second"][index] + (1 - beta2) * value * value
        state["first"][index] = first
        state["second"][index] = second
        corrected_first = first / (1 - state["power1"])
        corrected_second = second / (1 - state["power2"])
        theta[index] -= (
            learning_rate * corrected_first / (math.sqrt(corrected_second) + epsilon)
        )
