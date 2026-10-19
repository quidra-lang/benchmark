"""Holdout accuracy, seasonal scaling, interval loss and deterministic ranks."""

from math import sqrt

from decomposition import total


def seasonal_scale(values, season):
    return total(abs(values[t] - values[t - season])
                 for t in range(season, len(values))) / (len(values) - season)


def accuracy(actual, predicted, scale):
    count = len(actual)
    errors = [observed - forecast for observed, forecast in zip(actual, predicted)]
    mae = total(abs(value) for value in errors) / count
    return {
        "me": total(errors) / count, "mae": mae,
        "rmse": sqrt(total(value * value for value in errors) / count),
        "mape": 100 * total(abs(error) / value for error, value in zip(errors, actual)) / count,
        "smape": 100 * total(2 * abs(error) / (abs(a) + abs(f))
                             for error, a, f in zip(errors, actual, predicted)) / count,
        "mase": mae / scale,
    }


def winkler(actual, low, high, multiplier):
    if actual < low:
        return high - low + multiplier * (low - actual)
    if actual > high:
        return high - low + multiplier * (actual - high)
    return high - low


def rank_models(ordered_names, metrics):
    return sorted(ordered_names, key=lambda name: (metrics[name]["rmse"], ordered_names.index(name)))
