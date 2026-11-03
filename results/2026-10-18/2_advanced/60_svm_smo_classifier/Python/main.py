"""Train, compare, analyze, and report the deterministic SVM experiments."""

from math import exp, floor, log, sqrt

from dataset import read_inputs
from evaluation import (
    auc, binary_counts, confusion_lines, confusion_matrix, correct_count,
    fixed, folds, ratio, sign, write_lines,
)
from kernels import submatrix
from multiclass import MulticlassModels, PAIRS
from smo import train


def support_counts(model):
    total = sum(alpha > 0 for alpha in model.alpha)
    bound = sum(alpha > 0 and alpha == model.C for alpha in model.alpha)
    return total, bound, total - bound


def support_text(model):
    total, bound, free = support_counts(model)
    return f"support_vectors {total} bound {bound} free {free}"


def run_info(model):
    convergence = "yes" if model.converged else "no"
    return f"passes {model.passes} steps {model.steps} converged {convergence}"


def objectives(model, alpha=None):
    if alpha is None:
        alpha = model.alpha
    scores = []
    for row in model.matrix:
        score = 0.0
        for index, coefficient in enumerate(alpha):
            if coefficient > 0:
                score += coefficient * model.labels[index] * row[index]
        scores.append(score)
    quadratic = 0.0
    alpha_total = 0.0
    for index, coefficient in enumerate(alpha):
        quadratic += coefficient * model.labels[index] * scores[index]
        alpha_total += coefficient
    return quadratic, alpha_total - quadratic / 2


def cross_validate(training, settings):
    points = [example.point for example in training]
    labels = [example.label for example in training]
    partitions = folds(len(training), settings.folds)
    matrices = []
    combinations = []
    best = []
    for kernel_index, kernel in enumerate(settings.kernels):
        matrix = kernel.matrix(points)
        matrices.append(matrix)
        candidates = []
        for coefficient in settings.c_grid:
            decisions = [0.0] * len(training)
            fold_results = []
            total_correct = total_support = total_passes = total_steps = 0
            for train_indices, test_indices in partitions:
                fold_points = [points[i] for i in train_indices]
                fold_labels = [labels[i] for i in train_indices]
                fold_matrix = submatrix(matrix, train_indices)
                model = train(fold_points, fold_labels, kernel, fold_matrix, coefficient, settings)
                correct = 0
                for index in test_indices:
                    value = model.decision(points[index])
                    decisions[index] = value
                    if sign(value) == labels[index]:
                        correct += 1
                support = support_counts(model)[0]
                fold_results.append({
                    "train": len(train_indices), "test": len(test_indices),
                    "correct": correct, "support": support, "model": model,
                })
                total_correct += correct
                total_support += support
                total_passes += model.passes
                total_steps += model.steps
            result = {
                "kernel": kernel, "kernel_index": kernel_index, "C": coefficient,
                "values": decisions, "folds": fold_results, "correct": total_correct,
                "support": total_support, "passes": total_passes, "steps": total_steps,
            }
            candidates.append(result)
            combinations.append(result)
        best.append(min(candidates, key=lambda result: (-result["correct"], result["C"])))
    def ranking_key(result):
        return -result["correct"], result["C"], result["kernel_index"]

    selected = min(best, key=ranking_key)
    ranking = sorted(combinations, key=ranking_key)
    return matrices, combinations, best, selected, ranking


def cross_validation_lines(size, fold_count, best, selected, ranking):
    lines = [f"cross_validation folds {fold_count} examples {size}"]
    for result in best:
        lines.append(
            f"best {result['kernel'].name} C {fixed(result['C'])} "
            f"correct {result['correct']}/{size} accuracy {ratio(result['correct'], size)}"
        )
    name = selected["kernel"].name
    lines.extend([f"selected {name} C {fixed(selected['C'])}", "ranking"])
    for rank, result in enumerate(ranking, 1):
        lines.append(
            f"{rank} {result['kernel'].name} C {fixed(result['C'])} "
            f"correct {result['correct']}/{size}"
        )
    lines.append(f"cv_detail {name} C {fixed(selected['C'])}")
    for fold_number, result in enumerate(selected["folds"], 1):
        lines.append(
            f"fold {fold_number} train {result['train']} test {result['test']} "
            f"correct {result['correct']} support_vectors {result['support']} "
            f"{run_info(result['model'])}"
        )
    return lines


