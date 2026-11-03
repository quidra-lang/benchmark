"""Train, evaluate, annotate, and diagnose the file-driven discrete HMMs."""

from itertools import permutations
from math import floor

from evaluation import (
    accumulate_confusion, boundary_counts, confusion_matrix, correct_count,
    fraction, matrix_lines, metric_lines, region_counts, runs,
)
from inference import decode, maximum_index, viterbi
from model_io import model_lines, read_inputs, real, write_lines
from sampler import MINSTD, posterior_path, synthetic_sequence
from training import baum_welch_step, estimate_by_counting, total_loglik


class Record:
    def __init__(self, name, observations, path=None):
        self.name = name
        self.observations = observations
        self.path = path


def interpret_parameters(rows, model):
    raw = {row[0]: row[1:] for row in rows}
    integer_keys = (
        "iterations", "folds", "min_sequence_length", "max_missing_percent",
        "merge_gap", "min_segment_length", "min_rich_percent",
        "min_motif_percent", "boundary_tolerance", "posterior_seed",
        "posterior_samples", "sample_seed", "sample_count", "sample_length",
    )
    parameters = {key: int(raw[key][0]) for key in integer_keys}
    parameters["pseudocount"] = float(raw["pseudocount"][0])
    parameters["confidence"] = float(raw["confidence"][0])
    parameters["smoothing"] = [(text, float(text)) for text in raw["smoothing"]]
    parameters["segment_state"] = model.states.index(raw["segment_state"][0])
    parameters["motif"] = tuple(model.symbols.index(symbol) for symbol in raw["motif"])
    parameters["rich_symbols"] = {
        model.symbols.index(symbol) for symbol in raw["rich_symbols"]
    }
    return parameters


def rejection_reason(name, observations, labels, seen, model, parameters):
    if name in seen:
        return "duplicate name"
    seen.add(name)
    for position, character in enumerate(observations, 1):
        if character not in model.symbols and character != model.missing:
            return f"invalid symbol {character} at position {position}"
    if labels is not None:
        for position, character in enumerate(labels, 1):
            if character not in model.states:
                return f"invalid label {character} at position {position}"
        if len(observations) != len(labels):
            return f"length mismatch {len(observations)} {len(labels)}"
    length = len(observations)
    if length < parameters["min_sequence_length"]:
        return f"too short {length}"
    missing = observations.count(model.missing)
    if 100 * missing > parameters["max_missing_percent"] * length:
        return f"too many missing {missing}"
    return None


def encode_observations(text, model):
    return [
        -1 if character == model.missing else model.symbols.index(character)
        for character in text
    ]


def validate_inputs(sequence_rows, labeled_rows, model, parameters):
    sequences = []
    training = []
    testing = []
    rejections = []
    seen = set()
    for line_number, (name, text) in enumerate(sequence_rows, 1):
        observations = text.upper()
        reason = rejection_reason(name, observations, None, seen, model, parameters)
        if reason is not None:
            rejections.append(f"REJECT sequences.txt line {line_number} {name} {reason}")
            continue
        sequences.append(Record(name, encode_observations(observations, model)))
    seen = set()
    for offset in range(0, len(labeled_rows), 2):
        name, role, text = labeled_rows[offset]
        observations = text.upper()
        labels = labeled_rows[offset + 1][0]
        reason = rejection_reason(name, observations, labels, seen, model, parameters)
        if reason is not None:
            rejections.append(f"REJECT labeled.txt line {offset + 1} {name} {reason}")
            continue
        record = Record(
            name, encode_observations(observations, model),
            [model.states.index(character) for character in labels],
        )
        if role == "TRAIN":
            training.append(record)
        else:
            testing.append(record)
    return sequences, training, testing, rejections


def maximum_change(previous, current):
    difference = 0.0
    previous_rows = [previous.initial] + previous.transition + previous.emission
    current_rows = [current.initial] + current.transition + current.emission
    for previous_row, current_row in zip(previous_rows, current_rows):
        for old, new in zip(previous_row, current_row):
            difference = max(difference, abs(new - old))
    return difference


