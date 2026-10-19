"""Backtracking decompositions, special forms, waiting tiles and wait shapes."""

from functools import lru_cache

from tiles import YAOCHUU


def set_key(block):
    return block[0], block[0] != block[-1]


@lru_cache(maxsize=16384)
def standard(counts, meld_count=0):
    needed = 4 - meld_count
    if sum(counts) != needed * 3 + 2:
        return ()
    remaining = list(counts)
    found = set()

    def visit(pair, sets):
        if len(sets) == needed:
            if not any(remaining):
                found.add((pair, tuple(sorted(sets, key=set_key))))
            return
        first = next((kind for kind, count in enumerate(remaining) if count), None)
        if first is None:
            return
        if remaining[first] >= 3:
            remaining[first] -= 3
            visit(pair, sets + ((first, first, first),))
            remaining[first] += 3
        if first < 27 and first % 9 <= 6 and remaining[first + 1] and remaining[first + 2]:
            for kind in (first, first + 1, first + 2):
                remaining[kind] -= 1
            visit(pair, sets + ((first, first + 1, first + 2),))
            for kind in (first, first + 1, first + 2):
                remaining[kind] += 1

    for pair in range(34):
        if remaining[pair] >= 2:
            remaining[pair] -= 2
            visit(pair, ())
            remaining[pair] += 2
    return tuple(sorted(found))


def seven_pairs(counts):
    return sum(count == 2 for count in counts) == 7 and all(count in (0, 2) for count in counts)


def thirteen_orphans(counts):
    return (sum(counts) == 14 and all(counts[kind] for kind in YAOCHUU)
            and all(not count for kind, count in enumerate(counts) if kind not in YAOCHUU))


def winning(counts, meld_count=0):
    return (bool(standard(tuple(counts), meld_count))
            or meld_count == 0 and (seven_pairs(counts) or thirteen_orphans(counts)))


def waiting_tiles(hand_counts, meld_counts, meld_count):
    waiting = []
    concealed = list(hand_counts)
    for kind in range(34):
        if hand_counts[kind] + meld_counts[kind] >= 4:
            continue
        concealed[kind] += 1
        if winning(concealed, meld_count):
            waiting.append(kind)
        concealed[kind] -= 1
    return waiting


def wait_shape(form, winning_block, winning_tile, hand_counts):
    if form == "chiitoitsu":
        return "tanki"
    if form == "kokushi":
        return "thirteen" if all(hand_counts[kind] == 1 for kind in YAOCHUU) else "single"
    if len(winning_block) == 2:
        return "tanki"
    if winning_block[0] == winning_block[-1]:
        return "shanpon"
    first = winning_block[0]
    if winning_tile == first + 1:
        return "kanchan"
    if first % 9 == 0 and winning_tile == first + 2 or first % 9 == 6 and winning_tile == first:
        return "penchan"
    return "ryanmen"
