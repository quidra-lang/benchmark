"""IPv4 notation and the ordered AS/link topology."""

from pathlib import Path


def address_value(text):
    value = 0
    for octet in text.split("."):
        value = (value << 8) + int(octet)
    return value


def address_text(value):
    return ".".join(str((value >> shift) & 255) for shift in (24, 16, 8, 0))


def parse_prefix(text):
    address, length = text.split("/")
    return address_value(address), int(length)


def prefix_text(prefix):
    return f"{address_text(prefix[0])}/{prefix[1]}"


def contains(prefix, address):
    shift = 32 - prefix[1]
    return address >> shift == prefix[0] >> shift


class Link:
    def __init__(self, number, name, first, second, relationship, delay, mrai):
        self.number = number
        self.name = name
        self.first = first
        self.second = second
        self.relationship = relationship
        self.delay = delay
        self.mrai = mrai
        self.up = True
        self.down_count = 0

    def other(self, owner):
        return self.second if owner == self.first else self.first

    def role(self, owner):
        if self.relationship == "P2P":
            return "peer"
        return "customer" if owner == self.first else "provider"

    def direction(self, owner):
        return {"customer": "D", "peer": "P", "provider": "U"}[self.role(owner)]


class Topology:
    def __init__(self, router_ids, links, initial):
        self.router_ids = router_ids
        self.ases = sorted(router_ids)
        self.links = links
        self.by_name = {link.name: link for link in links}
        self.at_as = {owner: [] for owner in self.ases}
        self.between = {}
        self.initial = initial
        for link in links:
            self.at_as[link.first].append(link)
            self.at_as[link.second].append(link)
            pair = tuple(sorted((link.first, link.second)))
            self.between.setdefault(pair, []).append(link)

    def connecting(self, first, second):
        return self.between[tuple(sorted((first, second)))]


def read_topology():
    router_ids, links, initial = {}, [], []
    for line in Path("input/topology.txt").read_text(encoding="ascii").splitlines():
        fields = line.split(" ")
        if fields[0] == "AS":
            router_ids[int(fields[1])] = address_value(fields[2])
        elif fields[0] == "LINK":
            name, first, second, relationship, delay, mrai = fields[1:]
            links.append(Link(len(links), name, int(first), int(second), relationship,
                              int(delay), int(mrai)))
        else:
            initial.append((int(fields[1]), parse_prefix(fields[2]), fields[3], fields[4:]))
    return Topology(router_ids, links, initial)
