"""Delivery-ordered messages, serial numbers, events, and simulation parameters."""

import heapq
from pathlib import Path

import topology


class Message:
    def __init__(self, serial, sender, receiver, link, prefix, content, arrival):
        self.serial = serial
        self.sender = sender
        self.receiver = receiver
        self.link = link
        self.prefix = prefix
        self.content = content
        self.arrival = arrival

    def key(self):
        return self.arrival, self.receiver, self.sender, self.serial


class MessageQueue:
    def __init__(self):
        self.heap = []
        self.serial = 0

    def send(self, time, sender, receiver, link, prefix, content):
        self.serial += 1
        message = Message(self.serial, sender, receiver, link, prefix, content, time + link.delay)
        heapq.heappush(self.heap, (*message.key(), message))
        return message

    def next_time(self):
        return self.heap[0][0] if self.heap else None

    def take(self):
        return heapq.heappop(self.heap)[-1]

    def ordered(self):
        return [entry[-1] for entry in sorted(self.heap)]

    def remove_link(self, link):
        removed = [message for message in self.ordered() if message.link is link]
        self.heap = [entry for entry in self.heap if entry[-1].link is not link]
        heapq.heapify(self.heap)
        return removed

    def state(self, time):
        return tuple((message.arrival - time, message.receiver, message.sender,
                      message.link.number, message.prefix, message.content)
                     for message in self.ordered())


class Event:
    def __init__(self, time, text):
        self.time = time
        self.text = text
        self.fields = text.split(" ")
        self.kind = "_".join(self.fields[:2]) if self.fields[0] in ("LINK", "POLICY") else self.fields[0]


def read_events():
    events = [Event(0, "INITIAL")]
    for line in Path("input/events.txt").read_text(encoding="ascii").splitlines():
        time, text = line.split(" ", 1)
        events.append(Event(int(time), text))
    return events


def read_params():
    lines = Path("input/params.txt").read_text(encoding="ascii").splitlines()
    customer, peer, provider = map(int, lines[0].split(" ")[1:])
    defaults = {"customer": customer, "peer": peer, "provider": provider}
    stepcap = int(lines[1].split(" ")[1])
    traces = []
    for line in lines[2:]:
        _, source, address = line.split(" ")
        traces.append((int(source), address, topology.address_value(address)))
    return defaults, stepcap, traces
