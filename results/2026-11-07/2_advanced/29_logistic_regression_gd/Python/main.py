from fractions import Fraction
import math
import os

from dataset import (
    compute_statistics, expanded_names, expanded_values, expansion_tuples, read_inputs,
    standardize,
)
from logistic import average_loss, gradient, hessian, loss, objective, probability, score
from metrics import Confusion, auc, fixed, fraction, ratio, roc_points
from optimizers import (
    NEWTON_ITERATIONS, Minstd, cholesky, gradient_descent, newton_direction, newton_method,
    shuffle, solve, stochastic_gradient_descent,
)
import softmax


INPUT_DIRECTORY = "input"
OUTPUT_DIRECTORY = "output"
FOLDS = 5
MODEL_PAIRS = ((0, 1), (0, 2), (1, 2))
BINS = 10
DECILES = 10
HOSMER_GROUPS = 10
LEARNING_STEPS = 4
PROFILE_STEPS = 4
LISTED_ROWS = 5
CRITICAL_Z = 1.96
BOOTSTRAP_TAIL = 40
RESIDUAL_LIMIT = 2


class Data:
    def __init__(self, names, train, test, settings):
        self.names = names
        self.train = train
        self.test = test
        self.settings = settings
        self.tuples = expansion_tuples(len(names), settings.degree)
        self.feature_names = expanded_names(names, self.tuples)
        self.feature_count = len(self.tuples)
        self.degree_counts = [
            sum(1 for indices in self.tuples if len(indices) <= degree)
            for degree in range(1, settings.degree + 1)
        ]
        self.classes = max(example.label for example in train) + 1
        self.train_expanded = [expanded_values(self.tuples, row.values) for row in train]
        self.test_expanded = [expanded_values(self.tuples, row.values) for row in test]
        self.overall = compute_statistics(self.train_expanded, self.feature_count)
        self.train_vectors = [self.standardized(values) for values in self.train_expanded]
        self.test_vectors = [self.standardized(values) for values in self.test_expanded]
        self.train_targets = [self.target(example.label) for example in train]
        self.test_targets = [self.target(example.label) for example in test]
        self.train_labels = [example.label for example in train]
        self.test_labels = [example.label for example in test]
        self.mean_values = self.overall.means[:len(names)]

    def target(self, label):
        return 1 if label == self.settings.positive else 0

    def standardized(self, expanded):
        return standardize(expanded, self.overall, self.feature_count)

    def vector(self, values):
        return self.standardized(expanded_values(self.tuples, values))


class CrossValidation:
    def __init__(self, lam, fold_losses, losses, probabilities, errors):
        self.lam = lam
        self.fold_losses = fold_losses
        self.loss = sequential_sum(losses) / len(losses)
        self.probabilities = probabilities
        self.errors = errors


class Selection:
    def __init__(self, results):
        best = results[0]
        for result in results:
            if result.loss <= best.loss:
                best = result
        mean = sequential_sum(best.fold_losses) / FOLDS
        spread = sequential_sum((value - mean) * (value - mean) for value in best.fold_losses)
        self.best = best
        self.se = math.sqrt(spread / (FOLDS - 1)) / math.sqrt(FOLDS)
        limit = best.loss + self.se
        self.one_se = max(result.lam for result in results if result.loss <= limit)


class Evaluation:
    def __init__(self, weights, vectors, targets, threshold):
        self.probabilities = model_probabilities(weights, vectors)
        self.predictions = predict(self.probabilities, threshold)
        self.loss = average_loss(weights, vectors, targets)
        self.correct = count_equal(self.predictions, targets)
        self.auc = auc(self.probabilities, targets)


class BinaryModel:
    def __init__(self, name, checkpoints, data):
        threshold = data.settings.threshold
        self.name = name
        self.checkpoints = checkpoints
        self.weights = final_weights(checkpoints)
        self.train = Evaluation(self.weights, data.train_vectors, data.train_targets, threshold)
        self.test = Evaluation(self.weights, data.test_vectors, data.test_targets, threshold)
        self.roc = roc_points(self.test.probabilities, data.test_targets)


class SoftmaxModel:
    def __init__(self, checkpoints, data):
        self.checkpoints = checkpoints
        self.weights = final_weights(checkpoints)
        self.test_probabilities = [
            softmax.probabilities(self.weights, vector) for vector in data.test_vectors
        ]
        self.test_predictions = [
            softmax.predicted_class(values) for values in self.test_probabilities
        ]


class Influence:
    def __init__(self, weights, vectors, targets, lam):
        size = len(weights)
        count = len(vectors)
        self.matrix = inverse(hessian(weights, vectors, lam))
        self.probabilities = []
        self.leverages = []
        self.residuals = []
        self.distances = []
        for vector, target in zip(vectors, targets):
            pi = probability(score(weights, vector))
            variance = pi * (1 - pi)
            quadratic = 0.0
            for j in range(size):
                for k in range(size):
                    quadratic += vector[j] * self.matrix[j][k] * vector[k]
            leverage = variance * quadratic / count
            pearson = (target - pi) / math.sqrt(variance)
            self.probabilities.append(pi)
            self.leverages.append(leverage)
            self.residuals.append(pearson / math.sqrt(1 - leverage))
            self.distances.append(
                pearson * pearson * leverage / (size * ((1 - leverage) * (1 - leverage)))
            )
        self.edf = sequential_sum(self.leverages)
        self.deviance = 2 * count * average_loss(weights, vectors, targets)
        self.aic = self.deviance + 2 * self.edf
        self.bic = self.deviance + math.log(count) * self.edf