def evaluate_final(model, training, testing, tolerance):
    n, m = len(training), len(testing)
    train_values = model.training_decisions()
    test_values = [model.decision(example.point) for example in testing]
    test_labels = [example.label for example in testing]
    quadratic, dual = objectives(model)
    label_alignment = matrix_squares = 0.0
    for i, row in enumerate(model.matrix):
        for j, value in enumerate(row):
            label_alignment += model.labels[i] * model.labels[j] * value
            matrix_squares += value * value
    alignment = label_alignment / (n * sqrt(matrix_squares))
    equality = 0.0
    w1 = w2 = 0.0
    class_counts = {1: {"bound": 0, "free": 0}, -1: {"bound": 0, "free": 0}}
    for example, alpha in zip(training, model.alpha):
        equality += alpha * example.label
        if model.kernel.kind == "linear":
            w1 += alpha * example.label * example.point[0]
            w2 += alpha * example.label * example.point[1]
        if alpha > 0:
            category = "bound" if alpha == model.C else "free"
            class_counts[example.label][category] += 1
    norm = sqrt(quadratic)
    radius = max(model.matrix[i][i] for i in range(n)) - min(
        value for row in model.matrix for value in row
    )
    hinge_total = 0.0
    violation_count = estimated_errors = 0
    largest_violation = 0.0
    for alpha, label, value in zip(model.alpha, model.labels, train_values):
        hinge = max(0.0, 1 - label * value)
        hinge_total += hinge
        residual = label * value - 1
        if alpha == 0:
            violation = max(0.0, -residual)
        elif alpha == model.C:
            violation = max(0.0, residual)
        else:
            violation = abs(residual)
        if violation > tolerance:
            violation_count += 1
        largest_violation = max(largest_violation, violation)
        if 2 * alpha * radius + hinge >= 1:
            estimated_errors += 1
    primal = quadratic / 2 + model.C * hinge_total
    train_correct = correct_count(model.labels, train_values)
    tp, fp, tn, fn = binary_counts(test_labels, test_values)
    inside_margin = 0
    positive_total = negative_total = 0.0
    for label, value in zip(test_labels, test_values):
        if abs(value) < 1:
            inside_margin += 1
        if label == 1:
            positive_total += value
        else:
            negative_total += value
    convergence = "yes" if model.converged else "no"
    choices, clipping = model.choices, model.clipping
    positive, negative = class_counts[1], class_counts[-1]
    lines = [
        f"model {model.kernel.name}",
        f"kernel {model.kernel.description()}",
        f"C {fixed(model.C)}",
        f"alignment {fixed(alignment, 6)}",
        f"passes {model.passes} full {model.full_passes} nonbound {model.nonbound_passes} "
        f"converged {convergence}",
        f"examined {model.examined} steps {model.steps}",
        f"choice heuristic {choices['heuristic']} nonbound_loop {choices['nonbound_loop']} "
        f"full_loop {choices['full_loop']}",
        f"clipping none {clipping['none']} lower {clipping['lower']} upper {clipping['upper']}",
        support_text(model),
        f"b {fixed(model.b, 6)}",
        f"equality {fixed(equality, 6)}",
    ]
    if model.kernel.kind == "linear":
        lines.append(f"w {fixed(w1, 6)} {fixed(w2, 6)}")
    lines.extend([
        f"sv_by_class positive bound {positive['bound']} free {positive['free']} "
        f"negative bound {negative['bound']} free {negative['free']}",
        f"norm {fixed(norm, 6)} margin {fixed(2 / norm, 6)}",
        f"dual_objective {fixed(dual, 6)}",
        f"primal_objective {fixed(primal, 6)}",
        f"duality_gap {fixed(primal - dual, 6)}",
        f"kkt_violations {violation_count} max {fixed(largest_violation, 6)}",
        f"xi_alpha radius {fixed(radius, 6)} errors {estimated_errors}/{n} "
        f"accuracy {ratio(n - estimated_errors, n)}",
        f"train correct {train_correct}/{n} accuracy {ratio(train_correct, n)}",
        f"test correct {tp + tn}/{m} accuracy {ratio(tp + tn, m)} "
        f"tp {tp} fp {fp} tn {tn} fn {fn}",
        f"test precision {ratio(tp, tp + fp)} recall {ratio(tp, tp + fn)} "
        f"f1 {ratio(2 * tp, 2 * tp + fp + fn)} auc {fixed(auc(test_labels, test_values))}",
        f"test inside_margin {inside_margin}",
        f"test mean_decision positive {fixed(positive_total / (tp + fn))} "
        f"negative {fixed(negative_total / (fp + tn))}",
    ])
    for example, alpha, value in zip(training, model.alpha, train_values):
        if alpha > 0:
            category = "bound" if alpha == model.C else "free"
            lines.append(
                f"sv {example.id} y {example.label} alpha {fixed(alpha, 6)} "
                f"f {fixed(value)} {category}"
            )
    return {
        "model": model, "train_values": train_values, "test_values": test_values,
        "weights": (w1, w2), "lines": lines,
    }


