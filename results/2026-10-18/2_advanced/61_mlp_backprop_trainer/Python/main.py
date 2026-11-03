"""Train and evaluate fixed-architecture image MLPs from supplied weights.

Execute from the benchmark topic directory. All inputs are in input/;
all five outputs are written into output/ with no terminal output.
"""

from collections import Counter, defaultdict
from pathlib import Path
import math

from dataset import MINSTD, load_inputs
from evaluation import (
    ascii_image, best_two, binary_frequency, class_measures,
    confusion, level_maps, ratio, real,
)
from network import (
    average_gradient, evaluate, forward, gradient, layout_for,
)
from optimizers import epoch_rate, initialize, update


def mean(values):
    return sum(values) / len(values)


def weighted_l2(values):
    return math.sqrt(sum(value * value for value in values))


def training_partition(data):
    """The final fifth of train.csv is validation; order remains unchanged."""
    images = data["train"]
    validation_count = len(images) // 5
    split = len(images) - validation_count
    return images[:split], images[split:]


def network_catalog(data):
    return {
        architecture["name"]: {
            "architecture": architecture,
            "layout": layout_for(architecture),
            "initial": data["weights"][architecture["name"]],
        }
        for architecture in data["networks"]
    }


def check_network(name, network, training, settings):
    """Backpropagation versus central differences on a fixed shuffled batch."""
    rng = MINSTD(settings["seed"])
    sequence = list(range(len(training)))
    rng.shuffle(sequence)
    images = [
        training[i] for i in sequence[:min(settings["batch_size"], len(training))]
    ]
    architecture = network["architecture"]
    layout = network["layout"]
    theta = network["initial"].copy()
    analytic, _ = average_gradient(
        architecture, layout, theta, images
    )
    checked = list(range(0, layout["parameters"], settings["gradient_stride"]))
    h = 0.00001
    passed = True
    for index in checked:
        original = theta[index]
        theta[index] = original + h
        higher = evaluate(architecture, layout, theta, images)["loss"]
        theta[index] = original - h
        lower = evaluate(architecture, layout, theta, images)["loss"]
        theta[index] = original
        derivative = (higher - lower) / (2 * h)
        error = abs(analytic[index] - derivative) / (
            max(1, abs(analytic[index]) + abs(derivative))
        )
        if error >= 0.000001:
            passed = False
    lines = [
        f"network {name}",
        f"parameters {layout['parameters']}",
        "batch " + " ".join(image["id"] for image in images),
    ]
    selected = set(checked)
    for number, layer in enumerate(layout["layers"], 1):
        weights = sum(
            index in selected
            for index in range(layer["weight_start"], layer["weight_end"])
        )
        biases = sum(
            index in selected
            for index in range(layer["bias_start"], layer["bias_end"])
        )
        lines.append(f"layer {number} weights {weights} biases {biases}")
    lines.extend([f"checked {len(checked)}",
                  f"result {'PASS' if passed else 'FAIL'}"])
    return lines


def gradient_check_lines(catalog, architectures, training, settings):
    lines = []
    for index, architecture in enumerate(architectures):
        if index:
            lines.append("")
        name = architecture["name"]
        lines.extend(check_network(name, catalog[name], training, settings))
    return lines