def train_baum_welch(initial, observations, heldout, parameters):
    current = initial
    previous_loglik = total_loglik(current, observations)
    initial_loglik = previous_loglik
    heldout_loglik = total_loglik(current, heldout)
    best_heldout = heldout_loglik
    best_iteration = 0
    violations = 0
    trace = [
        "iteration,loglik,heldout,change,max_change,status",
        f"0,{real(previous_loglik)},{real(heldout_loglik)},,,",
    ]
    for iteration in range(1, parameters["iterations"] + 1):
        updated = baum_welch_step(current, observations, parameters["pseudocount"])
        loglik = total_loglik(updated, observations)
        heldout_loglik = total_loglik(updated, heldout)
        change = loglik - previous_loglik
        largest_change = maximum_change(current, updated)
        violation = loglik < previous_loglik - 0.000001 * abs(previous_loglik)
        if violation:
            violations += 1
        if heldout_loglik > best_heldout:
            best_heldout = heldout_loglik
            best_iteration = iteration
        status = "violation" if violation else "ok"
        trace.append(
            f"{iteration},{real(loglik)},{real(heldout_loglik)},"
            f"{real(change)},{real(largest_change, 6)},{status}"
        )
        current = updated
        previous_loglik = loglik
    summary = {
        "iterations": parameters["iterations"],
        "initial_loglik": initial_loglik,
        "final_loglik": previous_loglik,
        "violations": violations,
        "best_heldout_iteration": best_iteration,
    }
    return current, trace, summary


def viterbi_paths(model, observations):
    paths = []
    total_logprob = 0.0
    for sequence in observations:
        path, logprob = viterbi(model, sequence)
        paths.append(path)
        total_logprob += logprob
    return paths, total_logprob


def train_viterbi(initial, observations, parameters):
    current = initial
    paths, logprob = viterbi_paths(current, observations)
    loglik = total_loglik(current, observations)
    trace = [
        "iteration,logprob,loglik,changed",
        f"0,{real(logprob)},{real(loglik)},",
    ]
    for iteration in range(1, parameters["iterations"] + 1):
        current = estimate_by_counting(
            initial, zip(observations, paths), parameters["pseudocount"],
            "VITERBI_TRAINING",
        )
        updated_paths, logprob = viterbi_paths(current, observations)
        changed = 0
        for previous, updated in zip(paths, updated_paths):
            changed += len(previous) - correct_count(previous, updated)
        loglik = total_loglik(current, observations)
        trace.append(f"{iteration},{real(logprob)},{real(loglik)},{changed}")
        paths = updated_paths
        if changed == 0:
            break
    summary = {"iterations": iteration, "converged": changed == 0}
    return current, trace, summary


def record_pairs(records):
    return [(record.observations, record.path) for record in records]


def cross_validate(initial, records, parameters):
    folds = parameters["folds"]
    positions = sum(len(record.observations) for record in records)
    results = []
    for candidate, alpha in parameters["smoothing"]:
        matrix = confusion_matrix(len(initial.states))
        fold_results = []
        total_correct = 0
        for fold in range(folds):
            fitting = [record for index, record in enumerate(records) if index % folds != fold]
            validating = [record for index, record in enumerate(records) if index % folds == fold]
            model = estimate_by_counting(initial, record_pairs(fitting), alpha)
            fold_positions = 0
            fold_correct = 0
            for record in validating:
                path, _ = viterbi(model, record.observations)
                fold_positions += len(path)
                fold_correct += correct_count(record.path, path)
                accumulate_confusion(matrix, record.path, path)
            total_correct += fold_correct
            fold_results.append((len(validating), fold_positions, fold_correct))
        results.append({
            "candidate": candidate, "alpha": alpha, "correct": total_correct,
            "folds": fold_results, "matrix": matrix,
        })
    selected = results[maximum_index([result["correct"] for result in results])]
    lines = [f"CROSS_VALIDATION folds {folds}"]
    for result in results:
        correct = result["correct"]
        lines.append(
            f"SMOOTHING {result['candidate']} positions {positions} correct {correct} "
            f"accuracy {fraction(correct, positions)}"
        )
    lines.append(f"SELECTED {selected['candidate']}")
    for fold, (record_count, fold_positions, correct) in enumerate(selected["folds"], 1):
        lines.append(
            f"FOLD {fold} records {record_count} positions {fold_positions} "
            f"correct {correct} accuracy {fraction(correct, fold_positions)}"
        )
    lines.extend(matrix_lines(initial.states, selected["matrix"]))
    lines.extend(metric_lines(initial.states, selected["matrix"]))
    supervised = estimate_by_counting(initial, record_pairs(records), selected["alpha"])
    return supervised, selected, lines


