"""CV/CA Kalman models, Joseph updates and backward RTS smoothing."""

from math import log, pi

from matrix import (add, determinant2, diagonal, identity, inverse, matrix_vector,
                    product, quadratic2, subtract, transpose, vector_add,
                    vector_subtract, zeros)


def transition(model, interval):
    result = identity(4 if model == "CV" else 6)
    result[0][2] = result[1][3] = interval
    if model == "CA":
        result[0][4] = result[1][5] = interval * interval / 2
        result[2][4] = result[3][5] = interval
    return result


def process_noise(model, interval, q):
    t = interval
    if model == "CV":
        entries = ((0, 0, q * t * t * t / 3),
                   (0, 2, q * t * t / 2), (2, 2, q * t))
        result = zeros(4)
    else:
        entries = ((0, 0, q * t * t * t * t * t / 20),
                   (0, 2, q * t * t * t * t / 8),
                   (0, 4, q * t * t * t / 6),
                   (2, 2, q * t * t * t / 3),
                   (2, 4, q * t * t / 2), (4, 4, q * t))
        result = zeros(6)
    for axis in range(2):
        for row, column, value in entries:
            result[row + axis][column + axis] = value
            result[column + axis][row + axis] = value
    return result


class Kalman:
    def __init__(self, model, q, sigma, velocity_variance, acceleration_variance, measurement):
        self.model = model
        self.q = q
        size = 4 if model == "CV" else 6
        self.x = list(measurement) + [0.0] * (size - 2)
        variances = [sigma * sigma, sigma * sigma, velocity_variance, velocity_variance]
        if size == 6:
            variances.extend((acceleration_variance, acceleration_variance))
        self.P = diagonal(variances)
        self.H = zeros(2, size)
        self.H[0][0] = self.H[1][1] = 1.0
        self.R = diagonal([sigma * sigma, sigma * sigma])
        self.F = self.xp = self.Pp = None

    def predict(self, interval):
        self.F = transition(self.model, interval)
        self.x = matrix_vector(self.F, self.x)
        self.P = add(product(product(self.F, self.P), transpose(self.F)),
                     process_noise(self.model, interval, self.q))
        self.xp, self.Pp = self.x, self.P

    def innovation(self, measurement):
        residual = vector_subtract(measurement, matrix_vector(self.H, self.x))
        covariance = add(product(product(self.H, self.P), transpose(self.H)), self.R)
        precision = inverse(covariance)
        distance2 = quadratic2(residual, precision)
        return residual, covariance, precision, distance2

    def update(self, measurement, innovation=None):
        residual, covariance, precision, distance2 = (
            self.innovation(measurement) if innovation is None else innovation)
        gain = product(product(self.P, transpose(self.H)), precision)
        correction = subtract(identity(len(self.x)), product(gain, self.H))
        self.x = vector_add(self.x, matrix_vector(gain, residual))
        self.P = add(product(product(correction, self.P), transpose(correction)),
                     product(product(gain, self.R), transpose(gain)))
        likelihood = -log(2 * pi) - log(determinant2(covariance)) / 2 - distance2 / 2
        return distance2, likelihood, covariance

    def snapshot(self):
        return {"x": self.x, "P": self.P, "xp": self.xp, "Pp": self.Pp, "F": self.F}


def smooth(history):
    states = [None] * len(history)
    states[-1] = history[-1]["x"]
    for index in range(len(history) - 2, -1, -1):
        current, following = history[index], history[index + 1]
        gain = product(product(current["P"], transpose(following["F"])), inverse(following["Pp"]))
        difference = vector_subtract(states[index + 1], following["xp"])
        states[index] = vector_add(current["x"], matrix_vector(gain, difference))
    return states
