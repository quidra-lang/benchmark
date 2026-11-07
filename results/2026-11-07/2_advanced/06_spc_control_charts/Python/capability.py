from math import sqrt

from variable_charts import real_sum


CAPABLE_CPK = 1.33
MARGINAL_CPK = 1.00
BAR_LENGTH = 50


class HistogramBin:
    def __init__(self, lower, upper, frequency, length, marks):
        self.lower = lower
        self.upper = upper
        self.frequency = frequency
        self.length = length
        self.marks = marks


class Capability:
    def __init__(self, subgroups, settings, constants):
        values = [value for subgroup in subgroups for value in subgroup.values]
        count = len(values)
        self.count = count
        self.mean = sum(values) / count
        rbar = sum(subgroup.range for subgroup in subgroups) / len(subgroups)
        sbar = real_sum(subgroup.sd for subgroup in subgroups) / len(subgroups)
        self.sigma_within = rbar / constants.d2
        self.sigma_sbar = sbar / constants.c4
        squares = real_sum((value - self.mean) * (value - self.mean) for value in values)
        self.sigma_overall = sqrt(squares / (count - 1))
        self.cp, self.cpu, self.cpl, self.cpk = indices(self.mean, self.sigma_within, settings)
        self.pp, self.ppu, self.ppl, self.ppk = indices(self.mean, self.sigma_overall, settings)
        offset = self.mean - settings.target
        self.cpm = (settings.usl - settings.lsl) / (
            6 * sqrt(self.sigma_overall * self.sigma_overall + offset * offset)
        )
        self.cpk_interval = confidence_interval(self.cpk, count, settings.ci_z)
        self.ppk_interval = confidence_interval(self.ppk, count, settings.ci_z)
        self.below = sum(value < settings.lsl for value in values)
        self.above = sum(value > settings.usl for value in values)
        self.ppm = 1000000 * (self.below + self.above) / count
        self.verdict = verdict(self.cpk)
        self.bins = histogram(values, settings)


def indices(mean, sigma, settings):
    potential = (settings.usl - settings.lsl) / (6 * sigma)
    upper = (settings.usl - mean) / (3 * sigma)
    lower = (mean - settings.lsl) / (3 * sigma)
    return potential, upper, lower, min(upper, lower)


def confidence_interval(index, count, z):
    delta = z * sqrt(1 / (9 * count) + index * index / (2 * (count - 1)))
    return index - delta, index + delta


def verdict(cpk):
    if cpk >= CAPABLE_CPK:
        return "capable"
    if cpk >= MARGINAL_CPK:
        return "marginal"
    return "incapable"


def histogram(values, settings):
    width = settings.histogram_bin
    low = width * (min(min(values), settings.lsl) // width)
    high = width * (max(max(values), settings.usl) // width) + width
    frequencies = [0] * ((high - low) // width)
    for value in values:
        frequencies[(value - low) // width] += 1
    top = max(frequencies)
    points = (("lsl", settings.lsl), ("target", settings.target), ("usl", settings.usl))
    bins = []
    for index, frequency in enumerate(frequencies):
        lower = low + index * width
        upper = lower + width - 1
        marks = [name for name, point in points if lower <= point <= upper]
        length = (BAR_LENGTH * frequency + top - 1) // top
        bins.append(HistogramBin(lower, upper, frequency, length, marks))
    return bins