def training_log(model):
    lines = [f"training_log {model.kernel.name}"]
    index = 0
    while index < len(model.records):
        record = model.records[index]
        if record["full"]:
            dual = objectives(model, record["alpha"])[1]
            lines.append(
                f"pass {index + 1} full examined {record['examined']} "
                f"changed {record['changed']} dual_objective {fixed(dual, 6)}"
            )
            index += 1
        else:
            first = index + 1
            examined = changed = 0
            while index < len(model.records) and not model.records[index]["full"]:
                examined += model.records[index]["examined"]
                changed += model.records[index]["changed"]
                index += 1
            lines.append(
                f"passes {first}-{index} nonbound examined {examined} changed {changed}"
            )
    return lines


def c_path(training, testing, selected, matrix, settings):
    kernel = selected["kernel"]
    points = [example.point for example in training]
    labels = [example.label for example in training]
    test_labels = [example.label for example in testing]
    lines = [f"c_path {kernel.name}"]
    for coefficient in settings.c_grid:
        model = train(points, labels, kernel, matrix, coefficient, settings)
        dual = objectives(model)[1]
        train_correct = correct_count(labels, model.training_decisions())
        test_values = [model.decision(example.point) for example in testing]
        test_correct = correct_count(test_labels, test_values)
        lines.append(
            f"C {fixed(coefficient)} {support_text(model)} dual_objective {fixed(dual, 6)} "
            f"train {train_correct}/{len(training)} test {test_correct}/{len(testing)} "
            f"{run_info(model)}"
        )
    return lines


def learning_curve(training, testing, selected, matrix, settings):
    kernel, coefficient = selected["kernel"], selected["C"]
    test_labels = [example.label for example in testing]
    lines = [f"learning_curve {kernel.name} C {fixed(coefficient)}"]
    for percentage in settings.learning_curve:
        size = len(training) * percentage // 100
        examples = training[:size]
        points = [example.point for example in examples]
        labels = [example.label for example in examples]
        curve_matrix = submatrix(matrix, range(size))
        model = train(points, labels, kernel, curve_matrix, coefficient, settings)
        train_correct = correct_count(labels, model.training_decisions())
        test_values = [model.decision(example.point) for example in testing]
        test_correct = correct_count(test_labels, test_values)
        lines.append(
            f"size {size} support_vectors {support_counts(model)[0]} "
            f"train {train_correct}/{size} test {test_correct}/{len(testing)} {run_info(model)}"
        )
    return lines