class Bin:
    def __init__(self):
        self.count = 0
        self.total = 0.0
        self.hits = 0


def sequential_sum(values):
    total = 0.0
    for value in values:
        total += value
    return total


def length(values):
    return math.sqrt(sequential_sum(value * value for value in values))


def final_weights(checkpoints):
    return checkpoints[-1][1]


def model_probabilities(weights, vectors):
    return [probability(score(weights, vector)) for vector in vectors]


def predict(probabilities, threshold):
    return [1 if value >= threshold else 0 for value in probabilities]


def count_equal(first, second):
    return sum(1 for a, b in zip(first, second) if a == b)


def softmax_correct(weights, vectors, labels):
    predictions = [softmax.predicted_class(softmax.probabilities(weights, v)) for v in vectors]
    return count_equal(predictions, labels)


def inverse(matrix):
    size = len(matrix)
    lower = cholesky(matrix)
    result = [[0.0] * size for _ in range(size)]
    for k in range(size):
        unit = [0.0] * size
        unit[k] = 1.0
        column = solve(lower, unit)
        for j in range(size):
            result[j][k] = column[j]
    return result


def original_units(weights, statistics):
    scaled = [weights[j + 1] / statistics.deviations[j] for j in range(len(weights) - 1)]
    shift = sequential_sum(value * mean for value, mean in zip(scaled, statistics.means))
    return [weights[0] - shift] + scaled


def bin_index(value):
    return min(BINS - 1, math.floor(value * BINS))


def bin_range(index):
    return f"{index / BINS:.1f}-{(index + 1) / BINS:.1f}"


def fill_bins(values, hits):
    bins = [Bin() for _ in range(BINS)]
    for value, hit in zip(values, hits):
        target = bins[bin_index(value)]
        target.count += 1
        target.total += value
        target.hits += hit
    return bins


def bin_lines(bins, mean_label, rate_label):
    lines = []
    for index, group in enumerate(bins):
        mean = fixed(group.total / group.count, 4) if group.count else "-"
        lines.append(
            f"bin {bin_range(index)} count {group.count} {mean_label} {mean} "
            f"{rate_label} {ratio(group.hits, group.count)}"
        )
    return lines


def calibration_error(bins, size):
    return sequential_sum(abs(group.total - group.hits) for group in bins if group.count) / size


def cross_validate(data, lam, count):
    size = len(data.train)
    threshold = data.settings.threshold
    losses = [0.0] * size
    probabilities = [0.0] * size
    fold_losses = []
    errors = 0
    for fold in range(FOLDS):
        fitting = [i for i in range(size) if i % FOLDS != fold]
        checking = [i for i in range(size) if i % FOLDS == fold]
        statistics = compute_statistics([data.train_expanded[i] for i in fitting], count)
        vectors = [standardize(data.train_expanded[i], statistics, count) for i in fitting]
        targets = [data.train_targets[i] for i in fitting]
        weights = final_weights(newton_method(vectors, targets, lam))
        fold_total = 0.0
        for i in checking:
            u = score(weights, standardize(data.train_expanded[i], statistics, count))
            losses[i] = loss(u, data.train_targets[i])
            probabilities[i] = probability(u)
            fold_total += losses[i]
            if (1 if probabilities[i] >= threshold else 0) != data.train_targets[i]:
                errors += 1
        fold_losses.append(fold_total / len(checking))
    return CrossValidation(lam, fold_losses, losses, probabilities, errors)


def term_lines(names, weights, statistics):
    original = original_units(weights, statistics)
    lines = [
        f"term intercept standardized {fixed(weights[0], 4)} original {fixed(original[0], 4)}"
    ]
    for name, weight, value in zip(names, weights[1:], original[1:]):
        lines.append(f"term {name} standardized {fixed(weight, 4)} original {fixed(value, 4)}")
    return lines


def features_part(data):
    settings = data.settings
    count = data.feature_count
    size = len(data.train)
    correlation = []
    for j in range(1, count + 1):
        row = []
        for k in range(1, count + 1):
            total = sequential_sum(vector[j] * vector[k] for vector in data.train_vectors)
            row.append(total / (size - 1))
        correlation.append(row)
    inflation = inverse(correlation)
    lines = [f"features {len(data.names)} degree {settings.degree} expanded {count}"]
    lines.append("standardization")
    for j, name in enumerate(data.feature_names):
        lines.append(
            f"{name} mean {fixed(data.overall.means[j], 6)} "
            f"sd {fixed(data.overall.deviations[j], 6)} vif {fixed(inflation[j][j], 4)}"
        )
    lines.append("correlation")
    lines.extend(" ".join(fixed(value, 4) for value in row) for row in correlation)
    return lines


