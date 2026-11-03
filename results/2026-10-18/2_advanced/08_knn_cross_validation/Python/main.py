import os

from dataset import read_dataset
from neighbors import distance, sort_neighbors, vote
from report import fixed, four_decimal, fraction, ratio, write_lines
from scaling import compute_scaling
from validation import (
    Model, fold_training_rows, mae, neighbor_orders, predict, predict_rows,
    prediction_from_order, r_squared, rmse, stratified_folds,
)


INPUT_DIRECTORY = "input"
OUTPUT_DIRECTORY = "output"
IDS_PER_LINE = 10
PROTOTYPE_SETS = ("original", "edited", "condensed", "edited_condensed")


class CrossValidation:
    def __init__(self, model, rows, predictions):
        self.model = model
        self.predictions = predictions
        self.hits = [
            prediction.label == row.label for prediction, row in zip(predictions, rows)
        ]
        self.correct = sum(self.hits)
        self.rmse = rmse([
            prediction.estimate - row.target for prediction, row in zip(predictions, rows)
        ])


class ClassifierSpace:
    def __init__(self, model, train, test):
        self.model = model
        scaling = compute_scaling(train, model.scaling)
        features = list(range(len(train[0].values)))
        references = [scaling.transform(row.values, features) for row in train]
        self.distances = {}
        for query in train + test:
            vector = scaling.transform(query.values, features)
            self.distances[query.ident] = {
                row.ident: distance(vector, reference, model.metric)
                for row, reference in zip(train, references)
            }

    def neighbor_order(self, query, rows):
        gaps = self.distances[query.ident]
        return sort_neighbors([(gaps[row.ident], row) for row in rows])

    def vote(self, query, rows, k):
        return vote(self.neighbor_order(query, rows)[:k], self.model.weighting)

    def nearest_label(self, query, rows):
        _, nearest = self.neighbor_order(query, rows)[0]
        return nearest.label


def build_grid(settings):
    return [
        Model(k, metric, weighting, scaling)
        for k in settings.k_values
        for metric in settings.metrics
        for weighting in settings.weightings
        for scaling in settings.scalings
    ]


def model_spaces(models):
    spaces = []
    for model in models:
        space = (model.scaling, model.metric)
        if space not in spaces:
            spaces.append(space)
    return spaces


def cross_validate(models, rows, fold_count, features):
    predictions = [[None] * len(rows) for _ in models]
    for fold in stratified_folds(rows, fold_count):
        training = fold_training_rows(rows, fold)
        queries = [rows[index] for index in fold]
        for scaling_method, metric in model_spaces(models):
            orders = neighbor_orders(training, queries, scaling_method, metric, features)
            for number, model in enumerate(models):
                if model.scaling != scaling_method or model.metric != metric:
                    continue
                for index, order in zip(fold, orders):
                    predictions[number][index] = prediction_from_order(
                        order, model.k, model.weighting
                    )
    return [
        CrossValidation(model, rows, model_predictions)
        for model, model_predictions in zip(models, predictions)
    ]


def best_classifier(results):
    return max(results, key=lambda result: result.correct)


def best_regressor(results):
    return min(results, key=lambda result: four_decimal(result.rmse))


def correct_count(predictions, rows):
    return sum(prediction.label == row.label for prediction, row in zip(predictions, rows))


def id_order(rows):
    return sorted(rows, key=lambda row: row.ident)


def label_counts(rows, labels):
    counts = {label: 0 for label in labels}
    for row in rows:
        counts[row.label] += 1
    return " ".join(f"{label} {counts[label]}" for label in labels)


def curve_rows(rows, labels, limit):
    taken = {label: 0 for label in labels}
    selected = []
    for row in rows:
        if taken[row.label] < limit:
            taken[row.label] += 1
            selected.append(row)
    return selected