def probability(value, coefficient, intercept):
    return 1 / (1 + exp(coefficient * value + intercept))


def negative_log_likelihood(values, targets, coefficient, intercept):
    total = 0.0
    for value, target in zip(values, targets):
        p = probability(value, coefficient, intercept)
        total += target * log(p) + (1 - target) * log(1 - p)
    return -total


def calibrate(training, testing, selected, test_values, iterations):
    positive_count = sum(example.label == 1 for example in training)
    negative_count = len(training) - positive_count
    targets = [
        (positive_count + 1) / (positive_count + 2) if example.label == 1
        else 1 / (negative_count + 2)
        for example in training
    ]
    values = selected["values"]
    coefficient = 0.0
    intercept = log((negative_count + 1) / (positive_count + 1))
    nll = negative_log_likelihood(values, targets, coefficient, intercept)
    lines = [
        f"calibration {selected['kernel'].name} C {fixed(selected['C'])} "
        f"positives {positive_count} negatives {negative_count}",
        f"start A {fixed(coefficient, 6)} B {fixed(intercept, 6)} nll {fixed(nll, 6)}",
    ]
    for iteration in range(1, iterations + 1):
        g1 = g2 = h11 = h21 = h22 = 0.0
        for value, target in zip(values, targets):
            p = probability(value, coefficient, intercept)
            g1 += value * (target - p)
            g2 += target - p
            h11 += value * value * p * (1 - p)
            h21 += value * p * (1 - p)
            h22 += p * (1 - p)
        determinant = h11 * h22 - h21 * h21
        coefficient = coefficient - (h22 * g1 - h21 * g2) / determinant
        intercept = intercept - (h11 * g2 - h21 * g1) / determinant
        nll = negative_log_likelihood(values, targets, coefficient, intercept)
        lines.append(
            f"iteration {iteration} A {fixed(coefficient, 6)} B {fixed(intercept, 6)} "
            f"nll {fixed(nll, 6)}"
        )
    probabilities = [probability(value, coefficient, intercept) for value in test_values]
    log_total = brier_total = 0.0
    bins = [{"count": 0, "total": 0.0, "positive": 0} for _ in range(5)]
    for example, p in zip(testing, probabilities):
        positive = example.label == 1
        log_total += log(p) if positive else log(1 - p)
        difference = p - (1 if positive else 0)
        brier_total += difference * difference
        bin_result = bins[min(4, floor(p * 5))]
        bin_result["count"] += 1
        bin_result["total"] += p
        bin_result["positive"] += int(positive)
    lines.append(
        f"test log_loss {fixed(-log_total / len(testing), 6)} "
        f"brier {fixed(brier_total / len(testing), 6)}"
    )
    ranges = ("0.0-0.2", "0.2-0.4", "0.4-0.6", "0.6-0.8", "0.8-1.0")
    for name, bin_result in zip(ranges, bins):
        count = bin_result["count"]
        mean = fixed(bin_result["total"] / count) if count else "-"
        lines.append(
            f"bin {name} count {count} mean_probability {mean} "
            f"positive_rate {ratio(bin_result['positive'], count)}"
        )
    closest = sorted(range(len(testing)), key=lambda index: abs(test_values[index]))[:5]
    for index in closest:
        example = testing[index]
        lines.append(
            f"closest {example.id} label {example.label} decision {fixed(test_values[index])} "
            f"probability {fixed(probabilities[index])}"
        )
    return coefficient, intercept, probabilities, lines


def linear_decision(weights, point):
    w1, w2, bias = weights
    return w1 * point[0] + w2 * point[1] + bias


