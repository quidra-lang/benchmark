"""Generate the five grain-classifier reports from the four input files."""

from collections import namedtuple
from itertools import combinations
from math import floor, log, sqrt

from dataset import read_inputs
from evaluation import RandomGenerator, mcnemar, measures
from gaussian_models import MODEL_NAMES, argmax, argmin, train_model
from linalg import backward, cholesky, dot, forward, jacobi, log_determinant
from linalg import ordered_sum, quadratic_form, zeros
from plot import cell, fraction_text, frame, join_sections, ratio_text, real, reals, write_lines


CrossValidation = namedtuple("CrossValidation", "predictions fold_correct correct")


def confusion_lines(classes, matrix):
    return [
        f"confusion {name} " + " ".join(str(value) for value in counts)
        for name, counts in zip(classes, matrix)
    ]


def comparison_lines(title, names, predictions, actual):
    lines = [title]
    for a, b in combinations(range(len(names)), 2):
        b01, b10, chi2, significant = mcnemar(actual, predictions[a], predictions[b])
        lines.append(
            f"{names[a]} {names[b]} b01 {b01} b10 {b10} chi2 {real(chi2)} "
            f"significant {'yes' if significant else 'no'}"
        )
    return lines


def point_grid(points, actual, letters, limits, size):
    xmin, xmax, ymin, ymax = limits
    width, height = size
    grid = [[" "] * width for _ in range(height)]
    for (x, y), class_index in zip(points, actual):
        column = cell(x, xmin, xmax, width)
        row = height - 1 - cell(y, ymin, ymax, height)
        letter = letters[class_index]
        previous = grid[row][column]
        grid[row][column] = letter if previous in (" ", letter) else "*"
    return grid


def nearest_centroid_correct(points, actual, centroids, dimensions):
    correct = 0
    for point, expected in zip(points, actual):
        distances = []
        for centroid in centroids:
            difference = point[0] - centroid[0]
            distance = difference * difference
            if dimensions == 2:
                difference = point[1] - centroid[1]
                distance = distance + difference * difference
            distances.append(distance)
        correct += argmin(distances) == expected
    return correct


