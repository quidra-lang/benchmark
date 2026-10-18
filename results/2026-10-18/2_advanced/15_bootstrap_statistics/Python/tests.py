from itertools import combinations, groupby
from math import gcd

from resampling import mean, sequential_sum


def position_choices(total, size):
    return combinations(range(total), size)


def reduced_fraction(numerator, denominator):
    divisor = gcd(numerator, denominator)
    return numerator // divisor, denominator // divisor


def contrast(first_total, first_size, second_total, second_size):
    return second_size * first_total - first_size * second_total


def value_counts(values):
    return [(value, len(list(run))) for value, run in groupby(sorted(values))]


def doubled_ranks(values):
    ranks = {}
    smaller = 0
    for value, count in value_counts(values):
        ranks[value] = 2 * smaller + count + 1
        smaller += count
    return [ranks[value] for value in values]


def split_list(items, sizes):
    parts = []
    start = 0
    for size in sizes:
        parts.append(items[start:start + size])
        start += size
    return parts


def sums_of_squares(samples):
    count = sum(len(sample) for sample in samples)
    grand_mean = sum(sum(sample) for sample in samples) / (100 * count)
    between = 0.0
    within = 0.0
    for sample in samples:
        group_mean = mean(sample)
        between += len(sample) * ((group_mean - grand_mean) * (group_mean - grand_mean))
        squares = 0.0
        for value in sample:
            deviation = value / 100 - group_mean
            squares += deviation * deviation
        within += squares
    return between, within


def f_statistic(between, within, group_count, total_count):
    return between / (group_count - 1) / (within / (total_count - group_count))


def h_statistic(rank_sums, sizes, correction):
    count = sum(sizes)
    total = sequential_sum(rank * rank / (4 * size) for rank, size in zip(rank_sums, sizes))
    return (12 * total / (count * (count + 1)) - 3 * (count + 1)) / correction
