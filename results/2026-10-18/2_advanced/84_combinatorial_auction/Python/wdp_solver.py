"""Exact depth-first winner determination and the prescribed greedy order."""

from fractions import Fraction
from functools import cmp_to_key
from types import SimpleNamespace


def shares(items, reserves, bids):
    result = []
    for item in items:
        share, source = Fraction(reserves[item]), None
        for bid in bids:
            if item in bid.bundle:
                candidate = Fraction(bid.amount, len(bid.bundle))
                if candidate > share:
                    share, source = candidate, bid.number
        result.append((item, share, source))
    return result


def solve(items, reserves, bids):
    bids = sorted(bids, key=lambda bid: bid.number)
    root_shares = shares(items, reserves, bids)
    root_bound = sum((share for _, share, _ in root_shares), Fraction(0))
    result = SimpleNamespace(welfare=None, numbers=(), nodes=0, pruned=0, leaves=0,
                             improvements=[], shares=root_shares, bound=root_bound)

    def visit(decided, used, welfare, chosen):
        result.nodes += 1
        if len(decided) == len(items):
            result.leaves += 1
            numbers = tuple(sorted(bid.number for bid in chosen))
            if result.welfare is None or welfare > result.welfare or welfare == result.welfare and numbers < result.numbers:
                result.welfare, result.numbers = welfare, numbers
                result.improvements.append((result.nodes, welfare, numbers))
            return
        available = [bid for bid in bids if not bid.bundle & decided and not (bid.xor and bid.bidder in used)]
        remaining = [item for item in items if item not in decided]
        bound = welfare + sum((share for _, share, _ in shares(remaining, reserves, available)), Fraction(0))
        if result.welfare is not None and bound < result.welfare:
            result.pruned += 1
            return
        first = remaining[0]
        for bid in available:
            if first in bid.bundle:
                next_used = used | {bid.bidder} if bid.xor else used
                visit(decided | bid.bundle, next_used, welfare + bid.amount, chosen + (bid,))
        visit(decided | {first}, used, welfare + reserves[first], chosen)

    visit(set(), set(), 0, ())
    by_number = {bid.number: bid for bid in bids}
    result.winning = [by_number[number] for number in result.numbers]
    return result


def greedy_order(bids):
    def compare(first, second):
        left = first.amount * first.amount * len(second.bundle)
        right = second.amount * second.amount * len(first.bundle)
        if left != right:
            return -1 if left > right else 1
        return (first.number > second.number) - (first.number < second.number)

    return sorted(bids, key=cmp_to_key(compare))


def greedy_select(bids):
    occupied, used, chosen = set(), set(), []
    for bid in bids:
        if bid.bundle & occupied or bid.xor and bid.bidder in used:
            continue
        chosen.append(bid)
        occupied.update(bid.bundle)
        if bid.xor:
            used.add(bid.bidder)
    return chosen