def learning_curve(initial, training, testing, alpha):
    positions = sum(len(record.observations) for record in testing)
    lines = ["LEARNING_CURVE"]
    for count in range(1, len(training) + 1):
        model = estimate_by_counting(initial, record_pairs(training[:count]), alpha)
        correct = 0
        for record in testing:
            path, _ = viterbi(model, record.observations)
            correct += correct_count(record.path, path)
        lines.append(f"RECORDS {count} correct {correct} accuracy {fraction(correct, positions)}")
    return lines


def extract_segments(path, parameters):
    segments = []
    for state, start, end in runs(path):
        if state != parameters["segment_state"]:
            continue
        if segments and start - segments[-1][1] - 1 <= parameters["merge_gap"]:
            segments[-1] = (segments[-1][0], end)
        else:
            segments.append((start, end))
    return [
        (start, end) for start, end in segments
        if end - start + 1 >= parameters["min_segment_length"]
    ]


def composition(observations, segment, parameters):
    start, end = segment
    first, second = parameters["motif"]
    observed = 0
    rich = 0
    first_count = 0
    second_count = 0
    pairs = 0
    for position in range(start - 1, end):
        symbol = observations[position]
        if symbol != -1:
            observed += 1
            if symbol in parameters["rich_symbols"]:
                rich += 1
            if symbol == first:
                first_count += 1
            if symbol == second:
                second_count += 1
        if position + 1 < end:
            if symbol == first and observations[position + 1] == second:
                pairs += 1
    denominator = first_count * second_count
    rich_fraction = rich / observed if observed else None
    pair_ratio = (pairs * observed) / denominator if denominator else None
    island = (
        denominator > 0
        and 100 * rich >= parameters["min_rich_percent"] * observed
        and 100 * pairs * observed >= parameters["min_motif_percent"] * first_count * second_count
    )
    return rich_fraction, pair_ratio, island


def evaluate_model(model, records, parameters):
    decoded = [decode(model, record.observations) for record in records]
    blocks = []
    correct_totals = []
    for decoder in ("VITERBI", "POSTERIOR"):
        matrix = confusion_matrix(len(model.states))
        regions = [0, 0, 0, 0]
        boundaries = [0, 0, 0, 0]
        calibration = [[0, 0] for _ in range(10)]
        record_lines = []
        total_correct = 0
        for record, result in zip(records, decoded):
            path = result.viterbi if decoder == "VITERBI" else result.posterior
            correct = correct_count(record.path, path)
            total_correct += correct
            accumulate_confusion(matrix, record.path, path)
            predicted_regions = extract_segments(path, parameters)
            true_regions = [
                (start, end) for state, start, end in runs(record.path)
                if state == parameters["segment_state"]
            ]
            region_result = region_counts(predicted_regions, true_regions)
            boundary_result = boundary_counts(path, record.path, parameters["boundary_tolerance"])
            for index in range(4):
                regions[index] += region_result[index]
                boundaries[index] += boundary_result[index]
            if decoder == "POSTERIOR":
                for confidence, predicted, actual in zip(result.confidence, path, record.path):
                    bucket = min(floor(10 * confidence), 9)
                    calibration[bucket][0] += 1
                    calibration[bucket][1] += predicted == actual
            record_lines.append(f"RECORD {record.name} length {len(path)} correct {correct}")
        lines = [f"EVALUATION {model.name} {decoder}"]
        lines.extend(matrix_lines(model.states, matrix))
        lines.extend(metric_lines(model.states, matrix))
        segment_state = model.states[parameters["segment_state"]]
        lines.append(
            f"REGIONS {segment_state} predicted {regions[0]} true {regions[1]} "
            f"precision {fraction(regions[2], regions[0])} "
            f"recall {fraction(regions[3], regions[1])}"
        )
        lines.append(
            f"BOUNDARIES predicted {boundaries[0]} true {boundaries[1]} "
            f"precision {fraction(boundaries[2], boundaries[0])} "
            f"recall {fraction(boundaries[3], boundaries[1])}"
        )
        if decoder == "POSTERIOR":
            for bucket, (positions, correct) in enumerate(calibration):
                if positions:
                    interval = f"0.{bucket}-0.{bucket + 1}" if bucket < 9 else "0.9-1.0"
                    lines.append(
                        f"CALIBRATION {interval} positions {positions} correct {correct} "
                        f"accuracy {fraction(correct, positions)}"
                    )
        lines.extend(record_lines)
        blocks.append(lines)
        correct_totals.append(total_correct)
    return blocks, correct_totals


def state_string(model, path):
    return "".join(model.states[state] for state in path)


