"""Magnitude formulae, median, decimal classes, and Gutenberg-Richter fit."""

import math
from collections import Counter


LOG10_DENOMINATOR = 2.302585092994046


def log10(value):
    return math.log(value) / LOG10_DENOMINATOR


def median(values):
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2


def per_pick_magnitude(pick, distance_km, params):
    a_local, b_local, c_local = params["local_magnitude"]
    a_duration, b_duration, c_duration = params["duration_magnitude"]
    duration_seconds = pick["duration"] / 100
    result = {
        "r": distance_km,
        "md": a_duration + b_duration * log10(duration_seconds)
              + c_duration * distance_km,
        "ml": None,
    }
    if not pick["clipped"]:
        result["ml"] = (
            log10(pick["amplitude"]) +
            a_local * log10(distance_km / 100) +
            b_local * (distance_km - 100) + c_local
        )
    return result


def class_number(magnitude):
    """The decimal class of a magnitude rounded to two displayed decimals."""
    decimal = f"{magnitude:.2f}"
    hundredths = int(round(float(decimal) * 100))
    return (hundredths + 5) // 10


def magnitude_class(value):
    sign = "-" if value < 0 else ""
    absolute = abs(value)
    return f"{sign}{absolute // 10}.{absolute % 10}"


def frequency_statistics(events):
    classes = [class_number(event["ml"]) for event in events
               if event["ml"] is not None]
    counts = Counter(classes)
    completeness = min(counts, key=lambda c: (-counts[c], c))
    above = [value for value in classes if value >= completeness]
    mc = completeness / 10
    mean = sum(above) / (10 * len(above))
    bvalue = 0.4342944819032518 / (mean - (mc - 0.05))
    sigma = bvalue / math.sqrt(len(above))
    avalue = log10(len(above)) + bvalue * mc
    x = [event["md"] for event in events if event["ml"] is not None]
    y = [event["ml"] for event in events if event["ml"] is not None]
    size = len(x)
    xm, ym = sum(x) / size, sum(y) / size
    xx = sum((value - xm) ** 2 for value in x)
    xy = sum((a - xm) * (b - ym) for a, b in zip(x, y))
    yy = sum((value - ym) ** 2 for value in y)
    slope = xy / xx
    return {
        "classes": counts, "completeness": completeness,
        "nb": len(above), "bvalue": bvalue,
        "sigma": sigma, "avalue": avalue,
        "mlmd": {
            "n": size, "slope": slope, "intercept": ym - slope * xm,
            "r": xy / math.sqrt(xx * yy), "mean_diff": ym - xm,
        },
    }
