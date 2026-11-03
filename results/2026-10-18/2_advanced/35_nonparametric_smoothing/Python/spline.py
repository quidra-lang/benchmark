"""Reinsch smoothing splines with a reusable pentadiagonal LDL decomposition."""

from bisect import bisect_left

from selection import ordered_sum


class SplineFit:
    def __init__(self, positions, values, penalty, diagnostics=True):
        self.positions = positions
        self.x = [position / 100 for position in positions]
        self.penalty = penalty
        self.h = [right - left for left, right in zip(self.x, self.x[1:])]
        self.decompose()
        self.fit = self.fit_values(values)
        self.fitted = self.fit[0]
        self.basis = None
        self.leverage = None
        self.edf = None
        if diagnostics:
            self.prepare_basis()

    def decompose(self):
        h = self.h
        size = len(self.positions) - 2
        a = [1 / h[i] for i in range(size)]
        c = [1 / h[i + 1] for i in range(size)]
        b = [-(left + right) for left, right in zip(a, c)]
        penalty = self.penalty
        diagonal = [(h[i] + h[i + 1]) / 3
                    + penalty * (a[i] * a[i] + b[i] * b[i] + c[i] * c[i])
                    for i in range(size)]
        first = [h[i + 1] / 6 + penalty * c[i] * (b[i] + b[i + 1])
                 for i in range(size - 1)]
        second = [penalty * c[i] * c[i + 1] for i in range(size - 2)]
        self.d = [0.0] * size
        self.l1 = [0.0] * size
        self.l2 = [0.0] * size
        for i in range(size):
            if i >= 2:
                self.l2[i] = second[i - 2] / self.d[i - 2]
            if i >= 1:
                correction = (self.l2[i] * self.d[i - 2] * self.l1[i - 1]
                              if i >= 2 else 0.0)
                self.l1[i] = (first[i - 1] - correction) / self.d[i - 1]
            value = diagonal[i]
            if i >= 1:
                value -= self.l1[i] * self.l1[i] * self.d[i - 1]
            if i >= 2:
                value -= self.l2[i] * self.l2[i] * self.d[i - 2]
            self.d[i] = value

    def fit_values(self, values):
        n = len(values)
        size = n - 2
        z = [0.0] * size
        for i in range(size):
            value = ((values[i + 2] - values[i + 1]) / self.h[i + 1]
                     - (values[i + 1] - values[i]) / self.h[i])
            if i >= 1:
                value -= self.l1[i] * z[i - 1]
            if i >= 2:
                value -= self.l2[i] * z[i - 2]
            z[i] = value
        gamma = [0.0] * n
        for i in range(size - 1, -1, -1):
            value = z[i] / self.d[i]
            if i + 1 < size:
                value -= self.l1[i + 1] * gamma[i + 2]
            if i + 2 < size:
                value -= self.l2[i + 2] * gamma[i + 3]
            gamma[i + 1] = value
        omega = [(gamma[1] - gamma[0]) / self.h[0]]
        for i in range(1, n - 1):
            omega.append((gamma[i + 1] - gamma[i]) / self.h[i]
                         - (gamma[i] - gamma[i - 1]) / self.h[i - 1])
        omega.append(0 - (gamma[-1] - gamma[-2]) / self.h[-1])
        fitted = [value - self.penalty * adjustment
                  for value, adjustment in zip(values, omega)]
        return fitted, gamma

    def evaluate_fit(self, fit, position):
        fitted, gamma = fit
        x0 = position / 100
        index = bisect_left(self.positions, position)
        if index < len(self.positions) and self.positions[index] == position:
            return fitted[index]
        if index == 0:
            slope = ((fitted[1] - fitted[0]) / self.h[0]
                     - self.h[0] * gamma[1] / 6)
            return fitted[0] - (self.x[0] - x0) * slope
        if index == len(self.positions):
            slope = ((fitted[-1] - fitted[-2]) / self.h[-1]
                     + self.h[-1] * gamma[-2] / 6)
            return fitted[-1] + (x0 - self.x[-1]) * slope
        i = index - 1
        left = x0 - self.x[i]
        right = self.x[i + 1] - x0
        return ((left * fitted[i + 1] + right * fitted[i]) / self.h[i]
                - left * right * ((1 + left / self.h[i]) * gamma[i + 1]
                                  + (1 + right / self.h[i]) * gamma[i]) / 6)

    def prepare_basis(self):
        if self.basis is None:
            self.basis = []
            n = len(self.positions)
            for i in range(n):
                unit = [0.0] * n
                unit[i] = 1.0
                self.basis.append(self.fit_values(unit))
            self.leverage = [fit[0][i] for i, fit in enumerate(self.basis)]
            self.edf = ordered_sum(self.leverage)

    def estimate(self, position):
        return self.evaluate_fit(self.fit, position)

    def weights(self, position):
        self.prepare_basis()
        return [self.evaluate_fit(fit, position) for fit in self.basis]
