"""Auction clocks and feasible XOR/OR candidate values."""

from collections import namedtuple
from types import SimpleNamespace


Candidate = namedtuple("Candidate", "number bundle value")


def candidates(bids, xor):
    result = []
    for number in range(1, 1 << len(bids)):
        if xor and number.bit_count() != 1:
            continue
        bundle, value = set(), 0
        for index, bid in enumerate(bids):
            if number & (1 << index):
                if bundle & bid.bundle:
                    break
                bundle.update(bid.bundle)
                value += bid.amount
        else:
            result.append(Candidate(number, frozenset(bundle), value))
    return result


def value_of(candidates, items):
    return max((candidate.value for candidate in candidates if candidate.bundle <= items), default=0)


def english(participants, reserve, increment):
    price, steps = reserve, 0
    remaining = [index for index, bidder in enumerate(participants) if bidder.value >= price]
    while len(remaining) >= 2:
        previous = remaining
        price += increment
        steps += 1
        remaining = [index for index, bidder in enumerate(participants) if bidder.value >= price]
        if not remaining:
            winner, paid = previous[0], price - increment
            break
    else:
        winner = remaining[0] if remaining else None
        paid = price if remaining else 0
    drops = []
    for bidder in participants:
        drop = reserve if bidder.value < reserve else reserve + ((bidder.value - reserve) // increment + 1) * increment
        drops.append(drop if drop <= price else None)
    return SimpleNamespace(winner=winner, price=paid, steps=steps, drops=drops)


def dutch(participants, reserve, start, decrement):
    price, steps = start, 0
    while price >= reserve:
        eligible = [index for index, bidder in enumerate(participants) if bidder.bid >= price]
        if eligible:
            winner = max(eligible, key=lambda index: participants[index].bid)
            return SimpleNamespace(winner=winner, price=price, steps=steps)
        price -= decrement
        steps += 1
    return SimpleNamespace(winner=None, price=0, steps=steps)
