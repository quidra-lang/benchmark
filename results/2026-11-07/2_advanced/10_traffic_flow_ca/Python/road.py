EMPTY = 0
OBSTACLE = -1
CHANGE_KINDS = ("overtaking", "return", "avoidance")


class Turn:
    def __init__(self, target, weight):
        self.target = target
        self.weight = weight
        self.vehicles = 0


class BusStop:
    def __init__(self, segment, cell, dwell):
        self.segment = segment
        self.cell = cell
        self.dwell = dwell
        self.buses = 0


class Segment:
    def __init__(self, segment_id, start, end, length, lanes, limit):
        self.id = segment_id
        self.start = start
        self.end = end
        self.length = length
        self.lanes = lanes
        self.limit = limit
        self.cells = [[EMPTY] * length for _ in range(lanes)]
        self.junction = None
        self.turns = []
        self.stop = None
        self.entered = 0
        self.vehicle_sum = 0
        self.speed_sum = 0
        self.max_vehicles = 0
        self.green_steps = 0
        self.queue_sum = 0
        self.max_queue = 0
        self.failures = 0
        self.passed = 0
        self.blocked = 0
        self.changes = dict.fromkeys(CHANGE_KINDS, 0)

    def is_empty(self, lane, cell):
        return self.cells[lane - 1][cell] == EMPTY

    def is_obstacle(self, lane, cell):
        return self.cells[lane - 1][cell] == OBSTACLE

    def put(self, lane, cell, value):
        self.cells[lane - 1][cell] = value

    def clear(self, lane, cell):
        self.cells[lane - 1][cell] = EMPTY

    def free(self, lane, cell, limit):
        row = self.cells[lane - 1]
        count = 0
        while count < limit and cell + count + 1 < self.length and row[cell + count + 1] == EMPTY:
            count += 1
        return count

    def first(self, lane):
        row = self.cells[lane - 1]
        for cell in range(self.length):
            if row[cell] != EMPTY:
                return cell
        return self.length

    def safe(self, lane, cell):
        row = self.cells[lane - 1]
        return all(row[x] == EMPTY for x in range(max(0, cell - self.limit), cell + 1))

    def vehicle_numbers(self, lane):
        return [value for value in self.cells[lane - 1] if value > 0]

    def cells_text(self, lane, vehicles):
        symbols = []
        for value in self.cells[lane - 1]:
            if value == EMPTY:
                symbols.append(".")
            elif value == OBSTACLE:
                symbols.append("#")
            else:
                symbols.append(str(vehicles[value - 1].speed))
        return "".join(symbols)


class Incident:
    def __init__(self, segment, lane, cell, start, end):
        self.segment = segment
        self.lane = lane
        self.cell = cell
        self.start = start
        self.end = end
        self.state = "planned"
        self.active_start = None
        self.active_end = None

    def update(self, step):
        event = None
        if self.state == "active" and step > self.end:
            self.state = "cleared"
            self.segment.clear(self.lane, self.cell)
            event = "INCIDENT_END"
        elif self.state == "planned" and step > self.end:
            self.state = "cancelled"
        elif self.state == "planned" and step >= self.start:
            if self.segment.is_empty(self.lane, self.cell):
                self.state = "active"
                self.segment.put(self.lane, self.cell, OBSTACLE)
                self.active_start = step
                event = "INCIDENT_START"
        if self.state == "active":
            self.active_end = step
        return event
