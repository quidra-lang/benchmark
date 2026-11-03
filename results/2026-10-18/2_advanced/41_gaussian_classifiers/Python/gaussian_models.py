"""Fit and evaluate NB, LDA, and QDA directly from their definitions."""

from collections import namedtuple
from math import exp, log, pi

from linalg import cholesky, log_determinant, ordered_sum, quadratic_form, zeros


MODEL_NAMES = ("NB", "LDA", "QDA")
Prediction = namedtuple(
    "Prediction", "predicted posterior log_posterior confidence decision"
)


def argmax(values):
    best = 0
    for index in range(1, len(values)):
        if values[index] > values[best]:
            best = index
    return best


def argmin(values):
    best = 0
    for index in range(1, len(values)):
        if values[index] < values[best]:
            best = index
    return best


class Statistics:
    def __init__(self, rows, features, class_count):
        self.row_count = len(rows)
        self.feature_count = len(features)
        groups = [[] for _ in range(class_count)]
        vectors = []
        for row in rows:
            vector = [row.values[j] for j in features]
            vectors.append(vector)
            groups[row.class_index].append(vector)
        self.counts = [len(group) for group in groups]
        self.means = [
            [ordered_sum(vector[j] for vector in group) / len(group)
             for j in range(self.feature_count)]
            for group in groups
        ]
        self.scatter = []
        for group, mean in zip(groups, self.means):
            scatter = zeros(self.feature_count)
            for a in range(self.feature_count):
                for b in range(self.feature_count):
                    scatter[a][b] = ordered_sum(
                        (vector[a] - mean[a]) * (vector[b] - mean[b])
                        for vector in group
                    )
            self.scatter.append(scatter)
        self.center = [
            ordered_sum(vector[j] for vector in vectors) / self.row_count
            for j in range(self.feature_count)
        ]
        self.variances = [
            ordered_sum(
                (vector[j] - self.center[j]) * (vector[j] - self.center[j])
                for vector in vectors
            ) / self.row_count
            for j in range(self.feature_count)
        ]

    def pooled_covariance(self):
        divisor = self.row_count - len(self.counts)
        return [
            [ordered_sum(scatter[a][b] for scatter in self.scatter) / divisor
             for b in range(self.feature_count)]
            for a in range(self.feature_count)
        ]


class GaussianModel:
    def __init__(self, name, features, statistics, prior_mode, epsilon, gamma):
        self.name = name
        self.features = tuple(features)
        self.statistics = statistics
        self.means = statistics.means
        self.epsilon = epsilon
        self.gamma = gamma
        class_count = len(statistics.counts)
        if prior_mode == "empirical":
            self.priors = [count / statistics.row_count for count in statistics.counts]
        else:
            self.priors = [1 / class_count] * class_count
        self.max_variance = max(statistics.variances)
        self.added_variance = epsilon * self.max_variance
        self.covariances = []
        if name == "LDA":
            pooled = statistics.pooled_covariance()
            self.covariances = [pooled] * class_count
        else:
            for count, scatter in zip(statistics.counts, statistics.scatter):
                covariance = zeros(len(features))
                for a in range(len(features)):
                    for b in range(len(features)):
                        if name == "NB":
                            if a == b:
                                covariance[a][b] = scatter[a][b] / count + self.added_variance
                        else:
                            value = scatter[a][b] / (count - 1)
                            covariance[a][b] = value if a == b else value * (1 - gamma)
                self.covariances.append(covariance)
        if name == "LDA":
            lower = cholesky(self.covariances[0])
            self.factors = [lower] * class_count
            self.log_determinants = [log_determinant(lower)] * class_count
        else:
            self.factors = [cholesky(matrix) for matrix in self.covariances]
            self.log_determinants = [log_determinant(lower) for lower in self.factors]
        self.log_priors = [log(prior) for prior in self.priors]
        self.normalizer = len(features) * log(2 * pi) / 2

    def vector(self, values):
        return [values[j] for j in self.features]

    def squared_distances(self, vector):
        return [
            quadratic_form(lower, [value - center for value, center in zip(vector, mean)])
            for lower, mean in zip(self.factors, self.means)
        ]

    def distances(self, values):
        return self.squared_distances(self.vector(values))

    def scores(self, vector):
        distances = self.squared_distances(vector)
        return [
            prior - self.normalizer - determinant / 2 - distance / 2
            for prior, determinant, distance in zip(
                self.log_priors, self.log_determinants, distances
            )
        ]

    def predict_vector(self, vector):
        return argmax(self.scores(vector))

    def predict(self, values):
        return self.predict_vector(self.vector(values))

    def infer_vector(self, vector, costs=None):
        scores = self.scores(vector)
        predicted = argmax(scores)
        maximum = scores[predicted]
        exponentials = [exp(score - maximum) for score in scores]
        total = ordered_sum(exponentials)
        probabilities = [value / total for value in exponentials]
        log_total = log(total)
        log_probabilities = [(score - maximum) - log_total for score in scores]
        decision = predicted
        if costs is not None:
            risks = [
                ordered_sum(probabilities[k] * costs[k][b] for k in range(len(scores)))
                for b in range(len(scores))
            ]
            decision = argmin(risks)
        return Prediction(
            predicted, probabilities, log_probabilities, max(probabilities), decision
        )

    def infer(self, values, costs=None):
        return self.infer_vector(self.vector(values), costs)


def train_model(rows, features, class_count, name, prior_mode, epsilon, gamma):
    statistics = Statistics(rows, features, class_count)
    return GaussianModel(name, features, statistics, prior_mode, epsilon, gamma)