class Analysis:
    def __init__(self, data):
        self.data = data
        self.params = data.params
        self.features = data.features
        self.classes = data.classes
        self.train = data.train
        self.test = data.test
        self.n, self.m = len(self.train), len(self.test)
        self.d, self.class_count = len(self.features), len(self.classes)
        self.all_features = tuple(range(self.d))
        self.train_actual = [row.class_index for row in self.train]
        self.test_actual = [row.class_index for row in self.test]
        self.upper_letters = [name[0].upper() for name in self.classes]
        self.lower_letters = [name[0] for name in self.classes]
        self.folds = [row.id % self.params.folds for row in self.train]
        self.fold_sizes = [self.folds.count(fold) for fold in range(self.params.folds)]
        self.cv_cache = {}
        self.main_models = [self.fit(name) for name in MODEL_NAMES]
        self.results = [
            [model.infer(row.values, self.data.costs) for row in self.test]
            for model in self.main_models
        ]
        self.predictions = [[result.predicted for result in results] for results in self.results]

    def fit(self, name, features=None, rows=None, prior_mode=None, epsilon=None, gamma=None):
        return train_model(
            self.train if rows is None else rows,
            self.all_features if features is None else features,
            self.class_count,
            name,
            self.params.prior if prior_mode is None else prior_mode,
            self.params.epsilon if epsilon is None else epsilon,
            self.params.gamma if gamma is None else gamma,
        )

    def cross_validate(self, name, features, epsilon=None, gamma=None):
        features = tuple(features)
        epsilon = self.params.epsilon if epsilon is None else epsilon
        gamma = self.params.gamma if gamma is None else gamma
        key = name, features, epsilon, gamma
        if key in self.cv_cache:
            return self.cv_cache[key]
        predictions = [0] * self.n
        fold_correct = []
        for fold in range(self.params.folds):
            retained = [row for row, assigned in zip(self.train, self.folds) if assigned != fold]
            model = self.fit(name, features, retained, epsilon=epsilon, gamma=gamma)
            correct = 0
            for index, row in enumerate(self.train):
                if self.folds[index] == fold:
                    predictions[index] = model.predict(row.values)
                    correct += predictions[index] == row.class_index
            fold_correct.append(correct)
        result = CrossValidation(predictions, fold_correct, sum(fold_correct))
        self.cv_cache[key] = result
        return result

    def model_sections(self):
        nb, lda, qda = self.main_models
        statistics = nb.statistics
        sections = []
        lines = [
            "features " + " ".join(self.features),
            "classes " + " ".join(self.classes),
            f"prior_mode {self.params.prior}",
        ]
        for k, name in enumerate(self.classes):
            lines.append(
                f"class {name} letter {self.upper_letters[k]} count {statistics.counts[k]} "
                f"prior {real(nb.priors[k])} mean {reals(statistics.means[k])}"
            )
        sections.append(lines)
        lines = [
            "model NB",
            f"smoothing epsilon {real(nb.epsilon)} max_variance {real(nb.max_variance)} "
            f"added {real(nb.added_variance)}",
        ]
        for k, name in enumerate(self.classes):
            diagonal = [nb.covariances[k][j][j] for j in range(self.d)]
            lines.append(
                f"class {name} variance {reals(diagonal)} log_det {real(nb.log_determinants[k])}"
            )
        sections.append(lines)
        lower = lda.factors[0]
        lines = ["model LDA", f"log_det {real(lda.log_determinants[0])}"]
        lines.extend("  " + reals(row) for row in lda.covariances[0])
        for k, name in enumerate(self.classes):
            coefficients = backward(lower, forward(lower, lda.means[k]))
            intercept = log(lda.priors[k]) - dot(lda.means[k], coefficients) / 2
            lines.append(f"class {name} intercept {real(intercept)} coef {reals(coefficients)}")
        sections.append(lines)
        lines = [f"model QDA gamma {real(qda.gamma)}"]
        for k, name in enumerate(self.classes):
            eigenvalues, _, _ = jacobi(qda.covariances[k])
            eigenvalues.sort(reverse=True)
            condition = eigenvalues[0] / eigenvalues[-1]
            lines.append(
                f"class {name} log_det {real(qda.log_determinants[k])} "
                f"eigenvalues {reals(eigenvalues)} condition {real(condition)}"
            )
            lines.extend("  " + reals(row) for row in qda.covariances[k])
        sections.append(lines)
        lines = ["separation"]
        for a, b in combinations(range(self.class_count), 2):
            difference = [statistics.means[a][j] - statistics.means[b][j] for j in range(self.d)]
            mahalanobis = sqrt(quadratic_form(lower, difference))
            average = [
                [(qda.covariances[a][i][j] + qda.covariances[b][i][j]) / 2
                 for j in range(self.d)]
                for i in range(self.d)
            ]
            average_lower = cholesky(average)
            bhattacharyya = quadratic_form(average_lower, difference) / 8 + (
                log_determinant(average_lower)
                - (qda.log_determinants[a] + qda.log_determinants[b]) / 2
            ) / 2
            lines.append(
                f"{self.classes[a]} {self.classes[b]} mahalanobis {real(mahalanobis)} "
                f"bhattacharyya {real(bhattacharyya)}"
            )
        sections.append(lines)
        outliers = []
        for index, row in enumerate(self.train):
            distance = qda.distances(row.values)[row.class_index]
            if distance > self.params.outlier_threshold:
                outliers.append((distance, index, row))
        outliers.sort(key=lambda item: (-item[0], item[1]))
        lines = [f"outliers threshold {real(self.params.outlier_threshold)}"]
        lines.extend(f"{row.id} {row.label} q {real(distance)}" for distance, _, row in outliers)
        lines.append(f"count {len(outliers)}")
        sections.append(lines)
        return sections

    def prediction_lines(self):
        lines = ["id,model,actual,predicted,decision," + ",".join(self.classes)]
        for index, row in enumerate(self.test):
            for model_index, name in enumerate(MODEL_NAMES):
                result = self.results[model_index][index]
                fields = [
                    str(row.id), name, row.label,
                    self.classes[result.predicted], self.classes[result.decision],
                ]
                fields.extend(real(probability) for probability in result.posterior)
                lines.append(",".join(fields))
        return lines

    def model_evaluation(self, model_index):
        results = self.results[model_index]
        metrics = measures(self.test_actual, self.predictions[model_index], self.class_count)
        lines = [f"model {MODEL_NAMES[model_index]}"]
        lines.extend(confusion_lines(self.classes, metrics["matrix"]))
        for key in ("accuracy", "balanced_accuracy", "kappa"):
            lines.append(f"{key} {fraction_text(metrics[key])}")
        for k, name in enumerate(self.classes):
            lines.append(
                f"class {name} support {metrics['support'][k]} "
                f"recall {fraction_text(metrics['recall'][k])} "
                f"precision {fraction_text(metrics['precision'][k])} "
                f"f1 {fraction_text(metrics['f1'][k])}"
            )
        log_loss = -ordered_sum(
            result.log_posterior[row.class_index] for row, result in zip(self.test, results)
        ) / self.m
        lines.extend([f"macro_f1 {real(metrics['macro_f1'])}", f"log_loss {real(log_loss)}"])
        errors = [(row, result) for row, result in zip(self.test, results)
                  if result.predicted != row.class_index]
        lines.append(f"errors {len(errors)}")
        for row, result in errors:
            lines.append(
                f"error {row.id} actual {row.label} predicted {self.classes[result.predicted]} "
                f"confidence {real(result.confidence)}"
            )
        edges = [0.0, *self.params.calibration_edges, 1.0]
        calibration_error = 0.0
        for bin_index, (low, high) in enumerate(zip(edges, edges[1:])):
            last_bin = bin_index == len(edges) - 2
            indices = [
                index for index, result in enumerate(results)
                if result.confidence >= low
                and (result.confidence < high or (last_bin and result.confidence == high))
            ]
            count = len(indices)
            confidence_sum = ordered_sum(results[index].confidence for index in indices)
            correct = sum(results[index].predicted == self.test_actual[index] for index in indices)
            confidence_text = real(confidence_sum / count) if count else "-"
            lines.append(
                f"bin {real(low)} {real(high)} count {count} confidence {confidence_text} "
                f"accuracy {ratio_text(correct, count)}"
            )
            calibration_error += abs(correct - confidence_sum)
        lines.append(f"ece {real(calibration_error / self.m)}")
        for threshold in self.params.reject_thresholds:
            indices = [index for index, result in enumerate(results) if result.confidence >= threshold]
            count = len(indices)
            correct = sum(results[index].predicted == self.test_actual[index] for index in indices)
            lines.append(
                f"reject {real(threshold)} accepted {count} coverage {ratio_text(count, self.m)} "
                f"accuracy {ratio_text(correct, count)}"
            )
        return lines

    def ensemble_predictions(self):
        predictions = []
        for index in range(self.m):
            posterior = [
                ordered_sum(self.results[model][index].posterior[k] for model in range(3)) / 3
                for k in range(self.class_count)
            ]
            predictions.append(argmax(posterior))
        return predictions

    def cost_lines(self):
        lines = ["costs"]
        for name, results in zip(MODEL_NAMES, self.results):
            argmax_total = ordered_sum(
                self.data.costs[row.class_index][result.predicted]
                for row, result in zip(self.test, results)
            )
            decision_total = ordered_sum(
                self.data.costs[row.class_index][result.decision]
                for row, result in zip(self.test, results)
            )
            changed = sum(result.predicted != result.decision for result in results)
            correct = sum(row.class_index == result.decision for row, result in zip(self.test, results))
            lines.append(
                f"{name} argmax_total {real(argmax_total)} decision_total {real(decision_total)} "
                f"changed {changed} decision_accuracy {ratio_text(correct, self.m)}"
            )
        return lines

    def novelty_lines(self):
        novel = []
        for index, row in enumerate(self.test):
            distances = self.main_models[2].distances(row.values)
            nearest = argmin(distances)
            distance = distances[nearest]
            if distance > self.params.outlier_threshold:
                novel.append((distance, index, row.id, nearest))
        novel.sort(key=lambda item: (-item[0], item[1]))
        lines = [f"novelty threshold {real(self.params.outlier_threshold)}"]
        for distance, _, identifier, nearest in novel:
            lines.append(f"{identifier} nearest {self.classes[nearest]} q {real(distance)}")
        lines.append(f"count {len(novel)}")
        return lines

    def bootstrap_lines(self):
        count = self.params.bootstrap_count
        generator = RandomGenerator(self.params.seed)
        resamples = [[] for _ in MODEL_NAMES]
        for _ in range(count):
            correct = [0] * 3
            for _ in range(self.m):
                index = generator.draw() % self.m
                for model in range(3):
                    correct[model] += self.predictions[model][index] == self.test_actual[index]
            for model in range(3):
                resamples[model].append(correct[model])
        lines = [f"bootstrap resamples {count} seed {self.params.seed}"]
        offset = count // 40
        for name, counts in zip(MODEL_NAMES, resamples):
            ordered = sorted(counts)
            mean = sum(counts) / count / self.m
            lines.append(
                f"{name} mean {real(mean)} interval {ratio_text(ordered[offset], self.m)} "
                f"{ratio_text(ordered[-offset - 1], self.m)}"
            )
        for a, b in combinations(range(3), 2):
            wins = sum(left > right for left, right in zip(resamples[a], resamples[b]))
            ties = sum(left == right for left, right in zip(resamples[a], resamples[b]))
            losses = count - wins - ties
            lines.append(f"{MODEL_NAMES[a]} {MODEL_NAMES[b]} wins {wins} ties {ties} losses {losses}")
        return lines

    def prior_lines(self):
        alternative = "uniform" if self.params.prior == "empirical" else "empirical"
        lines = [f"prior_sensitivity alternative {alternative}"]
        for model_index, name in enumerate(MODEL_NAMES):
            model = self.fit(name, prior_mode=alternative)
            predictions = [model.predict(row.values) for row in self.test]
            metrics = measures(self.test_actual, predictions, self.class_count)
            changed = sum(a != b for a, b in zip(predictions, self.predictions[model_index]))
            lines.append(
                f"{name} accuracy {fraction_text(metrics['accuracy'])} "
                f"balanced_accuracy {fraction_text(metrics['balanced_accuracy'])} changed {changed}"
            )
        return lines

    def learning_curve_lines(self):
        lines = ["learning_curve"]
        for size in self.params.curve:
            taken = [0] * self.class_count
            rows = []
            for row in self.train:
                if taken[row.class_index] < size:
                    rows.append(row)
                    taken[row.class_index] += 1
            fields = [f"size {size} rows {len(rows)}"]
            for name in MODEL_NAMES:
                model = self.fit(name, rows=rows)
                correct = sum(model.predict(row.values) == row.class_index for row in self.test)
                fields.append(f"{name} {ratio_text(correct, self.m)}")
            lines.append(" ".join(fields))
        return lines

    def subset_lines(self):
        lines = [
            f"cross_validation folds {self.params.folds}",
            "fold_sizes " + " ".join(str(size) for size in self.fold_sizes),
        ]
        best_key = None
        best = None
        for subset_index, (subset_name, features) in enumerate(self.params.subsets):
            names = " ".join(self.features[index] for index in features)
            lines.append(f"subset {subset_name} features {names}")
            for model_index, name in enumerate(MODEL_NAMES):
                result = self.cross_validate(name, features)
                counts = " ".join(str(count) for count in result.fold_correct)
                lines.append(
                    f"  {name} fold_correct {counts} correct {result.correct} "
                    f"accuracy {ratio_text(result.correct, self.n)}"
                )
                key = -result.correct, len(features), subset_index, model_index
                if best_key is None or key < best_key:
                    best_key = key
                    best = subset_name, features, name, result.correct
        subset_name, features, name, correct = best
        lines.append(
            f"best subset {subset_name} model {name} correct {correct} "
            f"accuracy {ratio_text(correct, self.n)}"
        )
        model = self.fit(name, features)
        correct = sum(model.predict(row.values) == row.class_index for row in self.test)
        lines.append(f"refit_test correct {correct} accuracy {ratio_text(correct, self.m)}")
        return lines

    def leave_one_out_lines(self):
        lines = ["leave_one_out"]
        for name in MODEL_NAMES:
            correct = 0
            for index, row in enumerate(self.train):
                rows = self.train[:index] + self.train[index + 1:]
                model = self.fit(name, rows=rows)
                correct += model.predict(row.values) == row.class_index
            lines.append(f"{name} correct {correct} accuracy {ratio_text(correct, self.n)}")
        return lines

    def forward_selection_sections(self):
        sections = []
        for name in MODEL_NAMES:
            lines = [f"forward_selection model {name}"]
            selected = []
            best_step, best_correct = 0, -1
            for step in range(1, self.d + 1):
                added, step_correct = None, -1
                for feature in self.all_features:
                    if feature in selected:
                        continue
                    result = self.cross_validate(name, [*selected, feature])
                    if result.correct > step_correct:
                        added, step_correct = feature, result.correct
                selected.append(added)
                lines.append(
                    f"step {step} add {self.features[added]} correct {step_correct} "
                    f"accuracy {ratio_text(step_correct, self.n)}"
                )
                if step_correct > best_correct:
                    best_step, best_correct = step, step_correct
            names = " ".join(self.features[feature] for feature in selected[:best_step])
            lines.append(f"best_step {best_step} features {names}")
            sections.append(lines)
        return sections

    def tuning_lines(self, name, parameter, values, title):
        lines = [title]
        best_value, best_correct = None, -1
        for value in values:
            result = self.cross_validate(name, self.all_features, **{parameter: value})
            lines.append(
                f"value {real(value)} correct {result.correct} "
                f"accuracy {ratio_text(result.correct, self.n)}"
            )
            # A later grid entry wins an equal score, even if its value is smaller.
            if result.correct >= best_correct:
                best_value, best_correct = value, result.correct
        model = self.fit(name, **{parameter: best_value})
        correct = sum(model.predict(row.values) == row.class_index for row in self.test)
        lines.append(f"best {real(best_value)} test correct {correct} accuracy {ratio_text(correct, self.m)}")
        return lines

    def evaluation_sections(self):
        sections = [[f"test rows {self.m}"]]
        sections.extend(self.model_evaluation(index) for index in range(3))
        ensemble = self.ensemble_predictions()
        metrics = measures(self.test_actual, ensemble, self.class_count)
        sections.append([
            "ensemble soft_vote",
            f"accuracy {fraction_text(metrics['accuracy'])} "
            f"balanced_accuracy {fraction_text(metrics['balanced_accuracy'])} "
            f"kappa {fraction_text(metrics['kappa'])}",
        ])
        sections.append(comparison_lines(
            "mcnemar test", (*MODEL_NAMES, "ENSEMBLE"), [*self.predictions, ensemble], self.test_actual
        ))
        sections.extend([
            self.cost_lines(), self.novelty_lines(), self.bootstrap_lines(),
            self.prior_lines(), self.learning_curve_lines(), self.subset_lines(),
        ])
        cross_validation = [self.cross_validate(name, self.all_features) for name in MODEL_NAMES]
        sections.append(comparison_lines(
            "mcnemar cross_validation", MODEL_NAMES,
            [result.predictions for result in cross_validation], self.train_actual,
        ))
        for name, result in zip(MODEL_NAMES, cross_validation):
            metrics = measures(self.train_actual, result.predictions, self.class_count)
            lines = [f"cv_confusion model {name}"]
            lines.extend(confusion_lines(self.classes, metrics["matrix"]))
            lines.append(
                f"balanced_accuracy {fraction_text(metrics['balanced_accuracy'])} "
                f"kappa {fraction_text(metrics['kappa'])}"
            )
            sections.append(lines)
        sections.append(self.leave_one_out_lines())
        sections.extend(self.forward_selection_sections())
        sections.append(self.tuning_lines("NB", "epsilon", self.params.smoothing_grid, "nb_smoothing_path"))
        sections.append(self.tuning_lines("QDA", "gamma", self.params.gamma_grid, "qda_gamma_path"))
        return sections

    def boundary_sections(self):
        sections = []
        width, height = self.params.map_size
        for fx, fy in self.params.pairs:
            xmin = min(row.values[fx] for row in self.train)
            xmax = max(row.values[fx] for row in self.train)
            ymin = min(row.values[fy] for row in self.train)
            ymax = max(row.values[fy] for row in self.train)
            dx = (xmax - xmin) / (width - 1)
            dy = (ymax - ymin) / (height - 1)
            grid_points = [
                [(xmin + column * dx, ymax - row * dy) for column in range(width)]
                for row in range(height)
            ]
            lines = [
                f"pair {self.features[fx]} {self.features[fy]}",
                f"x {self.features[fx]} {real(xmin)} {real(xmax)} "
                f"y {self.features[fy]} {real(ymin)} {real(ymax)} grid {width}x{height}",
            ]
            all_grids = []
            for name in MODEL_NAMES:
                model = self.fit(name, (fx, fy))
                correct = sum(model.predict(row.values) == row.class_index for row in self.train)
                cross_validation = self.cross_validate(name, (fx, fy))
                lines.append(
                    f"model {name} train_accuracy {ratio_text(correct, self.n)} "
                    f"cv_accuracy {ratio_text(cross_validation.correct, self.n)}"
                )
                results = [[model.infer_vector(point) for point in row] for row in grid_points]
                all_grids.append(results)
                letter_grid = [[self.upper_letters[item.predicted] for item in row] for row in results]
                lines.extend(frame(letter_grid))
                counts = [0] * self.class_count
                for row in results:
                    for result in row:
                        counts[result.predicted] += 1
                lines.append("cells " + " ".join(
                    f"{letter} {count}" for letter, count in zip(self.upper_letters, counts)
                ))
            agreement = []
            uncertainty = []
            disagreements = 0
            level_characters = " .:-=+*#%@"
            for row in range(height):
                agreement_row = []
                uncertainty_row = []
                for column in range(width):
                    distinct = len({grid[row][column].predicted for grid in all_grids})
                    agreement_row.append("." if distinct == 1 else str(distinct))
                    disagreements += distinct != 1
                    confidence = all_grids[2][row][column].confidence
                    uncertainty_value = (1 - confidence) / (1 - 1 / self.class_count)
                    level = min(9, floor(10 * uncertainty_value))
                    uncertainty_row.append(level_characters[level])
                agreement.append(agreement_row)
                uncertainty.append(uncertainty_row)
            lines.append("agreement")
            lines.extend(frame(agreement))
            lines.extend([f"disagreement_cells {disagreements}", "uncertainty QDA"])
            lines.extend(frame(uncertainty))
            points = [(row.values[fx], row.values[fy]) for row in self.train]
            grid = point_grid(
                points, self.train_actual, self.lower_letters,
                (xmin, xmax, ymin, ymax), self.params.map_size,
            )
            lines.append("points")
            lines.extend(frame(grid))
            sections.append(lines)
        return sections

    def projection_sections(self):
        statistics = self.main_models[0].statistics
        center = statistics.center
        within = zeros(self.d)
        between = zeros(self.d)
        for a in range(self.d):
            for b in range(self.d):
                within[a][b] = ordered_sum(scatter[a][b] for scatter in statistics.scatter)
                between[a][b] = ordered_sum(
                    statistics.counts[k] * (statistics.means[k][a] - center[a])
                    * (statistics.means[k][b] - center[b])
                    for k in range(self.class_count)
                )
        f_values = [
            (between[j][j] / (self.class_count - 1)) / (within[j][j] / (self.n - self.class_count))
            for j in range(self.d)
        ]
        feature_order = sorted(self.all_features, key=lambda j: (-f_values[j], j))
        univariate = ["univariate"]
        for rank, j in enumerate(feature_order, 1):
            univariate.append(
                f"rank {rank} {self.features[j]} f {real(f_values[j])} "
                f"between {real(between[j][j])} within {real(within[j][j])}"
            )
        lower = cholesky(within)
        transformed = zeros(self.d)
        for j in range(self.d):
            column = forward(lower, [between[a][j] for a in range(self.d)])
            for a in range(self.d):
                transformed[a][j] = column[a]
        whitened = zeros(self.d)
        for i in range(self.d):
            column = forward(lower, transformed[i])
            for a in range(self.d):
                whitened[a][i] = column[a]
        symmetric = [
            [(whitened[a][b] + whitened[b][a]) / 2 for b in range(self.d)]
            for a in range(self.d)
        ]
        eigenvalues, eigenvectors, sweeps = jacobi(symmetric)
        eigenvalue_order = sorted(self.all_features, key=lambda j: (-eigenvalues[j], j))
        eigenvalue_sum = ordered_sum(eigenvalues)
        directions = []
        for index in eigenvalue_order[:2]:
            eigenvector = [eigenvectors[j][index] for j in range(self.d)]
            direction = backward(lower, eigenvector)
            norm = sqrt(dot(direction, direction))
            direction = [value / norm for value in direction]
            pivot = argmax([abs(value) for value in direction])
            if direction[pivot] < 0:
                direction = [-value for value in direction]
            directions.append(direction)

        def project(vector):
            return [
                ordered_sum(direction[j] * (vector[j] - center[j]) for j in range(self.d))
                for direction in directions
            ]

        train_points = [project(row.values) for row in self.train]
        test_points = [project(row.values) for row in self.test]
        centroids = [project(mean) for mean in statistics.means]
        fisher = [
            "fisher features " + " ".join(self.features),
            "center " + reals(center),
            f"sweeps {sweeps}",
            "eigenvalues " + reals(eigenvalues[index] for index in eigenvalue_order),
            "ratios " + reals(eigenvalues[index] / eigenvalue_sum for index in eigenvalue_order),
        ]
        pooled = self.main_models[1].covariances[0]
        for dimension, direction in enumerate(directions, 1):
            standardized = [direction[j] * sqrt(pooled[j][j]) for j in range(self.d)]
            fisher.append(f"direction {dimension} {reals(direction)}")
            fisher.append(f"standardized {dimension} {reals(standardized)}")
        for k, name in enumerate(self.classes):
            spread = [
                sqrt(ordered_sum(
                    (point[t] - centroids[k][t]) * (point[t] - centroids[k][t])
                    for point, actual in zip(train_points, self.train_actual) if actual == k
                ) / statistics.counts[k])
                for t in range(2)
            ]
            fisher.append(f"centroid {name} {reals(centroids[k])} spread {reals(spread)}")
        for dimensions in (1, 2):
            train_correct = nearest_centroid_correct(train_points, self.train_actual, centroids, dimensions)
            test_correct = nearest_centroid_correct(test_points, self.test_actual, centroids, dimensions)
            fisher.append(
                f"nearest_centroid dims {dimensions} train {ratio_text(train_correct, self.n)} "
                f"test {ratio_text(test_correct, self.m)}"
            )
        xmin = min(point[0] for point in train_points)
        xmax = max(point[0] for point in train_points)
        ymin = min(point[1] for point in train_points)
        ymax = max(point[1] for point in train_points)
        width, height = self.params.plot_size
        grid = point_grid(
            train_points, self.train_actual, self.lower_letters,
            (xmin, xmax, ymin, ymax), self.params.plot_size,
        )
        for k, (x, y) in enumerate(centroids):
            column = cell(x, xmin, xmax, width)
            row = height - 1 - cell(y, ymin, ymax, height)
            grid[row][column] = self.upper_letters[k]
        scatter = [
            f"plot x {real(xmin)} {real(xmax)} y {real(ymin)} {real(ymax)} size {width}x{height}",
            *frame(grid),
        ]
        return [univariate, fisher, scatter]


def main():
    analysis = Analysis(read_inputs())
    write_lines("output/models.txt", join_sections(analysis.model_sections()))
    write_lines("output/predictions.csv", analysis.prediction_lines())
    write_lines("output/evaluation.txt", join_sections(analysis.evaluation_sections()))
    write_lines("output/boundaries.txt", join_sections(analysis.boundary_sections()))
    write_lines("output/projection.txt", join_sections(analysis.projection_sections()))


if __name__ == "__main__":
    main()