def train_run(definition, network, training, validation, settings):
    """Train one optimizer run from the original theta, with early stopping."""
    architecture = network["architecture"]
    layout = network["layout"]
    theta = network["initial"].copy()
    optimizer_state = initialize(definition, len(theta))
    generator = MINSTD(settings["seed"])
    order = list(range(len(training)))
    epochs = []
    correctness = []
    best_epoch = None
    best_loss = None
    best_theta = None
    saved_correct = 0
    patience_count = 0
    updates = 0
    stop = "max_epochs"
    for epoch in range(1, settings["max_epochs"] + 1):
        rate = epoch_rate(
            definition, epoch, settings["lr_step"], settings["lr_gamma"]
        )
        generator.shuffle(order)
        gradient_norms = []
        for start in range(0, len(order), settings["batch_size"]):
            image_batch = [
                training[i] for i in order[start:start + settings["batch_size"]]
            ]
            grad, _ = average_gradient(
                architecture, layout, theta, image_batch
            )
            for index, is_weight in enumerate(layout["is_weight"]):
                if is_weight:
                    grad[index] += definition["decay"] * theta[index]
            gradient_norms.append(weighted_l2(grad))
            update(theta, grad, optimizer_state, definition, rate)
            updates += 1
        train_eval = evaluate(architecture, layout, theta, training)
        validation_eval = evaluate(architecture, layout, theta, validation)
        correctness.append([
            outcome["predicted"] == outcome["label"]
            for outcome in train_eval["outcomes"]
        ])
        improved = best_epoch is None or validation_eval["loss"] < best_loss
        if improved:
            best_epoch = epoch
            best_loss = validation_eval["loss"]
            saved_correct = validation_eval["correct"]
            best_theta = theta.copy()
            patience_count = 0
        else:
            patience_count += 1
        epochs.append({
            "epoch": epoch, "lr": rate,
            "grad_norm": mean(gradient_norms),
            "train_loss": train_eval["loss"],
            "train_correct": train_eval["correct"],
            "val_loss": validation_eval["loss"],
            "val_correct": validation_eval["correct"],
            "improved": improved,
        })
        if patience_count >= settings["patience"]:
            stop = "early"
            break
    return {
        **definition, "network_data": network,
        "best_theta": best_theta, "best_epoch": best_epoch,
        "best_val_loss": best_loss, "best_val_correct": saved_correct,
        "epochs": epochs, "updates": updates,
        "stop": stop, "correctness": correctness,
    }


def training_log_lines(runs, train_count, val_count):
    lines = [
        "run,epoch,lr,grad_norm,train_loss,train_acc,"
        "val_loss,val_acc,improved"
    ]
    for run in runs:
        for record in run["epochs"]:
            lines.append(",".join([
                run["name"], str(record["epoch"]),
                real(record["lr"], 6),
                real(record["grad_norm"], 4),
                real(record["train_loss"], 6),
                ratio(record["train_correct"], train_count),
                real(record["val_loss"], 6),
                ratio(record["val_correct"], val_count),
                "1" if record["improved"] else "0",
            ]))
    return lines


def final_weight_lines(runs):
    result = []
    for index, run in enumerate(runs):
        if index:
            result.append("")
        result.append(
            f"RUN {run['name']} NETWORK {run['network']} "
            f"EPOCH {run['best_epoch']}"
        )
        layout = run["network_data"]["layout"]
        theta = run["best_theta"]
        for number, layer in enumerate(layout["layers"], 1):
            result.append(
                f"LAYER {number} {layer['outputs']} {layer['inputs']}"
            )
            cursor = layer["weight_start"]
            for _ in range(layer["outputs"]):
                values = theta[cursor:cursor + layer["inputs"]]
                result.append("W " + " ".join(real(v, 4) for v in values))
                cursor += layer["inputs"]
            result.append(
                "B " + " ".join(
                    real(v, 4)
                    for v in theta[layer["bias_start"]:layer["bias_end"]]
                )
            )
    return result