def evaluation_lines(pairs, labels):
    matrix = {truth: {predicted: 0 for predicted in labels} for truth in labels}
    for truth, predicted in pairs:
        matrix[truth][predicted] += 1
    lines = ["true\\predicted " + " ".join(labels)]
    for truth in labels:
        counts = " ".join(str(matrix[truth][predicted]) for predicted in labels)
        lines.append(f"{truth} {counts}")
    totals = [0.0, 0.0, 0.0]
    valued = [0, 0, 0]
    for label in labels:
        hits = matrix[label][label]
        predicted = sum(matrix[truth][label] for truth in labels)
        actual = sum(matrix[label][other] for other in labels)
        metrics = ((hits, predicted), (hits, actual), (2 * hits, predicted + actual))
        for position, (numerator, denominator) in enumerate(metrics):
            if denominator > 0:
                totals[position] += numerator / denominator
                valued[position] += 1
        lines.append(
            f"class {label} precision {fraction(hits, predicted)} "
            f"recall {fraction(hits, actual)} "
            f"f1 {fraction(2 * hits, predicted + actual)} support {actual}"
        )
    averages = [
        fixed(total / count) if count else "-" for total, count in zip(totals, valued)
    ]
    lines.append(f"macro precision {averages[0]} recall {averages[1]} f1 {averages[2]}")
    return lines


def reliability_lines(pairs, bounds):
    lowers = [0.0] + bounds
    counts = [0] * len(lowers)
    hits = [0] * len(lowers)
    shares = [0.0] * len(lowers)
    for prediction, truth in pairs:
        position = sum(bound <= prediction.share for bound in bounds)
        counts[position] += 1
        if prediction.label == truth:
            hits[position] += 1
        shares[position] += prediction.share
    lines = []
    for position, lower in enumerate(lowers):
        if counts[position] == 0:
            lines.append(f"bin {fixed(lower, 2)} rows 0")
        else:
            lines.append(
                f"bin {fixed(lower, 2)} rows {counts[position]} "
                f"correct {ratio(hits[position], counts[position])} "
                f"share {fixed(shares[position] / counts[position])}"
            )
    return lines


def wilson_editing(space, rows, edit_k):
    current = rows
    passes = []
    while True:
        removals = []
        for row in current:
            others = [other for other in current if other is not row]
            result = space.vote(row, others, edit_k)
            if result.label != row.label:
                removals.append((row, result))
        passes.append(removals)
        if not removals:
            return current, passes
        removed = {row.ident for row, _ in removals}
        current = [row for row in current if row.ident not in removed]


def hart_condensing(space, rows):
    store = [rows[0]]
    stored = {rows[0].ident}
    scans = 0
    added = True
    while added:
        scans += 1
        added = False
        for row in rows:
            if row.ident in stored:
                continue
            if space.nearest_label(row, store) != row.label:
                store.append(row)
                stored.add(row.ident)
                added = True
    return id_order(store), scans


def id_lines(rows):
    idents = [row.ident for row in rows]
    return [
        " ".join(idents[start:start + IDS_PER_LINE])
        for start in range(0, len(idents), IDS_PER_LINE)
    ]


def join_parts(parts):
    lines = []
    for part in parts:
        if lines:
            lines.append("")
        lines.extend(part)
    return lines


