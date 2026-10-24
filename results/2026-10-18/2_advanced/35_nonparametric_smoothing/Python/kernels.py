"""Nadaraya-Watson and local-linear fits with exact support comparisons."""

from selection import ordered_sum


KAPPA = {"epanechnikov": 0.75, "biweight": 0.9375, "triweight": 1.09375}


class KernelFit:
    def __init__(self, positions, values, bandwidth, kernel, local_linear,
                 diagnostics=True):
        self.positions = positions
        self.x = [position / 100 for position in positions]
        self.y = values
        self.bandwidth = bandwidth
        self.kernel = kernel
        self.local_linear = local_linear
        self.cache = {}
        self.fitted = None
        self.leverage = None
        self.edf = None
        if not diagnostics:
            return
        pairs = [self.evaluate(position) for position in positions]
        self.fitted = [value for value, _ in pairs]
        if any(value is None for value in self.fitted):
            self.fitted = None
        else:
            self.leverage = [weights[i] for i, (_, weights) in enumerate(pairs)]
            self.edf = ordered_sum(self.leverage)

    def evaluate(self, position):
        if position in self.cache:
            return self.cache[position]
        used = [i for i, value in enumerate(self.positions)
                if abs(value - position) < self.bandwidth]
        minimum = 2 if self.local_linear else 1
        if len(used) < minimum:
            self.cache[position] = None, None
            return None, None
        x0 = position / 100
        h = self.bandwidth / 100
        kernel_values = []
        differences = []
        for i in used:
            delta = self.x[i] - x0
            u = delta / h
            t = 1 - u * u
            weight = KAPPA[self.kernel] * t
            if self.kernel != "epanechnikov":
                weight *= t
            if self.kernel == "triweight":
                weight *= t
            differences.append(delta)
            kernel_values.append(weight)
        s0 = ordered_sum(kernel_values)
        t0 = ordered_sum(weight * self.y[i]
                         for i, weight in zip(used, kernel_values))
        weights = [0.0] * len(self.positions)
        if self.local_linear:
            s1 = ordered_sum(k * d for k, d in zip(kernel_values, differences))
            s2 = ordered_sum(k * d * d for k, d in zip(kernel_values, differences))
            t1 = ordered_sum(k * d * self.y[i]
                             for i, k, d in zip(used, kernel_values, differences))
            determinant = s0 * s2 - s1 * s1
            estimate = (s2 * t0 - s1 * t1) / determinant
            for i, k, d in zip(used, kernel_values, differences):
                weights[i] = k * (s2 - s1 * d) / determinant
        else:
            estimate = t0 / s0
            for i, weight in zip(used, kernel_values):
                weights[i] = weight / s0
        self.cache[position] = estimate, weights
        return estimate, weights

    def estimate(self, position):
        return self.evaluate(position)[0]

    def weights(self, position):
        return self.evaluate(position)[1]