def prepare_run_evaluation(run, training, test, settings):
    """Evaluate saved weights and cache accuracy, calibration and robustness."""
    network = run["network_data"]
    architecture = network["architecture"]
    layout = network["layout"]
    theta = run["best_theta"]
    test_eval = evaluate(architecture, layout, theta, test)
    outcomes = test_eval["outcomes"]
    run["test"] = test_eval
    run["confusion"] = confusion(outcomes, architecture["classes"])
    run["top2"] = sum(
        item["label"] in best_two(item["scores"]) for item in outcomes
    )
    correct_confidence = [
        item["confidence"] for item in outcomes
        if item["predicted"] == item["label"]
    ]
    wrong_confidence = [
        item["confidence"] for item in outcomes
        if item["predicted"] != item["label"]
    ]
    run["confidence_correct"] = (
        mean(correct_confidence) if correct_confidence else None
    )
    run["confidence_wrong"] = (
        mean(wrong_confidence) if wrong_confidence else None
    )
    statuses = run["correctness"]
    training_count = len(training)
    events_per_image = [
        sum(statuses[epoch - 1][i] and not statuses[epoch][i]
            for epoch in range(1, len(statuses)))
        for i in range(training_count)
    ]
    run["forgetting"] = {
        "events": sum(events_per_image),
        "rows": sum(count > 0 for count in events_per_image),
        "never": sum(
            not any(epoch[i] for epoch in statuses)
            for i in range(training_count)
        ),
    }
    run["weight_norms"] = []
    run["weight_changes"] = []
    for layer in layout["layers"]:
        start, end = layer["weight_start"], layer["weight_end"]
        final = theta[start:end]
        initial = network["initial"][start:end]
        run["weight_norms"].append(weighted_l2(final))
        run["weight_changes"].append(
            weighted_l2([a - b for a, b in zip(final, initial)])
        )
    calibration_bins = settings["calibration_bins"]
    bins = [[] for _ in range(calibration_bins)]
    for outcome in outcomes:
        bin_number = min(
            calibration_bins - 1,
            math.floor(outcome["confidence"] * calibration_bins)
        )
        bins[bin_number].append(outcome)
    run["calibration"] = bins
    ece = 0.0
    for bucket in bins:
        if bucket:
            accurate = sum(item["predicted"] == item["label"] for item in bucket)
            mean_confidence = mean([item["confidence"] for item in bucket])
            ece += len(bucket) / len(test) * abs(
                accurate / len(bucket) - mean_confidence
            )
    run["ece"] = ece

    layer_means = []
    for index, layer in enumerate(layout["layers"][:-1]):
        means = []
        for klass in range(architecture["classes"]):
            subset = [
                item["hidden"][index] for item in outcomes if item["label"] == klass
            ]
            means.append(
                [mean([values[j] for values in subset])
                 for j in range(layer["outputs"])]
                if subset else None
            )
        preferred = [
            max((klass for klass, values in enumerate(means)
                 if values is not None),
                key=lambda klass: (means[klass][j], -klass))
            for j in range(layer["outputs"])
        ]
        zero_counts = [
            sum(item["hidden"][index][j] == 0 for item in outcomes)
            for j in range(layer["outputs"])
        ]
        layer_means.append({
            "means": means, "preferred": preferred,
            "zero_counts": zero_counts,
        })
    run["hidden_summary"] = layer_means

    ordered_weights = sorted(
        (index for index, is_weight in enumerate(layout["is_weight"])
         if is_weight), key=lambda index: (abs(theta[index]), index)
    )
    pruning = []
    for percent in settings["prune"]:
        count = percent * len(ordered_weights) // 100
        pruned = theta.copy()
        for index in ordered_weights[:count]:
            pruned[index] = 0.0
        evaluation = evaluate(architecture, layout, pruned, test)
        pruning.append({
            "percent": percent, "removed": count,
            "correct": evaluation["correct"], "loss": evaluation["loss"],
        })
    run["pruning"] = pruning

    noise = []
    for percent in settings["noise"]:
        generator = MINSTD(settings["seed"])
        altered = []
        flipped = 0
        for image in test:
            vector = image["vector"].copy()
            for position in range(len(vector)):
                if generator.draw() % 100 < percent:
                    vector[position] = 1.0 - vector[position]
                    flipped += 1
            altered.append({**image, "vector": vector})
        evaluation = evaluate(architecture, layout, theta, altered)
        noise.append({
            "percent": percent, "flipped": flipped,
            "correct": evaluation["correct"],
        })
    run["noise_results"] = noise
    run["misclassified"] = [
        item for item in outcomes if item["predicted"] != item["label"]
    ]


def prediction_lines(runs):
    result = ["run,id,label,predicted,confidence"]
    for run in runs:
        for item in run["test"]["outcomes"]:
            result.append(",".join([
                run["name"], item["id"], str(item["label"]),
                str(item["predicted"]), real(item["confidence"], 4),
            ]))
    return result


