"""Risk sets, Kaplan-Meier, Nelson-Aalen and actuarial life tables."""

from collections import Counter
from math import exp, log, sqrt

from numerics import Z95


def risk_sets(subjects):
    counts = Counter(subject["time"] for subject in subjects)
    events = Counter(subject["time"] for subject in subjects if subject["event"])
    risk = len(subjects)
    rows = []
    for time in sorted(counts):
        deaths = events[time]
        rows.append((time, risk, deaths, counts[time] - deaths))
        risk -= counts[time]
    return rows


def kaplan_meier(subjects):
    times = risk_sets(subjects)
    event_times = [time for time, _, deaths, _ in times if deaths]
    survival = 1.0
    greenwood = hazard = hazard_variance = 0.0
    rows = []
    for time, risk, deaths, _ in times:
        if not deaths:
            continue
        survival *= (risk - deaths) / risk
        if risk == deaths:
            greenwood = None
        elif greenwood is not None:
            greenwood += deaths / (risk * (risk - deaths))
        if survival == 0.0:
            error = lower = upper = None
        else:
            error = survival * sqrt(greenwood)
            logarithm = log(survival)
            omega = Z95 * sqrt(greenwood) / (-logarithm)
            lower = exp(logarithm * exp(omega))
            upper = exp(logarithm * exp(-omega))
        hazard += deaths / risk
        hazard_variance += deaths / (risk * risk)
        index = len(rows)
        next_time = event_times[index + 1] if index + 1 < len(event_times) else None
        censored = sum(
            subject["event"] == 0
            and subject["time"] >= time
            and (next_time is None or subject["time"] < next_time)
            for subject in subjects
        )
        rows.append({
            "time": time,
            "risk": risk,
            "events": deaths,
            "censored": censored,
            "survival": survival,
            "se": error,
            "lower": lower,
            "upper": upper,
            "hazard": hazard,
            "hazard_se": sqrt(hazard_variance),
        })
    return rows


def row_at(rows, time):
    for row in reversed(rows):
        if row["time"] <= time:
            return row
    return {
        "survival": 1.0,
        "se": 0.0,
        "lower": None,
        "upper": None,
        "hazard": 0.0,
        "hazard_se": 0.0,
    }


def life_table(subjects, width, count):
    survival = 1.0
    variance_sum = 0.0
    rows = []
    for interval in range(count):
        start = interval * width
        end = (interval + 1) * width
        risk = sum(subject["time"] >= start for subject in subjects)
        deaths = sum(
            start <= subject["time"] < end and subject["event"] == 1
            for subject in subjects
        )
        withdrawn = sum(
            start <= subject["time"] < end and subject["event"] == 0
            for subject in subjects
        )
        exposed_twice = 2 * risk - withdrawn
        survival *= (exposed_twice - 2 * deaths) / exposed_twice
        variance_sum += 4 * deaths / (exposed_twice * (exposed_twice - 2 * deaths))
        rows.append({
            "start": start,
            "end": end,
            "risk": risk,
            "events": deaths,
            "withdrawn": withdrawn,
            "exposed": exposed_twice / 2,
            "q": 2 * deaths / exposed_twice,
            "survival": survival,
            "se": survival * sqrt(variance_sum),
            "hazard": 2000 * deaths / (width * (exposed_twice - deaths)),
        })
    return rows