def binary_weights_part(data, model, newton_weights, lam):
    lines = [f"model {model.name} lambda {fixed(lam, 4)}"]
    lines.extend(term_lines(data.feature_names, model.weights, data.overall))
    lines.append(f"norm {fixed(length(model.weights[1:]), 4)}")
    if model.name != "newton":
        differences = [a - b for a, b in zip(model.weights, newton_weights)]
        lines.append(f"distance_to_newton {fixed(length(differences), 6)}")
    return lines


def coefficient_part(data, weights, influence, lam):
    size = len(data.train)
    lines = [f"coefficients newton lambda {fixed(lam, 4)}"]
    for j, name in enumerate(["intercept"] + data.feature_names):
        weight = weights[j]
        error = math.sqrt(influence.matrix[j][j] / size)
        lines.append(
            f"{name} weight {fixed(weight, 4)} se {fixed(error, 4)} "
            f"z {fixed(weight / error, 4)} lower {fixed(weight - CRITICAL_Z * error, 4)} "
            f"upper {fixed(weight + CRITICAL_Z * error, 4)} "
            f"odds_ratio {fixed(math.exp(weight), 4)}"
        )
    return lines


def softmax_weights_part(data, model):
    lines = [f"model softmax lambda {fixed(data.settings.softmax_lambda, 4)}"]
    for k, weights in enumerate(model.weights):
        lines.append(f"class {k}")
        lines.extend(term_lines(data.feature_names, weights, data.overall))
    return lines


def loss_trace_lines(data, models, softmax_model, lam):
    lines = ["optimizer,iteration,loss,gradient_norm,test_loss"]
    for model in models:
        for t, weights in model.checkpoints:
            value = objective(weights, data.train_vectors, data.train_targets, lam)
            slope = length(gradient(weights, data.train_vectors, data.train_targets, lam))
            test_loss = average_loss(weights, data.test_vectors, data.test_targets)
            lines.append(
                f"{model.name},{t},{fixed(value, 6)},{fixed(slope, 6)},{fixed(test_loss, 6)}"
            )
    softmax_lambda = data.settings.softmax_lambda
    for t, weights in softmax_model.checkpoints:
        value = softmax.objective(weights, data.train_vectors, data.train_labels, softmax_lambda)
        steps = softmax.gradient(weights, data.train_vectors, data.train_labels, softmax_lambda)
        slope = length([step for row in steps for step in row])
        test_loss = softmax.average_loss(weights, data.test_vectors, data.test_labels)
        lines.append(f"softmax,{t},{fixed(value, 6)},{fixed(slope, 6)},{fixed(test_loss, 6)}")
    return lines


def prediction_lines(data, models, softmax_model):
    lines = ["id,model,probability,predicted,actual"]
    for model in models:
        for j, example in enumerate(data.test):
            lines.append(
                f"{example.ident},{model.name},{fixed(model.test.probabilities[j], 6)},"
                f"{model.test.predictions[j]},{data.test_targets[j]}"
            )
    for j, example in enumerate(data.test):
        predicted = softmax_model.test_predictions[j]
        confidence = softmax_model.test_probabilities[j][predicted]
        lines.append(f"{example.ident},softmax,{fixed(confidence, 6)},{predicted},{example.label}")
    return lines


def roc_lines(data, models):
    positives = sum(data.test_targets)
    negatives = len(data.test) - positives
    lines = ["model,threshold,tpr,fpr,precision"]
    for model in models:
        lines.append(f"{model.name},inf,0.0000,0.0000,-")
        for point in model.roc:
            lines.append(
                f"{model.name},{fixed(point.threshold, 6)},{ratio(point.tp, positives)},"
                f"{ratio(point.fp, negatives)},{ratio(point.tp, point.tp + point.fp)}"
            )
    return lines


def data_part(data):
    settings = data.settings
    size = len(data.train)
    test_size = len(data.test)
    train_counts = " ".join(str(data.train_labels.count(k)) for k in range(data.classes))
    test_counts = " ".join(str(data.test_labels.count(k)) for k in range(data.classes))
    return [
        f"data train {size} test {test_size} base_features {len(data.names)} "
        f"degree {settings.degree} features {data.feature_count}",
        f"binary positive_class {settings.positive} train {sum(data.train_targets)}/{size} "
        f"test {sum(data.test_targets)}/{test_size}",
        f"classes {data.classes} train {train_counts} test {test_counts}",
    ]


def cross_validation_part(data, results, selection):
    size = len(data.train)
    lines = [f"cross_validation folds {FOLDS} newton_iterations {NEWTON_ITERATIONS}"]
    for result in results:
        fold_losses = " ".join(fixed(value, 6) for value in result.fold_losses)
        lines.append(
            f"lambda {fixed(result.lam, 4)} fold_loss {fold_losses} "
            f"cv_loss {fixed(result.loss, 6)} errors {result.errors}/{size}"
        )
    best = selection.best
    lines.append(
        f"selected lambda {fixed(best.lam, 4)} cv_loss {fixed(best.loss, 6)} "
        f"se {fixed(selection.se, 6)} lambda_1se {fixed(selection.one_se, 4)}"
    )
    matrix = Confusion(predict(best.probabilities, data.settings.threshold), data.train_targets)
    lines.append(
        f"out_of_fold tp {matrix.tp} fp {matrix.fp} tn {matrix.tn} fn {matrix.fn} "
        f"accuracy {ratio(matrix.tp + matrix.tn, size)} "
        f"auc {fraction(*auc(best.probabilities, data.train_targets))}"
    )
    return lines