def imputed_string(model, observations, posterior):
    symbols = []
    for position, observation in enumerate(observations):
        if observation != -1:
            symbols.append(model.symbols[observation])
            continue
        probabilities = []
        for symbol in range(len(model.symbols)):
            total = 0.0
            for state in range(len(model.states)):
                total += posterior[position][state] * model.emission[state][symbol]
            probabilities.append(total)
        chosen = maximum_index(probabilities)
        symbols.append(model.symbols[chosen].lower())
    return "".join(symbols)


def segment_line(record, decoder, segment, result, samples, parameters):
    start, end = segment
    length = end - start + 1
    state = parameters["segment_state"]
    total_posterior = 0.0
    for position in range(start - 1, end):
        total_posterior += result.fb.posterior[position][state]
    support = 0
    for path in samples:
        count = sum(path[position] == state for position in range(start - 1, end))
        if 2 * count > length:
            support += 1
    rich_fraction, pair_ratio, island = composition(record.observations, segment, parameters)
    return ",".join((
        record.name, decoder, str(start), str(end), str(length),
        real(total_posterior / length), str(support), real(rich_fraction),
        real(pair_ratio), "yes" if island else "no",
    ))


def annotate_sequences(model, records, decoded, parameters):
    generator = MINSTD(parameters["posterior_seed"])
    decoding_lines = []
    segment_lines = [
        "sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island"
    ]
    for record, result in zip(records, decoded):
        samples = []
        sample_segments = 0
        for _ in range(parameters["posterior_samples"]):
            path = posterior_path(model, result.fb.forward, generator)
            samples.append(path)
            sample_segments += len(extract_segments(path, parameters))
        expected_segments = sample_segments / parameters["posterior_samples"]
        length = len(record.observations)
        differences = length - correct_count(result.viterbi, result.posterior)
        uncertain = sum(value < parameters["confidence"] for value in result.confidence)
        confident = "".join(
            "." if confidence < parameters["confidence"] else model.states[state]
            for state, confidence in zip(result.posterior, result.confidence)
        )
        decoding_lines.extend([
            f"SEQUENCE {record.name} length {length} loglik {real(result.fb.loglik)} "
            f"viterbi {real(result.viterbi_logprob)} differences {differences} "
            f"uncertain {uncertain} expected_segments {real(expected_segments)}",
            "VITERBI " + state_string(model, result.viterbi),
            "POSTERIOR " + state_string(model, result.posterior),
            "CONFIDENT " + confident,
            "IMPUTED " + imputed_string(model, record.observations, result.fb.posterior),
        ])
        for decoder, path in (("viterbi", result.viterbi), ("posterior", result.posterior)):
            for segment in extract_segments(path, parameters):
                segment_lines.append(
                    segment_line(record, decoder, segment, result, samples, parameters)
                )
    return decoding_lines, segment_lines


def synthetic_output(model, parameters):
    generator = MINSTD(parameters["sample_seed"])
    lines = []
    viterbi_total = 0
    posterior_total = 0
    positions = 0
    for number in range(1, parameters["sample_count"] + 1):
        truth, observations = synthetic_sequence(model, parameters["sample_length"], generator)
        result = decode(model, observations)
        viterbi_correct = correct_count(truth, result.viterbi)
        posterior_correct = correct_count(truth, result.posterior)
        positions += len(truth)
        viterbi_total += viterbi_correct
        posterior_total += posterior_correct
        lines.extend([
            f"SAMPLE {number} loglik {real(result.fb.loglik)} "
            f"viterbi {real(result.viterbi_logprob)} viterbi_correct {viterbi_correct} "
            f"posterior_correct {posterior_correct}",
            "STATES " + state_string(model, truth),
            "SYMBOLS " + "".join(model.symbols[symbol] for symbol in observations),
            "VITERBI " + state_string(model, result.viterbi),
            "POSTERIOR " + state_string(model, result.posterior),
        ])
    lines.append(
        f"TOTAL positions {positions} viterbi_accuracy {fraction(viterbi_total, positions)} "
        f"posterior_accuracy {fraction(posterior_total, positions)}"
    )
    return lines


def path_statistics(paths, state_count):
    counts = [0] * state_count
    run_counts = [0] * state_count
    total = 0
    for path in paths:
        total += len(path)
        for state, start, end in runs(path):
            counts[state] += end - start + 1
            run_counts[state] += 1
    return counts, run_counts, total


