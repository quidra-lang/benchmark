from collections import Counter


def directly_follows(log):
    counts = Counter()
    for trace, weight in log:
        for first, second in zip(trace, trace[1:]):
            counts[first, second] += weight
    return counts


def basic_relation(counts, first, second):
    forward = counts[first, second] > 0
    backward = counts[second, first] > 0
    if forward and not backward:
        return "->"
    if backward and not forward:
        return "<-"
    return "||" if forward else "#"


def table(rows, width):
    size = len(rows)
    lines = ["    " + "".join(f"{number:>{width}}" for number in range(1, size + 1))]
    for number, row in enumerate(rows, 1):
        lines.append(f"{number:>4}" + "".join(f"{str(value):>{width}}" for value in row))
    return lines


def footprint(activities, relation):
    lines = [f"ACTIVITY {number} {activity}" for number, activity in enumerate(activities, 1)]
    rows = [[relation(first, second) for second in activities] for first in activities]
    lines.extend(table(rows, 4))
    return lines
