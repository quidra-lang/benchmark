"""Train six binary models and apply the specified multiclass tie rules."""

from collections import namedtuple

from kernels import submatrix
from smo import train


PAIRS = ((1, 2), (1, 3), (2, 3))
Classification = namedtuple("Classification", "ovr_values ovo_values ovr ovo votes tied")


class MulticlassModels:
    def __init__(self, examples, kernel, coefficient, settings):
        self.kernel = kernel
        self.C = coefficient
        points = [example.point for example in examples]
        classes = [example.class_number for example in examples]
        matrix = kernel.matrix(points)
        self.ovr_models = []
        for class_number in range(1, 4):
            labels = [1 if value == class_number else -1 for value in classes]
            self.ovr_models.append(train(points, labels, kernel, matrix, coefficient, settings))
        self.ovo_models = []
        for first, second in PAIRS:
            indices = [i for i, value in enumerate(classes) if value in (first, second)]
            pair_points = [points[i] for i in indices]
            labels = [1 if classes[i] == first else -1 for i in indices]
            pair_matrix = submatrix(matrix, indices)
            self.ovo_models.append(
                train(pair_points, labels, kernel, pair_matrix, coefficient, settings)
            )

    def classify(self, point):
        rest_values = [model.decision(point) for model in self.ovr_models]
        rest_prediction = 1
        for index in range(1, 3):
            if rest_values[index] > rest_values[rest_prediction - 1]:
                rest_prediction = index + 1
        pair_values = []
        votes = [0, 0, 0]
        scores = [0.0, 0.0, 0.0]
        for (first, second), model in zip(PAIRS, self.ovo_models):
            value = model.decision(point)
            pair_values.append(value)
            winner = first if value > 0 else second
            votes[winner - 1] += 1
            scores[first - 1] += value
            scores[second - 1] -= value
        most_votes = max(votes)
        candidates = [index for index in range(3) if votes[index] == most_votes]
        pair_prediction = candidates[0]
        for index in candidates[1:]:
            if scores[index] > scores[pair_prediction]:
                pair_prediction = index
        return Classification(
            rest_values, pair_values, rest_prediction, pair_prediction + 1,
            votes, len(candidates) > 1
        )
