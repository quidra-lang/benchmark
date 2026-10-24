"""Train the requested ensembles and assemble the nine benchmark reports."""

from bisect import bisect_right
from itertools import combinations
from math import exp, floor, log
from pathlib import Path

from adaboost import train_discrete, train_samme
from dataset import read_inputs
from evaluation import auc, confusion, count_at_most, number, prediction, ratio, write_lines
from stumps import SearchSpace, ordered_sum
from variants import train_gentle, train_logit, train_real


class Minstd:
    def __init__(self, seed):
        self.state = seed

    def draw(self):
        self.state = (48271 * self.state) % 2147483647
        return self.state


def train_variant(variant, rows, params):
    if variant == "discrete":
        return train_discrete(rows, params.rounds)
    if variant == "real":
        return train_real(
            rows, params.rounds, params.bins, params.smoothing, params.convergence
        )
    if variant == "gentle":
        return train_gentle(rows, params.rounds)
    return train_logit(rows, params.rounds, params.clip)


def row_score(rounds, values):
    return ordered_sum(record.stump(values) for record in rounds)


def score_rows(rounds, rows):
    return [row_score(rounds, row.values) for row in rows]


def add_round_scores(record, rows, scores):
    for index, row in enumerate(rows):
        scores[index] += record.stump(row.values)


def magnitude(record):
    return max(abs(value) for value in record.stump.values)


def total_magnitude(rounds):
    return ordered_sum(magnitude(record) for record in rounds)


def contributions(rounds, values, features):
    result = [0.0] * features
    for record in rounds:
        result[record.stump.feature] += record.stump(values)
    return result


def count_errors(rows, scores):
    return sum(prediction(score) != row.label for row, score in zip(rows, scores))


def loss(rows, scores, variant):
    if variant == "logit":
        terms = (log(1 + exp(-2 * row.label * score)) for row, score in zip(rows, scores))
    else:
        terms = (exp(-row.label * score) for row, score in zip(rows, scores))
    return ordered_sum(terms) / len(rows)


def metrics_line(kind, variant, rounds, rows, scores):
    tp = fp = tn = fn = 0
    for row, score in zip(rows, scores):
        if prediction(score) == 1:
            if row.label == 1:
                tp += 1
            else:
                fp += 1
        elif row.label == -1:
            tn += 1
        else:
            fn += 1
    return (
        f"{kind} {variant} rounds {rounds} correct {tp + tn}/{len(rows)} "
        f"accuracy {ratio(tp + tn, len(rows))} tp {tp} fp {fp} tn {tn} fn {fn} "
        f"precision {ratio(tp, tp + fp)} recall {ratio(tp, tp + fn)} "
        f"f1 {ratio(2 * tp, 2 * tp + fp + fn)} auc {ratio(*auc(rows, scores))} "
        f"loss {number(loss(rows, scores, variant))}"
    )


def training_curve(rounds, training, testing, variant):
    train_scores = [0.0] * len(training)
    test_scores = [0.0] * len(testing)
    scale = 0.0
    curve = []
    for round_number, record in enumerate(rounds, 1):
        add_round_scores(record, training, train_scores)
        add_round_scores(record, testing, test_scores)
        scale += magnitude(record)
        minimum = min(row.label * score for row, score in zip(training, train_scores))
        curve.append({
            "round": round_number,
            "train_errors": count_errors(training, train_scores),
            "test_errors": count_errors(testing, test_scores),
            "train_loss": loss(training, train_scores, variant),
            "test_loss": loss(testing, test_scores, variant),
            "margin": minimum / scale,
        })
    return curve


def cross_validate(rows, params):
    space = SearchSpace(rows)
    folds = []
    errors = [0] * params.rounds
    for fold_number in range(params.folds):
        indices = [index for index in range(len(rows)) if index % params.folds == fold_number]
        training_count = len(rows) - len(indices)
        weights = [
            0.0 if index % params.folds == fold_number else 1 / training_count
            for index in range(len(rows))
        ]
        model = train_discrete(rows, params.rounds, weights=weights, space=space)
        validation = [rows[index] for index in indices]
        scores = [0.0] * len(validation)
        fold_errors = []
        for index in range(params.rounds):
            if index < len(model.rounds):
                add_round_scores(model.rounds[index], validation, scores)
            count = count_errors(validation, scores)
            fold_errors.append(count)
            errors[index] += count
        folds.append({
            "indices": indices, "train": training_count,
            "model": model, "errors": fold_errors,
        })
    selected = min(range(params.rounds), key=errors.__getitem__) + 1
    oof_scores = [0.0] * len(rows)
    for fold in folds:
        rounds = fold["model"].rounds[:selected]
        for index in fold["indices"]:
            oof_scores[index] = row_score(rounds, rows[index].values)
    return {"folds": folds, "errors": errors, "selected": selected, "scores": oof_scores}