def lambda_path_part(data):
    threshold = data.settings.threshold
    lines = ["lambda_path"]
    for lam in data.settings.lambdas:
        weights = final_weights(newton_method(data.train_vectors, data.train_targets, lam))
        train = Evaluation(weights, data.train_vectors, data.train_targets, threshold)
        test = Evaluation(weights, data.test_vectors, data.test_targets, threshold)
        value = objective(weights, data.train_vectors, data.train_targets, lam)
        lines.append(
            f"lambda {fixed(lam, 4)} objective {fixed(value, 6)} "
            f"train_loss {fixed(train.loss, 6)} test_loss {fixed(test.loss, 6)} "
            f"train_accuracy {ratio(train.correct, len(data.train))} "
            f"test_accuracy {ratio(test.correct, len(data.test))} "
            f"norm {fixed(length(weights[1:]), 4)}"
        )
    return lines


def degree_part(data, lam):
    threshold = data.settings.threshold
    lines = [f"degrees lambda {fixed(lam, 4)}"]
    for degree, count in enumerate(data.degree_counts, 1):
        train_vectors = [vector[:count + 1] for vector in data.train_vectors]
        test_vectors = [vector[:count + 1] for vector in data.test_vectors]
        weights = final_weights(newton_method(train_vectors, data.train_targets, lam))
        validation = cross_validate(data, lam, count)
        train = Evaluation(weights, train_vectors, data.train_targets, threshold)
        test = Evaluation(weights, test_vectors, data.test_targets, threshold)
        influence = Influence(weights, train_vectors, data.train_targets, lam)
        lines.append(
            f"degree {degree} features {count} cv_loss {fixed(validation.loss, 6)} "
            f"train_loss {fixed(train.loss, 6)} test_loss {fixed(test.loss, 6)} "
            f"test_accuracy {ratio(test.correct, len(data.test))} auc {fraction(*test.auc)} "
            f"edf {fixed(influence.edf, 4)} aic {fixed(influence.aic, 4)} "
            f"bic {fixed(influence.bic, 4)}"
        )
    return lines


def learning_curve_part(data, lam):
    threshold = data.settings.threshold
    count = data.feature_count
    lines = [f"learning_curve lambda {fixed(lam, 4)}"]
    for step in range(1, LEARNING_STEPS + 1):
        size = step * len(data.train) // LEARNING_STEPS
        rows = data.train_expanded[:size]
        statistics = compute_statistics(rows, count)
        train_vectors = [standardize(values, statistics, count) for values in rows]
        test_vectors = [standardize(values, statistics, count) for values in data.test_expanded]
        targets = data.train_targets[:size]
        weights = final_weights(newton_method(train_vectors, targets, lam))
        train = Evaluation(weights, train_vectors, targets, threshold)
        test = Evaluation(weights, test_vectors, data.test_targets, threshold)
        lines.append(
            f"size {size} train_loss {fixed(train.loss, 6)} test_loss {fixed(test.loss, 6)} "
            f"test_accuracy {ratio(test.correct, len(data.test))} auc {fraction(*test.auc)}"
        )
    return lines


def cost_of(point, positives, settings):
    return settings.cost_fp * point.fp + settings.cost_fn * (positives - point.tp)


def average_precision(points, positives):
    total = 0.0
    previous = 0
    for point in points:
        total += (point.tp - previous) * point.tp / (point.tp + point.fp)
        previous = point.tp
    return total / positives


def calibration_lines(probabilities, targets):
    bins = fill_bins(probabilities, targets)
    lines = ["calibration"] + bin_lines(bins, "mean_probability", "positive_rate")
    filled = [group for group in bins if group.count]
    ece = calibration_error(bins, len(targets))
    mce = 0.0
    for group in filled:
        mce = max(mce, abs(group.total / group.count - group.hits / group.count))
    statistic = sequential_sum(
        (group.hits - group.total) * (group.hits - group.total)
        / (group.total * (1 - group.total / group.count))
        for group in filled
    )
    lines.append(
        f"ece {fixed(ece, 4)} mce {fixed(mce, 4)} hosmer_lemeshow {fixed(statistic, 4)} "
        f"groups {len(filled)}"
    )
    return lines


def gains_lines(probabilities, targets):
    size = len(targets)
    positives = sum(targets)
    order = sorted(range(size), key=lambda j: -probabilities[j])
    lines = ["gains"]
    for decile in range(1, DECILES + 1):
        rows = decile * size // DECILES
        hits = sum(targets[j] for j in order[:rows])
        lines.append(
            f"decile {decile} rows {rows} positives {hits} gain {ratio(hits, positives)} "
            f"lift {ratio(hits * size, rows * positives)}"
        )
    return lines


