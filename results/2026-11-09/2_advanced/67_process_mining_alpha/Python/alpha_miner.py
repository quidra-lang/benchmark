from collections import Counter


def extend_pair(pair, activity, side, relation):
    first, second = pair
    group = first if side == 0 else second
    if activity in group or relation(activity, activity) != "#":
        return None
    if any(relation(activity, other) != "#" for other in group):
        return None
    if side == 0:
        if any(relation(activity, other) != "->" for other in second):
            return None
        return first | {activity}, second
    if any(relation(other, activity) != "->" for other in first):
        return None
    return first, second | {activity}


def pair_order(pair):
    return tuple(sorted(pair[0])), tuple(sorted(pair[1]))


def triangle_counts(log):
    counts = Counter()
    for trace, weight in log:
        for first, second, third in zip(trace, trace[1:], trace[2:]):
            if first == third and first != second:
                counts[first, second] += weight
    return counts


def plus_relation(counts, triangles, first, second):
    forward = counts[first, second] > 0
    backward = counts[second, first] > 0
    loop = first != second and triangles[first, second] > 0 and triangles[second, first] > 0
    if forward and (not backward or loop):
        return "->"
    if backward and (not forward or loop):
        return "<-"
    return "||" if forward and backward else "#"