def magnitude_importance(rounds, feature_count, samme=False):
    scores = [0.0] * feature_count
    counts = [0] * feature_count
    for record in rounds:
        feature = record.stump.feature
        scores[feature] += record.alpha if samme else magnitude(record)
        counts[feature] += 1
    return {
        "scores": scores,
        "counts": counts,
        "total": ordered_sum(scores),
        "order": sorted(range(feature_count), key=lambda feature: -scores[feature]),
    }


def importance_lines(importance, features):
    lines = ["importance"]
    for rank, feature in enumerate(importance["order"], 1):
        score = importance["scores"][feature]
        lines.append(
            f"{rank} {features[feature]} score {number(score)} "
            f"share {ratio(score, importance['total'])} "
            f"rounds {importance['counts'][feature]}"
        )
    return lines


def analyze_variants(inputs, selected):
    analysis = {}
    for variant in inputs.params.variants:
        model = train_variant(variant, inputs.train, inputs.params)
        rounds = model.rounds[:selected] if variant == "discrete" else model.rounds
        analysis[variant] = {
            "full": model,
            "rounds": rounds,
            "scale": total_magnitude(rounds),
            "train": score_rows(rounds, inputs.train),
            "test": score_rows(rounds, inputs.test),
            "curve": training_curve(model.rounds, inputs.train, inputs.test, variant),
            "importance": magnitude_importance(rounds, len(inputs.features)),
        }
    return analysis


def ensemble_lines(inputs, analysis, cv):
    params = inputs.params
    lines = []
    for variant in params.variants:
        if lines:
            lines.append("")
        model = analysis[variant]["full"]
        header = f"variant {variant} rounds {len(model.rounds)} stop {model.stop}"
        if variant == "real":
            header += (
                f" bins {params.bins} smoothing {number(params.smoothing)} "
                f"convergence {number(params.convergence, 6)}"
            )
        elif variant == "logit":
            header += f" clip {number(params.clip)}"
        lines.append(header)
        if variant == "real":
            for feature, cuts in zip(inputs.features, model.cuts):
                lines.append(f"cuts {feature} " + " ".join(map(number, cuts)))
        for round_number, record in enumerate(model.rounds, 1):
            stump = record.stump
            line = f"round {round_number} feature {inputs.features[stump.feature]}"
            if variant == "real":
                line += f" z {number(record.z)} bound {number(record.bound)} values "
                line += " ".join(map(number, stump.values))
            else:
                line += f" threshold {number(stump.thresholds[0])}"
                if variant == "discrete":
                    line += (
                        f" polarity {record.polarity} error {number(record.error)} "
                        f"alpha {number(record.alpha)} z {number(record.z)} "
                        f"bound {number(record.bound)}"
                    )
                else:
                    line += (
                        f" left {number(stump.values[0])} right {number(stump.values[1])} "
                        f"error {number(record.error)}"
                    )
                    if variant == "logit":
                        line += f" loss {number(record.loss)}"
            lines.append(line)
            if variant == "discrete":
                maximum = max(range(len(record.weights)), key=record.weights.__getitem__)
                ess = 1 / ordered_sum(weight * weight for weight in record.weights)
                lines.append(
                    f"weights {round_number} max {number(record.weights[maximum], 6)} "
                    f"id {inputs.train[maximum].id} ess {number(ess)}"
                )
        if variant == "discrete":
            selected = cv["selected"]
            lines.append(
                f"cv folds {params.folds} selected {selected} "
                f"errors {cv['errors'][selected - 1]}/{len(inputs.train)}"
            )
            for fold_number, fold in enumerate(cv["folds"], 1):
                validation = len(fold["indices"])
                result = fold["model"]
                lines.append(
                    f"fold {fold_number} train {fold['train']} validation {validation} "
                    f"rounds {len(result.rounds)} stop {result.stop} "
                    f"selected {fold['errors'][selected - 1]}/{validation} "
                    f"final {fold['errors'][-1]}/{validation}"
                )
            lines.append("cv_errors " + " ".join(map(str, cv["errors"])))
    return lines