def data_summary_lines(training, validation, test, architectures):
    width = architectures[0]["width"]
    height = architectures[0]["height"]
    pixels = width * height
    classes = architectures[0]["classes"]
    lines = [
        "data",
        f"train {len(training)} validation {len(validation)} "
        f"test {len(test)} pixels {pixels}",
    ]
    for klass in range(classes):
        train_group = [image for image in training if image["label"] == klass]
        val_count = sum(image["label"] == klass for image in validation)
        test_count = sum(image["label"] == klass for image in test)
        ink = sum(image["pixels"].count("1") for image in train_group)
        lines.append(
            f"class {klass} train {len(train_group)} "
            f"validation {val_count} test {test_count} "
            f"ink {ratio(ink, len(train_group))}"
        )
    lines.append("mean_images " + " ".join(map(str, range(classes))))
    maps = [
        binary_frequency(training, klass, pixels)
        for klass in range(classes)
    ]
    lines.extend(level_maps(maps, width, height))
    return lines


def curve_lines(run):
    maximum = max(
        max(item["train_loss"], item["val_loss"])
        for item in run["epochs"]
    )
    lines = ["curve"]
    for item in run["epochs"]:
        canvas = [" "] * 40
        training_column = math.floor(39 * item["train_loss"] / maximum + 0.5)
        validation_column = math.floor(39 * item["val_loss"] / maximum + 0.5)
        canvas[training_column] = "t"
        canvas[validation_column] = (
            "*" if validation_column == training_column else "v"
        )
        line = f"{item['epoch']:>2} |{''.join(canvas)}|"
        if item["epoch"] == run["best_epoch"]:
            line += " best"
        lines.append(line)
    return lines


def confusion_lines(run):
    table = run["confusion"]
    classes = len(table)
    lines = ["confusion"]
    for klass, row in enumerate(table):
        lines.append(f"{klass}: " + " ".join(map(str, row)))
    for klass in range(classes):
        stats = class_measures(table, klass)
        lines.append(
            f"class {klass} support {stats['support']} "
            f"predicted {stats['predicted']} "
            f"precision {stats['precision']} recall {stats['recall']} "
            f"f1 {stats['f1']}"
        )
    return lines


def calibration_lines(run, settings):
    count = settings["calibration_bins"]
    lines = ["calibration"]
    for index, bucket in enumerate(run["calibration"]):
        if bucket:
            accurate = sum(item["predicted"] == item["label"] for item in bucket)
            confidence = mean([item["confidence"] for item in bucket])
            accuracy_text = ratio(accurate, len(bucket))
            confidence_text = real(confidence, 4)
        else:
            accuracy_text = "-"
            confidence_text = "-"
        lines.append(
            f"bin {index + 1} {real(index / count, 2)} "
            f"{real((index + 1) / count, 2)} "
            f"count {len(bucket)} accuracy {accuracy_text} "
            f"confidence {confidence_text}"
        )
    lines.append(f"ece {real(run['ece'], 4)}")
    return lines


def hidden_lines(run):
    lines = []
    layout = run["network_data"]["layout"]
    classes = run["network_data"]["architecture"]["classes"]
    for layer_index, layer in enumerate(layout["layers"][:-1]):
        summary = run["hidden_summary"][layer_index]
        lines.append(
            f"hidden {layer_index + 1} {layer['activation']} "
            f"units {layer['outputs']}"
        )
        for klass in range(classes):
            values = summary["means"][klass]
            text = "-" if values is None else (
                " ".join(real(value, 4) for value in values)
            )
            lines.append(f"class {klass} mean {text}")
        lines.append(
            "preferred " + " ".join(map(str, summary["preferred"]))
        )
        if layer["activation"] == "RELU":
            lines.append(
                "zero_counts " + " ".join(map(str, summary["zero_counts"]))
            )
    return lines


