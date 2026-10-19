"""VCG, critical prices, coalition searches and ad-slot payment formulas."""

from fractions import Fraction
from itertools import combinations
from types import SimpleNamespace

from wdp_solver import greedy_select, solve


def vcg_payments(items, reserves, bids, optimal, bidders):
    results = {}
    for bidder in bidders:
        winning = [bid for bid in optimal.winning if bid.bidder == bidder]
        if winning:
            alternative = solve(items, reserves, [bid for bid in bids if bid.bidder != bidder])
            value = sum(bid.amount for bid in winning)
            payment = alternative.welfare - (optimal.welfare - value)
            results[bidder] = payment, alternative
    return results


def critical_payments(order, winning, reserves):
    results = {}
    for bid in winning:
        selected = greedy_select([other for other in order if other.number != bid.number])
        rival = next((other for other in selected
                      if bid.bundle & other.bundle or bid.xor and bid.bidder == other.bidder), None)
        reserve = sum(reserves[item] for item in bid.bundle)
        payment = reserve
        if rival is not None:
            threshold = rival.amount * rival.amount * len(bid.bundle)

            def earlier(amount):
                value = amount * amount * len(rival.bundle)
                return value > threshold or value == threshold and bid.number < rival.number

            low, high = 1, 1
            while not earlier(high):
                high *= 2
            while low < high:
                middle = (low + high) // 2
                if earlier(middle):
                    high = middle
                else:
                    low = middle + 1
            payment = max(reserve, low)
        results[bid.number] = payment, rival
    return results


def coalition_welfares(items, reserves, bids, bidders):
    coalitions = []
    for size in range(len(bidders) + 1):
        for positions in combinations(range(len(bidders)), size):
            members = tuple(bidders[position] for position in positions)
            result = solve(items, reserves, [bid for bid in bids if bid.bidder in members])
            coalitions.append(SimpleNamespace(members=members, mask=sum(1 << position for position in positions),
                                              welfare=result.welfare, numbers=result.numbers))
    return coalitions


def blocking_coalitions(coalitions, seller, utilities):
    blocking, minimal = [], []
    for coalition in coalitions:
        payoff = seller + sum(utilities[bidder] for bidder in coalition.members)
        if coalition.welfare > payoff:
            record = SimpleNamespace(coalition=coalition, payoff=payoff, deficit=coalition.welfare - payoff)
            if not any(previous.coalition.mask & coalition.mask == previous.coalition.mask for previous in blocking):
                minimal.append(record)
            blocking.append(record)
    return blocking, minimal


def gsp_price(ranking, rank):
    return ranking[rank + 1].bid if rank + 1 < len(ranking) else 0


def slot_vcg_payment(ranking, rates, rank):
    payment = Fraction(0)
    for following in range(rank + 1, min(len(ranking), len(rates) + 1)):
        next_rate = rates[following] if following < len(rates) else 0
        payment += ranking[following].value * (rates[following - 1] - next_rate)
    return payment
