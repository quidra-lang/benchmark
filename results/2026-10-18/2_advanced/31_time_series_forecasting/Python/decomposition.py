"""Classical centered decomposition and ordered statistical reductions."""


def total(values):
    result = 0.0
    for value in values:
        result += value
    return result


def mean(values):
    return total(values) / len(values)


def sample_variance(values):
    average = mean(values)
    return total((value - average) * (value - average) for value in values) / (len(values) - 1)


def decompose(values, season):
    count = len(values)
    half = season // 2
    defined = list(range(half, count - half))
    trend = [None] * count
    for t in defined:
        value = 0.5 * values[t - half]
        for i in range(t - half + 1, t + half):
            value += values[i]
        value += 0.5 * values[t + half]
        trend[t] = value / season
    additive = []
    multiplicative = []
    for position in range(season):
        times = [t for t in defined if t % season == position]
        additive.append(mean([values[t] - trend[t] for t in times]))
        multiplicative.append(mean([values[t] / trend[t] for t in times]))
    average_add = total(additive) / season
    average_mult = total(multiplicative) / season
    additive = [value - average_add for value in additive]
    multiplicative = [value / average_mult for value in multiplicative]
    residual_add = [None] * count
    residual_mult = [None] * count
    for t in defined:
        residual_add[t] = values[t] - trend[t] - additive[t % season]
        residual_mult[t] = values[t] / (trend[t] * multiplicative[t % season])
    return {"trend": trend, "additive": additive, "multiplicative": multiplicative,
            "residual_add": residual_add, "residual_mult": residual_mult, "defined": defined}


def least_squares_line(values):
    count = len(values)
    center = (count + 1) / 2
    average = mean(values)
    numerator = total((t + 1 - center) * (value - average) for t, value in enumerate(values))
    denominator = total((t + 1 - center) * (t + 1 - center) for t in range(count))
    slope = numerator / denominator
    return average - slope * center, slope
