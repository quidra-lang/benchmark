"""Evaluate tidal harmonics and locate refined high and low waters."""

import math

from harmonic_fit import angle
from records import date_at_minute


def predict_height(model, time):
    result = model["mean_level"]
    for constituent in model["selected"]:
        constant = model["constants"][constituent["name"]]
        theta = angle(constituent["speed"], time)
        result += constant["a"] * math.cos(theta) + constant["b"] * math.sin(theta)
    return result


def predict_hours(model, start_hour, count):
    return [predict_height(model, start_hour + i) for i in range(count + 1)]


def find_extrema(model, start_hour, hours, grid_minutes, minimum_range):
    """Find strict extrema on the grid, then drop smallest neighboring pairs."""
    count = hours * 60 // grid_minutes
    minutes = [
        start_hour * 60 + i * grid_minutes for i in range(count + 1)
    ]
    heights = [predict_height(model, minute / 60) for minute in minutes]
    extrema = []
    for j in range(1, count):
        left, center, right = heights[j - 1:j + 2]
        if left < center > right:
            kind = "high"
        elif left > center < right:
            kind = "low"
        else:
            continue
        delta = (left - right) / (2 * (left - 2 * center + right))
        precise_minute = minutes[j] + delta * grid_minutes
        height = center - (left - right) * delta / 4
        extrema.append({
            "kind": kind, "minute": precise_minute,
            "rounded": math.floor(precise_minute + 0.5),
            "height": height,
        })
    raw = len(extrema)
    while len(extrema) >= 2:
        index = min(range(len(extrema) - 1),
                    key=lambda i: abs(extrema[i]["height"] - extrema[i + 1]["height"]))
        if abs(extrema[index]["height"] - extrema[index + 1]["height"]) >= minimum_range:
            break
        del extrema[index:index + 2]
    return extrema, raw


def label_extrema(extrema, epoch):
    """Assign HHW/LHW and HLW/LLW by daily extremes, preserving time order."""
    by_date = {}
    for item in extrema:
        date = date_at_minute(epoch, item["rounded"])
        item["date"] = date
        by_date.setdefault(date, []).append(item)
    for group in by_date.values():
        highs = [item for item in group if item["kind"] == "high"]
        lows = [item for item in group if item["kind"] == "low"]
        if highs:
            best = max(highs, key=lambda item: item["height"])
            for item in highs:
                item["label"] = "HHW" if item is best else "LHW"
        if lows:
            best = min(lows, key=lambda item: item["height"])
            for item in lows:
                item["label"] = "LLW" if item is best else "HLW"
    return extrema
