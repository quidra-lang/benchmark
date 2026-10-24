def class_document_counts(sequences, labels, class_count):
    counts = {}
    for sequence, label in zip(sequences, labels):
        for term in set(sequence):
            if term not in counts:
                counts[term] = [0] * class_count
            counts[term][label] += 1
    return counts


def chi_square(with_term, frequency, class_size, total):
    others_with_term = frequency - with_term
    without_term = class_size - with_term
    others_without_term = total - class_size - others_with_term
    numerator = total * (with_term * others_without_term - others_with_term * without_term) ** 2
    denominator = frequency * (total - frequency) * class_size * (total - class_size)
    if denominator == 0:
        return 0.0
    return numerator / denominator


def first_occurrences(sequence):
    return list(dict.fromkeys(sequence))


class RankedTerm:
    def __init__(self, term, frequency, score, best_class):
        self.term = term
        self.frequency = frequency
        self.score = score
        self.best_class = best_class


class Vocabulary:
    def __init__(self, sequences, labels, class_count, min_frequency, size):
        counts = class_document_counts(sequences, labels, class_count)
        class_sizes = [0] * class_count
        for label in labels:
            class_sizes[label] += 1
        total = len(sequences)
        self.term_count = len(counts)
        ranking = []
        for term in sorted(counts):
            frequency = sum(counts[term])
            if frequency < min_frequency:
                continue
            best_class = 0
            best_score = chi_square(counts[term][0], frequency, class_sizes[0], total)
            for label in range(1, class_count):
                score = chi_square(counts[term][label], frequency, class_sizes[label], total)
                if score > best_score:
                    best_class = label
                    best_score = score
            ranking.append(RankedTerm(term, frequency, best_score, best_class))
        self.candidate_count = len(ranking)
        ranking.sort(key=lambda entry: (-entry.score, entry.term))
        if size > 0 and len(ranking) > size:
            ranking = ranking[:size]
        self.ranking = ranking
        self.terms = sorted(entry.term for entry in ranking)
        self.index = {term: position for position, term in enumerate(self.terms)}
        frequencies = {entry.term: entry.frequency for entry in ranking}
        self.frequencies = [frequencies[term] for term in self.terms]

    def size(self):
        return len(self.terms)

    def encode(self, sequence):
        return [self.index[term] for term in sequence if term in self.index]
