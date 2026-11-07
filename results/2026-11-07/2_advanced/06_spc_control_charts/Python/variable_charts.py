from math import sqrt


class Subgroup:
    def __init__(self, number, values):
        size = len(values)
        self.number = number
        self.values = values
        self.total = sum(values)
        self.squares = sum(value * value for value in values)
        self.mean = self.total / size
        self.range = max(values) - min(values)
        self.sd = sqrt((size * self.squares - self.total * self.total) / (size * (size - 1)))


class Limits:
    def __init__(self, lcl, cl, ucl):
        self.lcl = lcl
        self.cl = cl
        self.ucl = ucl

    def outside(self, value):
        return value > self.ucl or value < self.lcl


def real_sum(values):
    total = 0.0
    for value in values:
        total += value
    return total


def subgroup_statistics(values, size):
    return [
        Subgroup(start // size + 1, values[start:start + size])
        for start in range(0, len(values), size)
    ]


def moving_ranges(values):
    return [abs(values[j] - values[j - 1]) for j in range(1, len(values))]


def grand_mean(subgroups, size):
    return sum(subgroup.total for subgroup in subgroups) / (len(subgroups) * size)


def xbar_r_limits(subgroups, size, constants):
    xbar = grand_mean(subgroups, size)
    rbar = sum(subgroup.range for subgroup in subgroups) / len(subgroups)
    return (
        Limits(xbar - constants.a2 * rbar, xbar, xbar + constants.a2 * rbar),
        Limits(constants.d3 * rbar, rbar, constants.d4 * rbar),
    )


def xbar_s_limits(subgroups, size, constants):
    xbar = grand_mean(subgroups, size)
    sbar = real_sum(subgroup.sd for subgroup in subgroups) / len(subgroups)
    return (
        Limits(xbar - constants.a3 * sbar, xbar, xbar + constants.a3 * sbar),
        Limits(constants.b3 * sbar, sbar, constants.b4 * sbar),
    )


def i_mr_limits(values, pair_constants):
    ranges = moving_ranges(values)
    ybar = sum(values) / len(values)
    mrbar = sum(ranges) / len(ranges)
    return (
        Limits(ybar - 3 * mrbar / pair_constants.d2, ybar, ybar + 3 * mrbar / pair_constants.d2),
        Limits(pair_constants.d3 * mrbar, mrbar, pair_constants.d4 * mrbar),
    )
