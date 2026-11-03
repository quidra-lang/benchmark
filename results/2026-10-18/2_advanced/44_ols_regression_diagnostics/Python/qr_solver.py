"""Ordered Householder least squares, including aliases and influence factors."""

from math import sqrt


def ordered_sum(values):
    """Use the task's ordinary left-to-right double-precision accumulation."""
    result = 0.0
    for value in values:
        result = result + value
    return result


class Fit:
    def __init__(self, matrix, response, weights, tolerance):
        self.matrix = matrix
        self.response = response
        self.weights = weights
        self.n = len(matrix)
        self.p = len(matrix[0])
        roots = [sqrt(weight) for weight in weights]
        weighted = [[roots[i] * value for value in row]
                    for i, row in enumerate(matrix)]
        lengths = [sqrt(ordered_sum(weighted[i][j] * weighted[i][j]
                                    for i in range(self.n)))
                   for j in range(self.p)]
        work = [row[:] for row in weighted]
        transformed = [roots[i] * response[i] for i in range(self.n)]
        triangular = [[0.0] * self.p for _ in range(self.p)]
        self.accepted = []
        self.aliases = []
        for j in range(self.p):
            k = len(self.accepted)
            eta = sqrt(ordered_sum(work[i][j] * work[i][j]
                                   for i in range(k, self.n)))
            if eta <= tolerance * lengths[j]:
                self.aliases.append(j)
                continue
            self.accepted.append(j)
            alpha = -eta if work[k][j] >= 0.0 else eta
            vector = [work[k][j] - alpha]
            vector.extend(work[i][j] for i in range(k + 1, self.n))
            squared_length = ordered_sum(value * value for value in vector)
            for l in range(k):
                triangular[l][k] = work[l][j]
            triangular[k][k] = alpha
            for l in range(j + 1, self.p):
                dot = ordered_sum(vector[i - k] * work[i][l]
                                  for i in range(k, self.n))
                delta = 2.0 * dot / squared_length
                for i in range(k, self.n):
                    work[i][l] = work[i][l] - delta * vector[i - k]
            dot = ordered_sum(vector[i - k] * transformed[i]
                              for i in range(k, self.n))
            delta = 2.0 * dot / squared_length
            for i in range(k, self.n):
                transformed[i] = transformed[i] - delta * vector[i - k]

        self.rank = len(self.accepted)
        r = self.rank
        self.triangular = [row[:r] for row in triangular[:r]]
        self.effects = transformed[:r]
        self.beta = [None] * self.p
        for k in range(r - 1, -1, -1):
            tail = ordered_sum(self.triangular[k][l] * self.beta[self.accepted[l]]
                               for l in range(k + 1, r))
            self.beta[self.accepted[k]] = ((self.effects[k] - tail)
                                            / self.triangular[k][k])

        self.inverse = [[0.0] * r for _ in range(r)]
        for m in range(r):
            for l in range(r - 1, -1, -1):
                diagonal = 1.0 if l == m else 0.0
                tail = ordered_sum(self.triangular[l][q] * self.inverse[q][m]
                                   for q in range(l + 1, r))
                self.inverse[l][m] = ((diagonal - tail)
                                      / self.triangular[l][l])
        self.variance = [ordered_sum(value * value for value in row)
                         for row in self.inverse]
        self.u = []
        self.g = []
        self.leverage = []
        self.fitted = []
        self.residual = []
        self.weighted_residual = []
        for i in range(self.n):
            u = [ordered_sum(weighted[i][self.accepted[m]] * self.inverse[m][k]
                             for m in range(r)) for k in range(r)]
            self.u.append(u)
            self.leverage.append(ordered_sum(value * value for value in u))
            self.g.append([
                ordered_sum(self.inverse[k][m] * u[m] for m in range(r))
                for k in range(r)
            ])
            fitted = ordered_sum(matrix[i][self.accepted[k]]
                                 * self.beta[self.accepted[k]] for k in range(r))
            residual = response[i] - fitted
            self.fitted.append(fitted)
            self.residual.append(residual)
            self.weighted_residual.append(roots[i] * residual)
        self.rss = ordered_sum(value * value for value in self.weighted_residual)
