from collections import Counter
from functools import cmp_to_key
import math
import os

from evaluation import Evaluation, fraction_text, proportion_text, real_text
from naive_bayes import (
    BERNOULLI_OUTCOMES, NB_MODELS, NaiveBayes, TrainingCounts, smoothed_log, train_model,
)
from rocchio import Rocchio
from tokenizer import Tokens, is_bigram
from vocabulary import Vocabulary, first_occurrences


INPUT_DIR = "input"
OUTPUT_DIR = "output"
FOLD_COUNT = 5
BASE_MODELS = NB_MODELS + ("rocchio",)
MODELS = BASE_MODELS + ("vote",)
MODEL_PAIRS = tuple(
    (first, second)
    for position, first in enumerate(BASE_MODELS)
    for second in BASE_MODELS[position + 1:]
)
TERM_KINDS = (("unigrams", False), ("bigrams", True))
CHARACTERISTIC_MODELS = ("multinomial", "bernoulli")
EVIDENCE_TERMS = 3
UNKNOWN_CLASS = "?"
RANDOM_MULTIPLIER = 48271
RANDOM_MODULUS = 2147483647
BOOTSTRAP_TAIL = 40


def read_lines(name):
    with open(os.path.join(INPUT_DIR, name)) as handle:
        return handle.read().splitlines()


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w") as handle:
        handle.write("".join(line + "\n" for line in lines))


def join_parts(parts):
    lines = []
    for part in parts:
        if lines:
            lines.append("")
        lines.extend(part)
    return lines


def hundredths(text):
    whole, fraction = text.split(".")
    return int(whole) * 100 + int(fraction)


def hundredths_text(value):
    return f"{value // 100}.{value % 100:02d}"


def class_counts_text(names, counts):
    return " ".join(f"{name} {count}" for name, count in zip(names, counts))


def bucket_of(value, boundaries):
    bucket = 0
    for boundary in boundaries:
        if value >= boundary:
            bucket += 1
    return bucket


def compare_ratios(first, second):
    left = first[0] * second[1]
    right = second[0] * first[1]
    if left != right:
        return -1 if left > right else 1
    return first[2] - second[2]


def ranked_by_ratio(entries):
    return sorted(entries, key=cmp_to_key(compare_ratios))


def evaluation_fields(evaluation):
    return [
        str(evaluation.correct), real_text(evaluation.micro_f1), real_text(evaluation.macro_f1)
    ]


class Settings:
    def __init__(self, lines):
        values = {}
        for line in lines:
            keyword, *arguments = line.split(" ")
            values[keyword] = arguments
        self.alphas = [hundredths(text) for text in values["ALPHAS"]]
        self.min_df = int(values["MIN_DF"][0])
        self.features = int(values["FEATURES"][0])
        self.bigrams = values["BIGRAMS"][0] == "yes"
        self.top = int(values["TOP"][0])
        self.curve = [int(text) for text in values["CURVE"]]
        self.sizes = [int(text) for text in values["SIZES"]]
        self.thresholds = [hundredths(text) for text in values["THRESHOLDS"]]
        self.lengths = [int(text) for text in values["LENGTHS"]]
        self.iterations = int(values["EM_ITERATIONS"][0])
        self.weight = hundredths(values["EM_WEIGHT"][0])
        self.resamples = int(values["BOOTSTRAP"][0])
        self.seed = int(values["BOOTSTRAP"][1])


class Document:
    def __init__(self, name, label, tokens):
        self.name = name
        self.label = label
        self.tokens = tokens


class VotePrediction:
    def __init__(self, label, score):
        self.label = label
        self.score = score


def majority_vote(labels, class_count):
    votes = [0] * class_count
    for label in labels:
        votes[label] += 1
    winner = labels[0]
    for label in labels:
        if votes[label] > votes[winner]:
            winner = label
    return VotePrediction(winner, votes[winner] / len(labels))


class FoldSummary:
    def __init__(self, train_count, validate_count, vocabulary):
        self.train_count = train_count
        self.validate_count = validate_count
        self.candidate_count = vocabulary.candidate_count
        self.vocabulary_size = vocabulary.size()


class CrossValidationRun:
    def __init__(self, predictions, evaluation, fold_correct):
        self.predictions = predictions
        self.evaluation = evaluation
        self.fold_correct = fold_correct


