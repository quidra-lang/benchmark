"""Pairwise deletion, integer saturation tests, and distance matrices."""

from math import log

from alignment import BASES


MODELS = ("P", "JC", "K2P")
TRANSITIONS = {("A", "G"), ("G", "A"), ("C", "T"), ("T", "C")}


def pair_counts(first, second, weights):
    sites = transitions = transversions = 0
    for a, b, weight in zip(first, second, weights):
        if a not in BASES or b not in BASES:
            continue
        sites += weight
        if a != b:
            if (a, b) in TRANSITIONS:
                transitions += weight
            else:
                transversions += weight
    return sites, transitions, transversions


def all_pairs(sequences, weights):
    pairs = []
    for first in range(len(sequences)):
        for second in range(first + 1, len(sequences)):
            counts = pair_counts(sequences[first], sequences[second], weights)
            pairs.append((first, second, *counts))
    return pairs


def corrected(model, sites, transitions, transversions, replacement):
    saturated = sites == 0
    if model == "JC":
        saturated |= 4 * (transitions + transversions) >= 3 * sites
    elif model == "K2P":
        saturated |= 2 * transitions + transversions >= sites or 2 * transversions >= sites
    if saturated:
        return replacement, True
    if model == "P":
        value = (transitions + transversions) / sites
    elif model == "JC":
        value = -(3 / 4) * log(1 - (4 * (transitions + transversions)) / (3 * sites))
    else:
        value = (-(1 / 2) * log(1 - (2 * transitions) / sites - transversions / sites)
                 - (1 / 4) * log(1 - (2 * transversions) / sites))
    return value, False


def build_matrix(pairs, count, model, replacement):
    matrix = [[0.0] * count for _ in range(count)]
    saturated = []
    for first, second, sites, transitions, transversions in pairs:
        value, replaced = corrected(model, sites, transitions, transversions, replacement)
        matrix[first][second] = matrix[second][first] = value
        if replaced:
            saturated.append((first, second, sites))
    return matrix, saturated
