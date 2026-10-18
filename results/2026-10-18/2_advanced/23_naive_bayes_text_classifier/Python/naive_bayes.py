import math

from vocabulary import first_occurrences


NB_MODELS = ("multinomial", "bernoulli", "complement")
BERNOULLI_OUTCOMES = 2


def smoothed_log(count, total, alpha, outcomes):
    return math.log((100 * count + alpha) / (100 * total + alpha * outcomes))


class TrainingCounts:
    def __init__(self, sequences, labels, class_count, vocabulary_size):
        self.class_count = class_count
        self.vocabulary_size = vocabulary_size
        self.document_total = len(sequences)
        self.documents = [0] * class_count
        self.occurrences = [[0] * vocabulary_size for _ in range(class_count)]
        self.containing = [[0] * vocabulary_size for _ in range(class_count)]
        for sequence, label in zip(sequences, labels):
            self.documents[label] += 1
            for term in sequence:
                self.occurrences[label][term] += 1
            for term in set(sequence):
                self.containing[label][term] += 1
        self.totals = [sum(row) for row in self.occurrences]
        self.total = sum(self.totals)
        self.term_totals = [
            sum(row[term] for row in self.occurrences) for term in range(vocabulary_size)
        ]

    def log_priors(self):
        return [math.log(count / self.document_total) for count in self.documents]


class Posterior:
    def __init__(self, scores):
        self.scores = scores
        self.ranking = sorted(range(len(scores)), key=lambda label: -scores[label])
        self.label = self.ranking[0]
        self.runner_up = self.ranking[1]
        best = scores[self.label]
        exponentials = [math.exp(score - best) for score in scores]
        self.normalizer = 0.0
        for value in exponentials:
            self.normalizer += value
        self.probabilities = [value / self.normalizer for value in exponentials]
        self.score = self.probabilities[self.label]
        self.margin = best - scores[self.runner_up]


class NaiveBayes:
    def __init__(self, kind, priors, base, weights):
        self.kind = kind
        self.priors = priors
        self.base = base
        self.weights = weights

    def scores(self, sequence):
        terms = first_occurrences(sequence) if self.kind == "bernoulli" else sequence
        scores = []
        for label, row in enumerate(self.weights):
            score = self.base[label]
            for term in terms:
                score += row[term]
            scores.append(score + self.priors[label])
        return scores

    def predict(self, sequence):
        return Posterior(self.scores(sequence))


def multinomial_model(counts, alpha):
    weights = [
        [smoothed_log(count, counts.totals[label], alpha, counts.vocabulary_size) for count in row]
        for label, row in enumerate(counts.occurrences)
    ]
    return NaiveBayes("multinomial", counts.log_priors(), [0.0] * counts.class_count, weights)


def bernoulli_model(counts, alpha):
    base = []
    weights = []
    for label, row in enumerate(counts.containing):
        documents = counts.documents[label]
        absent_sum = 0.0
        differences = []
        for containing in row:
            present = smoothed_log(containing, documents, alpha, BERNOULLI_OUTCOMES)
            absent = smoothed_log(documents - containing, documents, alpha, BERNOULLI_OUTCOMES)
            absent_sum += absent
            differences.append(present - absent)
        base.append(absent_sum)
        weights.append(differences)
    return NaiveBayes("bernoulli", counts.log_priors(), base, weights)


def complement_model(counts, alpha):
    size = counts.vocabulary_size
    weights = []
    for label, row in enumerate(counts.occurrences):
        other_total = counts.total - counts.totals[label]
        weights.append([
            -smoothed_log(counts.term_totals[term] - count, other_total, alpha, size)
            for term, count in enumerate(row)
        ])
    return NaiveBayes("complement", counts.log_priors(), [0.0] * counts.class_count, weights)


def train_model(kind, counts, alpha):
    if kind == "multinomial":
        return multinomial_model(counts, alpha)
    if kind == "bernoulli":
        return bernoulli_model(counts, alpha)
    return complement_model(counts, alpha)
