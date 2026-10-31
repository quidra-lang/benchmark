from collections import defaultdict
from fractions import Fraction
from pathlib import Path


MONTH_DAYS = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)


class Event:
    def __init__(self, line, case_id, activity, timestamp, resource, time):
        self.line = line
        self.case_id = case_id
        self.activity = activity
        self.timestamp = timestamp
        self.resource = resource
        self.time = time


class Case:
    def __init__(self, identifier, events):
        self.identifier = identifier
        self.events = sorted(events, key=lambda event: (event.time, event.line))
        self.trace = tuple(event.activity for event in self.events)
        self.duration = self.events[-1].time - self.events[0].time


def read_inputs():
    lines = Path("input/eventlog.csv").read_text(encoding="ascii").splitlines()
    rows = [(number, *line.split(",")) for number, line in enumerate(lines[1:], 2)]
    parameters = {}
    for line in Path("input/params.txt").read_text(encoding="ascii").splitlines():
        name, value = line.split(" ")
        parameters[name] = value
    return rows, parameters


def timestamp_minutes(timestamp):
    month = int(timestamp[5:7])
    day = int(timestamp[8:10])
    hour = int(timestamp[11:13])
    minute = int(timestamp[14:16])
    if not 1 <= month <= 12:
        return None
    if not 1 <= day <= MONTH_DAYS[month - 1]:
        return None
    if not 0 <= hour <= 23 or not 0 <= minute <= 59:
        return None
    return ((sum(MONTH_DAYS[:month - 1]) + day - 1) * 24 + hour) * 60 + minute


def group_cases(events):
    grouped = defaultdict(list)
    for event in events:
        grouped[event.case_id].append(event)
    return [Case(identifier, grouped[identifier]) for identifier in sorted(grouped)]


def median(values):
    values = sorted(values)
    middle = len(values) // 2
    if len(values) % 2:
        return Fraction(values[middle])
    return Fraction(values[middle - 1] + values[middle], 2)
