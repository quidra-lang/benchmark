"""Deterministic Platt SMO with the specified partner and pass ordering."""


class Model:
    def __init__(self, points, labels, kernel, matrix, coefficient, settings):
        self.points = points
        self.labels = labels
        self.kernel = kernel
        self.matrix = matrix
        self.C = coefficient
        self.tolerance = settings.tolerance
        self.eps = settings.eps
        self.max_passes = settings.max_passes
        self.alpha = [0.0] * len(points)
        self.b = 0.0
        self.errors = [-float(label) for label in labels]
        self.full_passes = 0
        self.nonbound_passes = 0
        self.examined = 0
        self.steps = 0
        self.choices = {"heuristic": 0, "nonbound_loop": 0, "full_loop": 0}
        self.clipping = {"none": 0, "lower": 0, "upper": 0}
        self.records = []
        self.converged = False

    @property
    def passes(self):
        return self.full_passes + self.nonbound_passes

    def nonbound(self, index):
        return 0 < self.alpha[index] < self.C

    def snap(self, value):
        if value < 0.00000001:
            return 0.0
        if value > self.C - 0.00000001:
            return self.C
        return value

    def take(self, first, second):
        if first == second:
            return False
        alpha1, alpha2 = self.alpha[first], self.alpha[second]
        y1, y2 = self.labels[first], self.labels[second]
        error1, error2 = self.errors[first], self.errors[second]
        if y1 != y2:
            lower = max(0.0, alpha2 - alpha1)
            upper = min(self.C, self.C + alpha2 - alpha1)
        else:
            lower = max(0.0, alpha2 + alpha1 - self.C)
            upper = min(self.C, alpha2 + alpha1)
        if lower == upper:
            return False
        k11 = self.matrix[first][first]
        k12 = self.matrix[first][second]
        k22 = self.matrix[second][second]
        eta = k11 + k22 - 2 * k12
        if eta <= 0:
            return False
        a2 = alpha2 + y2 * (error1 - error2) / eta
        clipping = "none"
        if a2 < lower:
            a2 = lower
            clipping = "lower"
        elif a2 > upper:
            a2 = upper
            clipping = "upper"
        a2 = self.snap(a2)
        if abs(a2 - alpha2) < self.eps * (a2 + alpha2 + self.eps):
            return False
        a1 = self.snap(alpha1 + y1 * y2 * (alpha2 - a2))
        t1 = y1 * (a1 - alpha1)
        t2 = y2 * (a2 - alpha2)
        b1 = error1 + t1 * k11 + t2 * k12 + self.b
        b2 = error2 + t1 * k12 + t2 * k22 + self.b
        if 0 < a1 < self.C:
            threshold = b1
        elif 0 < a2 < self.C:
            threshold = b2
        else:
            threshold = (b1 + b2) / 2
        delta = threshold - self.b
        for index in range(len(self.points)):
            self.errors[index] = self.errors[index] + (
                t1 * self.matrix[first][index] + t2 * self.matrix[second][index] - delta
            )
        if 0 < a1 < self.C:
            self.errors[first] = 0.0
        if 0 < a2 < self.C:
            self.errors[second] = 0.0
        self.alpha[first], self.alpha[second] = a1, a2
        self.b = threshold
        self.steps += 1
        self.clipping[clipping] += 1
        return True

    def examine(self, second):
        self.examined += 1
        residual = self.errors[second] * self.labels[second]
        violates = (
            residual < -self.tolerance and self.alpha[second] < self.C
        ) or (residual > self.tolerance and self.alpha[second] > 0)
        if not violates:
            return 0
        partner = None
        largest_difference = -1.0
        for index in range(len(self.points)):
            if index != second and self.nonbound(index):
                difference = abs(self.errors[index] - self.errors[second])
                if difference > largest_difference:
                    largest_difference = difference
                    partner = index
        if partner is not None and self.take(partner, second):
            self.choices["heuristic"] += 1
            return 1
        for first in range(len(self.points)):
            if self.nonbound(first) and self.take(first, second):
                self.choices["nonbound_loop"] += 1
                return 1
        for first in range(len(self.points)):
            if self.take(first, second):
                self.choices["full_loop"] += 1
                return 1
        return 0

    def fit(self):
        examine_all = True
        while True:
            examined_before = self.examined
            changed = 0
            for index in range(len(self.points)):
                if examine_all or self.nonbound(index):
                    changed += self.examine(index)
            if examine_all:
                self.full_passes += 1
            else:
                self.nonbound_passes += 1
            record = {
                "full": examine_all,
                "examined": self.examined - examined_before,
                "changed": changed,
            }
            if examine_all:
                record["alpha"] = self.alpha[:]
            self.records.append(record)
            if examine_all and changed == 0:
                self.converged = True
                break
            if self.passes == self.max_passes:
                break
            if examine_all:
                examine_all = False
            elif changed == 0:
                examine_all = True
        return self

    def decision(self, point):
        total = 0.0
        for index, alpha in enumerate(self.alpha):
            if alpha > 0:
                total += alpha * self.labels[index] * self.kernel.value(self.points[index], point)
        return total - self.b

    def training_decisions(self):
        values = []
        for row in self.matrix:
            total = 0.0
            for index, alpha in enumerate(self.alpha):
                if alpha > 0:
                    total += alpha * self.labels[index] * row[index]
            values.append(total - self.b)
        return values


def train(points, labels, kernel, matrix, coefficient, settings):
    return Model(points, labels, kernel, matrix, coefficient, settings).fit()