def run_evaluation_lines(run, training, validation, test):
    """All required per-run evaluation blocks, preserving method and class order."""
    network = run["network_data"]
    test_eval = run["test"]
    test_count = len(test)
    correct = test_eval["correct"]
    forgetting = run["forgetting"]
    confidence_correct = run["confidence_correct"]
    confidence_wrong = run["confidence_wrong"]
    lines = [
        f"run {run['name']} network {run['network']} "
        f"optimizer {run['optimizer']}",
        f"epochs {len(run['epochs'])} best_epoch {run['best_epoch']} "
        f"stop {run['stop']} updates {run['updates']}",
        f"best_val_loss {real(run['best_val_loss'], 6)} "
        f"best_val_acc {ratio(run['best_val_correct'], len(validation))} "
        f"correct {run['best_val_correct']}/{len(validation)}",
        f"test_loss {real(test_eval['loss'], 6)} "
        f"test_acc {ratio(correct, test_count)} correct {correct}/{test_count}",
        f"top2_acc {ratio(run['top2'], test_count)} "
        f"correct {run['top2']}/{test_count}",
        f"confidence correct "
        f"{real(confidence_correct, 4) if confidence_correct is not None else '-'} "
        f"wrong {real(confidence_wrong, 4) if confidence_wrong is not None else '-'}",
        f"forgetting events {forgetting['events']} rows {forgetting['rows']} "
        f"never_learned {forgetting['never']}",
        "weight_norms " + " ".join(real(v, 4) for v in run["weight_norms"]),
        "weight_changes " + " ".join(real(v, 4) for v in run["weight_changes"]),
    ]
    lines.extend(curve_lines(run))
    lines.extend(confusion_lines(run))
    lines.extend(calibration_lines(run, network["settings"]))
    lines.extend(hidden_lines(run))
    lines.append("pruning")
    for item in run["pruning"]:
        lines.append(
            f"prune {item['percent']} removed {item['removed']} "
            f"correct {item['correct']} "
            f"test_acc {ratio(item['correct'], test_count)} "
            f"test_loss {real(item['loss'], 6)}"
        )
    lines.append("noise")
    for item in run["noise_results"]:
        lines.append(
            f"noise {item['percent']} correct {item['correct']} "
            f"test_acc {ratio(item['correct'], test_count)}"
        )
    ids = [item["id"] for item in run["misclassified"]]
    lines.append(
        f"misclassified {len(ids)}" + (" " + " ".join(ids) if ids else "")
    )
    return lines


def ranked_runs(runs):
    order = {id(run): i for i, run in enumerate(runs)}
    return sorted(
        runs, key=lambda run: (
            -run["test"]["correct"],
            run["best_val_loss"], order[id(run)],
        )
    )


def ensembles(runs, rank, test):
    """Majority rank tie-break, and mean probability over softmax runs."""
    classes = runs[0]["network_data"]["architecture"]["classes"]
    majority = []
    soft = []
    soft_runs = [
        run for run in runs
        if run["network_data"]["architecture"]["layers"][-1]["activation"]
        == "SOFTMAX"
    ]
    for index in range(len(test)):
        votes = Counter(
            run["test"]["outcomes"][index]["predicted"] for run in runs
        )
        max_vote = max(votes.values())
        winning = {
            klass for klass, count in votes.items() if count == max_vote
        }
        chosen = next(
            run["test"]["outcomes"][index]["predicted"] for run in rank
            if run["test"]["outcomes"][index]["predicted"] in winning
        )
        majority.append(chosen)
        if soft_runs:
            means = [
                sum(run["test"]["outcomes"][index]["scores"][klass]
                    for run in soft_runs) / len(soft_runs)
                for klass in range(classes)
            ]
            soft.append(max(range(classes), key=lambda k: (means[k], -k)))
    return majority, soft, len(soft_runs)