def binary_model_part(data, model, lam):
    settings = data.settings
    targets = data.test_targets
    size = len(targets)
    positives = sum(targets)
    negatives = size - positives
    matrix = Confusion(model.test.predictions, targets)
    tp, fp, tn, fn = matrix.tp, matrix.fp, matrix.tn, matrix.fn
    brier = sequential_sum(
        (pi - y) * (pi - y) for pi, y in zip(model.test.probabilities, targets)
    ) / size
    youden = max(model.roc, key=lambda point: point.tp * negatives - point.fp * positives)
    best_f1 = max(
        model.roc, key=lambda point: Fraction(2 * point.tp, positives + point.tp + point.fp)
    )
    cheapest = min(model.roc, key=lambda point: cost_of(point, positives, settings))
    lines = [
        f"model {model.name} lambda {fixed(lam, 4)}",
        f"train correct {model.train.correct}/{len(data.train)} "
        f"accuracy {ratio(model.train.correct, len(data.train))}",
        f"test tp {tp} fp {fp} tn {tn} fn {fn}",
        f"test accuracy {ratio(tp + tn, size)} precision {ratio(tp, tp + fp)} "
        f"recall {ratio(tp, tp + fn)} specificity {ratio(tn, tn + fp)} "
        f"f1 {ratio(2 * tp, 2 * tp + fp + fn)}",
        f"log_loss {fixed(model.test.loss, 6)} brier {fixed(brier, 6)}",
        f"auc {fraction(*model.test.auc)} "
        f"average_precision {fixed(average_precision(model.roc, positives), 4)}",
        f"youden threshold {fixed(youden.threshold, 6)} tpr {ratio(youden.tp, positives)} "
        f"fpr {ratio(youden.fp, negatives)} "
        f"j {ratio(youden.tp * negatives - youden.fp * positives, positives * negatives)}",
        f"best_f1 threshold {fixed(best_f1.threshold, 6)} "
        f"precision {ratio(best_f1.tp, best_f1.tp + best_f1.fp)} "
        f"recall {ratio(best_f1.tp, positives)} "
        f"f1 {ratio(2 * best_f1.tp, positives + best_f1.tp + best_f1.fp)}",
        f"min_cost threshold {fixed(cheapest.threshold, 6)} "
        f"cost {cost_of(cheapest, positives, settings)} fp {cheapest.fp} "
        f"fn {positives - cheapest.tp}",
    ]
    lines.extend(calibration_lines(model.test.probabilities, targets))
    lines.extend(gains_lines(model.test.probabilities, targets))
    return lines


def comparison_part(data, models):
    targets = data.test_targets
    size = len(targets)
    lines = []
    for first_index, second_index in MODEL_PAIRS:
        first = models[first_index]
        second = models[second_index]
        same = count_equal(first.test.predictions, second.test.predictions)
        only_first = 0
        only_second = 0
        for a, b, y in zip(first.test.predictions, second.test.predictions, targets):
            if a == y and b != y:
                only_first += 1
            elif b == y and a != y:
                only_second += 1
        gap = abs(only_first - only_second) - 1
        lines.append(
            f"agreement {first.name} {second.name} same {same}/{size} "
            f"only_first {only_first} only_second {only_second} "
            f"mcnemar {ratio(gap * gap, only_first + only_second)}"
        )
    return lines


def fit_line(data, model, influence):
    base_rate = sum(data.train_targets) / len(data.train)
    null_loss = -(base_rate * math.log(base_rate) + (1 - base_rate) * math.log(1 - base_rate))
    train_loss = model.train.loss
    return (
        f"fit null_loss {fixed(null_loss, 6)} train_loss {fixed(train_loss, 6)} "
        f"mcfadden_r2 {fixed(1 - train_loss / null_loss, 4)} "
        f"deviance {fixed(influence.deviance, 4)} edf {fixed(influence.edf, 4)} "
        f"aic {fixed(influence.aic, 4)} bic {fixed(influence.bic, 4)}"
    )


