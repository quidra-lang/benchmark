"""Differencing, Yule-Walker recursion, AR forecasts and Ljung-Box tails."""

from math import exp

from decomposition import mean, total


KINDS = ("none", "first", "seasonal", "both")


def difference(values, season, kind):
    if kind == "none":
        return list(values), 0
    if kind == "first":
        return [values[t] - values[t - 1] for t in range(1, len(values))], 1
    if kind == "seasonal":
        return [values[t] - values[t - season] for t in range(season, len(values))], season
    return ([(values[t] - values[t - 1]) - (values[t - season] - values[t - season - 1])
             for t in range(season + 1, len(values))], season + 1)


def autocorrelation(values, max_lag):
    average = mean(values)
    centered = [value - average for value in values]
    count = len(values)
    variance = total(value * value for value in centered) / count
    correlations = [1.0]
    for lag in range(1, max_lag + 1):
        numerator = total(centered[i] * centered[i + lag] for i in range(count - lag))
        correlations.append(numerator / count / variance)
    return average, variance, correlations


def durbin_levinson(correlations):
    coefficients = [[]]
    partial = [0.0]
    variances = [1.0]
    for order in range(1, len(correlations)):
        previous = coefficients[-1]
        correction = total(previous[j - 1] * correlations[order - j] for j in range(1, order))
        theta = (correlations[order] - correction) / variances[-1]
        current = [previous[j - 1] - theta * previous[order - j - 1]
                   for j in range(1, order)] + [theta]
        coefficients.append(current)
        partial.append(theta)
        variances.append(variances[-1] * (1 - theta * theta))
    return coefficients, partial, variances


def residuals(values, average, coefficients):
    order = len(coefficients)
    return [values[i] - average - total(coefficients[j - 1] * (values[i - j] - average)
                                        for j in range(1, order + 1))
            for i in range(order, len(values))]


def forecast(values, differenced, offset, kind, average, coefficients, origin, steps, season):
    transformed = list(differenced[:origin - offset])
    extended = list(values[:origin])
    result = []
    for _ in range(steps):
        predicted = average + total(coefficient * (transformed[-j] - average)
                                    for j, coefficient in enumerate(coefficients, 1))
        transformed.append(predicted)
        if kind == "first":
            predicted += extended[-1]
        elif kind == "seasonal":
            predicted += extended[-season]
        elif kind == "both":
            predicted = predicted + extended[-1] + extended[-season] - extended[-season - 1]
        extended.append(predicted)
        result.append(predicted)
    return result


def ljung_box(errors, lags):
    count = len(errors)
    _, _, correlations = autocorrelation(errors, max(lags))
    result = []
    for lag in lags:
        q = count * (count + 2) * total(correlations[k] * correlations[k] / (count - k)
                                      for k in range(1, lag + 1))
        x = q / 2
        term = 1.0
        terms = [term]
        for i in range(1, lag // 2):
            term = term * x / i
            terms.append(term)
        result.append((lag, q, exp(-x) * total(terms)))
    return result
