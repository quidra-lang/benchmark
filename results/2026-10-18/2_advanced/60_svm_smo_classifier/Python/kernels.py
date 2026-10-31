"""Kernel definitions and complete, ordered training matrices."""

from math import exp

from evaluation import fixed


class Kernel:
    def __init__(self, name, kind, *arguments):
        self.name = name
        self.kind = kind
        if kind == "poly":
            self.degree = int(arguments[0])
            self.gamma = float(arguments[1])
            self.coef0 = float(arguments[2])
        elif kind == "rbf":
            self.gamma = float(arguments[0])

    def value(self, first, second):
        if self.kind == "rbf":
            e1 = first[0] - second[0]
            e2 = first[1] - second[1]
            return exp(-self.gamma * (e1 * e1 + e2 * e2))
        dot = first[0] * second[0] + first[1] * second[1]
        if self.kind == "linear":
            return dot
        factor = self.gamma * dot + self.coef0
        value = 1.0
        for _ in range(self.degree):
            value *= factor
        return value

    def description(self):
        if self.kind == "linear":
            return "linear"
        if self.kind == "rbf":
            return f"rbf gamma {fixed(self.gamma)}"
        return (
            f"poly degree {self.degree} gamma {fixed(self.gamma)} "
            f"coef0 {fixed(self.coef0)}"
        )

    def matrix(self, points):
        return [[self.value(first, second) for second in points] for first in points]


def submatrix(matrix, indices):
    return [[matrix[i][j] for j in indices] for i in indices]