def hosmer_lemeshow_lines(data, influence):
    size = len(data.train)
    probabilities = influence.probabilities
    order = sorted(range(size), key=lambda i: probabilities[i])
    statistic = 0.0
    group_lines = []
    for group in range(1, HOSMER_GROUPS + 1):
        members = order[(group - 1) * size // HOSMER_GROUPS:group * size // HOSMER_GROUPS]
        observed = sum(data.train_targets[i] for i in members)
        expected = sequential_sum(probabilities[i] for i in members)
        statistic += (
            (observed - expected) * (observed - expected)
            / (expected * (1 - expected / len(members)))
        )
        group_lines.append(
            f"group {group} rows {len(members)} observed {observed} expected {fixed(expected, 4)}"
        )
    header = f"hosmer_lemeshow_train groups {HOSMER_GROUPS} statistic {fixed(statistic, 4)}"
    return [header] + group_lines


def iteration_lines(data, model, lam):
    lines = ["newton_iterations"]
    for t in range(1, NEWTON_ITERATIONS + 1):
        weights = model.checkpoints[t - 1][1]
        direction, step = newton_direction(weights, data.train_vectors, data.train_targets, lam)
        value = objective(weights, data.train_vectors, data.train_targets, lam)
        decrease = sequential_sum(g * delta for g, delta in zip(direction, step)) / 2
        lines.append(
            f"iteration {t} objective {fixed(value, 6)} "
            f"gradient_norm {fixed(length(direction), 6)} step_norm {fixed(length(step), 6)} "
            f"predicted_decrease {fixed(decrease, 6)}"
        )
    return lines


def slope(tuples, original, values, base):
    total = 0.0
    for j, indices in enumerate(tuples):
        occurrences = indices.count(base)
        if occurrences == 0:
            continue
        remaining = list(indices)
        remaining.remove(base)
        product = 1.0
        for index in remaining:
            product *= values[index]
        total += original[j + 1] * (occurrences * product)
    return total


def marginal_lines(data, model, influence):
    original = original_units(model.weights, data.overall)
    centre = probability(score(model.weights, data.vector(data.mean_values)))
    lines = []
    for base, name in enumerate(data.names):
        total = 0.0
        for example, pi in zip(data.train, influence.probabilities):
            total += pi * (1 - pi) * slope(data.tuples, original, example.values, base)
        average = total / len(data.train)
        at_mean = centre * (1 - centre) * slope(data.tuples, original, data.mean_values, base)
        lines.append(f"marginal {name} average {fixed(average, 4)} at_mean {fixed(at_mean, 4)}")
    return lines


def threshold_lines(data, model):
    size = len(data.test)
    lines = []
    for cut in range(1, 10):
        matrix = Confusion(predict(model.test.probabilities, cut / 10), data.test_targets)
        tp, fp, tn, fn = matrix.tp, matrix.fp, matrix.tn, matrix.fn
        lines.append(
            f"cut 0.{cut} positive {tp + fp} tp {tp} fp {fp} precision {ratio(tp, tp + fp)} "
            f"recall {ratio(tp, tp + fn)} accuracy {ratio(tp + tn, size)}"
        )
    return lines


def error_lines(data, model):
    threshold = data.settings.threshold
    probabilities = model.test.probabilities
    wrong = [j for j in range(len(data.test)) if model.test.predictions[j] != data.test_targets[j]]
    wrong.sort(key=lambda j: -abs(probabilities[j] - threshold))
    return [
        f"error {data.test[j].ident} actual {data.test_targets[j]} "
        f"probability {fixed(probabilities[j], 6)}"
        for j in wrong[:LISTED_ROWS]
    ]


def bootstrap_line(data, model):
    settings = data.settings
    size = len(data.test)
    count = settings.bootstrap_count
    generator = Minstd(settings.bootstrap_seed)
    samples = []
    for _ in range(count):
        picks = [generator.draw() % size for _ in range(size)]
        scores = [model.test.probabilities[j] for j in picks]
        targets = [data.test_targets[j] for j in picks]
        samples.append(auc(scores, targets))
    values = [numerator / denominator for numerator, denominator in samples]
    mean = sequential_sum(values) / count
    deviation = math.sqrt(
        sequential_sum((value - mean) * (value - mean) for value in values) / (count - 1)
    )
    ordered = sorted(samples, key=lambda sample: sample[0] / sample[1])
    tail = count // BOOTSTRAP_TAIL
    lower = ordered[tail]
    upper = ordered[count - tail - 1]
    return (
        f"bootstrap resamples {count} seed {settings.bootstrap_seed} "
        f"auc_mean {fixed(mean, 4)} auc_sd {fixed(deviation, 4)} "
        f"lower {fraction(*lower)} upper {fraction(*upper)}"
    )


def influence_lines(data, influence):
    size = len(data.train)
    large = sum(1 for value in influence.residuals if abs(value) > RESIDUAL_LIMIT)
    lines = [
        f"influence effective_parameters {fixed(influence.edf, 4)} large_residuals {large}"
    ]
    order = sorted(range(size), key=lambda i: -influence.distances[i])
    for i in order[:LISTED_ROWS]:
        lines.append(
            f"cook {data.train[i].ident} actual {data.train_targets[i]} "
            f"probability {fixed(influence.probabilities[i], 4)} "
            f"leverage {fixed(influence.leverages[i], 4)} "
            f"residual {fixed(influence.residuals[i], 4)} distance {fixed(influence.distances[i], 4)}"
        )
    return lines


def diagnostics_part(data, model, influence, lam):
    lines = [f"diagnostics newton lambda {fixed(lam, 4)}", fit_line(data, model, influence)]
    lines.extend(hosmer_lemeshow_lines(data, influence))
    lines.extend(iteration_lines(data, model, lam))
    lines.extend(marginal_lines(data, model, influence))
    lines.extend(threshold_lines(data, model))
    lines.extend(error_lines(data, model))
    lines.append(bootstrap_line(data, model))
    lines.extend(influence_lines(data, influence))
    return lines


def importance_part(data, model, softmax_model):
    settings = data.settings
    size = len(data.test)
    repeats = settings.permutation_count
    base_loss = model.test.loss
    base_auc, denominator = model.test.auc
    base_correct = count_equal(softmax_model.test_predictions, data.test_labels)
    lines = [
        f"importance repeats {repeats} seed {settings.permutation_seed}",
        f"baseline log_loss {fixed(base_loss, 6)} auc {fraction(base_auc, denominator)} "
        f"softmax_accuracy {ratio(base_correct, size)}",
    ]
    generator = Minstd(settings.permutation_seed)
    for base, name in enumerate(data.names):
        losses = []
        auc_total = 0
        correct_total = 0
        for _ in range(repeats):
            order = list(range(size))
            shuffle(order, generator)
            vectors = []
            for j, example in enumerate(data.test):
                values = list(example.values)
                values[base] = data.test[order[j]].values[base]
                vectors.append(data.vector(values))
            losses.append(average_loss(model.weights, vectors, data.test_targets))
            permuted_auc, _ = auc(model_probabilities(model.weights, vectors), data.test_targets)
            auc_total += permuted_auc
            correct_total += softmax_correct(softmax_model.weights, vectors, data.test_labels)
        increase = sequential_sum(losses) / repeats - base_loss
        lines.append(
            f"feature {name} log_loss_increase {fixed(increase, 6)} "
            f"auc {fraction(auc_total, repeats * denominator)} "
            f"softmax_accuracy {ratio(correct_total, repeats * size)}"
        )
    return lines


def profile_part(data, model, softmax_model):
    lines = ["profiles"]
    for base, name in enumerate(data.names):
        column = [example.values[base] for example in data.train]
        low = min(column)
        high = max(column)
        for step in range(PROFILE_STEPS + 1):
            values = list(data.mean_values)
            values[base] = low + (high - low) * step / PROFILE_STEPS
            vector = data.vector(values)
            newton_probability = probability(score(model.weights, vector))
            class_probabilities = softmax.probabilities(softmax_model.weights, vector)
            listed = " ".join(fixed(value, 4) for value in class_probabilities)
            lines.append(
                f"profile {name} value {fixed(values[base], 4)} "
                f"newton {fixed(newton_probability, 4)} softmax {listed}"
            )
    return lines


def confidence_lines(model, labels):
    confidences = []
    hits = []
    for values, predicted, label in zip(model.test_probabilities, model.test_predictions, labels):
        confidences.append(values[predicted])
        hits.append(1 if predicted == label else 0)
    bins = fill_bins(confidences, hits)
    lines = ["confidence"] + bin_lines(bins, "mean_confidence", "accuracy")
    lines.append(f"ece {fixed(calibration_error(bins, len(labels)), 4)}")
    return lines


def binary_view_line(data, model, newton_model):
    settings = data.settings
    targets = data.test_targets
    size = len(targets)
    scores = [values[settings.positive] for values in model.test_probabilities]
    log_loss = sequential_sum(
        -math.log(value if y == 1 else 1 - value) for value, y in zip(scores, targets)
    ) / size
    predictions = predict(scores, settings.threshold)
    correct = count_equal(predictions, targets)
    agreement = count_equal(predictions, newton_model.test.predictions)
    return (
        f"binary_view positive_class {settings.positive} auc {fraction(*auc(scores, targets))} "
        f"log_loss {fixed(log_loss, 6)} accuracy {ratio(correct, size)} "
        f"agreement_with_newton {agreement}/{size}"
    )


def softmax_part(data, model, newton_model):
    settings = data.settings
    classes = data.classes
    labels = data.test_labels
    size = len(labels)
    table = [[0] * classes for _ in range(classes)]
    for label, predicted in zip(labels, model.test_predictions):
        table[label][predicted] += 1
    row_totals = [sum(table[k]) for k in range(classes)]
    column_totals = [sum(table[c][k] for c in range(classes)) for k in range(classes)]
    lines = [
        f"softmax classes {classes} lambda {fixed(settings.softmax_lambda, 4)} "
        f"iterations {settings.softmax_iterations}",
        "confusion",
    ]
    lines.extend(" ".join(str(value) for value in row) for row in table)
    for k in range(classes):
        scores = [values[k] for values in model.test_probabilities]
        class_targets = [1 if label == k else 0 for label in labels]
        hits = table[k][k]
        lines.append(
            f"class {k} precision {ratio(hits, column_totals[k])} "
            f"recall {ratio(hits, row_totals[k])} "
            f"f1 {ratio(2 * hits, column_totals[k] + row_totals[k])} "
            f"auc {fraction(*auc(scores, class_targets))}"
        )
    diagonal = sum(table[k][k] for k in range(classes))
    chance = sum(row_totals[k] * column_totals[k] for k in range(classes))
    lines.append(
        f"accuracy {ratio(diagonal, size)} "
        f"kappa {ratio(size * diagonal - chance, size * size - chance)}"
    )
    log_loss = softmax.average_loss(model.weights, data.test_vectors, labels)
    squares = []
    for values, label in zip(model.test_probabilities, labels):
        squares.append(sequential_sum(
            (value - (1 if k == label else 0)) * (value - (1 if k == label else 0))
            for k, value in enumerate(values)
        ))
    brier = sequential_sum(squares) / size
    lines.append(f"log_loss {fixed(log_loss, 6)} brier {fixed(brier, 6)}")
    lines.append(binary_view_line(data, model, newton_model))
    lines.extend(confidence_lines(model, labels))
    return lines


def one_vs_rest_part(data, softmax_model):
    lam = data.settings.softmax_lambda
    size = len(data.test)
    lines = [f"one_vs_rest lambda {fixed(lam, 4)} newton_iterations {NEWTON_ITERATIONS}"]
    class_probabilities = []
    for k in range(data.classes):
        targets = [1 if label == k else 0 for label in data.train_labels]
        test_targets = [1 if label == k else 0 for label in data.test_labels]
        weights = final_weights(newton_method(data.train_vectors, targets, lam))
        test = Evaluation(weights, data.test_vectors, test_targets, data.settings.threshold)
        value = objective(weights, data.train_vectors, targets, lam)
        lines.append(f"class {k} objective {fixed(value, 6)} auc {fraction(*test.auc)}")
        class_probabilities.append(test.probabilities)
    predictions = []
    for j in range(size):
        column = [probabilities[j] for probabilities in class_probabilities]
        predictions.append(column.index(max(column)))
    correct = count_equal(predictions, data.test_labels)
    agreement = count_equal(predictions, softmax_model.test_predictions)
    lines.append(f"accuracy {ratio(correct, size)} agreement_with_softmax {agreement}/{size}")
    return lines


def map_part(data, model, softmax_model):
    settings = data.settings
    width = settings.map_width
    height = settings.map_height
    first = [example.values[0] for example in data.train]
    second = [example.values[1] for example in data.train]
    low_x, high_x = min(first), max(first)
    low_y, high_y = min(second), max(second)
    cells = [0] * data.classes
    class_rows = []
    probability_rows = []
    for r in range(height):
        class_row = []
        probability_row = []
        for c in range(width):
            values = list(data.mean_values)
            values[0] = low_x + (c + 0.5) * (high_x - low_x) / width
            values[1] = high_y - (r + 0.5) * (high_y - low_y) / height
            vector = data.vector(values)
            class_probabilities = softmax.probabilities(softmax_model.weights, vector)
            predicted = softmax.predicted_class(class_probabilities)
            cells[predicted] += 1
            class_row.append(str(predicted))
            probability_row.append(str(bin_index(probability(score(model.weights, vector)))))
        class_rows.append("".join(class_row))
        probability_rows.append("".join(probability_row))
    header = f"map {data.names[0]} {data.names[1]} width {width} height {height}"
    counts = "cells " + " ".join(str(count) for count in cells)
    return (
        [header, "softmax_classes"] + class_rows + [counts, "newton_probability"]
        + probability_rows
    )


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIRECTORY, name), "w", newline="\n") as file:
        file.write("\n".join(lines) + "\n")


