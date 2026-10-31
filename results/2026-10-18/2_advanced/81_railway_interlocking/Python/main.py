"""Simulate railway interlocking and train movements in twelve ordered steps."""

from collections import Counter, defaultdict
from pathlib import Path
from types import SimpleNamespace

from interlocking import Interlocking
from layout import Layout
from safety import Safety
from signals import aspects
from trains import read_trains, select_speed


class Simulation:
    def __init__(self):
        self.layout = Layout()
        self.interlocking = Interlocking(self.layout)
        self.routes = self.interlocking.routes
        self.trains, requests = read_trains()
        self.planned_requests = defaultdict(list)
        for time, train, route in requests:
            self.planned_requests[time].append((train, route))
        self.events = defaultdict(list)
        for line in Path("input/events.txt").read_text(encoding="ascii").splitlines():
            time, command, *arguments = line.split()
            self.events[int(time)].append((command, arguments))
        settings = {}
        for line in Path("input/params.txt").read_text(encoding="ascii").splitlines():
            name, *values = line.split()
            settings[name] = list(map(int, values))
        self.end, self.throw_time, self.overlap_time = settings["END"][0], settings["THROW"][0], settings["OVERLAP"][0]
        self.snapshot_times = set(settings["SNAPSHOTS"])
        self.time, self.request_count, self.dropped = 0, 0, 0
        self.queue, self.log_lines, self.snapshots = [], [], []
        self.safety = Safety()

    def log(self, content):
        self.log_lines.append(f"{self.time} {content}")

    def occupied(self, name):
        section = self.layout.sections[name]
        return bool(section.occupants) or section.failed

    def start_throw(self, point, target):
        point.moving, point.target = True, target
        point.completion = self.time + self.throw_time
        self.log(f"MOVE {point.name} {target} until {point.completion}")

    def complete_throws(self):
        for point in self.layout.points.values():
            if point.moving and point.completion == self.time:
                point.position = point.target
                point.moving, point.completion = False, None
                self.log(f"POINT {point.name} {point.position}")
                point.throws += 1

    def release_approaches(self):
        for route in self.routes.values():
            if route.state == "APPROACH" and route.release_time == self.time:
                self.interlocking.release(route)
                self.log("TIMEOUT " + route.name)

    def add_request(self, name, requester):
        self.request_count += 1
        request = SimpleNamespace(number=self.request_count, route=name, time=self.time, reason=None)
        self.log(f"REQUEST q{request.number} {name} {requester}")
        self.routes[name].requests += 1
        self.queue.append(request)

    def cancel(self, name):
        removed = [request for request in self.queue if request.route == name]
        if removed:
            for request in removed:
                self.log(f"DROP q{request.number} {name}")
                self.dropped += 1
            self.queue = [request for request in self.queue if request.route != name]
            return
        route = self.routes[name]
        if route.state == "LOCKED":
            route.cancels += 1
            signal = self.layout.signals[route.start]
            if signal.aspect != "RED" and self.occupied(signal.section):
                route.state = "APPROACH"
                route.release_time = self.time + route.approach_time
                self.log(f"CANCEL {name} approach until {route.release_time}")
            else:
                self.interlocking.release(route)
                self.log(f"CANCEL {name} released")
        else:
            self.log(f"CANCEL {name} " + ("none" if route.state is None else "refused"))

    def individual_throw(self, name, target):
        point = self.layout.points[name]
        if point.locks:
            result = "locked"
        elif point.failed:
            result = "failed"
        elif point.moving:
            result = "moving"
        elif self.occupied(point.common):
            result = "occupied"
        elif point.position == target:
            result = "none"
        else:
            result = "start"
        self.log(f"THROW {name} {target} {result}")
        if result == "start":
            self.start_throw(point, target)

    def point_failure(self, command, name):
        point = self.layout.points[name]
        point.failed = command == "POINTFAIL"
        if point.failed and point.moving:
            point.completion = None
        self.log(command + " " + name)
        if not point.failed and point.moving:
            self.start_throw(point, point.target)

    def execute_events(self):
        for command, arguments in self.events[self.time]:
            if command == "REQUEST":
                self.add_request(arguments[0], "OPERATOR")
            elif command == "CANCEL":
                self.cancel(arguments[0])
            elif command == "THROW":
                self.individual_throw(*arguments)
            elif command in ("TCFAIL", "TCFIX"):
                self.layout.sections[arguments[0]].failed = command == "TCFAIL"
                self.log(command + " " + arguments[0])
            else:
                self.point_failure(command, arguments[0])

    def opposite_lock(self, names, route):
        return any(self.routes[name].direction != route.direction for name in names)

    def request_reason(self, route):
        if route.state is not None:
            return "busy"
        for name in route.conflicts:
            if self.routes[name].state in ("LOCKED", "APPROACH"):
                return "conflict " + name
        for name in route.sections:
            section = self.layout.sections[name]
            if self.occupied(name):
                return "occupied " + name
            if section.route_lock is not None or self.opposite_lock(section.overlap_locks, route):
                return "locked " + name
        for name in route.overlap:
            section = self.layout.sections[name]
            if self.occupied(name):
                return "occupied " + name
            locks = set(section.overlap_locks)
            if section.route_lock is not None:
                locks.add(section.route_lock)
            if self.opposite_lock(locks, route):
                return "locked " + name
        for name, target in route.requirements:
            point = self.layout.points[name]
            if any(position != target for _, position in point.locks):
                return "point " + name + " locked"
            if not point.moving and point.position == target or point.moving and point.target == target:
                continue
            if point.failed:
                return "point " + name + " failed"
            if point.moving:
                return "point " + name + " moving"
            if self.occupied(point.common):
                return "point " + name + " occupied"
        return None

    def judge_requests(self):
        waiting = []
        for request in self.queue:
            route = self.routes[request.route]
            reason = self.request_reason(route)
            if reason is not None:
                if reason != request.reason:
                    self.log(f"WAIT q{request.number} {route.name} {reason}")
                    request.reason = reason
                waiting.append(request)
                continue
            self.interlocking.lock(route)
            wait = self.time - request.time
            self.log(f"GRANT q{request.number} {route.name} wait {wait}")
            route.grants += 1
            route.wait += wait
            route.maxwait = max(route.maxwait, wait)
            for name, target in route.requirements:
                point = self.layout.points[name]
                if not point.moving and point.position != target:
                    self.start_throw(point, target)
        self.queue = waiting

    def decide_signals(self):
        decided = aspects(self.interlocking, self.occupied)
        for signal, aspect in decided:
            if signal.aspect != aspect:
                signal.aspect = aspect
                self.log(f"SIGNAL {signal.name} {aspect}")

    def occupied_parts(self, train):
        parts = []
        if train.state == "RUNNING":
            tail = train.head - train.length
            for name, start in train.path:
                end = start + self.layout.sections[name].length
                if start < train.head and end > tail:
                    parts.append((name, start, max(tail, start), min(train.head, end)))
        return parts

    def head_section(self, train):
        for name, start in reversed(train.path):
            if start < train.head:
                return name, start
        return train.path[0]

    def enter(self, train, entered_boundaries):
        if train.state == "EXITED":
            return False
        if train.state == "RUNNING":
            return True
        boundary = self.layout.boundaries[train.entry]
        if self.time < train.entry_time or self.occupied(boundary.section) or train.entry in entered_boundaries:
            return False
        train.state = "RUNNING"
        train.direction = "UP" if boundary.end == "L" else "DOWN"
        train.path, train.head, train.speed = [(boundary.section, 0)], 0, train.entry_speed
        train.entered = self.time
        entered_boundaries.add(train.entry)
        self.log(f"ENTER {train.name} {train.entry}")
        return True

    def reverse(self, train, stop):
        name, start = self.head_section(train)
        end = start + self.layout.sections[name].length
        occupied = self.occupied_parts(train)
        train.path = [(section, end - (origin + self.layout.sections[section].length))
                      for section, origin, _, _ in reversed(occupied)]
        train.head = end - (train.head - train.length)
        train.direction = "DOWN" if train.direction == "UP" else "UP"
        self.log(f"REVERSE {train.name} {stop.section}")

    def finish_dwell(self, train):
        if not train.dwelling:
            return True
        stop = train.next_stop
        if self.time < stop.arrival + stop.dwell or self.time < stop.scheduled_departure:
            return False
        train.dwelling, train.awaiting_departure = False, stop
        train.stop_index += 1
        if stop.kind == "TURN":
            self.reverse(train, stop)
        return True

    def limit_distance(self, train):
        if train.boundary is not None:
            return None
        name, start = self.head_section(train)
        distance = start + self.layout.sections[name].length - train.head
        while True:
            signal = self.layout.signals_at.get((name, train.direction))
            if signal is not None and signal.aspect == "RED":
                return distance
            if train.next_stop is not None and train.next_stop.section == name:
                return distance
            kind, following = self.layout.beyond(name, train.direction)
            if kind == "boundary":
                return None
            if kind in ("buffer", "impassable"):
                return distance
            distance += self.layout.sections[following].length
            name = following

    def pass_signal(self, train, signal):
        route = next((route for route in self.routes.values()
                      if route.start == signal.name and route.state in ("LOCKED", "APPROACH")), None)
        route_name = route.name if route is not None else "-"
        self.log(f"PASS {train.name} {signal.name} {signal.aspect} {route_name}")
        signal.passes += 1
        train.passes += 1
        if route is not None:
            route.state = "USED"
            route.uses += 1
        if signal.aspect == "RED":
            self.log(f"SPAD {train.name} {signal.name}")
            self.safety.check(self.time, "SIGNAL_PASSING", train.name + " " + signal.name)
            train.emergency = True
        else:
            self.safety.check(self.time, "SIGNAL_PASSING")

    def move(self, train, distance):
        name, start = self.head_section(train)
        remaining = distance
        while remaining > 0:
            if train.boundary is not None:
                train.head += remaining
                break
            end = start + self.layout.sections[name].length
            if train.head + remaining <= end:
                train.head += remaining
                break
            remaining -= end - train.head
            train.head = end
            signal = self.layout.signals_at.get((name, train.direction))
            if signal is not None:
                self.pass_signal(train, signal)
            stop = train.awaiting_departure
            if stop is not None and stop.section == name:
                self.log(f"DEPART {train.name} {name}")
                stop.departure = self.time
                train.awaiting_departure = None
            kind, following = self.layout.beyond(name, train.direction)
            if kind == "boundary":
                train.boundary, train.boundary_coordinate = following, end
            else:
                name, start = following, end
                train.path.append((name, start))

    def after_movement(self, train, speed, previous_speed):
        train.speed = speed
        train.distance += speed
        train.maximum_speed = max(train.maximum_speed, speed)
        if speed == 0:
            train.emergency = False
        name, start = self.head_section(train)
        stop = train.next_stop
        arrived = (stop is not None and speed == 0 and name == stop.section
                   and train.head == start + self.layout.sections[name].length)
        if arrived:
            train.dwelling, stop.arrival = True, self.time
            self.log(f"ARRIVE {train.name} {name}")
        if speed == 0 and not arrived:
            train.standing += 1
            if previous_speed > 0:
                self.log(f"HOLD {train.name} {name}")
        if train.boundary is not None and train.head - train.length >= train.boundary_coordinate:
            train.state, train.exited = "EXITED", self.time
            self.log(f"EXIT {train.name} {train.boundary}")

    def run_trains(self):
        entered_boundaries = set()
        for train in self.trains.values():
            if not self.enter(train, entered_boundaries):
                continue
            if not self.finish_dwell(train):
                continue
            distance = self.limit_distance(train)
            previous_speed = train.speed
            speed = select_speed(train, distance)
            self.move(train, speed)
            self.after_movement(train, speed, previous_speed)

    def recompute_occupancy(self):
        for section in self.layout.sections.values():
            section.occupants = []
        for train in self.trains.values():
            for name, _, _, _ in self.occupied_parts(train):
                if train.name not in self.layout.sections[name].occupants:
                    self.layout.sections[name].occupants.append(train.name)

    def sectional_release(self):
        for route in self.routes.values():
            if route.state != "USED":
                continue
            remaining = [name for name in route.sections if self.layout.sections[name].route_lock == route.name]
            for name in remaining:
                if self.occupied(name):
                    route.passed.add(name)
            for name in remaining:
                if name not in route.passed or self.occupied(name):
                    break
                self.interlocking.unlock_section(route, name)
                self.log(f"RELEASE {route.name} {name}")
            if not any(self.layout.sections[name].route_lock == route.name for name in route.sections):
                self.interlocking.release(route)
                self.log("DONE " + route.name)
            elif route.overlap and route.overlap_locked:
                route.overlap_counter = route.overlap_counter + 1 if self.occupied(route.sections[-1]) else 0
                if route.overlap_counter >= self.overlap_time:
                    self.interlocking.unlock_overlap(route)
                    self.log("OVERLAP " + route.name)

    def record_statistics(self):
        for route in self.routes.values():
            route.locked_seconds += route.state is not None
        for point in self.layout.points.values():
            point.locked_seconds += bool(point.locks)
            point.moving_seconds += point.moving
        for section in self.layout.sections.values():
            section.occupied_seconds += self.occupied(section.name)
            section.locked_seconds += section.route_lock is not None or bool(section.overlap_locks)
            section.trains.update(section.occupants)
        for signal in self.layout.signals.values():
            signal.seconds[signal.aspect] += 1

    def diagram(self):
        sections = list(self.layout.sections.values())
        symbols = list(self.layout.points.values()) + list(self.layout.signals.values()) + list(self.layout.buffers.values())
        rows = [section.row for section in sections] + [item.row for item in symbols]
        columns = [section.last for section in sections] + [item.column for item in symbols]
        rows.extend(row for row, _, _ in self.layout.labels)
        columns.extend(column + len(text) - 1 for _, column, text in self.layout.labels)
        grid = [[" "] * (max(columns) + 1) for _ in range(max(rows) + 1)]
        for row, column, text in self.layout.labels:
            for offset, character in enumerate(text):
                grid[row][column + offset] = character
        for section in sections:
            character = "#" if section.failed else "=" if section.route_lock is not None else "~" if section.overlap_locks else "-"
            for column in range(section.first, section.last + 1):
                grid[section.row][column] = character
        for train in self.trains.values():
            for name, start, low, high in self.occupied_parts(train):
                section = self.layout.sections[name]
                length, cells = section.length, section.last - section.first + 1
                if train.direction == "UP":
                    left, right = low - start, high - start
                else:
                    left, right = length - (high - start), length - (low - start)
                for cell in range(cells):
                    if left * cells < (cell + 1) * length and right * cells > cell * length:
                        column = section.first + cell
                        previous = grid[section.row][column]
                        grid[section.row][column] = "*" if "a" <= previous <= "z" or previous == "*" else train.symbol
        for buffer in self.layout.buffers.values():
            grid[buffer.row][buffer.column] = "|"
        for point in self.layout.points.values():
            grid[point.row][point.column] = point.position if point.detected else "?"
        for signal in self.layout.signals.values():
            grid[signal.row][signal.column] = {"RED": "X", "YELLOW": "Y", "GREEN": "G"}[signal.aspect]
        return ["".join(row).rstrip(" ") for row in grid]

    def snapshot(self):
        lines = ["SNAPSHOT " + str(self.time)]
        lines.extend(self.diagram())
        for train in self.trains.values():
            if train.state == "RUNNING":
                sections = ",".join(name for name, _, _, _ in self.occupied_parts(train))
                lines.append(f"TRAIN {train.symbol} {train.name} {train.direction} {train.speed} {sections}")
        routes = [route.name + "/" + route.state for route in self.routes.values() if route.state is not None]
        lines.append("ROUTES " + (" ".join(routes) if routes else "-"))
        return lines

    def train_rows(self):
        rows = []
        for train in self.trains.values():
            rows.append((train.name, "enter:" + train.entry, train.entry_time, train.entered))
            for stop in train.stops:
                rows.append((train.name, "arr:" + stop.section, stop.scheduled_arrival, stop.arrival))
                rows.append((train.name, "dep:" + stop.section, stop.scheduled_departure, stop.departure))
            rows.append((train.name, "exit:" + train.exit, train.scheduled_exit, train.exited))
        return rows

    def train_report(self, rows):
        lines = ["train,location,scheduled,actual,delay"]
        for name, location, scheduled, actual in rows:
            timing = "-,-" if actual is None else f"{actual},{actual - scheduled}"
            lines.append(f"{name},{location},{scheduled},{timing}")
        return lines

    def punctuality(self, rows):
        on_time, late, missing, total_delay, maximum = 0, 0, 0, 0, 0
        for _, _, scheduled, actual in rows:
            if actual is None:
                missing += 1
                continue
            delay = actual - scheduled
            if delay <= 0:
                on_time += 1
            else:
                late += 1
                total_delay += delay
                maximum = max(maximum, delay)
        return (f"PUNCTUALITY on_time {on_time} late {late} missing {missing} "
                f"total_delay {total_delay} max_delay {maximum}")

    def summary(self, rows):
        lines = []
        for route in self.routes.values():
            lines.append(f"ROUTE {route.name} {route.start}-{route.finish} requests {route.requests} "
                         f"grants {route.grants} uses {route.uses} cancels {route.cancels} wait {route.wait} "
                         f"maxwait {route.maxwait} locked {route.locked_seconds}")
        for point in self.layout.points.values():
            final = point.position if point.detected else "?"
            lines.append(f"POINT {point.name} throws {point.throws} locked {point.locked_seconds} "
                         f"moving {point.moving_seconds} final {final}")
        for section in self.layout.sections.values():
            lines.append(f"SECTION {section.name} occupied {section.occupied_seconds} "
                         f"locked {section.locked_seconds} trains {len(section.trains)}")
        for signal in self.layout.signals.values():
            lines.append(f"SIGNAL {signal.name} red {signal.seconds['RED']} yellow {signal.seconds['YELLOW']} "
                         f"green {signal.seconds['GREEN']} passes {signal.passes}")
        for train in self.trains.values():
            lines.append(f"TRAIN {train.name} {train.symbol} {train.state} distance {train.distance} "
                         f"maxspeed {train.maximum_speed} standing {train.standing} passes {train.passes}")
        states = Counter(train.state for train in self.trains.values())
        lines.append(f"TRAINS total {len(self.trains)} exited {states['EXITED']} "
                     f"running {states['RUNNING']} waiting {states['WAITING']}")
        lines.append(self.punctuality(rows))
        grants = sum(route.grants for route in self.routes.values())
        lines.append(f"REQUESTS total {self.request_count} granted {grants} dropped {self.dropped} pending {len(self.queue)}")
        return lines

    def write_reports(self):
        rows = self.train_rows()
        reports = [("events.txt", self.log_lines), ("snapshots.txt", self.snapshots),
                   ("train_log.csv", self.train_report(rows)), ("safety.txt", self.safety.report()),
                   ("summary.txt", self.summary(rows))]
        Path("output").mkdir(exist_ok=True)
        for name, lines in reports:
            with open("output/" + name, "w", encoding="ascii", newline="\n") as destination:
                for line in lines:
                    destination.write(line + "\n")

    def run(self):
        for time in range(self.end + 1):
            self.time = time
            self.complete_throws()
            self.release_approaches()
            for train, route in self.planned_requests[time]:
                self.add_request(route, train)
            self.execute_events()
            self.judge_requests()
            self.decide_signals()
            self.run_trains()
            self.recompute_occupancy()
            self.sectional_release()
            self.safety.inspect(time, self.layout, self.routes)
            self.record_statistics()
            if time in self.snapshot_times:
                self.snapshots.extend(self.snapshot())
        self.write_reports()


def main():
    Simulation().run()


if __name__ == "__main__":
    main()