def comparison_lines(runs, training, all_train, test, settings):
    """Rank, ensembles, McNemar, saliency, hardest and mistaken examples."""
    rank = ranked_runs(runs)
    top = rank[0]
    test_count = len(test)
    top_outcomes = top["test"]["outcomes"]
    majority, soft, soft_count = ensembles(runs, rank, test)
    lines = ["comparison"]
    for index, run in enumerate(rank, 1):
        count = run["test"]["correct"]
        lines.append(
            f"rank {index} {run['name']} correct {count} "
            f"test_acc {ratio(count, test_count)} "
            f"best_val_loss {real(run['best_val_loss'], 6)} "
            f"test_loss {real(run['test']['loss'], 6)} "
            f"best_epoch {run['best_epoch']} "
            f"epochs {len(run['epochs'])} updates {run['updates']}"
        )
    lines.append("agreement")
    for a in runs:
        agreement = [
            sum(first["predicted"] == second["predicted"]
                for first, second in zip(
                    a["test"]["outcomes"], b["test"]["outcomes"]
                ))
            for b in runs
        ]
        lines.append(a["name"] + " " + " ".join(map(str, agreement)))
    lines.append(f"mcnemar {top['name']}")
    for run in rank[1:]:
        b = sum(
            reference["predicted"] == reference["label"]
            and alternate["predicted"] != alternate["label"]
            for reference, alternate in zip(
                top_outcomes, run["test"]["outcomes"]
            )
        )
        c = sum(
            reference["predicted"] != reference["label"]
            and alternate["predicted"] == alternate["label"]
            for reference, alternate in zip(
                top_outcomes, run["test"]["outcomes"]
            )
        )
        numerator = max(abs(b - c) - 1, 0) ** 2
        denominator = b + c
        chi = ratio(numerator, denominator) if denominator else "0.0000"
        lines.append(
            f"vs {run['name']} b {b} c {c} chi2 {chi} "
            f"significant {'yes' if numerator * 1000 > 3841 * denominator else 'no'}"
        )
    majority_correct = sum(
        prediction == image["label"]
        for prediction, image in zip(majority, test)
    )
    fixed = sum(
        prediction == image["label"] and ref["predicted"] != ref["label"]
        for prediction, image, ref in zip(majority, test, top_outcomes)
    )
    broken = sum(
        prediction != image["label"] and ref["predicted"] == ref["label"]
        for prediction, image, ref in zip(majority, test, top_outcomes)
    )
    lines.append(
        f"ensemble correct {majority_correct}/{test_count} "
        f"test_acc {ratio(majority_correct, test_count)} "
        f"fixed {fixed} broken {broken}"
    )
    if soft_count:
        soft_correct = sum(
            prediction == image["label"]
            for prediction, image in zip(soft, test)
        )
        lines.append(
            f"soft_ensemble runs {soft_count} correct {soft_correct}/{test_count} "
            f"test_acc {ratio(soft_correct, test_count)}"
        )
    else:
        lines.append("soft_ensemble none")
    for index, percent in enumerate(settings["noise"]):
        flipped = runs[0]["noise_results"][index]["flipped"]
        lines.append(f"noise {percent} flipped {flipped}")
    classes = top["network_data"]["architecture"]["classes"]
    confusion_total = [
        [sum(run["confusion"][a][b] for run in runs)
         for b in range(classes)] for a in range(classes)
    ]
    pairs = [
        (a, b) for a in range(classes) for b in range(classes)
        if a != b and confusion_total[a][b] > 0
    ]
    pairs.sort(key=lambda pair: (
        -confusion_total[pair[0]][pair[1]], pair[0], pair[1]
    ))
    lines.append("confused_pairs")
    for a, b in pairs[:5]:
        lines.append(f"{a} as {b} count {confusion_total[a][b]}")
    lines.append("")
    lines.extend(saliency_lines(top, test))
    lines.append("")
    lines.extend(hardest_examples_lines(top, training))
    lines.append("")
    lines.extend(misclassified_examples_lines(
        top, runs, test, all_train, majority,
    ))
    return lines