def error_curve_lines(inputs, analysis, samme_curve):
    lines = ["variant,round,train_error,test_error,train_loss,test_loss,min_margin"]
    for variant in inputs.params.variants:
        for point in analysis[variant]["curve"]:
            lines.append(
                f"{variant},{point['round']},"
                f"{ratio(point['train_errors'], len(inputs.train))},"
                f"{ratio(point['test_errors'], len(inputs.test))},"
                f"{number(point['train_loss'])},{number(point['test_loss'])},"
                f"{number(point['margin'])}"
            )
    for round_number, training_errors, testing_errors in samme_curve:
        lines.append(
            f"samme,{round_number},{ratio(training_errors, len(inputs.multi_train))},"
            f"{ratio(testing_errors, len(inputs.multi_test))},-,-,-"
        )
    return lines


def prediction_lines(inputs, analysis):
    lines = ["id,variant,score,label," + ",".join(inputs.features)]
    for index, row in enumerate(inputs.test):
        for variant in inputs.params.variants:
            result = analysis[variant]
            score = result["test"][index]
            parts = contributions(result["rounds"], row.values, len(inputs.features))
            lines.append(
                f"{row.id},{variant},{number(score)},{prediction(score)},"
                + ",".join(map(number, parts))
            )
    return lines


def roc_lines(inputs, analysis):
    lines = ["variant,threshold,tp,fp"]
    for variant in inputs.params.variants:
        scores = analysis[variant]["test"]
        for threshold in sorted(set(scores), reverse=True):
            tp = fp = 0
            for row, score in zip(inputs.test, scores):
                if score >= threshold:
                    if row.label == 1:
                        tp += 1
                    else:
                        fp += 1
            lines.append(f"{variant},{number(threshold)},{tp},{fp}")
    return lines


def permutation_importance(rounds, rows, feature_count, repeats, generator):
    base = len(rows) - count_errors(rows, score_rows(rounds, rows))
    results = []
    for feature in range(feature_count):
        counts = []
        for _ in range(repeats):
            permutation = list(range(len(rows)))
            for index in range(len(rows) - 1, 0, -1):
                other = generator.draw() % (index + 1)
                permutation[index], permutation[other] = permutation[other], permutation[index]
            correct = 0
            for index, row in enumerate(rows):
                values = list(row.values)
                values[feature] = rows[permutation[index]].values[feature]
                if prediction(row_score(rounds, values)) == row.label:
                    correct += 1
            counts.append(correct)
        drop = sum(base - count for count in counts)
        results.append((feature, drop, min(counts), max(counts)))
    results.sort(key=lambda result: -result[1])
    return base, results


def margin_lines(inputs, analysis):
    lines = []
    repeats, seed = inputs.params.permutation
    generator = Minstd(seed)
    for variant in inputs.params.variants:
        if lines:
            lines.append("")
        result = analysis[variant]
        train_margins = [
            row.label * score / result["scale"]
            for row, score in zip(inputs.train, result["train"])
        ]
        test_margins = [
            row.label * score / result["scale"]
            for row, score in zip(inputs.test, result["test"])
        ]
        lines.append(
            f"variant {variant} rounds {len(result['rounds'])} scale {number(result['scale'])}"
        )
        lines.append(
            f"train min {number(min(train_margins))} "
            f"mean {number(ordered_sum(train_margins) / len(inputs.train))}"
        )
        for threshold in inputs.params.margins:
            count = count_at_most(train_margins, threshold)
            lines.append(
                f"train le {number(threshold)} {count}/{len(inputs.train)} "
                f"{ratio(count, len(inputs.train))}"
            )
        histogram = [0] * 20
        for margin in train_margins:
            histogram[min(19, floor((margin + 1) * 10))] += 1
        lines.append("histogram " + " ".join(map(str, histogram)))
        hardest = sorted(range(len(inputs.train)), key=train_margins.__getitem__)[:5]
        for index in hardest:
            lines.append(
                f"hardest {inputs.train[index].id} label {inputs.train[index].label} "
                f"margin {number(train_margins[index])}"
            )
        lines.append(
            f"test min {number(min(test_margins))} "
            f"mean {number(ordered_sum(test_margins) / len(inputs.test))}"
        )
        for threshold in inputs.params.margins:
            count = count_at_most(test_margins, threshold)
            lines.append(
                f"test le {number(threshold)} {count}/{len(inputs.test)} "
                f"{ratio(count, len(inputs.test))}"
            )
        for threshold in inputs.params.margins:
            confident = [index for index, margin in enumerate(test_margins) if abs(margin) > threshold]
            correct = sum(
                prediction(result["test"][index]) == inputs.test[index].label for index in confident
            )
            lines.append(
                f"test confident {number(threshold)} {len(confident)}/{len(inputs.test)} "
                f"correct {correct}/{len(confident)} {ratio(correct, len(confident))}"
            )
        lines.extend(importance_lines(result["importance"], inputs.features))
        base, permutation = permutation_importance(
            result["rounds"], inputs.test, len(inputs.features), repeats, generator
        )
        lines.append(f"permutation repeats {repeats} base {base}/{len(inputs.test)}")
        for rank, (feature, drop, minimum, maximum) in enumerate(permutation, 1):
            lines.append(
                f"{rank} {inputs.features[feature]} drop {ratio(drop, repeats * len(inputs.test))} "
                f"min {minimum}/{len(inputs.test)} max {maximum}/{len(inputs.test)}"
            )
    return lines


