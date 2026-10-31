from math import exp, log, sqrt


def sequential_sum(values):
    total = 0.0
    for value in values:
        total += value
    return total


def mean(values):
    return sum(values) / (100 * len(values))


def doubled_median(values):
    ordered = sorted(values)
    count = len(ordered)
    return ordered[(count + 1) // 2 - 1] + ordered[(count + 2) // 2 - 1]


def median(values):
    return doubled_median(values) / 200


def trim_count(count):
    return count // 10


def trimmed_mean(values):
    ordered = sorted(values)
    count = len(ordered)
    trim = trim_count(count)
    return sum(ordered[trim:count - trim]) / (100 * (count - 2 * trim))


def deviations(values):
    center = mean(values)
    return [value / 100 - center for value in values]


def sd(values):
    squares = sequential_sum(deviation * deviation for deviation in deviations(values))
    return sqrt(squares / (len(values) - 1))


def central_moments(values):
    second = 0.0
    third = 0.0
    fourth = 0.0
    for deviation in deviations(values):
        second += deviation * deviation
        third += deviation * deviation * deviation
        fourth += deviation * deviation * deviation * deviation
    count = len(values)
    return second / count, third / count, fourth / count


def mad(values):
    center = doubled_median(values)
    return doubled_median([abs(2 * value - center) for value in values]) / 400


def quantile_numerator(values, percent):
    ordered = sorted(values)
    position = (len(ordered) - 1) * percent
    index = position // 100
    fraction = position - 100 * index
    if fraction == 0:
        return 100 * ordered[index]
    return 100 * ordered[index] + fraction * (ordered[index + 1] - ordered[index])


def winsorized(values):
    ordered = sorted(values)
    trim = trim_count(len(ordered))
    low = ordered[trim]
    high = ordered[len(ordered) - 1 - trim]
    return [min(max(value, low), high) for value in values]


def mean_difference(x, y):
    return (len(y) * sum(x) - len(x) * sum(y)) / (100 * len(x) * len(y))


def median_ratio(x, y):
    return doubled_median(x) / doubled_median(y)


def hodges_lehmann(x, y):
    return doubled_median([first - second for first in x for second in y]) / 200


def pooled_sd(x, y):
    first = sd(x)
    second = sd(y)
    squares = (len(x) - 1) * first * first + (len(y) - 1) * second * second
    return sqrt(squares / (len(x) + len(y) - 2))


def cohen_d(x, y):
    return mean_difference(x, y) / pooled_sd(x, y)


def correlation(x, y):
    first = deviations(x)
    second = deviations(y)
    products = sequential_sum(e * f for e, f in zip(first, second))
    first_squares = sequential_sum(e * e for e in first)
    second_squares = sequential_sum(f * f for f in second)
    return products / sqrt(first_squares * second_squares)


def resample_indices(generator, size):
    return [generator.draw_below(size) for _ in range(size)]


def ordinary_indices(generator, size, count):
    return [resample_indices(generator, size) for _ in range(count)]


def balanced_indices(generator, size, count):
    sequence = list(range(size)) * count
    generator.shuffle(sequence)
    return [sequence[r * size:(r + 1) * size] for r in range(count)]


def without(values, index):
    return values[:index] + values[index + 1:]


def mean_and_se(values):
    count = len(values)
    average = sequential_sum(values) / count
    squares = sequential_sum((value - average) * (value - average) for value in values)
    return average, sqrt(squares / (count - 1))


def phi(x):
    if x < 0:
        return 1 - phi(-x)
    eta = 1 / (1 + 0.2316419 * x)
    psi = eta * (0.319381530 + eta * (-0.356563782 + eta * (
        1.781477937 + eta * (-1.821255978 + eta * 1.330274429)
    )))
    return 1 - 0.3989422804014327 * exp(-(x * x) / 2) * psi


def phi_inverse(p):
    if p > 0.5:
        return -phi_inverse(1 - p)
    eta = sqrt(-2 * log(p))
    numerator = 2.515517 + eta * (0.802853 + eta * 0.010328)
    denominator = 1 + eta * (1.432788 + eta * (0.189269 + eta * 0.001308))
    return -(eta - numerator / denominator)
