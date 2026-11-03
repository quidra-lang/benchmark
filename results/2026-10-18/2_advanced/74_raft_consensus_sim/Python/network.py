"""Ordered message delivery, directional links, loss rules, and counters."""

from collections import namedtuple
from heapq import heappop, heappush
from pathlib import Path


TYPES = ("RV", "RVR", "AE", "AER", "TN")
FIELDS = ("sent", "delivered", "inflight", "partition", "rule", "loss", "down")
REASONS = ("partition", "rule", "loss", "down")
Message = namedtuple("Message", "kind source destination term data")


class Link:
    def __init__(self, delay):
        self.delay = delay
        self.loss = 0
        self.passed = 0
        self.drops = []
        self.stats = dict.fromkeys(FIELDS, 0)


class Network:
    def __init__(self, count, path="input/network.txt"):
        with Path(path).open(encoding="ascii") as source:
            default = int(source.readline().split()[1])
            rules = [line.split() for line in source]
        self.links = {(first, second): Link(default) for first in range(1, count + 1)
                      for second in range(1, count + 1) if first != second}
        for kind, first, second, *values in rules:
            for (source, destination), link in self.links.items():
                if first != "*" and int(first) != source:
                    continue
                if second != "*" and int(second) != destination:
                    continue
                if kind == "DELAY":
                    link.delay = int(values[0])
                elif kind == "LOSS":
                    link.loss = int(values[0])
                else:
                    link.drops.append((values[0], int(values[1]), int(values[2])))
        self.groups = dict.fromkeys(range(1, count + 1), 0)
        self.total = dict.fromkeys(FIELDS, 0)
        self.by_type = {kind: dict.fromkeys(FIELDS, 0) for kind in TYPES}
        self.queue = []
        self.serial = 0

    def partition(self, groups):
        for number, group in enumerate(groups):
            for node in group:
                self.groups[node] = number

    def heal(self):
        for node in self.groups:
            self.groups[node] = 0

    def separated(self, first, second):
        return self.groups[first] != self.groups[second]

    def count(self, message, field, amount=1):
        link = self.links[message.source, message.destination]
        for statistics in (self.total, self.by_type[message.kind], link.stats):
            statistics[field] += amount

    def send(self, time, source, destination, term, kind, data):
        message = Message(kind, source, destination, term, data)
        self.serial += 1
        self.count(message, "sent")
        link = self.links[source, destination]
        if self.separated(source, destination):
            self.count(message, "partition")
            return
        if any(message_type in (kind, "ALL") and start <= time <= stop
               for message_type, start, stop in link.drops):
            self.count(message, "rule")
            return
        link.passed += 1
        if link.loss and link.passed % link.loss == 0:
            self.count(message, "loss")
            return
        self.count(message, "inflight")
        heappush(self.queue, (time + link.delay, source, self.serial, message))

    def arrivals(self, time):
        while self.queue and self.queue[0][0] == time:
            arrival, source, serial, message = heappop(self.queue)
            self.count(message, "inflight", -1)
            yield message

    def deliver(self, message, destination_up):
        if not destination_up:
            self.count(message, "down")
            return False
        if self.separated(message.source, message.destination):
            self.count(message, "partition")
            return False
        self.count(message, "delivered")
        return True