def shape_lines(inputs, analysis):
    lines = []
    for variant in inputs.params.variants:
        if lines:
            lines.append("")
        rounds = analysis[variant]["rounds"]
        lines.append(f"variant {variant} rounds {len(rounds)}")
        for feature, name in enumerate(inputs.features):
            collected = [record for record in rounds if record.stump.feature == feature]
            cuts = sorted({cut for record in collected for cut in record.stump.thresholds})
            values = [ordered_sum(record.stump.values[0] for record in collected)]
            for cut in cuts:
                values.append(ordered_sum(
                    record.stump.values[bisect_right(record.stump.thresholds, cut)]
                    for record in collected
                ))
            lines.append(
                f"feature {name} rounds {len(collected)} cuts {len(cuts)} "
                f"range {number(max(values) - min(values))}"
            )
            for index, value in enumerate(values):
                lower = "-inf" if index == 0 else number(cuts[index - 1])
                upper = "inf" if index == len(cuts) else number(cuts[index])
                lines.append(f"interval {lower} {upper} value {number(value)}")
    return lines


def calibration_lines(variant, rows, scores):
    counts = [0] * 5
    totals = [0.0] * 5
    positives = [0] * 5
    brier = 0.0
    for row, score in zip(rows, scores):
        probability = 1 / (1 + exp(-2 * score))
        target = 1 if row.label == 1 else 0
        difference = probability - target
        brier += difference * difference
        index = min(4, floor(probability * 5))
        counts[index] += 1
        totals[index] += probability
        positives[index] += target
    lines = [f"calibration {variant} brier {number(brier / len(rows))}"]
    ranges = ("0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0")
    for index, interval in enumerate(ranges):
        lines.append(
            f"bin {interval} count {counts[index]} mean {ratio(totals[index], counts[index])} "
            f"positives {positives[index]}"
        )
    return lines


def comparison_lines(inputs, analysis):
    predictions = {
        variant: list(map(prediction, analysis[variant]["test"]))
        for variant in inputs.params.variants
    }
    all_wrong = [
        row.id for index, row in enumerate(inputs.test)
        if all(predictions[variant][index] != row.label for variant in inputs.params.variants)
    ]
    lines = [" ".join(["all_wrong", str(len(all_wrong)), *all_wrong]), "agreement"]
    for first, second in combinations(inputs.params.variants, 2):
        agree = only_first = only_second = 0
        for index, row in enumerate(inputs.test):
            a = predictions[first][index]
            b = predictions[second][index]
            agree += a == b
            only_first += a == row.label and b != row.label
            only_second += b == row.label and a != row.label
        difference = abs(only_first - only_second) - 1
        lines.append(
            f"{first} {second} agree {agree}/{len(inputs.test)} only_first {only_first} "
            f"only_second {only_second} chi2 {ratio(difference * difference, only_first + only_second)}"
        )
    return lines