def stationary_distribution(model):
    count = len(model.states)
    matrix = []
    for equation in range(count - 1):
        row = [
            model.transition[state][equation] - (1.0 if state == equation else 0.0)
            for state in range(count)
        ]
        matrix.append(row + [0.0])
    matrix.append([1.0] * count + [1.0])
    for column in range(count):
        pivot = max(range(column, count), key=lambda row: abs(matrix[row][column]))
        matrix[column], matrix[pivot] = matrix[pivot], matrix[column]
        divisor = matrix[column][column]
        for index in range(column, count + 1):
            matrix[column][index] /= divisor
        for row in range(count):
            if row == column:
                continue
            factor = matrix[row][column]
            for index in range(column, count + 1):
                matrix[row][index] -= factor * matrix[column][index]
    return [matrix[state][count] for state in range(count)]


def state_alignment(model, records):
    count = len(model.states)
    matrix = confusion_matrix(count)
    positions = 0
    for record in records:
        path, _ = viterbi(model, record.observations)
        accumulate_confusion(matrix, record.path, path)
        positions += len(path)
    best_permutation = None
    best_correct = -1
    for permutation in permutations(range(count)):
        correct = 0
        for predicted, actual in enumerate(permutation):
            correct += matrix[actual][predicted]
        if correct > best_correct:
            best_correct = correct
            best_permutation = permutation
    mapping = " ".join(
        f"{model.states[state]}={model.states[actual]}"
        for state, actual in enumerate(best_permutation)
    )
    return f"ALIGNMENT {mapping} agreement {fraction(best_correct, positions)}"


def model_diagnostics(model, records, decoded, training, testing, parameters):
    loglik = 0.0
    observed = 0
    segment_count = 0
    segment_length = 0
    islands = 0
    for record, result in zip(records, decoded):
        loglik += result.fb.loglik
        observed += sum(symbol != -1 for symbol in record.observations)
        for segment in extract_segments(result.viterbi, parameters):
            segment_count += 1
            segment_length += segment[1] - segment[0] + 1
            _, _, island = composition(record.observations, segment, parameters)
            islands += island
    test_loglik = total_loglik(model, [record.observations for record in testing])
    counts, run_counts, total = path_statistics(
        [result.viterbi for result in decoded], len(model.states)
    )
    stationary = stationary_distribution(model)
    mean_length = segment_length / segment_count if segment_count else None
    lines = [
        f"MODEL {model.name}",
        f"LOGLIK unlabeled {real(loglik)} per_symbol {real(loglik / observed)} "
        f"test {real(test_loglik)}",
        f"SEGMENTS count {segment_count} mean_length {real(mean_length)} islands {islands}",
        state_alignment(model, training),
    ]
    for state, name in enumerate(model.states):
        duration = 1.0 / (1.0 - model.transition[state][state])
        occupancy = counts[state] / total
        mean_run = counts[state] / run_counts[state] if run_counts[state] else None
        lines.append(
            f"STATE {name} stationary {real(stationary[state])} duration {real(duration)} "
            f"occupancy {real(occupancy)} mean_run {real(mean_run)}"
        )
    return lines


def input_report(model, sequences, training, testing, rejections, sequence_count, labeled_count):
    positions = sum(len(record.observations) for record in sequences)
    missing = sum(record.observations.count(-1) for record in sequences)
    labeled = training + testing
    labeled_positions = sum(len(record.observations) for record in labeled)
    labeled_missing = sum(record.observations.count(-1) for record in labeled)
    lines = [
        "INPUT",
        f"SEQUENCES accepted {len(sequences)} rejected {sequence_count - len(sequences)} "
        f"positions {positions} missing {missing}",
        f"LABELED train {len(training)} test {len(testing)} rejected {labeled_count - len(labeled)} "
        f"positions {labeled_positions} missing {labeled_missing}",
    ]
    lines.extend(rejections)
    symbols = [0] * len(model.symbols)
    for record in sequences:
        for symbol in record.observations:
            if symbol != -1:
                symbols[symbol] += 1
    observed = positions - missing
    fields = ["COMPOSITION"]
    for symbol, count in zip(model.symbols, symbols):
        fields.extend((symbol, real(count / observed)))
    lines.append(" ".join(fields))
    for role, records in (("TRAIN", training), ("TEST", testing)):
        counts, run_counts, total = path_statistics(
            [record.path for record in records], len(model.states)
        )
        for state, name in enumerate(model.states):
            occupancy = counts[state] / total
            mean_run = counts[state] / run_counts[state] if run_counts[state] else None
            lines.append(
                f"TRUTH {role} {name} occupancy {real(occupancy)} mean_run {real(mean_run)}"
            )
    return lines


