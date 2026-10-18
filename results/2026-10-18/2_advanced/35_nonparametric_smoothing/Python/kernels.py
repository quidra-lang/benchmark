KERNEL_CONSTANTS = {"epanechnikov": 0.75, "biweight": 0.9375, "triweight": 1.09375}


def kernel_value(kernel, t):
    if kernel == "epanechnikov":
        return 0.75 * t
    if kernel == "biweight":
        return 0.9375 * t * t
    return 1.09375 * t * t * t


class KernelEstimate:
    def __init__(self, points, kernel, bandwidth, position, local_linear):
        h = bandwidth / 100
        x0 = position / 100
        self.n = points.n
        self.kappa = KERNEL_CONSTANTS[kernel]
        self.local_linear = local_linear
        self.used = []
        self.factors = []
        self.offsets = []
        self.s0 = 0.0
        self.s1 = 0.0
        self.s2 = 0.0
        self.t0 = 0.0
        self.t1 = 0.0
        for j in range(points.n):
            if abs(points.X[j] - position) >= bandwidth:
                continue
            u = (points.x[j] - x0) / h
            factor = kernel_value(kernel, 1 - u * u)
            d = points.x[j] - x0
            self.used.append(j)
            self.factors.append(factor)
            self.offsets.append(d)
            self.s0 += factor
            self.s1 += factor * d
            self.s2 += factor * d * d
            self.t0 += factor * points.y[j]
            self.t1 += factor * d * points.y[j]
        self.q = self.s0 * self.s2 - self.s1 * self.s1
        self.defined = len(self.used) >= (2 if local_linear else 1)

    def value(self):
        if not self.defined:
            return None
        if self.local_linear:
            return (self.s2 * self.t0 - self.s1 * self.t1) / self.q
        return self.t0 / self.s0

    def leverage(self):
        if self.local_linear:
            return self.kappa * self.s2 / self.q
        return self.kappa / self.s0

    def weights(self):
        weights = [0.0] * self.n
        for j, factor, d in zip(self.used, self.factors, self.offsets):
            if self.local_linear:
                weights[j] = factor * (self.s2 - self.s1 * d) / self.q
            else:
                weights[j] = factor / self.s0
        return weights