def bootstrap_lines(inputs, analysis):
    samples, seed = inputs.params.bootstrap
    generator = Minstd(seed)
    correct = {
        variant: [prediction(score) == row.label for row, score in zip(inputs.test, result["test"])]
        for variant, result in analysis.items()
    }
    counts = {variant: [] for variant in inputs.params.variants}
    for _ in range(samples):
        selected = [generator.draw() % len(inputs.test) for _ in inputs.test]
        for variant in inputs.params.variants:
            counts[variant].append(sum(correct[variant][index] for index in selected))
    lines = [f"bootstrap samples {samples} seed {seed}"]
    trim = samples // 40
    for variant in inputs.params.variants:
        ordered = sorted(counts[variant])
        lines.append(
            f"{variant} mean {ratio(sum(counts[variant]), samples * len(inputs.test))} "
            f"low {ratio(ordered[trim], len(inputs.test))} "
            f"high {ratio(ordered[samples - trim - 1], len(inputs.test))}"
        )
    for first, second in combinations(inputs.params.variants, 2):
        wins = ties = losses = 0
        for a, b in zip(counts[first], counts[second]):
            wins += a > b
            ties += a == b
            losses += a < b
        lines.append(f"{first} {second} first {wins} tie {ties} second {losses}")
    return lines


def feature_summary(rows, feature):
    values = [row.values[feature] for row in rows]
    return (
        f"{number(min(values))} {number(max(values))} "
        f"{number(ordered_sum(values) / len(values))} {len(set(values))}"
    )


def summary_lines(inputs, analysis, cv):
    training, testing, params = inputs.train, inputs.test, inputs.params
    lines = [
        f"data train {len(training)} test {len(testing)} features {len(inputs.features)} "
        f"positives {sum(row.label == 1 for row in training)} "
        f"{sum(row.label == 1 for row in testing)}"
    ]
    for feature, name in enumerate(inputs.features):
        lines.append(
            f"feature {name} train {feature_summary(training, feature)} "
            f"test {feature_summary(testing, feature)}"
        )
    selected = cv["selected"]
    errors = cv["errors"][selected - 1]
    lines.append(f"cv selected {selected} errors {errors}/{len(training)} rate {ratio(errors, len(training))}")
    lines.append(metrics_line("oof", "discrete", selected, training, cv["scores"]))
    committee_train = [0.0] * len(training)
    committee_test = [0.0] * len(testing)
    committee_rounds = 0
    for variant in params.variants:
        result = analysis[variant]
        rounds = len(result["rounds"])
        lines.append(metrics_line("train", variant, rounds, training, result["train"]))
        lines.append(metrics_line("test", variant, rounds, testing, result["test"]))
        committee_rounds += rounds
        for index, score in enumerate(result["train"]):
            committee_train[index] += score / result["scale"]
        for index, score in enumerate(result["test"]):
            committee_test[index] += score / result["scale"]
    lines.append(metrics_line("train", "committee", committee_rounds, training, committee_train))
    lines.append(metrics_line("test", "committee", committee_rounds, testing, committee_test))
    for variant in params.variants:
        curve = analysis[variant]["curve"]
        train_minimum = min(curve, key=lambda point: point["train_errors"])
        test_minimum = min(curve, key=lambda point: point["test_errors"])
        lines.append(
            f"curve {variant} rounds {len(curve)} train_min {train_minimum['train_errors']}/{len(training)} "
            f"at {train_minimum['round']} test_min {test_minimum['test_errors']}/{len(testing)} "
            f"at {test_minimum['round']}"
        )
    lines.extend(comparison_lines(inputs, analysis))
    lines.extend(bootstrap_lines(inputs, analysis))
    for variant in params.variants:
        lines.extend(calibration_lines(variant, testing, analysis[variant]["test"]))
    return lines


def class_prediction(scores):
    return max(range(len(scores)), key=scores.__getitem__) + 1


def class_errors(rows, predictions):
    return sum(row.label != predicted for row, predicted in zip(rows, predictions))


def samme_progression(rounds, training, testing, classes):
    train_scores = [[0.0] * classes for _ in training]
    test_scores = [[0.0] * classes for _ in testing]
    curve = []
    for round_number, record in enumerate(rounds, 1):
        for rows, scores in ((training, train_scores), (testing, test_scores)):
            for row, row_scores in zip(rows, scores):
                row_scores[record.stump(row.values) - 1] += record.alpha
        train_predictions = list(map(class_prediction, train_scores))
        test_predictions = list(map(class_prediction, test_scores))
        curve.append((
            round_number, class_errors(training, train_predictions),
            class_errors(testing, test_predictions),
        ))
    return train_scores, test_scores, curve