class Experiment:
    def __init__(self, feature_names, train, test, settings):
        self.feature_names = feature_names
        self.features = list(range(len(feature_names)))
        self.train = train
        self.test = test
        self.settings = settings
        self.labels = sorted({row.label for row in train})
        self.labelled = [row for row in test if row.label is not None]
        self.targeted = [row for row in test if row.target is not None]
        self.grid = build_grid(settings)
        self.folds = stratified_folds(train, settings.folds)
        self.results = cross_validate(self.grid, train, settings.folds, self.features)
        self.classifier = best_classifier(self.results)
        self.regressor = best_regressor(self.results)
        self.test_predictions = predict_rows(self.classifier.model, train, test, self.features)
        self.test_estimates = [
            prediction.estimate
            for prediction in predict_rows(self.regressor.model, train, test, self.features)
        ]
        self.labelled_predictions = [
            (row, prediction)
            for row, prediction in zip(test, self.test_predictions)
            if row.label is not None
        ]

    def names(self, features):
        return " ".join(self.feature_names[feature] for feature in features)

    def train_ratio(self, count):
        return ratio(count, len(self.train))

    def classifier_summary(self, result):
        return (
            f"{result.model.notation()} correct {self.train_ratio(result.correct)} "
            f"rmse {fixed(result.rmse)}"
        )

    def regressor_summary(self, result):
        return (
            f"{result.model.notation()} rmse {fixed(result.rmse)} "
            f"correct {self.train_ratio(result.correct)}"
        )

    def grid_table(self):
        lines = ["k,metric,weighting,scaling,correct,accuracy,rmse"]
        for result in self.results:
            model = result.model
            lines.append(
                f"{model.k},{model.metric},{model.weighting},{model.scaling},"
                f"{result.correct},{fixed(result.correct / len(self.train))},"
                f"{fixed(result.rmse)}"
            )
        return lines

    def prediction_table(self):
        lines = ["id,label,vote_share,estimate"]
        for row, prediction, estimate in zip(
            self.test, self.test_predictions, self.test_estimates
        ):
            lines.append(
                f"{row.ident},{prediction.label},{fixed(prediction.share)},{fixed(estimate)}"
            )
        return lines

    def data_part(self):
        return [
            f"data train {len(self.train)} test {len(self.test)} "
            f"labelled {len(self.labelled)} targets {len(self.targeted)} "
            f"features {len(self.features)} classes {len(self.labels)}",
            "classes " + label_counts(self.train, self.labels),
        ]

    def scaling_part(self, method):
        scaling = compute_scaling(self.train, method)
        lines = [f"scaling {method}"]
        for feature, name in enumerate(self.feature_names):
            lines.append(
                f"{name} center {fixed(scaling.centers[feature], 6)} "
                f"scale {fixed(scaling.scales[feature], 6)}"
            )
        return lines

    def folds_part(self):
        lines = [f"folds {self.settings.folds}"]
        for number, fold in enumerate(self.folds, 1):
            rows = [self.train[index] for index in fold]
            lines.append(f"fold {number} size {len(rows)} {label_counts(rows, self.labels)}")
        return lines

    def selection_part(self):
        return [
            f"grid {len(self.grid)}",
            "best_classifier " + self.classifier_summary(self.classifier),
            "best_regressor " + self.regressor_summary(self.regressor),
        ]

    def accuracy_top_part(self):
        ranking = sorted(self.results, key=lambda result: -result.correct)
        lines = [f"top {self.settings.top} by accuracy"]
        for rank, result in enumerate(ranking[:self.settings.top], 1):
            lines.append(f"{rank} {self.classifier_summary(result)}")
        return lines

    def rmse_top_part(self):
        ranking = sorted(self.results, key=lambda result: four_decimal(result.rmse))
        lines = [f"top {self.settings.top} by rmse"]
        for rank, result in enumerate(ranking[:self.settings.top], 1):
            lines.append(f"{rank} {self.regressor_summary(result)}")
        return lines

    def best_per_item_parts(self):
        items = (
            ("k", self.settings.k_values, lambda model: model.k),
            ("metric", self.settings.metrics, lambda model: model.metric),
            ("weighting", self.settings.weightings, lambda model: model.weighting),
            ("scaling", self.settings.scalings, lambda model: model.scaling),
        )
        parts = []
        for item, values, attribute in items:
            lines = [f"best per {item}"]
            for value in values:
                group = [result for result in self.results if attribute(result.model) == value]
                classifier = best_classifier(group)
                regressor = best_regressor(group)
                lines.append(
                    f"{item}={value} classifier {classifier.model.notation()} "
                    f"accuracy {fixed(classifier.correct / len(self.train))} "
                    f"regressor {regressor.model.notation()} rmse {fixed(regressor.rmse)}"
                )
            parts.append(lines)
        return parts

    def classifier_folds_part(self):
        lines = ["classifier folds"]
        for number, fold in enumerate(self.folds, 1):
            correct = sum(self.classifier.hits[index] for index in fold)
            lines.append(f"fold {number} correct {ratio(correct, len(fold))}")
        return lines

    def regressor_folds_part(self):
        lines = ["regressor folds"]
        for number, fold in enumerate(self.folds, 1):
            errors = [
                self.regressor.predictions[index].estimate - self.train[index].target
                for index in fold
            ]
            lines.append(f"fold {number} size {len(fold)} rmse {fixed(rmse(errors))}")
        return lines

    def cross_validation_parts(self):
        predictions = self.classifier.predictions
        label_pairs = [
            (row.label, prediction.label) for row, prediction in zip(self.train, predictions)
        ]
        share_pairs = [
            (prediction, row.label) for row, prediction in zip(self.train, predictions)
        ]
        return [
            ["cross_validation classes"] + evaluation_lines(label_pairs, self.labels),
            ["cross_validation reliability"] + reliability_lines(share_pairs, self.settings.bins),
        ]

    def mcnemar_part(self):
        lines = ["mcnemar"]
        for metric in self.settings.metrics:
            comparison = best_classifier(
                [result for result in self.results if result.model.metric == metric]
            )
            only_selected = 0
            only_comparison = 0
            for selected_hit, comparison_hit in zip(self.classifier.hits, comparison.hits):
                if selected_hit and not comparison_hit:
                    only_selected += 1
                elif comparison_hit and not selected_hit:
                    only_comparison += 1
            disagreements = only_selected + only_comparison
            numerator = max(0, abs(only_selected - only_comparison) - 1) ** 2
            statistic = fraction(numerator, disagreements) if disagreements else "0/1 0.0000"
            significant = "yes" if 1000 * numerator > 3841 * disagreements else "no"
            lines.append(
                f"{comparison.model.notation()} b {only_selected} c {only_comparison} "
                f"statistic {statistic} significant {significant}"
            )
        return lines

    def leave_one_out_parts(self):
        model = self.classifier.model
        by_k = {k: [] for k in self.settings.k_values}
        estimates = []
        for index, row in enumerate(self.train):
            others = self.train[:index] + self.train[index + 1:]
            order = neighbor_orders(others, [row], model.scaling, model.metric, self.features)[0]
            for k in self.settings.k_values:
                by_k[k].append(prediction_from_order(order, k, model.weighting))
            estimates.append(predict(self.regressor.model, others, row, self.features).estimate)
        return [
            self.loo_classifier_part(by_k[model.k]),
            self.loo_regressor_part(estimates),
            self.loo_by_k_part(by_k),
        ]

    def loo_classifier_part(self, predictions):
        errors = [
            (row, prediction)
            for row, prediction in zip(self.train, predictions)
            if prediction.label != row.label
        ]
        class_errors = {label: 0 for label in self.labels}
        for row, _ in errors:
            class_errors[row.label] += 1
        lines = [
            f"leave_one_out classifier {self.classifier.model.notation()}",
            f"errors {self.train_ratio(len(errors))}",
            "class_errors " + " ".join(f"{label} {class_errors[label]}" for label in self.labels),
        ]
        for row, prediction in sorted(errors, key=lambda error: error[0].ident):
            lines.append(
                f"{row.ident} true {row.label} predicted {prediction.label} "
                f"share {fixed(prediction.share)}"
            )
        return lines

    def loo_regressor_part(self, estimates):
        residuals = [estimate - row.target for estimate, row in zip(estimates, self.train)]
        lines = [
            f"leave_one_out regressor {self.regressor.model.notation()}",
            f"rmse {fixed(rmse(residuals))} mae {fixed(mae(residuals))}",
            f"largest {self.settings.top} residuals",
        ]
        ranking = sorted(
            range(len(self.train)),
            key=lambda index: (-four_decimal(abs(residuals[index])), self.train[index].ident),
        )
        for index in ranking[:self.settings.top]:
            row = self.train[index]
            lines.append(
                f"{row.ident} target {fixed(row.target)} estimate {fixed(estimates[index])} "
                f"residual {fixed(residuals[index])}"
            )
        return lines

    def loo_by_k_part(self, by_k):
        model = self.classifier.model
        lines = [
            f"leave_one_out by k metric={model.metric} weighting={model.weighting} "
            f"scaling={model.scaling}"
        ]
        for k in self.settings.k_values:
            predictions = by_k[k]
            errors = [
                prediction.estimate - row.target
                for prediction, row in zip(predictions, self.train)
            ]
            correct = correct_count(predictions, self.train)
            lines.append(f"k={k} correct {self.train_ratio(correct)} rmse {fixed(rmse(errors))}")
        return lines

    def nested_part(self):
        lines = [f"nested_cross_validation folds {self.settings.folds}"]
        nested_estimates = [0.0] * len(self.train)
        outer_total = 0
        for number, fold in enumerate(self.folds, 1):
            inner_rows = fold_training_rows(self.train, fold)
            validation_rows = [self.train[index] for index in fold]
            results = cross_validate(self.grid, inner_rows, self.settings.folds, self.features)
            classifier = best_classifier(results)
            regressor = best_regressor(results)
            predictions = predict_rows(
                classifier.model, inner_rows, validation_rows, self.features
            )
            outer_correct = correct_count(predictions, validation_rows)
            outer_total += outer_correct
            estimates = predict_rows(regressor.model, inner_rows, validation_rows, self.features)
            errors = []
            for index, prediction in zip(fold, estimates):
                nested_estimates[index] = prediction.estimate
                errors.append(prediction.estimate - self.train[index].target)
            lines.append(
                f"fold {number} classifier {classifier.model.notation()} "
                f"inner {fixed(classifier.correct / len(inner_rows))} "
                f"outer {ratio(outer_correct, len(fold))}"
            )
            lines.append(
                f"fold {number} regressor {regressor.model.notation()} "
                f"inner {fixed(regressor.rmse)} outer {fixed(rmse(errors))}"
            )
        errors = [estimate - row.target for estimate, row in zip(nested_estimates, self.train)]
        lines.append(f"nested accuracy {self.train_ratio(outer_total)} rmse {fixed(rmse(errors))}")
        return lines

    def feature_selection_part(self):
        model = self.classifier.model
        current = self.features
        lines = [
            f"feature_selection {model.notation()}",
            f"start features {self.names(current)} "
            f"correct {self.train_ratio(self.classifier.correct)}",
        ]
        selected = current
        selected_correct = self.classifier.correct
        step = 0
        while len(current) >= 3:
            step += 1
            candidates = []
            for feature in current:
                remaining = [other for other in current if other != feature]
                result = cross_validate([model], self.train, self.settings.folds, remaining)[0]
                candidates.append((feature, result.correct))
            removed, correct = max(candidates, key=lambda candidate: candidate[1])
            current = [feature for feature in current if feature != removed]
            listing = " ".join(
                f"{self.feature_names[feature]} {count}" for feature, count in candidates
            )
            lines.append(
                f"step {step} remove {self.feature_names[removed]} "
                f"correct {self.train_ratio(correct)} candidates {listing}"
            )
            if correct >= selected_correct:
                selected = current
                selected_correct = correct
        predictions = predict_rows(model, self.train, self.labelled, selected)
        test_correct = correct_count(predictions, self.labelled)
        lines.append(
            f"selected features {self.names(selected)} "
            f"correct {self.train_ratio(selected_correct)}"
        )
        lines.append(f"selected test {ratio(test_correct, len(self.labelled))}")
        return lines

    def test_classification_part(self):
        pairs = [(row.label, prediction.label) for row, prediction in self.labelled_predictions]
        correct = sum(truth == predicted for truth, predicted in pairs)
        return [
            f"test classification {self.classifier.model.notation()}",
            f"labelled {len(self.labelled)} correct {ratio(correct, len(self.labelled))}",
        ] + evaluation_lines(pairs, self.labels)

    def test_reliability_part(self):
        pairs = [(prediction, row.label) for row, prediction in self.labelled_predictions]
        return ["test reliability"] + reliability_lines(pairs, self.settings.bins)

    def uncertain_part(self):
        margins = [
            prediction.share - prediction.runner_share for prediction in self.test_predictions
        ]
        ranking = sorted(range(len(self.test)), key=lambda index: four_decimal(margins[index]))
        lines = [f"uncertain {self.settings.top} test rows"]
        for index in ranking[:self.settings.top]:
            row = self.test[index]
            prediction = self.test_predictions[index]
            runner_up = prediction.runner_up if prediction.runner_up is not None else "-"
            truth = row.label if row.label is not None else "-"
            lines.append(
                f"{row.ident} predicted {prediction.label} share {fixed(prediction.share)} "
                f"runner_up {runner_up} share {fixed(prediction.runner_share)} "
                f"margin {fixed(margins[index])} true {truth}"
            )
        return lines

    def test_regression_part(self):
        pairs = [
            (row, estimate)
            for row, estimate in zip(self.test, self.test_estimates)
            if row.target is not None
        ]
        errors = [estimate - row.target for row, estimate in pairs]
        targets = [row.target for row, _ in pairs]
        lines = [
            f"test regression {self.regressor.model.notation()}",
            f"targets {len(pairs)} rmse {fixed(rmse(errors))} mae {fixed(mae(errors))} "
            f"r2 {fixed(r_squared(errors, targets))}",
        ]
        for label in self.labels:
            class_errors = [estimate - row.target for row, estimate in pairs if row.label == label]
            value = fixed(rmse(class_errors)) if class_errors else "-"
            lines.append(f"class {label} targets {len(class_errors)} rmse {value}")
        return lines

    def misclassified_part(self):
        lines = ["misclassified test rows"]
        count = 0
        for row, prediction in self.labelled_predictions:
            if prediction.label == row.label:
                continue
            count += 1
            lines.append(
                f"{row.ident} true {row.label} predicted {prediction.label} "
                f"share {fixed(prediction.share)}"
            )
            for gap, neighbor in prediction.neighbors:
                lines.append(f"  {neighbor.ident} {neighbor.label} {fixed(gap)}")
        lines.append(f"count {count}")
        return lines

    def metrics_report(self):
        parts = [self.data_part()]
        parts.extend(self.scaling_part(method) for method in self.settings.scalings)
        parts.append(self.folds_part())
        parts.append(self.selection_part())
        parts.append(self.accuracy_top_part())
        parts.append(self.rmse_top_part())
        parts.extend(self.best_per_item_parts())
        parts.append(self.classifier_folds_part())
        parts.append(self.regressor_folds_part())
        parts.extend(self.cross_validation_parts())
        parts.append(self.mcnemar_part())
        parts.extend(self.leave_one_out_parts())
        parts.append(self.nested_part())
        parts.append(self.feature_selection_part())
        parts.append(self.test_classification_part())
        parts.append(self.test_reliability_part())
        parts.append(self.uncertain_part())
        parts.append(self.test_regression_part())
        parts.append(self.misclassified_part())
        return join_parts(parts)

    def learning_curve_table(self):
        lines = ["n,train_size,correct,accuracy,rmse"]
        for limit in self.settings.curve:
            rows = curve_rows(self.train, self.labels, limit)
            predictions = predict_rows(self.classifier.model, rows, self.labelled, self.features)
            correct = correct_count(predictions, self.labelled)
            estimates = predict_rows(self.regressor.model, rows, self.targeted, self.features)
            errors = [
                prediction.estimate - row.target
                for prediction, row in zip(estimates, self.targeted)
            ]
            lines.append(
                f"{limit},{len(rows)},{correct},{fixed(correct / len(self.labelled))},"
                f"{fixed(rmse(errors))}"
            )
        return lines

    def editing_part(self, passes, edited):
        lines = [f"editing k={self.settings.edit_k}"]
        for number, removals in enumerate(passes, 1):
            lines.append(f"pass {number} removed {len(removals)}")
            for row, result in removals:
                lines.append(
                    f"  {row.ident} true {row.label} predicted {result.label} "
                    f"share {fixed(result.share)}"
                )
        lines.append(f"edited size {len(edited)} removed {len(self.train) - len(edited)}")
        return lines

    def prototype_line(self, space, name, rows):
        knn_correct = 0
        nearest_correct = 0
        for row in self.labelled:
            if space.vote(row, rows, self.classifier.model.k).label == row.label:
                knn_correct += 1
            if space.nearest_label(row, rows) == row.label:
                nearest_correct += 1
        return (
            f"set {name} size {len(rows)} {label_counts(rows, self.labels)} "
            f"knn {ratio(knn_correct, len(self.labelled))} "
            f"1nn {ratio(nearest_correct, len(self.labelled))}"
        )

    def borders_part(self, space, ordered):
        lines = ["borders"]
        total = 0
        for label in self.labels:
            members = [row for row in ordered if row.label == label]
            borders = 0
            same_total = 0.0
            other_total = 0.0
            for row in members:
                order = space.neighbor_order(row, [other for other in ordered if other is not row])
                same = next(gap for gap, neighbor in order if neighbor.label == label)
                other = next(gap for gap, neighbor in order if neighbor.label != label)
                if order[0][1].label != label:
                    borders += 1
                same_total += same
                other_total += other
            total += borders
            lines.append(
                f"class {label} size {len(members)} border {borders} "
                f"same {fixed(same_total / len(members))} "
                f"other {fixed(other_total / len(members))}"
            )
        lines.append(f"border total {self.train_ratio(total)}")
        return lines

    def hubs_part(self):
        occurrences = {row.ident: 0 for row in self.train}
        for prediction in self.test_predictions:
            for _, row in prediction.neighbors:
                occurrences[row.ident] += 1
        hub_order = sorted(self.train, key=lambda row: (-occurrences[row.ident], row.ident))
        lines = [f"hubs k={self.classifier.model.k} queries {len(self.test)}"]
        for row in hub_order[:self.settings.top]:
            lines.append(f"{row.ident} {row.label} {occurrences[row.ident]}")
        anti_hubs = sum(count == 0 for count in occurrences.values())
        lines.append(f"anti_hubs {anti_hubs}")
        return lines

    def prototypes_report(self):
        space = ClassifierSpace(self.classifier.model, self.train, self.test)
        ordered = id_order(self.train)
        edited, passes = wilson_editing(space, ordered, self.settings.edit_k)
        condensed, condensed_scans = hart_condensing(space, ordered)
        edited_condensed, edited_scans = hart_condensing(space, edited)
        sets = (ordered, edited, condensed, edited_condensed)
        return join_parts([
            [f"space {self.classifier.model.notation()}"],
            self.editing_part(passes, edited),
            [
                f"condensing original scans {condensed_scans} size {len(condensed)}",
                f"condensing edited scans {edited_scans} size {len(edited_condensed)}",
            ],
            [self.prototype_line(space, name, rows) for name, rows in zip(PROTOTYPE_SETS, sets)],
            ["prototypes condensed"] + id_lines(condensed),
            ["prototypes edited_condensed"] + id_lines(edited_condensed),
            self.borders_part(space, ordered),
            self.hubs_part(),
        ])


def main():
    feature_names, train, test, settings = read_dataset(INPUT_DIRECTORY)
    experiment = Experiment(feature_names, train, test, settings)
    os.makedirs(OUTPUT_DIRECTORY, exist_ok=True)
    outputs = (
        ("cv_grid.csv", experiment.grid_table()),
        ("predictions.csv", experiment.prediction_table()),
        ("metrics.txt", experiment.metrics_report()),
        ("learning_curve.csv", experiment.learning_curve_table()),
        ("prototypes.txt", experiment.prototypes_report()),
    )
    for name, lines in outputs:
        write_lines(os.path.join(OUTPUT_DIRECTORY, name), lines)


if __name__ == "__main__":
    main()
