"""Exhaustive block choices with cached suit states and exact shanten minima."""

from functools import lru_cache

from tiles import YAOCHUU


@lru_cache(maxsize=65536)
def patterns(counts, suited):
    first = next((kind for kind, count in enumerate(counts) if count), None)
    if first is None:
        return ((0, 0, 0),)
    choices = [((first,), 0, 0, 0)]
    if counts[first] >= 3:
        choices.append(((first, first, first), 1, 0, 0))
    if counts[first] >= 2:
        choices.append(((first, first), 0, 1, 0))
        choices.append(((first, first), 0, 0, 1))
    if suited:
        if first <= 6 and counts[first + 1] and counts[first + 2]:
            choices.append(((first, first + 1, first + 2), 1, 0, 0))
        for difference in (1, 2):
            other = first + difference
            if other < 9 and counts[other]:
                choices.append(((first, other), 0, 1, 0))
    best = {}
    for removed, extra_sets, extra_partial, extra_pair in choices:
        remaining = list(counts)
        for kind in removed:
            remaining[kind] -= 1
        for sets, partial, pair in patterns(tuple(remaining), suited):
            sets += extra_sets
            pair += extra_pair
            if sets > 4 or pair > 1:
                continue
            partial = min(4, partial + extra_partial)
            key = sets, pair
            if partial > best.get(key, -1):
                best[key] = partial
    return tuple((sets, partial, pair) for (sets, pair), partial in sorted(best.items()))


def standard(counts):
    states = {(0, 0): 0}
    for start, stop in ((0, 9), (9, 18), (18, 27), (27, 34)):
        local = patterns(tuple(counts[start:stop]), start < 27)
        combined = {}
        for (sets, pair), partial in states.items():
            for local_sets, local_partial, local_pair in local:
                total_sets, total_pair = sets + local_sets, pair + local_pair
                if total_sets > 4 or total_pair > 1:
                    continue
                total_partial = min(4, partial + local_partial)
                key = total_sets, total_pair
                if total_partial > combined.get(key, -1):
                    combined[key] = total_partial
        states = combined
    return min(8 - 2 * sets - min(partial, 4 - sets) - pair
               for (sets, pair), partial in states.items())


@lru_cache(maxsize=8192)
def numbers(counts):
    pairs = sum(count >= 2 for count in counts)
    kinds = sum(count >= 1 for count in counts)
    seven = 6 - pairs + max(0, 7 - kinds)
    orphans = 13 - sum(counts[kind] >= 1 for kind in YAOCHUU)
    if any(counts[kind] >= 2 for kind in YAOCHUU):
        orphans -= 1
    return standard(counts), seven, orphans