def confusion_lines(rows, predictions, classes):
    matrix = confusion(rows, predictions, classes)
    lines = ["confusion"]
    lines.extend(" ".join(map(str, row)) for row in matrix)
    for index in range(classes):
        true_positive = matrix[index][index]
        predicted = sum(row[index] for row in matrix)
        actual = sum(matrix[index])
        lines.append(
            f"class {index + 1} precision {ratio(true_positive, predicted)} "
            f"recall {ratio(true_positive, actual)}"
        )
    return lines


def multiclass_report(inputs):
    training, testing, params = inputs.multi_train, inputs.multi_test, inputs.params
    model = train_samme(training, params.samme_rounds, params.classes)
    train_scores, test_scores, curve = samme_progression(
        model.rounds, training, testing, params.classes
    )
    train_predictions = list(map(class_prediction, train_scores))
    test_predictions = list(map(class_prediction, test_scores))
    lines = [
        f"samme classes {params.classes} train {len(training)} test {len(testing)} "
        f"rounds {len(model.rounds)} stop {model.stop}"
    ]
    for round_number, record in enumerate(model.rounds, 1):
        stump = record.stump
        lines.append(
            f"round {round_number} feature {inputs.multi_features[stump.feature]} "
            f"threshold {number(stump.thresholds[0])} left {stump.values[0]} right {stump.values[1]} "
            f"error {number(record.error)} alpha {number(record.alpha)}"
        )
    for kind, rows, predictions in (("train", training, train_predictions), ("test", testing, test_predictions)):
        count = class_errors(rows, predictions)
        lines.append(f"{kind} errors {count}/{len(rows)} rate {ratio(count, len(rows))}")
    lines.extend(confusion_lines(testing, test_predictions, params.classes))
    importance = magnitude_importance(model.rounds, len(inputs.multi_features), samme=True)
    lines.extend(importance_lines(importance, inputs.multi_features))
    lines.extend(["", f"ovr classes {params.classes} rounds {params.samme_rounds}"])
    ovr_train_scores = []
    ovr_test_scores = []
    for klass in range(1, params.classes + 1):
        binary_training = [row._replace(label=1 if row.label == klass else -1) for row in training]
        binary_testing = [row._replace(label=1 if row.label == klass else -1) for row in testing]
        binary_model = train_discrete(binary_training, params.samme_rounds)
        binary_train_scores = score_rows(binary_model.rounds, binary_training)
        binary_test_scores = score_rows(binary_model.rounds, binary_testing)
        ovr_train_scores.append(binary_train_scores)
        ovr_test_scores.append(binary_test_scores)
        positives = sum(row.label == klass for row in training)
        lines.append(
            f"class {klass} rounds {len(binary_model.rounds)} stop {binary_model.stop} "
            f"positives {positives} train_errors {count_errors(binary_training, binary_train_scores)}/{len(training)} "
            f"test_errors {count_errors(binary_testing, binary_test_scores)}/{len(testing)}"
        )
    ovr_train_predictions = [class_prediction(scores) for scores in zip(*ovr_train_scores)]
    ovr_test_predictions = [class_prediction(scores) for scores in zip(*ovr_test_scores)]
    for kind, rows, predictions in (("train", training, ovr_train_predictions), ("test", testing, ovr_test_predictions)):
        count = class_errors(rows, predictions)
        lines.append(f"{kind} errors {count}/{len(rows)} rate {ratio(count, len(rows))}")
    lines.extend(confusion_lines(testing, ovr_test_predictions, params.classes))
    agreement = sum(first == second for first, second in zip(test_predictions, ovr_test_predictions))
    lines.extend([f"agreement {agreement}/{len(testing)}", "", "predictions"])
    for row, samme, ovr, scores in zip(testing, test_predictions, ovr_test_predictions, test_scores):
        lines.append(
            f"{row.id} class {row.label} samme {samme} ovr {ovr} scores "
            + " ".join(map(number, scores))
        )
    return lines, curve


def model_errors(model, training, testing):
    return (
        count_errors(training, score_rows(model.rounds, training)),
        count_errors(testing, score_rows(model.rounds, testing)),
    )


