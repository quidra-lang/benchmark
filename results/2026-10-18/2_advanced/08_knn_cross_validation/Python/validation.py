from math import sqrt

from neighbors import estimate, neighbor_order, vote
from scaling import compute_scaling


class Model:
    def __init__(self, k, metric, weighting, scaling):
        self.k = k
        self.metric = metric
        self.weighting = weighting
        self.scaling = scaling

    def notation(self):
        return (
            f"k={self.k} metric={self.metric} "
            f"weighting={self.weighting} scaling={self.scaling}"
        )


class Prediction:
    def __init__(self, nearest, weighting):
        result = vote(nearest, weighting)
        self.label = result.label
        self.share = result.share
        self.runner_up = result.runner_up
        self.runner_share = result.runner_share
        self.estimate = estimate(nearest, weighting)
        self.neighbors = nearest


def stratified_folds(rows, count):
    ordered = sorted(range(len(rows)), key=lambda index: (rows[index].label, rows[index].ident))
    folds = [[] for _ in range(count)]
    for position, index in enumerate(ordered):
        folds[position % count].append(index)
    return [sorted(fold) for fold in folds]


def fold_training_rows(rows, fold):
    excluded = set(fold)
    return [row for index, row in enumerate(rows) if index not in excluded]


def neighbor_orders(training, queries, scaling_method, metric, features):
    scaling = compute_scaling(training, scaling_method)
    references = [(scaling.transform(row.values, features), row) for row in training]
    return [
        neighbor_order(scaling.transform(query.values, features), references, metric)
        for query in queries
    ]


def prediction_from_order(order, k, weighting):
    return Prediction(order[:k], weighting)


def predict_rows(model, training, queries, features):
    orders = neighbor_orders(training, queries, model.scaling, model.metric, features)
    return [prediction_from_order(order, model.k, model.weighting) for order in orders]


def predict(model, training, query, features):
    return predict_rows(model, training, [query], features)[0]


def rmse(errors):
    total = 0.0
    for error in errors:
        total += error * error
    return sqrt(total / len(errors))


def mae(errors):
    total = 0.0
    for error in errors:
        total += abs(error)
    return total / len(errors)


def r_squared(errors, targets):
    total = 0.0
    for target in targets:
        total += target
    mean = total / len(targets)
    residual = 0.0
    for error in errors:
        residual += error * error
    spread = 0.0
    for target in targets:
        spread += (target - mean) * (target - mean)
    return 1 - residual / spread
