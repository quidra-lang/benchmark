class VehicleClass:
    def __init__(self, name, vmax, weight, overtakes, stops):
        self.name = name
        self.vmax = vmax
        self.weight = weight
        self.overtakes = overtakes
        self.stops = stops


class Vehicle:
    def __init__(self, number, vehicle_class, source, arrival):
        self.number = number
        self.vehicle_class = vehicle_class
        self.source = source
        self.arrival = arrival
        self.inserted = None
        self.exited = None
        self.sink = None
        self.segment = None
        self.lane = 0
        self.cell = 0
        self.speed = 0
        self.turn = None
        self.route = []
        self.steps = 0
        self.distance = 0
        self.stopped_steps = 0
        self.stop_count = 0
        self.lane_changes = 0
        self.dwell = 0
        self.completed_stops = set()

    def max_speed(self):
        return min(self.vehicle_class.vmax, self.segment.limit)

    def place(self, segment, lane, cell):
        if self.segment is not None:
            self.segment.clear(self.lane, self.cell)
        segment.put(lane, cell, self.number)
        self.segment = segment
        self.lane = lane
        self.cell = cell

    def leave(self):
        self.segment.clear(self.lane, self.cell)
        self.segment = None

    def heading_for_stop(self):
        if self.segment is None or not self.vehicle_class.stops:
            return False
        stop = self.segment.stop
        if stop is None or self.segment.id in self.completed_stops:
            return False
        return self.cell <= stop.cell

    def travel_time(self):
        return self.exited - self.inserted + 1


def random_slowdown(speed, previous, value, dawdle, dawdle_stopped):
    probability = dawdle_stopped if previous == 0 else dawdle
    if speed > 0 and value % 1000 < probability:
        return speed - 1
    return speed