def test_minimum(rounds, testing):
    scores = [0.0] * len(testing)
    counts = []
    for record in rounds:
        add_round_scores(record, testing, scores)
        counts.append(count_errors(testing, scores))
    index = min(range(len(counts)), key=counts.__getitem__)
    return counts[index], index + 1


def experiment_lines(inputs, analysis, selected):
    training, testing, params = inputs.train, inputs.test, inputs.params
    lines = []
    for percentage in params.sizes:
        size = len(training) * percentage // 100
        subset = training[:size]
        lines.append(f"size {percentage} rows {size}")
        for variant in params.variants:
            model = train_variant(variant, subset, params)
            train_errors, test_errors = model_errors(model, subset, testing)
            lines.append(
                f"{variant} rounds {len(model.rounds)} stop {model.stop} "
                f"train_errors {train_errors}/{size} test_errors {test_errors}/{len(testing)}"
            )
    for shrinkage in params.shrinkage:
        model = train_discrete(training, params.rounds, shrinkage=shrinkage)
        train_errors, test_errors = model_errors(model, training, testing)
        minimum, at = test_minimum(model.rounds, testing)
        lines.append(
            f"shrinkage {number(shrinkage)} rounds {len(model.rounds)} stop {model.stop} "
            f"train_errors {train_errors}/{len(training)} test_errors {test_errors}/{len(testing)} "
            f"test_min {minimum}/{len(testing)} at {at}"
        )
    ranked = analysis["discrete"]["importance"]["order"]
    for count in range(1, len(inputs.features) + 1):
        features = sorted(ranked[:count])
        reduced_training = [row._replace(values=tuple(row.values[j] for j in features)) for row in training]
        reduced_testing = [row._replace(values=tuple(row.values[j] for j in features)) for row in testing]
        model = train_discrete(reduced_training, selected)
        train_errors, test_errors = model_errors(model, reduced_training, reduced_testing)
        names = " ".join(inputs.features[feature] for feature in features)
        lines.append(
            f"top {count} features {names} rounds {len(model.rounds)} "
            f"train_errors {train_errors}/{len(training)} test_errors {test_errors}/{len(testing)}"
        )
    for percentage in params.noise:
        flipped_count = len(training) * percentage // 100
        generator = Minstd(params.noise_seed)
        permutation = list(range(len(training)))
        for index in range(flipped_count):
            other = generator.draw() % (len(training) - index) + index
            permutation[index], permutation[other] = permutation[other], permutation[index]
        flipped = set(permutation[:flipped_count])
        noisy = [
            row._replace(label=-row.label) if index in flipped else row
            for index, row in enumerate(training)
        ]
        lines.append(f"noise {percentage} flipped {flipped_count}")
        for variant in params.variants:
            model = train_variant(variant, noisy, params)
            train_errors, test_errors = model_errors(model, noisy, testing)
            minimum, at = test_minimum(model.rounds, testing)
            flipped_weight = ordered_sum(
                weight for index, weight in enumerate(model.rounds[-1].weights) if index in flipped
            )
            lines.append(
                f"{variant} rounds {len(model.rounds)} stop {model.stop} "
                f"train_errors {train_errors}/{len(training)} test_errors {test_errors}/{len(testing)} "
                f"test_min {minimum}/{len(testing)} at {at} flipped_weight {number(flipped_weight)}"
            )
    return lines


def main():
    inputs = read_inputs()
    cv = cross_validate(inputs.train, inputs.params)
    analysis = analyze_variants(inputs, cv["selected"])
    samme_lines, samme_curve = multiclass_report(inputs)
    reports = {
        "ensemble.txt": ensemble_lines(inputs, analysis, cv),
        "error_curve.csv": error_curve_lines(inputs, analysis, samme_curve),
        "predictions.csv": prediction_lines(inputs, analysis),
        "roc.csv": roc_lines(inputs, analysis),
        "margins.txt": margin_lines(inputs, analysis),
        "shapes.txt": shape_lines(inputs, analysis),
        "samme.txt": samme_lines,
        "summary.txt": summary_lines(inputs, analysis, cv),
        "experiments.txt": experiment_lines(inputs, analysis, cv["selected"]),
    }
    output = Path("output")
    output.mkdir(exist_ok=True)
    for filename, lines in reports.items():
        write_lines(output / filename, lines)


if __name__ == "__main__":
    main()
