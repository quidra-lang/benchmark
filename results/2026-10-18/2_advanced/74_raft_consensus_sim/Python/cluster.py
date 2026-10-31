"""Cluster settings, script controls, and mutable client request state."""

from collections import namedtuple
from pathlib import Path


Control = namedtuple("Control", "time kind arguments")


class Settings:
    def __init__(self, values):
        self.nodes = values["NODES"][0]
        self.election_min, self.election_max = values["ELECTION"]
        self.heartbeat = values["HEARTBEAT"][0]
        self.batch = values["BATCH"][0]
        self.quorum = values["QUORUM"][0]
        self.seed = values["SEED"][0]
        self.end = values["END"][0]
        self.retry = values["RETRY"][0]
        self.attempts = values["ATTEMPTS"][0]
        self.sample = values["SAMPLE"][0]


class Request:
    def __init__(self, number, time, destination, command):
        self.number = number
        self.time = time
        self.initial_destination = destination
        self.command = command
        self.scheduled = time
        self.destination = destination
        self.attempts = 0
        self.redirects = 0
        self.accepted = None
        self.abandoned = False
        self.status = None
        self.latency = None
        self.result = None


def read_settings(path="input/cluster.txt"):
    values = {}
    with Path(path).open(encoding="ascii") as source:
        for line in source:
            key, *numbers = line.split()
            values[key] = tuple(map(int, numbers))
    return Settings(values)


def read_script(path="input/script.txt"):
    controls = []
    requests = []
    with Path(path).open(encoding="ascii") as source:
        for line in source:
            time, kind, *arguments = line.split()
            time = int(time)
            if kind == "REQUEST":
                destination = int(arguments[0])
                operation, key = arguments[1:3]
                command = (operation, key)
                if operation in ("SET", "ADD"):
                    command += (int(arguments[3]),)
                requests.append(Request(len(requests) + 1, time, destination, command))
            else:
                if kind == "PARTITION":
                    arguments = [tuple(map(int, group.split(","))) for group in arguments]
                else:
                    arguments = list(map(int, arguments))
                controls.append(Control(time, kind, arguments))
    return controls, requests
