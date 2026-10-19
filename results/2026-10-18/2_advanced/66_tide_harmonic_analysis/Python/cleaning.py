"""Median/MAD spike checks, stuck sensors and missing observation gaps."""

from bisect import bisect_left, bisect_right


def median(values):
    ordered = sorted(values)
    length = len(ordered)
    if length % 2:
        return ordered[length // 2]
    return (ordered[length // 2 - 1] + ordered[length // 2]) / 2


def prepare_record(record, minimum_run):
    values = record["values"]
    numeric_times = sorted(t for t, value in values.items() if value is not None)
    first = numeric_times[0]
    last = numeric_times[-1]
    reasons = {}
    for time in range(first, last + 1):
        if time not in values:
            reasons[time] = "absent"
        elif values[time] is None:
            reasons[time] = "na"
    flat_runs = []
    cursor = 0
    while cursor < len(numeric_times):
        start = numeric_times[cursor]
        end = start
        while (cursor + 1 < len(numeric_times)
               and numeric_times[cursor + 1] == end + 1
               and values[numeric_times[cursor + 1]] == values[start]):
            cursor += 1
            end = numeric_times[cursor]
        if end - start + 1 >= minimum_run:
            flat_runs.append({"start": start, "end": end, "value": values[start]})
            for time in range(start + 1, end + 1):
                reasons[time] = "flat"
        cursor += 1
    candidates = [t for t in numeric_times if t not in reasons]
    return {
        "first": first, "last": last, "length": last - first,
        "numeric_times": numeric_times, "reasons": reasons,
        "flat_runs": flat_runs, "candidates": candidates,
        "values": values, "rows": record["rows"],
    }


def detect_spikes(cleaning, preliminary_residuals, settings):
    candidates = cleaning["candidates"]
    window = settings["spike_window"]
    required = settings["spike_minimum"]
    factor = settings["spike_factor"]
    floor = settings["spike_floor"]
    spike_records = []
    tested = 0
    for time in candidates:
        lo = bisect_left(candidates, time - window)
        hi = bisect_right(candidates, time + window)
        neighbors = [preliminary_residuals[t] for t in candidates[lo:hi]]
        if len(neighbors) < required:
            continue
        tested += 1
        center = median(neighbors)
        mad = median([abs(residual - center) for residual in neighbors])
        limit = max(factor * 1.4826 * mad, floor)
        residual = preliminary_residuals[time]
        if abs(residual - center) > limit:
            cleaning["reasons"][time] = "spike"
            spike_records.append({
                "time": time, "value": cleaning["values"][time],
                "residual": residual, "median": center,
                "mad": mad, "limit": limit,
            })
    cleaning["spikes"] = spike_records
    cleaning["tested"] = tested
    cleaning["usable"] = [t for t in candidates if t not in cleaning["reasons"]]
    cleaning["gaps"] = list_gaps(cleaning)
    return cleaning


def list_gaps(cleaning):
    first, last = cleaning["first"], cleaning["last"]
    reasons = cleaning["reasons"]
    gaps = []
    start = first
    while start <= last:
        if start not in reasons:
            start += 1
            continue
        end = start
        while end + 1 <= last and end + 1 in reasons:
            end += 1
        causes = {reasons[t] for t in range(start, end + 1)}
        gaps.append({
            "start": start, "end": end,
            "cause": next(iter(causes)) if len(causes) == 1 else "mixed",
        })
        start = end + 1
    return gaps
