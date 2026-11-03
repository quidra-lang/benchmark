"""Train plans and state, with integer braking and speed selection."""

from pathlib import Path


class Stop:
    def __init__(self, kind, fields):
        self.kind, self.section = kind, fields[0]
        self.dwell, self.scheduled_arrival, self.scheduled_departure = map(int, fields[1:])
        self.arrival, self.departure = None, None


class Train:
    def __init__(self, fields, symbol):
        self.name, self.symbol = fields[0], symbol
        self.length, self.acceleration, self.deceleration, self.max_speed = map(int, fields[1:5])
        self.entry, self.entry_time, self.entry_speed = fields[5], int(fields[6]), int(fields[7])
        self.exit, self.scheduled_exit = None, None
        self.stops, self.stop_index = [], 0
        self.state, self.direction, self.path = "WAITING", None, []
        self.head, self.speed, self.dwelling = 0, 0, False
        self.awaiting_departure, self.emergency = None, False
        self.boundary, self.boundary_coordinate = None, None
        self.entered, self.exited = None, None
        self.distance, self.maximum_speed, self.standing, self.passes = 0, 0, 0, 0

    @property
    def next_stop(self):
        return self.stops[self.stop_index] if self.stop_index < len(self.stops) else None


def read_trains():
    trains, requests = {}, []
    for line in Path("input/trains.txt").read_text(encoding="ascii").splitlines():
        kind, *fields = line.split()
        if kind == "TRAIN":
            train = Train(fields, chr(ord("a") + len(trains)))
            trains[train.name] = train
        elif kind == "REQUEST":
            requests.append((int(fields[2]), fields[0], fields[1]))
        elif kind in ("STOP", "TURN"):
            trains[fields[0]].stops.append(Stop(kind, fields[1:]))
        else:
            trains[fields[0]].exit = fields[1]
            trains[fields[0]].scheduled_exit = int(fields[2])
    return trains, requests


def braking_distance(speed, deceleration):
    count = speed // deceleration
    return count * speed - deceleration * count * (count + 1) // 2


def select_speed(train, distance):
    low = max(train.speed - train.deceleration, 0)
    if not train.emergency:
        high = min(train.speed + train.acceleration, train.max_speed)
        for speed in range(high, low - 1, -1):
            if distance is None or speed + braking_distance(speed, train.deceleration) <= distance:
                return speed
    return low
