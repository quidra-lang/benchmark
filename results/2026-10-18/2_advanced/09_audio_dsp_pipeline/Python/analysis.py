import math

from signals import MAX_SAMPLE, MIN_SAMPLE, peak


def energy(samples):
    return sum(x * x for x in samples)


def rms(samples):
    return math.isqrt(energy(samples) // len(samples))


def zero_crossings(samples):
    return sum(1 for a, b in zip(samples, samples[1:]) if (a < 0) != (b < 0))


def count_clipped(samples):
    return sum(1 for x in samples if x in (MAX_SAMPLE, MIN_SAMPLE))


def crest_fraction(samples):
    denominator = energy(samples)
    if denominator == 0:
        return None
    numerator = peak(samples) ** 2 * len(samples)
    divisor = math.gcd(numerator, denominator)
    return numerator // divisor, denominator // divisor


def autocorrelation(samples, lag):
    return sum(a * b for a, b in zip(samples, samples[lag:]))


def pitch_lag(samples, low, high):
    best_lag = low
    best_value = autocorrelation(samples, low)
    for lag in range(low + 1, high + 1):
        value = autocorrelation(samples, lag)
        if value > best_value:
            best_lag = lag
            best_value = value
    return best_lag if best_value > 0 else None
