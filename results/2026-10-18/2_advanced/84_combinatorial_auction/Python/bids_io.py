"""Read item, bidder, single-item and parameter records in file order."""

from collections import namedtuple
from pathlib import Path
from types import SimpleNamespace


Bid = namedtuple("Bid", "number bidder bundle amount xor")
Participant = namedtuple("Participant", "name value bid")


def records(name):
    return [line.split() for line in Path("input/" + name).read_text(encoding="ascii").splitlines()]


def read_inputs():
    items = {name: int(reserve) for name, reserve in records("items.txt")}
    auctions = {}
    for fields in records("bids.txt"):
        if fields[0] == "auction":
            auction = SimpleNamespace(name=fields[1], items=fields[2:], lines=[])
            auctions[auction.name] = auction
        else:
            auction.lines.append((fields[1], fields[2], fields[3:]))
    groups = []
    for fields in records("single_item.txt"):
        if fields[0] in ("lot", "slots"):
            group = SimpleNamespace(kind=fields[0], name=fields[1], arguments=fields[2:], participants=[])
            groups.append(group)
        else:
            group.participants.append(Participant(fields[1], int(fields[2]), int(fields[3])))
    parameters = {}
    for name, *values in records("params.txt"):
        parameters[name] = values if name == "run" else int(values[0])
    return items, auctions, groups, parameters
