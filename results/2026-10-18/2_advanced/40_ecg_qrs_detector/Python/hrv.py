"""Integer RR/NN variability statistics, histogram and consecutive runs."""

from collections import Counter
from report import rdiv, root


def mean(values):
    return rdiv(100 * sum(values), len(values)) if values else None


def rr_statistics(beats):
    intervals = [(beat["number"], beat["rr"]) for beat in beats if beat["rr"] is not None]
    values = [rr for _, rr in intervals]
    if not values:
        return {"count": 0, "mean_rr": None, "mean_hr": None,
                "shortest": None, "longest": None}
    shortest = min(intervals, key=lambda v: (v[1], v[0]))
    longest = max(intervals, key=lambda v: (v[1], -v[0]))
    return {
        "count": len(intervals), "mean_rr": mean(values),
        "mean_hr": rdiv(6000000 * len(values), sum(values)),
        "shortest": shortest, "longest": longest,
    }


def nn_statistics(beats):
    nn = {}
    for i in range(2, len(beats)):
        previous = beats[i - 1]
        current = beats[i]
        if (previous["label"] == "N" and current["label"] == "N"
                and 5 * abs(current["rr"] - previous["rr"]) <= previous["rr"]):
            nn[current["number"]] = current["rr"]
    pairs = [
        (nn[number - 1], value)
        for number, value in nn.items()
        if number - 1 in nn
    ]
    values = list(nn.values())
    differences = [b - a for a, b in pairs]
    sums = [a + b for a, b in pairs]
    e = len(values)
    k = len(pairs)
    result = {
        "intervals": values, "pairs": pairs, "e": e, "k": k,
        "mean_nn": mean(values),
        "sdnn": (root(e * sum(v * v for v in values) - sum(values) ** 2,
                      e * (e - 1)) if e >= 2 else None),
        "rmssd": root(sum(d * d for d in differences), k) if k else None,
        "sdsd": (root(k * sum(d * d for d in differences) - sum(differences) ** 2,
                      k * (k - 1)) if k >= 2 else None),
        "nn50": sum(abs(value) > 50 for value in differences),
        "pnn50": (rdiv(10000 * sum(abs(value) > 50 for value in differences), k)
                  if k else None),
        "sd1": (root(k * sum(d * d for d in differences) - sum(differences) ** 2,
                     2 * k * (k - 1)) if k >= 2 else None),
        "sd2": (root(k * sum(v * v for v in sums) - sum(sums) ** 2,
                     2 * k * (k - 1)) if k >= 2 else None),
    }
    result["histogram"] = Counter(16 * value // 125 for value in values)
    maximum = max(result["histogram"].values(), default=0)
    result["histogram_max"] = maximum
    result["triangular_index"] = (rdiv(100 * e, maximum) if maximum else None)
    return result


def consecutive_ranges(indices):
    """Produce maximal inclusive integer ranges in increasing order."""
    result = []
    if not indices:
        return result
    start = end = indices[0]
    for current in indices[1:]:
        if current == end + 1:
            end = current
        else:
            result.append((start, end))
            start = end = current
    result.append((start, end))
    return result


def linked_sequences(positions, interval, lookup):
    """Partition specified beat IDs by the requested alternating-V pattern."""
    chains = []
    current = []
    for index in positions:
        if (current and index == current[-1] + interval
                and all(lookup[j] == "N"
                        for j in range(current[-1] + 1, index))):
            current.append(index)
        else:
            if current:
                chains.append(current)
            current = [index]
    if current:
        chains.append(current)
    return chains