def saliency_lines(top, test):
    """Absolute input gradients averaged by true class and digitized."""
    network = top["network_data"]
    architecture = network["architecture"]
    layout = network["layout"]
    size = architecture["width"] * architecture["height"]
    maps = []
    for klass in range(architecture["classes"]):
        chosen = [image for image in test if image["label"] == klass]
        if not chosen:
            maps.append([0] * size)
            continue
        values = [0.0] * size
        for image in chosen:
            _, _, inputs = gradient(
                architecture, layout, top["best_theta"], image,
                input_gradient=True,
            )
            for index, derivative in enumerate(inputs):
                values[index] += abs(derivative)
        values = [value / len(chosen) for value in values]
        maximum = max(values)
        levels = (
            [min(9, math.floor(10 * value / maximum)) for value in values]
            if maximum > 0 else [0] * size
        )
        maps.append(levels)
    lines = [
        f"saliency {top['name']}",
        "classes " + " ".join(map(str, range(architecture["classes"]))),
    ]
    lines.extend(level_maps(
        maps, architecture["width"], architecture["height"]
    ))
    return lines


def hardest_examples_lines(top, training):
    network = top["network_data"]
    architecture = network["architecture"]
    layout = network["layout"]
    evaluated = evaluate(
        architecture, layout, top["best_theta"], training,
    )["outcomes"]
    order = sorted(
        range(len(training)),
        key=lambda index: (-evaluated[index]["loss"], index)
    )[:5]
    lines = [f"hardest_training_examples {top['name']}"]
    for index in order:
        image = training[index]
        outcome = evaluated[index]
        lines.append(
            f"{image['id']} label {image['label']} "
            f"predicted {outcome['predicted']} "
            f"loss {real(outcome['loss'], 6)}"
        )
    return lines


def misclassified_examples_lines(top, runs, test, all_train, majority):
    width = top["network_data"]["architecture"]["width"]
    lines = [f"misclassified_examples {top['name']}"]
    for index, (image, outcome) in enumerate(zip(
        test, top["test"]["outcomes"]
    )):
        if outcome["predicted"] == image["label"]:
            continue
        predictions = [
            str(run["test"]["outcomes"][index]["predicted"]) for run in runs
        ]
        distance, nearest_index = min(
            (
                sum(a != b for a, b in zip(
                    image["pixels"], candidate["pixels"]
                )), candidate_index
            )
            for candidate_index, candidate in enumerate(all_train)
        )
        nearest = all_train[nearest_index]
        lines.append(
            f"{image['id']} label {image['label']} "
            f"predicted {outcome['predicted']} "
            f"confidence {real(outcome['confidence'], 4)} "
            f"true_score {real(outcome['scores'][image['label']], 4)} "
            f"runs {' '.join(predictions)} ensemble {majority[index]}"
        )
        lines.append(
            f"nearest {nearest['id']} label {nearest['label']} "
            f"distance {distance}"
        )
        lines.extend(ascii_image(image["pixels"], width))
    return lines


def evaluation_lines(runs, training, validation, test, data):
    settings = data["settings"]
    result = data_summary_lines(
        training, validation, test, data["networks"]
    )
    result.append("")
    for run in runs:
        result.extend(run_evaluation_lines(run, training, validation, test))
        result.append("")
    result.extend(comparison_lines(
        runs, training, data["train"], test, settings,
    ))
    return result


def write_lines(filename, lines):
    output = Path("output") / filename
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="ascii")


def main():
    data = load_inputs()
    training, validation = training_partition(data)
    catalog = network_catalog(data)
    settings = data["settings"]
    checks = gradient_check_lines(
        catalog, data["networks"], training, settings
    )
    runs = []
    for definition in settings["runs"]:
        network = catalog[definition["network"]]
        run = train_run(
            definition, network, training, validation, settings,
        )
        run["network_data"]["settings"] = settings
        prepare_run_evaluation(run, training, data["test"], settings)
        runs.append(run)
    write_lines("gradient_check.txt", checks)
    write_lines("training_log.csv", training_log_lines(
        runs, len(training), len(validation),
    ))
    write_lines("final_weights.txt", final_weight_lines(runs))
    write_lines("predictions.csv", prediction_lines(runs))
    write_lines("evaluation.txt", evaluation_lines(
        runs, training, validation, data["test"], data,
    ))


if __name__ == "__main__":
    main()
