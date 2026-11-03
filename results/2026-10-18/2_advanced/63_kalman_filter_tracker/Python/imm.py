"""A two-model CV interacting multiple-model filter."""

from math import exp, pi, sqrt

from kalman import Kalman
from matrix import determinant2


class IMM:
    def __init__(self, densities, transition, initial, sigma, velocity_variance, measurement):
        self.models = [Kalman("CV", q, sigma, velocity_variance, 0.0, measurement) for q in densities]
        self.transition = [list(transition[:2]), list(transition[2:])]
        self.probabilities = list(initial)

    def step(self, interval, measurement):
        mu = self.probabilities
        transition = self.transition
        predicted = [transition[0][j] * mu[0] + transition[1][j] * mu[1] for j in range(2)]
        old_states = [model.x for model in self.models]
        old_covariances = [model.P for model in self.models]
        likelihoods = []
        for j, model in enumerate(self.models):
            w0 = transition[0][j] * mu[0] / predicted[j]
            w1 = transition[1][j] * mu[1] / predicted[j]
            mixed = [w0 * old_states[0][r] + w1 * old_states[1][r] for r in range(4)]
            covariance = [[
                w0 * (old_covariances[0][r][s]
                      + (old_states[0][r] - mixed[r]) * (old_states[0][s] - mixed[s]))
                + w1 * (old_covariances[1][r][s]
                        + (old_states[1][r] - mixed[r]) * (old_states[1][s] - mixed[s]))
                for s in range(4)] for r in range(4)]
            model.x, model.P = mixed, covariance
            model.predict(interval)
            likelihood = 1.0
            if measurement is not None:
                distance2, _, innovation_covariance = model.update(measurement)
                likelihood = exp(-distance2 / 2) / (2 * pi * sqrt(determinant2(innovation_covariance)))
            likelihoods.append(likelihood)
        denominator = likelihoods[0] * predicted[0] + likelihoods[1] * predicted[1]
        self.probabilities = [likelihoods[j] * predicted[j] / denominator for j in range(2)]

    def estimate(self):
        return [self.probabilities[0] * self.models[0].x[r]
                + self.probabilities[1] * self.models[1].x[r] for r in range(4)]
