from math import sqrt


class Scaling:
    def __init__(self, centers, scales):
        self.centers = centers
        self.scales = scales

    def transform(self, values, features):
        vector = []
        for feature in features:
            scale = self.scales[feature]
            if scale > 0:
                vector.append((values[feature] - self.centers[feature]) / scale)
            else:
                vector.append(0.0)
        return vector


def standard_parameters(column):
    total = 0.0
    for value in column:
        total += value
    center = total / len(column)
    if len(column) == 1:
        return center, 0.0
    squares = 0.0
    for value in column:
        squares += (value - center) * (value - center)
    return center, sqrt(squares / (len(column) - 1))


def minmax_parameters(column):
    lowest = min(column)
    return lowest, max(column) - lowest


def compute_scaling(rows, method):
    centers = []
    scales = []
    for feature in range(len(rows[0].values)):
        column = [row.values[feature] for row in rows]
        if method == "standard":
            center, scale = standard_parameters(column)
        else:
            center, scale = minmax_parameters(column)
        centers.append(center)
        scales.append(scale)
    return Scaling(centers, scales)