def training_report(models, baum_welch, viterbi_training, selected, decoded, scores, test_positions):
    lines = [
        f"TRAINING BAUM_WELCH iterations {baum_welch['iterations']} "
        f"initial_loglik {real(baum_welch['initial_loglik'])} "
        f"final_loglik {real(baum_welch['final_loglik'])} violations {baum_welch['violations']} "
        f"best_heldout_iteration {baum_welch['best_heldout_iteration']}",
        f"TRAINING VITERBI_TRAINING iterations {viterbi_training['iterations']} "
        f"converged {'yes' if viterbi_training['converged'] else 'no'}",
        f"TRAINING SUPERVISED smoothing {selected['candidate']}",
    ]
    preferences = [0] * len(models)
    for sequence in range(len(decoded[0])):
        likelihoods = [results[sequence].fb.loglik for results in decoded]
        preferences[maximum_index(likelihoods)] += 1
    preference_fields = ["PREFERENCE"]
    for model, count in zip(models, preferences):
        preference_fields.extend((model.name, str(count)))
    lines.append(" ".join(preference_fields))
    positions = sum(len(result.viterbi) for result in decoded[0])
    for first in range(len(models)):
        for second in range(first + 1, len(models)):
            correct = 0
            for left, right in zip(decoded[first], decoded[second]):
                correct += correct_count(left.viterbi, right.viterbi)
            lines.append(
                f"AGREEMENT {models[first].name} {models[second].name} {fraction(correct, positions)}"
            )
    for decoder, name in enumerate(("VITERBI", "POSTERIOR")):
        best = maximum_index([score[decoder] for score in scores])
        lines.append(
            f"BEST {name} {models[best].name} accuracy {fraction(scores[best][decoder], test_positions)}"
        )
    return lines


def join_blocks(blocks):
    lines = []
    for block in blocks:
        if lines:
            lines.append("")
        lines.extend(block)
    return lines


def main():
    initial, sequence_rows, labeled_rows, parameter_rows = read_inputs()
    parameters = interpret_parameters(parameter_rows, initial)
    sequences, training, testing, rejections = validate_inputs(
        sequence_rows, labeled_rows, initial, parameters
    )
    observations = [record.observations for record in sequences]
    heldout = [record.observations for record in training + testing]
    baum_welch, baum_trace, baum_summary = train_baum_welch(
        initial, observations, heldout, parameters
    )
    viterbi_training, viterbi_trace, viterbi_summary = train_viterbi(
        initial, observations, parameters
    )
    supervised, selected, cross_validation_lines = cross_validate(initial, training, parameters)
    learning_lines = learning_curve(initial, training, testing, selected["alpha"])
    models = [initial, baum_welch, viterbi_training, supervised]
    evaluation_blocks = []
    evaluation_scores = []
    for model in models:
        blocks, scores = evaluate_model(model, testing, parameters)
        evaluation_blocks.extend(blocks)
        evaluation_scores.append(scores)
    evaluation_blocks.extend((cross_validation_lines, learning_lines))
    decoded = [[decode(model, record.observations) for record in sequences] for model in models]
    decoding_lines, segment_lines = annotate_sequences(
        baum_welch, sequences, decoded[1], parameters
    )
    sample_lines = synthetic_output(baum_welch, parameters)
    report_blocks = [input_report(
        initial, sequences, training, testing, rejections,
        len(sequence_rows), len(labeled_rows) // 2,
    )]
    test_positions = sum(len(record.observations) for record in testing)
    report_blocks.append(training_report(
        models, baum_summary, viterbi_summary, selected,
        decoded, evaluation_scores, test_positions,
    ))
    for model, results in zip(models, decoded):
        report_blocks.append(model_diagnostics(
            model, sequences, results, training, testing, parameters
        ))
    outputs = {
        "trained_model.txt": join_blocks([model_lines(model) for model in models[1:]]),
        "loglik_trace.csv": baum_trace,
        "viterbi_trace.csv": viterbi_trace,
        "decodings.txt": decoding_lines,
        "segments.csv": segment_lines,
        "samples.txt": sample_lines,
        "evaluation.txt": join_blocks(evaluation_blocks),
        "report.txt": join_blocks(report_blocks),
    }
    for filename, lines in outputs.items():
        write_lines(filename, lines)


if __name__ == "__main__":
    main()