class Training:
    def __init__(self, documents, use_bigrams, class_count, min_df, size):
        self.use_bigrams = use_bigrams
        sequences = [document.tokens.terms(use_bigrams) for document in documents]
        labels = [document.label for document in documents]
        self.vocabulary = Vocabulary(sequences, labels, class_count, min_df, size)
        encoded = [self.vocabulary.encode(sequence) for sequence in sequences]
        self.counts = TrainingCounts(encoded, labels, class_count, self.vocabulary.size())
        self.rocchio = Rocchio(encoded, labels, class_count, self.vocabulary.frequencies)
        self.models = {}

    def train(self, alphas):
        for kind in NB_MODELS:
            self.models[kind] = train_model(kind, self.counts, alphas[kind])

    def encode(self, document):
        return self.vocabulary.encode(document.tokens.terms(self.use_bigrams))

    def classify(self, model, sequence):
        if model == "rocchio":
            return self.rocchio.predict(sequence)
        return self.models[model].predict(sequence)


class Experiment:
    def __init__(self):
        self.settings = Settings(read_lines("params.txt"))
        stopwords = set(read_lines("stopwords.txt"))
        rows = [line.split("\t") for line in read_lines("train.txt")]
        self.classes = sorted({label for label, _ in rows})
        self.class_count = len(self.classes)
        positions = {name: label for label, name in enumerate(self.classes)}
        self.training = [
            Document(str(number), positions[label], Tokens(text, stopwords))
            for number, (label, text) in enumerate(rows, 1)
        ]
        self.tests = []
        for line in read_lines("test.txt"):
            name, label, text = line.split("\t")
            truth = None if label == UNKNOWN_CLASS else positions[label]
            self.tests.append(Document(name, truth, Tokens(text, stopwords)))
        self.unlabelled = [
            Document(str(number), None, Tokens(text, stopwords))
            for number, text in enumerate(read_lines("unlabelled.txt"), 1)
        ]
        self.labelled = [
            index for index, document in enumerate(self.tests) if document.label is not None
        ]
        self.truths = [self.tests[index].label for index in self.labelled]

    def run(self):
        self.cross_validate()
        self.select_alphas()
        self.train_final()

    def trained(self, documents, use_bigrams, size):
        training = Training(documents, use_bigrams, self.class_count, self.settings.min_df, size)
        training.train(self.selected)
        return training

    def alpha_text(self, model):
        if model in self.selected:
            return hundredths_text(self.selected[model])
        return "-"

    def cross_validate(self):
        settings = self.settings
        count = len(self.training)
        nb_predictions = {
            kind: [[0] * count for _ in settings.alphas] for kind in NB_MODELS
        }
        rocchio_predictions = [0] * count
        self.folds = []
        for fold in range(FOLD_COUNT):
            members = [
                document for index, document in enumerate(self.training)
                if index % FOLD_COUNT != fold
            ]
            held_out = [index for index in range(count) if index % FOLD_COUNT == fold]
            training = Training(
                members, settings.bigrams, self.class_count, settings.min_df, settings.features
            )
            self.folds.append(FoldSummary(len(members), len(held_out), training.vocabulary))
            sequences = [training.encode(self.training[index]) for index in held_out]
            for kind in NB_MODELS:
                for position, alpha in enumerate(settings.alphas):
                    model = train_model(kind, training.counts, alpha)
                    for index, sequence in zip(held_out, sequences):
                        nb_predictions[kind][position][index] = model.predict(sequence).label
            for index, sequence in zip(held_out, sequences):
                rocchio_predictions[index] = training.rocchio.predict(sequence).label
        self.cv_runs = {
            kind: [self.cross_validation_run(labels) for labels in nb_predictions[kind]]
            for kind in NB_MODELS
        }
        self.cv_runs["rocchio"] = [self.cross_validation_run(rocchio_predictions)]

    def cross_validation_run(self, predictions):
        truths = [document.label for document in self.training]
        fold_correct = [0] * FOLD_COUNT
        for index, (truth, predicted) in enumerate(zip(truths, predictions)):
            if truth == predicted:
                fold_correct[index % FOLD_COUNT] += 1
        evaluation = Evaluation(self.class_count, truths, predictions)
        return CrossValidationRun(predictions, evaluation, fold_correct)

    def select_alphas(self):
        self.selected = {}
        self.selected_runs = {}
        for kind in NB_MODELS:
            runs = self.cv_runs[kind]
            best = 0
            for position in range(1, len(runs)):
                score = round(runs[position].evaluation.macro_f1, 4)
                if score > round(runs[best].evaluation.macro_f1, 4):
                    best = position
            self.selected[kind] = self.settings.alphas[best]
            self.selected_runs[kind] = runs[best]
        self.selected_runs["rocchio"] = self.cv_runs["rocchio"][0]

    def train_final(self):
        settings = self.settings
        self.final = self.trained(self.training, settings.bigrams, settings.features)
        self.test_sequences = [self.final.encode(document) for document in self.tests]
        self.predictions = {
            model: [self.final.classify(model, sequence) for sequence in self.test_sequences]
            for model in BASE_MODELS
        }
        self.predictions["vote"] = [
            majority_vote(
                [self.predictions[model][index].label for model in BASE_MODELS], self.class_count
            )
            for index in range(len(self.tests))
        ]
        self.correct = {
            model: [
                self.predictions[model][index].label == self.tests[index].label
                for index in self.labelled
            ]
            for model in MODELS
        }

    def test_evaluations(self, training):
        sequences = [training.encode(self.tests[index]) for index in self.labelled]
        evaluations = []
        for model in BASE_MODELS:
            predicted = [training.classify(model, sequence).label for sequence in sequences]
            evaluations.append(Evaluation(self.class_count, self.truths, predicted))
        return evaluations

    def vocabulary_lines(self):
        vocabulary = self.final.vocabulary
        lines = [
            f"documents {len(self.training)} terms {vocabulary.term_count}"
            f" candidates {vocabulary.candidate_count} vocabulary {vocabulary.size()}"
        ]
        for rank, entry in enumerate(vocabulary.ranking, 1):
            lines.append(
                f"{rank} {entry.term} {entry.frequency} {real_text(entry.score)}"
                f" {self.classes[entry.best_class]}"
            )
        return lines

    def cv_lines(self):
        lines = ["model,alpha,correct,accuracy,macro_f1,selected"]
        for kind in NB_MODELS:
            for alpha, run in zip(self.settings.alphas, self.cv_runs[kind]):
                selected = "yes" if alpha == self.selected[kind] else "no"
                fields = evaluation_fields(run.evaluation)
                lines.append(",".join([kind, hundredths_text(alpha), *fields, selected]))
        fields = evaluation_fields(self.cv_runs["rocchio"][0].evaluation)
        lines.append(",".join(["rocchio", "-", *fields, "yes"]))
        return lines

    def prediction_lines(self):
        lines = ["id,model,label,score"]
        for index, document in enumerate(self.tests):
            for model in MODELS:
                prediction = self.predictions[model][index]
                lines.append(
                    f"{document.name},{model},{self.classes[prediction.label]},"
                    f"{real_text(prediction.score)}"
                )
        return lines

    def curve_lines(self):
        settings = self.settings
        lines = ["size,vocabulary,model,correct,accuracy,macro_f1"]
        for size in settings.curve:
            training = self.trained(self.training[:size], settings.bigrams, settings.features)
            prefix = [str(size), str(training.vocabulary.size())]
            for model, evaluation in zip(BASE_MODELS, self.test_evaluations(training)):
                lines.append(",".join(prefix + [model] + evaluation_fields(evaluation)))
        return lines

    def feature_lines(self):
        lines = ["terms,features,vocabulary,model,correct,accuracy,macro_f1"]
        for kind, use_bigrams in TERM_KINDS:
            for size in self.settings.sizes:
                training = self.trained(self.training, use_bigrams, size)
                prefix = [kind, str(size), str(training.vocabulary.size())]
                for model, evaluation in zip(BASE_MODELS, self.test_evaluations(training)):
                    lines.append(",".join(prefix + [model] + evaluation_fields(evaluation)))
        return lines

    def data_part(self):
        settings = self.settings
        vocabulary = self.final.vocabulary
        lines = [
            f"documents train {len(self.training)} test {len(self.tests)}"
            f" labelled {len(self.labelled)} unlabelled {len(self.unlabelled)}"
            f" classes {self.class_count}"
        ]
        train_counts = [0] * self.class_count
        for document in self.training:
            train_counts[document.label] += 1
        test_counts = [0] * self.class_count
        for truth in self.truths:
            test_counts[truth] += 1
        for label, name in enumerate(self.classes):
            lines.append(f"class {name} train {train_counts[label]} test {test_counts[label]}")
        raw = stopwords = short = kept = bigrams = 0
        terms = set()
        for document in self.training:
            tokens = document.tokens
            raw += tokens.raw_count
            stopwords += tokens.stopword_count
            short += tokens.short_count
            kept += len(tokens.words)
            if settings.bigrams:
                bigrams += len(tokens.bigrams)
            terms.update(tokens.terms(settings.bigrams))
        distinct_bigrams = sum(1 for term in terms if is_bigram(term))
        lines.append(
            f"train_tokens raw {raw} stopwords {stopwords} short {short}"
            f" unigrams {kept} bigrams {bigrams}"
        )
        lines.append(
            f"train_terms unigrams {len(terms) - distinct_bigrams} bigrams {distinct_bigrams}"
            f" candidates {vocabulary.candidate_count} vocabulary {vocabulary.size()}"
        )
        total = sum(len(document.tokens.terms(settings.bigrams)) for document in self.tests)
        in_vocabulary = sum(len(sequence) for sequence in self.test_sequences)
        lines.append(f"test_terms total {total} in_vocabulary {in_vocabulary}")
        occurrences = Counter(
            word
            for document in self.tests
            for word in document.tokens.words
            if word not in vocabulary.index
        )
        ranked = sorted(occurrences.items(), key=lambda item: (-item[1], item[0]))
        parts = ["test_oov"]
        for word, count in ranked[:settings.top]:
            parts.append(f"{word} {count}")
        lines.append(" ".join(parts))
        return lines

    def folds_part(self):
        lines = [f"folds {FOLD_COUNT}"]
        for fold, summary in enumerate(self.folds, 1):
            lines.append(
                f"fold {fold} train {summary.train_count} validate {summary.validate_count}"
                f" candidates {summary.candidate_count} vocabulary {summary.vocabulary_size}"
            )
        return lines

    def selection_part(self):
        lines = ["selection"]
        for model in BASE_MODELS:
            run = self.selected_runs[model]
            evaluation = run.evaluation
            folds = " ".join(str(count) for count in run.fold_correct)
            lines.append(
                f"{model} alpha {self.alpha_text(model)}"
                f" correct {proportion_text(evaluation.correct, evaluation.total)}"
                f" macro_f1 {real_text(evaluation.macro_f1)} folds {folds}"
            )
        return lines

    def cross_validation_part(self, model):
        lines = [f"cross_validation {model} alpha {self.alpha_text(model)}"]
        lines.extend(self.selected_runs[model].evaluation.lines(self.classes))
        return lines

    def test_part(self, model):
        predictions = [self.predictions[model][index] for index in self.labelled]
        count = len(predictions)
        evaluation = Evaluation(
            self.class_count, self.truths, [prediction.label for prediction in predictions]
        )
        lines = [
            f"test {model} alpha {self.alpha_text(model)}",
            f"labelled {count} correct {proportion_text(evaluation.correct, count)}",
        ]
        if model in BASE_MODELS:
            top_two = sum(
                1 for prediction, truth in zip(predictions, self.truths)
                if truth in prediction.ranking[:2]
            )
            lines.append(f"top2 {proportion_text(top_two, count)}")
        lines.extend(evaluation.lines(self.classes))
        return lines

    def probability_part(self, kind):
        thresholds = self.settings.thresholds
        limits = [threshold / 100 for threshold in thresholds]
        count = len(self.labelled)
        bin_rows = [0] * (len(limits) + 1)
        bin_correct = [0] * (len(limits) + 1)
        bin_sums = [0.0] * (len(limits) + 1)
        accepted = [0] * len(limits)
        accepted_correct = [0] * len(limits)
        loss = 0.0
        brier = 0.0
        for position, index in enumerate(self.labelled):
            prediction = self.predictions[kind][index]
            truth = self.truths[position]
            correct = self.correct[kind][position]
            gap = prediction.scores[truth] - prediction.scores[prediction.label]
            loss += math.log(prediction.normalizer) - gap
            squares = 0.0
            for label, probability in enumerate(prediction.probabilities):
                difference = probability - (1.0 if label == truth else 0.0)
                squares += difference * difference
            brier += squares
            bucket = bucket_of(prediction.score, limits)
            bin_rows[bucket] += 1
            bin_sums[bucket] += prediction.score
            if correct:
                bin_correct[bucket] += 1
            for threshold, limit in enumerate(limits):
                if prediction.score >= limit:
                    accepted[threshold] += 1
                    if correct:
                        accepted_correct[threshold] += 1
        lines = [
            f"probability {kind} alpha {self.alpha_text(kind)}",
            f"log_loss {real_text(loss / count)} brier {real_text(brier / count)}",
        ]
        for bucket, bound in enumerate([0] + thresholds):
            rows = bin_rows[bucket]
            line = f"bin {hundredths_text(bound)} rows {rows}"
            if rows > 0:
                line += (
                    f" correct {proportion_text(bin_correct[bucket], rows)}"
                    f" mean {real_text(bin_sums[bucket] / rows)}"
                )
            lines.append(line)
        for position, threshold in enumerate(thresholds):
            covered = proportion_text(accepted[position], count)
            if accepted[position] > 0:
                precise = proportion_text(accepted_correct[position], accepted[position])
            else:
                precise = "-"
            lines.append(
                f"threshold {hundredths_text(threshold)} covered {covered} correct {precise}"
            )
        return lines

    def lengths_part(self):
        boundaries = self.settings.lengths
        rows = [0] * (len(boundaries) + 1)
        correct = {model: [0] * (len(boundaries) + 1) for model in MODELS}
        for position, index in enumerate(self.labelled):
            bucket = bucket_of(len(self.test_sequences[index]), boundaries)
            rows[bucket] += 1
            for model in MODELS:
                if self.correct[model][position]:
                    correct[model][bucket] += 1
        lines = ["lengths"]
        for bucket, bound in enumerate([0] + boundaries):
            parts = [f"length {bound} rows {rows[bucket]}"]
            if rows[bucket] > 0:
                for model in MODELS:
                    parts.append(f"{model} {proportion_text(correct[model][bucket], rows[bucket])}")
            lines.append(" ".join(parts))
        return lines

    def comparison_part(self):
        lines = ["comparison"]
        for first, second in MODEL_PAIRS:
            agree = sum(
                1 for one, other in zip(self.predictions[first], self.predictions[second])
                if one.label == other.label
            )
            first_only = sum(
                1 for one, other in zip(self.correct[first], self.correct[second])
                if one and not other
            )
            second_only = sum(
                1 for one, other in zip(self.correct[first], self.correct[second])
                if other and not one
            )
            discordant = first_only + second_only
            if discordant > 0:
                statistic = max(0, abs(first_only - second_only) - 1) ** 2
                statistic_text = fraction_text(statistic, discordant)
            else:
                statistic_text = fraction_text(0, 1)
            lines.append(
                f"{first} {second} agree {proportion_text(agree, len(self.tests))}"
                f" b {first_only} c {second_only} statistic {statistic_text}"
            )
        errors = [0] * (len(BASE_MODELS) + 1)
        for position in range(len(self.labelled)):
            wrong = sum(1 for model in BASE_MODELS if not self.correct[model][position])
            errors[wrong] += 1
        lines.append("errors " + " ".join(f"{wrong} {count}" for wrong, count in enumerate(errors)))
        return lines

    def bootstrap_part(self):
        settings = self.settings
        count = len(self.labelled)
        state = settings.seed
        totals = {model: [] for model in MODELS}
        for _ in range(settings.resamples):
            chosen = []
            for _ in range(count):
                state = RANDOM_MULTIPLIER * state % RANDOM_MODULUS
                chosen.append(state % count)
            for model in MODELS:
                flags = self.correct[model]
                totals[model].append(sum(1 for position in chosen if flags[position]))
        rank = settings.resamples // BOOTSTRAP_TAIL
        lines = [f"bootstrap resamples {settings.resamples} seed {settings.seed}"]
        for model in MODELS:
            ordered = sorted(totals[model])
            mean = sum(ordered) / (settings.resamples * count)
            low = ordered[rank]
            high = ordered[len(ordered) - 1 - rank]
            lines.append(
                f"{model} mean {real_text(mean)} low {proportion_text(low, count)}"
                f" high {proportion_text(high, count)}"
            )
        for first, second in MODEL_PAIRS:
            wins = ties = losses = 0
            for one, other in zip(totals[first], totals[second]):
                if one > other:
                    wins += 1
                elif one == other:
                    ties += 1
                else:
                    losses += 1
            lines.append(f"pair {first} {second} wins {wins} ties {ties} losses {losses}")
        return lines

    def hard_part(self):
        hard = []
        counts = [0] * self.class_count
        for index, document in enumerate(self.training):
            predicted = [self.selected_runs[model].predictions[index] for model in BASE_MODELS]
            if all(label != document.label for label in predicted):
                hard.append((document, predicted))
                counts[document.label] += 1
        lines = [f"hard_documents {len(hard)} {class_counts_text(self.classes, counts)}"]
        for document, predicted in hard[:self.settings.top]:
            names = " ".join(self.classes[label] for label in predicted)
            lines.append(
                f"{document.name} true {self.classes[document.label]} predicted {names}"
            )
        return lines

    def uncertain_part(self):
        predictions = self.predictions["multinomial"]
        order = sorted(
            range(len(self.tests)), key=lambda index: round(predictions[index].margin, 4)
        )
        shown = order[:self.settings.top]
        lines = [f"uncertain multinomial {len(shown)}"]
        for index in shown:
            document = self.tests[index]
            prediction = predictions[index]
            if document.label is None:
                truth = UNKNOWN_CLASS
            else:
                truth = self.classes[document.label]
            lines.append(
                f"{document.name} predicted {self.classes[prediction.label]}"
                f" runner_up {self.classes[prediction.runner_up]}"
                f" margin {real_text(prediction.margin)}"
                f" posterior {real_text(prediction.score)} true {truth}"
            )
        return lines

    def evidence_lines(self, sequence, predicted, truth):
        alpha = self.selected["multinomial"]
        occurrences = self.final.counts.occurrences
        weights = self.final.models["multinomial"].weights
        entries = [
            (
                100 * occurrences[predicted][term] + alpha,
                100 * occurrences[truth][term] + alpha,
                term,
            )
            for term in first_occurrences(sequence)
        ]
        lines = []
        for _, _, term in ranked_by_ratio(entries)[:EVIDENCE_TERMS]:
            evidence = weights[predicted][term] - weights[truth][term]
            lines.append(
                f"  {self.final.vocabulary.terms[term]} count {sequence.count(term)}"
                f" evidence {real_text(evidence)}"
            )
        return lines

    def misclassified_part(self):
        predictions = self.predictions["multinomial"]
        misclassified = [
            index for index in self.labelled
            if predictions[index].label != self.tests[index].label
        ]
        lines = [f"misclassified multinomial {len(misclassified)}"]
        for index in misclassified:
            document = self.tests[index]
            prediction = predictions[index]
            lines.append(
                f"{document.name} true {self.classes[document.label]}"
                f" predicted {self.classes[prediction.label]}"
                f" posterior {real_text(prediction.score)}"
            )
            sequence = self.test_sequences[index]
            lines.extend(self.evidence_lines(sequence, prediction.label, document.label))
        return lines

    def maximization(self, posteriors, sequences):
        settings = self.settings
        counts = self.final.counts
        weight = settings.weight / 100
        occurrences = [[float(count) for count in row] for row in counts.occurrences]
        documents = [float(count) for count in counts.documents]
        for posterior, sequence in zip(posteriors, sequences):
            frequencies = Counter(sequence)
            terms = first_occurrences(sequence)
            for label in range(self.class_count):
                share = weight * posterior.probabilities[label]
                documents[label] += share
                row = occurrences[label]
                for term in terms:
                    row[term] += share * frequencies[term]
        alpha = self.selected["multinomial"]
        size = self.final.vocabulary.size()
        weights = []
        for row in occurrences:
            total = 0.0
            for value in row:
                total += value
            weights.append([smoothed_log(value, total, alpha, size) for value in row])
        scale = len(self.training) + (settings.weight * len(self.unlabelled)) / 100
        priors = [math.log(value / scale) for value in documents]
        return NaiveBayes("multinomial", priors, [0.0] * self.class_count, weights)

    def semi_supervised_part(self):
        settings = self.settings
        sequences = [self.final.encode(document) for document in self.unlabelled]
        labelled_sequences = [self.test_sequences[index] for index in self.labelled]
        model = self.final.models["multinomial"]
        lines = [
            f"semi_supervised multinomial alpha {self.alpha_text('multinomial')}"
            f" weight {hundredths_text(settings.weight)} unlabelled {len(self.unlabelled)}"
        ]
        previous = None
        for iteration in range(settings.iterations + 1):
            posteriors = [model.predict(sequence) for sequence in sequences]
            assignments = [posterior.label for posterior in posteriors]
            predicted = [model.predict(sequence).label for sequence in labelled_sequences]
            evaluation = Evaluation(self.class_count, self.truths, predicted)
            if previous is None:
                changed = "-"
            else:
                changed = str(sum(1 for old, new in zip(previous, assignments) if old != new))
            assigned = [0] * self.class_count
            for label in assignments:
                assigned[label] += 1
            lines.append(
                f"iteration {iteration}"
                f" correct {proportion_text(evaluation.correct, evaluation.total)}"
                f" macro_f1 {real_text(evaluation.macro_f1)} changed {changed}"
                f" assigned {class_counts_text(self.classes, assigned)}"
            )
            if iteration < settings.iterations:
                model = self.maximization(posteriors, sequences)
            previous = assignments
        return lines

    def metrics_parts(self):
        parts = [self.data_part(), self.folds_part(), self.selection_part()]
        parts.extend(self.cross_validation_part(model) for model in BASE_MODELS)
        parts.extend(self.test_part(model) for model in MODELS)
        parts.extend(self.probability_part(kind) for kind in NB_MODELS)
        parts.append(self.lengths_part())
        parts.append(self.comparison_part())
        parts.append(self.bootstrap_part())
        parts.append(self.hard_part())
        parts.append(self.uncertain_part())
        parts.append(self.misclassified_part())
        parts.append(self.semi_supervised_part())
        return parts

    def characteristic_parts(self, kind):
        counts = self.final.counts
        terms = self.final.vocabulary.terms
        size = len(terms)
        alpha = self.selected[kind]
        if kind == "multinomial":
            table = counts.occurrences
            totals = counts.totals
            overall = counts.total
            outcomes = size
        else:
            table = counts.containing
            totals = counts.documents
            overall = counts.document_total
            outcomes = BERNOULLI_OUTCOMES
        term_totals = [sum(row[term] for row in table) for term in range(size)]
        parts = [[
            f"model {kind} alpha {hundredths_text(alpha)} vocabulary {size} top {self.settings.top}"
        ]]
        for label, name in enumerate(self.classes):
            total = totals[label]
            other = overall - total
            lines = [f"class {name} total {total} other {other}"]
            entries = [
                (100 * count + alpha, 100 * (term_totals[term] - count) + alpha, term)
                for term, count in enumerate(table[label])
            ]
            for rank, (_, _, term) in enumerate(ranked_by_ratio(entries)[:self.settings.top], 1):
                count = table[label][term]
                other_count = term_totals[term] - count
                log_odds = (
                    smoothed_log(count, total, alpha, outcomes)
                    - smoothed_log(other_count, other, alpha, outcomes)
                )
                lines.append(f"{rank} {terms[term]} {count} {other_count} {real_text(log_odds)}")
            parts.append(lines)
        return parts

    def top_feature_parts(self):
        parts = []
        for kind in CHARACTERISTIC_MODELS:
            parts.extend(self.characteristic_parts(kind))
        return parts


def main():
    experiment = Experiment()
    experiment.run()
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_lines("vocabulary.txt", experiment.vocabulary_lines())
    write_lines("cv_results.csv", experiment.cv_lines())
    write_lines("predictions.csv", experiment.prediction_lines())
    write_lines("learning_curve.csv", experiment.curve_lines())
    write_lines("feature_study.csv", experiment.feature_lines())
    write_lines("metrics.txt", join_parts(experiment.metrics_parts()))
    write_lines("top_features.txt", join_parts(experiment.top_feature_parts()))


if __name__ == "__main__":
    main()
