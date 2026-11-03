"""LOESS local polynomials, Cholesky systems and robustness iterations."""

from math import sqrt

from selection import ordered_sum


def median(values):
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2


def cholesky(matrix):
    size = len(matrix)
    lower = [[0.0] * size for _ in range(size)]
    for row in range(size):
        for column in range(row + 1):
            sigma = matrix[row][column]
            for k in range(column):
                sigma -= lower[row][k] * lower[column][k]
            lower[row][column] = (sqrt(sigma) if row == column
                                  else sigma / lower[column][column])
    return lower


def solve(lower, right):
    size = len(right)
    intermediate = [0.0] * size
    for row in range(size):
        value = right[row]
        for k in range(row):
            value -= lower[row][k] * intermediate[k]
        intermediate[row] = value / lower[row][row]
    solution = [0.0] * size
    for row in range(size - 1, -1, -1):
        value = intermediate[row]
        for k in range(row + 1, size):
            value -= lower[k][row] * solution[k]
        solution[row] = value / lower[row][row]
    return solution


class LoessFit:
    def __init__(self, positions, values, span, degree, iterations, diagnostics=True):
        self.positions = positions
        self.x = [position / 100 for position in positions]
        self.y = values
        self.span = span
        self.degree = degree
        self.rho = [1.0] * len(positions)
        self.records = []
        self.cache = {}
        self.fitted = None
        self.leverage = None
        self.edf = None
        if not diagnostics:
            return
        fits = [self.local_fit(position) for position in positions]
        for iteration in range(1, iterations + 1):
            residuals = [y - fit[0] for y, fit in zip(values, fits)]
            scale = median([abs(value) for value in residuals])
            for i, residual in enumerate(residuals):
                u = residual / (6 * scale)
                v = 1 - u * u
                self.rho[i] = v * v if abs(u) < 1 else 0.0
            updated = [self.local_fit(position) for position in positions]
            change = max(abs(new[0] - old[0]) for new, old in zip(updated, fits))
            self.records.append((iteration, scale, self.rho.count(0.0), change))
            fits = updated
        self.cache = dict(zip(positions, fits))
        self.fitted = [fit[0] for fit in fits]
        self.leverage = [rho * fit[1] for rho, fit in zip(self.rho, fits)]
        self.edf = ordered_sum(self.leverage)

    def local_fit(self, position):
        count = len(self.positions)
        q = self.span * count // 100
        neighborhood = sorted(range(count),
                              key=lambda i: (abs(self.positions[i] - position), i))[:q]
        distance = max(abs(self.positions[i] - position) for i in neighborhood)
        size = self.degree + 1
        matrix = [[0.0] * size for _ in range(size)]
        right = [0.0] * size
        rows = []
        for i in sorted(neighborhood):
            a = abs(self.positions[i] - position) / distance
            s = 1 - a * a * a
            weight = s * s * s * self.rho[i]
            delta = self.x[i] - position / 100
            basis = [1.0, delta] if self.degree == 1 else [1.0, delta, delta * delta]
            rows.append((i, weight, basis))
            for row in range(size):
                right[row] += weight * basis[row] * self.y[i]
                for column in range(size):
                    matrix[row][column] += weight * basis[row] * basis[column]
        lower = cholesky(matrix)
        beta = solve(lower, right)
        zeta = solve(lower, [1.0] + [0.0] * self.degree)
        weights = [0.0] * count
        for i, weight, basis in rows:
            weights[i] = weight * ordered_sum(zeta[k] * basis[k] for k in range(size))
        return beta[0], zeta[0], weights

    def evaluate(self, position):
        if position not in self.cache:
            self.cache[position] = self.local_fit(position)
        return self.cache[position]

    def estimate(self, position):
        return self.evaluate(position)[0]

    def weights(self, position):
        return self.evaluate(position)[2]
