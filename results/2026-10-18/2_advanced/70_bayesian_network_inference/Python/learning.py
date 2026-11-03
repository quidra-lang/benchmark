"""Ordered parent combinations, pseudocount CPTs and family scores."""

from math import log


def total(values):
    result = 0.0
    for value in values:
        result += value
    return result


def parent_row(parents, assignment, sizes):
    row = 0
    for parent in parents:
        row = row * sizes[parent] + assignment[parent]
    return row


def count_samples(variable, parents, samples, sizes):
    rows = 1
    for parent in parents:
        rows *= sizes[parent]
    counts = [[0] * sizes[variable] for _ in range(rows)]
    for sample in samples:
        counts[parent_row(parents, sample, sizes)][sample[variable]] += 1
    return counts


def learn(counts, alpha):
    cpt = []
    for row in counts:
        denominator = total(count + alpha for count in row)
        cpt.append([(count + alpha) / denominator for count in row])
    return cpt


def log_likelihood(counts, cpt):
    likelihood = 0.0
    for row, probabilities in zip(counts, cpt):
        for count, probability in zip(row, probabilities):
            if count:
                likelihood += count * log(probability)
    return likelihood


def parameter_count(counts):
    return (len(counts[0]) - 1) * len(counts)


def family_score(variable, parents, samples, sizes, alpha):
    counts = count_samples(variable, sorted(parents), samples, sizes)
    cpt = learn(counts, alpha)
    return log_likelihood(counts, cpt) - parameter_count(counts) * log(len(samples)) / 2