def write_parts(name, parts):
    lines = []
    for part in parts:
        if lines:
            lines.append("")
        lines.extend(part)
    write_lines(name, lines)


def main():
    names, train, test, settings = read_inputs(INPUT_DIRECTORY)
    data = Data(names, train, test, settings)
    results = [cross_validate(data, lam, data.feature_count) for lam in settings.lambdas]
    selection = Selection(results)
    lam = selection.best.lam
    vectors = data.train_vectors
    targets = data.train_targets
    gd = gradient_descent(vectors, targets, lam, settings.gd_rate, settings.gd_iterations)
    sgd = stochastic_gradient_descent(
        vectors, targets, lam, settings.sgd_rate, settings.batch_size, settings.epochs,
        settings.sgd_seed,
    )
    newton_model = BinaryModel("newton", newton_method(vectors, targets, lam), data)
    models = [BinaryModel("gd", gd, data), BinaryModel("sgd", sgd, data), newton_model]
    softmax_checkpoints = softmax.train(
        vectors, data.train_labels, data.classes, settings.softmax_lambda,
        settings.softmax_rate, settings.softmax_iterations,
    )
    softmax_model = SoftmaxModel(softmax_checkpoints, data)
    influence = Influence(newton_model.weights, vectors, targets, lam)
    os.makedirs(OUTPUT_DIRECTORY, exist_ok=True)
    weight_parts = [features_part(data)]
    for model in models:
        weight_parts.append(binary_weights_part(data, model, newton_model.weights, lam))
    weight_parts.append(coefficient_part(data, newton_model.weights, influence, lam))
    weight_parts.append(softmax_weights_part(data, softmax_model))
    write_parts("weights.txt", weight_parts)
    write_lines("loss_trace.csv", loss_trace_lines(data, models, softmax_model, lam))
    write_lines("predictions.csv", prediction_lines(data, models, softmax_model))
    evaluation_parts = [
        data_part(data),
        cross_validation_part(data, results, selection),
        lambda_path_part(data),
        degree_part(data, lam),
        learning_curve_part(data, lam),
    ]
    for model in models:
        evaluation_parts.append(binary_model_part(data, model, lam))
    evaluation_parts.extend([
        comparison_part(data, models),
        diagnostics_part(data, newton_model, influence, lam),
        importance_part(data, newton_model, softmax_model),
        profile_part(data, newton_model, softmax_model),
        softmax_part(data, softmax_model, newton_model),
        one_vs_rest_part(data, softmax_model),
        map_part(data, newton_model, softmax_model),
    ])
    write_parts("evaluation.txt", evaluation_parts)
    write_lines("roc.csv", roc_lines(data, models))


if __name__ == "__main__":
    main()