def pegasos(training, testing, parameters, comparison):
    regularization, iterations, seed = parameters
    state = seed
    w1 = w2 = bias = 0.0
    sum1 = sum2 = sum_bias = 0.0
    updates = 0
    n, m = len(training), len(testing)
    train_labels = [example.label for example in training]
    test_labels = [example.label for example in testing]
    lines = [f"pegasos lambda {fixed(regularization)} iterations {iterations} seed {seed}"]
    for iteration in range(1, iterations + 1):
        state = 48271 * state % 2147483647
        example = training[state % n]
        eta = 1 / (regularization * iteration)
        sigma = 1 - eta * regularization
        if example.label * linear_decision((w1, w2, bias), example.point) < 1:
            w1 = sigma * w1 + eta * example.label * example.point[0]
            w2 = sigma * w2 + eta * example.label * example.point[1]
            bias = sigma * bias + eta * example.label
            updates += 1
        else:
            w1 = sigma * w1
            w2 = sigma * w2
            bias = sigma * bias
        sum1 += w1
        sum2 += w2
        sum_bias += bias
        if iteration % (iterations // 10) == 0:
            train_values = [
                linear_decision((w1, w2, bias), item.point) for item in training
            ]
            hinge_total = 0.0
            for label, value in zip(train_labels, train_values):
                hinge_total += max(0.0, 1 - label * value)
            objective = regularization / 2 * (w1 * w1 + w2 * w2 + bias * bias) + hinge_total / n
            correct = correct_count(train_labels, train_values)
            lines.append(
                f"checkpoint {iteration} objective {fixed(objective, 6)} train {correct}/{n}"
            )
    weights = (w1, w2, bias)
    average = (sum1 / iterations, sum2 / iterations, sum_bias / iterations)
    train_values = [linear_decision(weights, example.point) for example in training]
    test_values = [linear_decision(weights, example.point) for example in testing]
    average_values = [linear_decision(average, example.point) for example in testing]
    train_correct = correct_count(train_labels, train_values)
    test_correct = correct_count(test_labels, test_values)
    average_correct = correct_count(test_labels, average_values)
    v1, v2 = comparison["weights"]
    cosine = (w1 * v1 + w2 * v2) / (sqrt(w1 * w1 + w2 * w2) * sqrt(v1 * v1 + v2 * v2))
    agreement = sum(
        sign(first) == sign(second)
        for first, second in zip(test_values, comparison["test_values"])
    )
    lines.extend([
        f"updates {updates}",
        f"w {fixed(w1, 6)} {fixed(w2, 6)} bias {fixed(bias, 6)}",
        f"train correct {train_correct}/{n} accuracy {ratio(train_correct, n)}",
        f"test correct {test_correct}/{m} accuracy {ratio(test_correct, m)}",
        f"average w {fixed(average[0], 6)} {fixed(average[1], 6)} "
        f"bias {fixed(average[2], 6)} test correct {average_correct}/{m}",
        f"compare {comparison['model'].kernel.name} cosine {fixed(cosine, 6)} "
        f"test_agreement {agreement}/{m}",
    ])
    return test_values, lines


def mcnemar_lines(testing, final_results, pegasos_values):
    names = [result["model"].kernel.name for result in final_results] + ["pegasos"]
    values = [result["test_values"] for result in final_results] + [pegasos_values]
    correctness = [
        [sign(value) == example.label for value, example in zip(decisions, testing)]
        for decisions in values
    ]
    lines = ["mcnemar"]
    for first in range(len(names)):
        for second in range(first + 1, len(names)):
            only_first = only_second = 0
            for a, b in zip(correctness[first], correctness[second]):
                if a and not b:
                    only_first += 1
                elif b and not a:
                    only_second += 1
            denominator = only_first + only_second
            difference = abs(only_first - only_second) - 1
            chi2 = fixed(difference * difference / denominator) if denominator else "-"
            lines.append(
                f"{names[first]} {names[second]} only_first {only_first} "
                f"only_second {only_second} chi2 {chi2}"
            )
    return lines


def multiclass_summary(role, examples, classifications):
    rest_correct = pair_correct = agreement = ties = 0
    for example, result in zip(examples, classifications):
        rest_correct += int(result.ovr == example.class_number)
        pair_correct += int(result.ovo == example.class_number)
        agreement += int(result.ovr == result.ovo)
        ties += int(result.tied)
    size = len(examples)
    return (
        f"{role} ovr {rest_correct}/{size} {ratio(rest_correct, size)} "
        f"ovo {pair_correct}/{size} {ratio(pair_correct, size)} "
        f"agreement {agreement}/{size} vote_ties {ties}"
    )


def multiclass_lines(training, testing, models):
    train_results = [models.classify(example.point) for example in training]
    test_results = [models.classify(example.point) for example in testing]
    n, m = len(training), len(testing)
    lines = [
        f"multiclass kernel {models.kernel.name} C {fixed(models.C)} "
        f"classes 3 train {n} test {m}",
        "ovr",
    ]
    for index, model in enumerate(models.ovr_models):
        correct = 0
        for example, result in zip(testing, test_results):
            expected = 1 if example.class_number == index + 1 else -1
            correct += int(sign(result.ovr_values[index]) == expected)
        positives = sum(label == 1 for label in model.labels)
        lines.append(
            f"model {index + 1}-rest examples {n} positives {positives} "
            f"{support_text(model)} b {fixed(model.b, 6)} {run_info(model)} test {correct}/{m}"
        )
    lines.append("ovo")
    for index, ((first, second), model) in enumerate(zip(PAIRS, models.ovo_models)):
        correct = test_count = 0
        for example, result in zip(testing, test_results):
            if example.class_number in (first, second):
                test_count += 1
                expected = 1 if example.class_number == first else -1
                correct += int(sign(result.ovo_values[index]) == expected)
        positives = sum(label == 1 for label in model.labels)
        lines.append(
            f"model {first}-{second} examples {len(model.points)} positives {positives} "
            f"{support_text(model)} b {fixed(model.b, 6)} {run_info(model)} "
            f"test {correct}/{test_count}"
        )
    lines.append("predictions")
    for example, result in zip(testing, test_results):
        rest = " ".join(fixed(value) for value in result.ovr_values)
        pair = " ".join(fixed(value) for value in result.ovo_values)
        votes = " ".join(str(value) for value in result.votes)
        lines.append(
            f"{example.id} class {example.class_number} ovr {rest} pred {result.ovr} "
            f"ovo {pair} votes {votes} pred {result.ovo}"
        )
    lines.append(multiclass_summary("train", training, train_results))
    lines.append(multiclass_summary("test", testing, test_results))
    classes = [example.class_number for example in testing]
    rest_matrix = confusion_matrix(classes, [result.ovr for result in test_results])
    pair_matrix = confusion_matrix(classes, [result.ovo for result in test_results])
    lines.append("confusion ovr")
    lines.extend(confusion_lines(rest_matrix))
    lines.append("confusion ovo")
    lines.extend(confusion_lines(pair_matrix))
    return lines


def framed_plot(cells, width, height):
    border = "+" + "-" * width + "+"
    lines = [border]
    for row in range(height):
        lines.append("|" + "".join(cells[row * width:(row + 1) * width]) + "|")
    lines.append(border)
    return lines


def plot_cell(point, x_min, y_max, dx, dy, width, height):
    column = floor((point[0] - x_min) / dx)
    row = floor((y_max - point[1]) / dy)
    if 0 <= column < width and 0 <= row < height:
        return row * width + column
    return None


def decision_plots(training, multi_training, final_results, selected, calibration, multi, settings):
    width, height = settings.plot_size
    x_min, x_max = settings.plot_x
    y_min, y_max = settings.plot_y
    dx = (x_max - x_min) / width
    dy = (y_max - y_min) / height
    cell_count = width * height
    coefficient, intercept = calibration
    model = final_results[selected["kernel_index"]]["model"]
    binary_cells, probability_cells, multi_cells = [], [], []
    grid_signs = [[] for _ in final_results]
    levels = [0] * 10
    for row in range(height):
        for column in range(width):
            point = (x_min + (column + 0.5) * dx, y_max - (row + 0.5) * dy)
            values = [result["model"].decision(point) for result in final_results]
            value = values[selected["kernel_index"]]
            if value >= 1:
                character = "+"
            elif value > 0:
                character = "."
            elif value > -1:
                character = "-"
            else:
                character = " "
            binary_cells.append(character)
            level = min(9, floor(probability(value, coefficient, intercept) * 10))
            probability_cells.append(str(level))
            levels[level] += 1
            for signs, decision in zip(grid_signs, values):
                signs.append(sign(decision))
            result = multi.classify(point)
            multi_cells.append("?" if result.ovr != result.ovo else (" ", ".", ":")[result.ovr - 1])
    binary_assignments = [None] * cell_count
    binary_outside = 0
    for index, example in enumerate(training):
        cell = plot_cell(example.point, x_min, y_max, dx, dy, width, height)
        if cell is None:
            binary_outside += 1
            continue
        previous = binary_assignments[cell]
        if previous is None or (model.alpha[index] > 0 and model.alpha[previous] <= 0):
            binary_assignments[cell] = index
    binary_points = 0
    for cell, index in enumerate(binary_assignments):
        if index is not None:
            binary_points += 1
            is_support = model.alpha[index] > 0
            if training[index].label == 1:
                binary_cells[cell] = "X" if is_support else "x"
            else:
                binary_cells[cell] = "O" if is_support else "o"
    multi_assignments = [None] * cell_count
    multi_outside = 0
    for index, example in enumerate(multi_training):
        cell = plot_cell(example.point, x_min, y_max, dx, dy, width, height)
        if cell is None:
            multi_outside += 1
        elif multi_assignments[cell] is None:
            multi_assignments[cell] = index
    multi_points = 0
    for cell, index in enumerate(multi_assignments):
        if index is not None:
            multi_points += 1
            multi_cells[cell] = str(multi_training[index].class_number)
    lines = [
        f"binary {model.kernel.name} C {fixed(model.C)}",
        f"x {fixed(x_min)} {fixed(x_max)} y {fixed(y_min)} {fixed(y_max)} grid {width}x{height}",
    ]
    lines.extend(framed_plot(binary_cells, width, height))
    lines.extend([
        f"cells outer_positive {binary_cells.count('+')} inner_positive {binary_cells.count('.')} "
        f"inner_negative {binary_cells.count('-')} outer_negative {binary_cells.count(' ')} "
        f"points {binary_points} outside {binary_outside}",
        "",
        f"probability {model.kernel.name} A {fixed(coefficient, 6)} B {fixed(intercept, 6)}",
    ])
    lines.extend(framed_plot(probability_cells, width, height))
    lines.extend(["levels " + " ".join(str(value) for value in levels), "", "grid_agreement"])
    positive_counts = [signs.count(1) for signs in grid_signs]
    for first in range(len(final_results)):
        for second in range(first + 1, len(final_results)):
            agreement = sum(a == b for a, b in zip(grid_signs[first], grid_signs[second]))
            first_name = final_results[first]["model"].kernel.name
            second_name = final_results[second]["model"].kernel.name
            lines.append(
                f"{first_name} {second_name} {agreement}/{cell_count} "
                f"positive {positive_counts[first]} {positive_counts[second]}"
            )
    lines.extend(["", f"multiclass {multi.kernel.name} C {fixed(multi.C)}"])
    lines.extend(framed_plot(multi_cells, width, height))
    lines.append(
        f"cells class1 {multi_cells.count(' ')} class2 {multi_cells.count('.')} "
        f"class3 {multi_cells.count(':')} disagree {multi_cells.count('?')} "
        f"points {multi_points} outside {multi_outside}"
    )
    return lines


def cv_grid_lines(combinations, fold_count, size):
    header = ["kernel", "C"] + [f"fold{index}" for index in range(1, fold_count + 1)]
    header.extend(["correct", "accuracy", "support_vectors", "passes", "steps"])
    lines = [",".join(header)]
    for result in combinations:
        row = [result["kernel"].name, fixed(result["C"])]
        row.extend(str(fold["correct"]) for fold in result["folds"])
        row.extend([
            str(result["correct"]), ratio(result["correct"], size),
            str(result["support"]), str(result["passes"]), str(result["steps"]),
        ])
        lines.append(",".join(row))
    return lines


def prediction_lines(testing, final_results, selected, pegasos_values, probabilities):
    header = ["id", "label"] + [result["model"].kernel.name for result in final_results]
    header.extend(["pegasos", "predicted", "probability"])
    lines = [",".join(header)]
    selected_values = final_results[selected["kernel_index"]]["test_values"]
    for index, example in enumerate(testing):
        row = [example.id, str(example.label)]
        row.extend(fixed(result["test_values"][index]) for result in final_results)
        row.extend([
            fixed(pegasos_values[index]), str(sign(selected_values[index])),
            fixed(probabilities[index]),
        ])
        lines.append(",".join(row))
    return lines


def main():
    training, testing, multi_training, multi_testing, settings = read_inputs()
    matrices, combinations, best, selected, ranking = cross_validate(training, settings)
    points = [example.point for example in training]
    labels = [example.label for example in training]
    final_results = []
    for index, result in enumerate(best):
        model = train(points, labels, result["kernel"], matrices[index], result["C"], settings)
        final_results.append(evaluate_final(model, training, testing, settings.tolerance))
    selected_result = final_results[selected["kernel_index"]]
    selected_matrix = matrices[selected["kernel_index"]]
    sections = [cross_validation_lines(len(training), settings.folds, best, selected, ranking)]
    sections.extend(result["lines"] for result in final_results)
    sections.append(training_log(selected_result["model"]))
    sections.append(c_path(training, testing, selected, selected_matrix, settings))
    sections.append(learning_curve(training, testing, selected, selected_matrix, settings))
    coefficient, intercept, probabilities, calibration_lines = calibrate(
        training, testing, selected, selected_result["test_values"], settings.newton_iterations
    )
    sections.append(calibration_lines)
    comparison = next(result for result in final_results if result["model"].kernel.kind == "linear")
    pegasos_values, pegasos_report = pegasos(training, testing, settings.pegasos, comparison)
    sections.append(pegasos_report)
    sections.append(mcnemar_lines(testing, final_results, pegasos_values))
    multi_name, multi_coefficient = settings.multiclass
    multi_kernel = next(kernel for kernel in settings.kernels if kernel.name == multi_name)
    multi = MulticlassModels(multi_training, multi_kernel, multi_coefficient, settings)
    multi_report = multiclass_lines(multi_training, multi_testing, multi)
    plots = decision_plots(
        training, multi_training, final_results, selected, (coefficient, intercept), multi, settings
    )
    model_lines = []
    for section in sections:
        if model_lines:
            model_lines.append("")
        model_lines.extend(section)
    write_lines("output/model.txt", model_lines)
    write_lines("output/cv_grid.csv", cv_grid_lines(combinations, settings.folds, len(training)))
    write_lines(
        "output/predictions.csv",
        prediction_lines(testing, final_results, selected, pegasos_values, probabilities),
    )
    write_lines("output/multiclass.txt", multi_report)
    write_lines("output/decision_plot.txt", plots)


if __name__ == "__main__":
    main()
