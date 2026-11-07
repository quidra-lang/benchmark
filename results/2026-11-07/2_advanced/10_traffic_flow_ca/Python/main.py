import os
from collections import deque
from fractions import Fraction

from minstd import Minstd, select
from road import CHANGE_KINDS, BusStop, Incident, Segment, Turn
from signals import Junction
from stats import dec, frac, histogram_lines, percentile
from vehicles import Vehicle, VehicleClass, random_slowdown


INPUT_DIR = "input"
OUTPUT_DIR = "output"
INPUT_FILES = ("network.txt", "demand.txt", "params.txt")


def time_text(step):
    return f"{step:04d}"


def flag_text(value):
    return "Y" if value else "N"


def optional_text(value):
    return "-" if value is None else str(value)


def share_text(share):
    return frac(share.numerator, share.denominator)


def read_lines(name):
    with open(os.path.join(INPUT_DIR, name)) as handle:
        return handle.read().splitlines()


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w") as handle:
        handle.write("".join(line + "\n" for line in lines))


class Source:
    def __init__(self, node, rates, segment):
        self.node = node
        self.rates = rates
        self.segment = segment
        self.queue = deque()
        self.queue_start = 0
        self.queue_max = 0

    def rate(self, step):
        for rate, end in self.rates:
            if step <= end:
                return rate
        return 0


class Detector:
    def __init__(self, name, segment, cell, width):
        self.name = name
        self.segment = segment
        self.cell = cell
        self.width = width

    def covers(self, cell):
        return self.cell <= cell < self.cell + self.width


class Diagram:
    def __init__(self, segment, lane, start, end):
        self.segment = segment
        self.lane = lane
        self.start = start
        self.end = end
        self.lines = []


class Ring:
    def __init__(self, number, values):
        self.number = number
        self.length, self.vmax, self.warmup, self.measure, self.seed = values[:5]
        self.counts = values[5:]


class Interval:
    def __init__(self, detector_count):
        self.arrivals = 0
        self.insertions = 0
        self.exits = 0
        self.vehicle_steps = 0
        self.speed_sum = 0
        self.passing = [0] * detector_count
        self.occupancy = [0] * detector_count
        self.occupancy_speed = [0] * detector_count


class Move:
    def __init__(self, vehicle):
        self.vehicle = vehicle
        self.segment = vehicle.segment
        self.cell = vehicle.cell
        self.speed = 0


def run_ring(ring, count, dawdle, dawdle_stopped):
    rng = Minstd(ring.seed)
    positions = [index * ring.length // count for index in range(count)]
    speeds = [0] * count
    total = 0
    for step in range(1, ring.warmup + ring.measure + 1):
        order = sorted(range(count), key=lambda index: positions[index], reverse=True)
        new_speeds = [0] * count
        for rank, index in enumerate(order):
            ahead = order[rank - 1] if rank > 0 else order[count - 1]
            gap = (positions[ahead] - positions[index] - 1) % ring.length
            speed = min(speeds[index] + 1, ring.vmax, gap)
            new_speeds[index] = random_slowdown(
                speed, speeds[index], rng.draw(), dawdle, dawdle_stopped
            )
        for index in range(count):
            positions[index] = (positions[index] + new_speeds[index]) % ring.length
        speeds = new_speeds
        if step > ring.warmup:
            total += sum(new_speeds)
    return total


class Simulation:
    def __init__(self):
        self.segments = []
        self.segment_by_id = {}
        self.junctions = []
        self.incidents = []
        self.stops = []
        self.classes = []
        self.sources = []
        self.sinks = []
        self.seed = 1
        self.steps = 0
        self.dawdle = 0
        self.dawdle_stopped = 0
        self.interval_length = 1
        self.bin_width = 1
        self.detectors = []
        self.diagrams = []
        self.track_numbers = []
        self.rings = []
        self.rng = None
        self.vehicles = []
        self.intervals = []
        self.events = []
        self.tracks = {}

    def add_segment(self, fields):
        segment_id, start, end, length, lanes, limit = fields
        segment = Segment(segment_id, start, end, int(length), int(lanes), int(limit))
        self.segments.append(segment)
        self.segment_by_id[segment_id] = segment

    def add_junction(self, fields):
        node, offset, *phases = fields
        junction = Junction(node, int(offset), phases)
        for segment in self.segments:
            if segment.end == node:
                segment.junction = junction
                junction.incoming.append(segment)
        self.junctions.append(junction)

    def add_incident(self, fields):
        segment_id, lane, cell, start, end = fields
        self.incidents.append(Incident(
            self.segment_by_id[segment_id], int(lane), int(cell), int(start), int(end)
        ))

    def add_stop(self, fields):
        segment_id, cell, dwell = fields
        segment = self.segment_by_id[segment_id]
        segment.stop = BusStop(segment, int(cell), int(dwell))
        self.stops.append(segment.stop)

    def add_class(self, fields):
        name, vmax, weight, overtake, stop = fields
        self.classes.append(
            VehicleClass(name, int(vmax), int(weight), overtake == "Y", stop == "Y")
        )

    def add_source(self, fields):
        node, *periods = fields
        rates = []
        for period in periods:
            rate, end = period.split(":")
            rates.append((int(rate), int(end)))
        entry = next(segment for segment in self.segments if segment.start == node)
        self.sources.append(Source(node, rates, entry))

    def add_sink(self, fields):
        self.sinks.append(fields[0])

    def add_turn(self, fields):
        from_id, to_id, weight = fields
        turn = Turn(self.segment_by_id[to_id], int(weight))
        self.segment_by_id[from_id].turns.append(turn)

    def set_seed(self, fields):
        self.seed = int(fields[0])

    def set_steps(self, fields):
        self.steps = int(fields[0])

    def set_dawdle(self, fields):
        self.dawdle = int(fields[0])
        self.dawdle_stopped = int(fields[1])

    def set_interval(self, fields):
        self.interval_length = int(fields[0])

    def set_bin(self, fields):
        self.bin_width = int(fields[0])

    def add_detector(self, fields):
        name, segment_id, cell, width = fields
        self.detectors.append(
            Detector(name, self.segment_by_id[segment_id], int(cell), int(width))
        )

    def add_diagram(self, fields):
        segment_id, lane, start, end = fields
        self.diagrams.append(
            Diagram(self.segment_by_id[segment_id], int(lane), int(start), int(end))
        )

    def set_track(self, fields):
        self.track_numbers = [int(value) for value in fields]
        self.tracks = {number: [] for number in self.track_numbers}

    def add_ring(self, fields):
        self.rings.append(Ring(len(self.rings) + 1, [int(value) for value in fields]))

    def load(self, files):
        handlers = {
            "SEGMENT": self.add_segment,
            "JUNCTION": self.add_junction,
            "INCIDENT": self.add_incident,
            "STOP": self.add_stop,
            "CLASS": self.add_class,
            "SOURCE": self.add_source,
            "SINK": self.add_sink,
            "TURN": self.add_turn,
            "seed": self.set_seed,
            "steps": self.set_steps,
            "dawdle": self.set_dawdle,
            "interval": self.set_interval,
            "bin": self.set_bin,
            "detector": self.add_detector,
            "diagram": self.add_diagram,
            "track": self.set_track,
            "ring": self.add_ring,
        }
        for lines in files:
            for line in lines:
                kind, *fields = line.split()
                handlers[kind](fields)

    def record(self, step, text):
        self.events.append(f"{time_text(step)} {text}")

    def green(self, segment, step):
        return segment.junction.green(segment.id, step)

    def vehicles_on(self, segment):
        return [
            self.vehicles[number - 1]
            for lane in range(1, segment.lanes + 1)
            for number in segment.vehicle_numbers(lane)
        ]

    def enter(self, vehicle, segment):
        vehicle.route.append(segment.id)
        segment.entered += 1
        if segment.junction is not None:
            weights = [turn.weight for turn in segment.turns]
            vehicle.turn = segment.turns[select(weights, self.rng.draw())]

    def update_incidents(self, step):
        for incident in self.incidents:
            event = incident.update(step)
            if event is not None:
                self.record(
                    step,
                    f"{event} {incident.segment.id} lane {incident.lane} cell {incident.cell}",
                )

    def arrive(self, step):
        interval = self.intervals[-1]
        weights = [vehicle_class.weight for vehicle_class in self.classes]
        for source in self.sources:
            if self.rng.draw() % 1000 < source.rate(step):
                vehicle_class = self.classes[select(weights, self.rng.draw())]
                vehicle = Vehicle(len(self.vehicles) + 1, vehicle_class, source.node, step)
                self.vehicles.append(vehicle)
                source.queue.append(vehicle)
                interval.arrivals += 1

    def entry_lane(self, segment):
        best_lane = None
        best_first = -1
        for lane in range(1, segment.lanes + 1):
            if segment.is_empty(lane, 0) and segment.first(lane) > best_first:
                best_lane = lane
                best_first = segment.first(lane)
        return best_lane

    def insert(self, step):
        interval = self.intervals[-1]
        for source in self.sources:
            segment = source.segment
            while source.queue:
                lane = self.entry_lane(segment)
                if lane is None:
                    break
                vehicle = source.queue.popleft()
                vehicle.place(segment, lane, 0)
                vehicle.inserted = step
                self.enter(vehicle, segment)
                interval.insertions += 1
            if source.queue and source.queue_start == 0:
                source.queue_start = step
                source.queue_max = 0
            if source.queue_start != 0:
                source.queue_max = max(source.queue_max, len(source.queue))
                if not source.queue:
                    self.record(
                        step,
                        f"QUEUE {source.node} from {source.queue_start} max {source.queue_max}",
                    )
                    source.queue_start = 0

    def desired_lane(self, vehicle):
        segment = vehicle.segment
        lane = vehicle.lane
        cell = vehicle.cell
        top = vehicle.max_speed()
        here = segment.free(lane, cell, top + 1)
        want = min(vehicle.speed + 1, top)
        ahead = cell + here + 1
        if here < top + 1 and ahead < segment.length and segment.is_obstacle(lane, ahead):
            for target in (lane + 1, lane - 1):
                if not 1 <= target <= segment.lanes:
                    continue
                if segment.free(target, cell, top + 1) > here and segment.safe(target, cell):
                    return target, "avoidance"
        if vehicle.heading_for_stop():
            if lane >= 2 and segment.safe(lane - 1, cell):
                return lane - 1, "return"
            return lane, None
        if (
            vehicle.vehicle_class.overtakes
            and lane + 1 <= segment.lanes
            and here < want
            and segment.free(lane + 1, cell, top + 1) > here
            and segment.safe(lane + 1, cell)
        ):
            return lane + 1, "overtaking"
        if (
            lane >= 2
            and segment.free(lane - 1, cell, top + 1) > want
            and segment.safe(lane - 1, cell)
        ):
            return lane - 1, "return"
        return lane, None

    def change_lanes(self):
        changes = []
        for segment in self.segments:
            if segment.lanes < 2:
                continue
            reserved = set()
            for lane in range(1, segment.lanes + 1):
                for number in segment.vehicle_numbers(lane):
                    vehicle = self.vehicles[number - 1]
                    if vehicle.dwell > 0:
                        continue
                    target, kind = self.desired_lane(vehicle)
                    if target != lane and (target, vehicle.cell) not in reserved:
                        reserved.add((target, vehicle.cell))
                        changes.append((vehicle, target, kind))
        for vehicle, target, kind in changes:
            segment = vehicle.segment
            vehicle.place(segment, target, vehicle.cell)
            vehicle.lane_changes += 1
            segment.changes[kind] += 1

    def processing_order(self):
        moves = []
        for segment in self.segments:
            for lane in range(1, segment.lanes + 1):
                for number in reversed(segment.vehicle_numbers(lane)):
                    moves.append(Move(self.vehicles[number - 1]))
        return moves

    def determine_speed(self, vehicle, step):
        segment = vehicle.segment
        lane = vehicle.lane
        cell = vehicle.cell
        accelerated = min(vehicle.speed + 1, vehicle.max_speed())
        gap = segment.free(lane, cell, accelerated)
        if gap < accelerated and cell + gap == segment.length - 1:
            if segment.junction is None:
                gap = accelerated
            elif self.green(segment, step):
                target = vehicle.turn.target
                gap += target.free(min(lane, target.lanes), -1, accelerated - gap)
        if vehicle.heading_for_stop():
            gap = min(gap, segment.stop.cell - cell)
        speed = min(accelerated, gap)
        speed = random_slowdown(
            speed, vehicle.speed, self.rng.draw(), self.dawdle, self.dawdle_stopped
        )
        if vehicle.dwell > 0:
            speed = 0
            vehicle.dwell -= 1
        return speed

    def move_vehicles(self, moves, step):
        interval = self.intervals[-1]
        passing = []
        for move in moves:
            vehicle = move.vehicle
            segment = move.segment
            if move.cell + move.speed < segment.length:
                vehicle.place(segment, vehicle.lane, move.cell + move.speed)
            elif segment.junction is None:
                vehicle.leave()
                vehicle.exited = step
                vehicle.sink = segment.end
                interval.exits += 1
            else:
                passing.append(move)
        return passing

    def pass_junctions(self, passing):
        for move in passing:
            vehicle = move.vehicle
            segment = move.segment
            target = vehicle.turn.target
            lane = min(vehicle.lane, target.lanes)
            overshoot = move.cell + move.speed - segment.length
            cell = min(overshoot, target.first(lane) - 1)
            if cell < overshoot:
                segment.blocked += 1
            if cell >= 0:
                vehicle.place(target, lane, cell)
                move.speed = segment.length - move.cell + cell
                segment.passed += 1
                vehicle.turn.vehicles += 1
                self.enter(vehicle, target)
            else:
                vehicle.place(segment, vehicle.lane, segment.length - 1)
                move.speed = segment.length - 1 - move.cell

    def track_line(self, vehicle, step):
        if vehicle.segment is None:
            return f"{time_text(step)} EXIT {vehicle.speed}"
        return (
            f"{time_text(step)} {vehicle.segment.id} {vehicle.lane} "
            f"{vehicle.cell} {vehicle.speed}"
        )

    def aggregate_vehicle(self, move, step):
        vehicle = move.vehicle
        interval = self.intervals[-1]
        speed = move.speed
        vehicle.steps += 1
        vehicle.distance += speed
        if speed == 0:
            vehicle.stopped_steps += 1
            if vehicle.speed > 0:
                vehicle.stop_count += 1
        vehicle.speed = speed
        interval.vehicle_steps += 1
        interval.speed_sum += speed
        if vehicle.heading_for_stop() and vehicle.lane == 1:
            stop = vehicle.segment.stop
            if vehicle.cell == stop.cell:
                vehicle.completed_stops.add(vehicle.segment.id)
                vehicle.dwell = stop.dwell
                stop.buses += 1
                self.record(
                    step, f"BUS_STOP {vehicle.number} {vehicle.segment.id} cell {stop.cell}"
                )
        if vehicle.number in self.tracks:
            self.tracks[vehicle.number].append(self.track_line(vehicle, step))
        for index, detector in enumerate(self.detectors):
            if move.segment is not detector.segment or move.cell >= detector.cell:
                continue
            if vehicle.segment is not detector.segment or vehicle.cell >= detector.cell:
                interval.passing[index] += 1

    def signal_text(self, segment, step):
        if segment.junction is None:
            return "E"
        return "G" if self.green(segment, step) else "R"

    def aggregate_state(self, step):
        interval = self.intervals[-1]
        for index, detector in enumerate(self.detectors):
            for vehicle in self.vehicles_on(detector.segment):
                if detector.covers(vehicle.cell):
                    interval.occupancy[index] += 1
                    interval.occupancy_speed[index] += vehicle.speed
        for segment in self.segments:
            present = self.vehicles_on(segment)
            segment.vehicle_sum += len(present)
            segment.speed_sum += sum(vehicle.speed for vehicle in present)
            segment.max_vehicles = max(segment.max_vehicles, len(present))
            if segment.junction is None:
                continue
            green = self.green(segment, step)
            if green:
                segment.green_steps += 1
            queued = sum(1 for vehicle in present if vehicle.speed == 0)
            segment.queue_sum += queued
            segment.max_queue = max(segment.max_queue, queued)
            if step < self.steps and queued > 0 and green and not self.green(segment, step + 1):
                segment.failures += 1
        for diagram in self.diagrams:
            if diagram.start <= step <= diagram.end:
                segment = diagram.segment
                diagram.lines.append(
                    f"{time_text(step)} {segment.cells_text(diagram.lane, self.vehicles)} "
                    f"{self.signal_text(segment, step)}"
                )

    def run(self):
        self.rng = Minstd(self.seed)
        for step in range(1, self.steps + 1):
            self.update_incidents(step)
            if (step - 1) % self.interval_length == 0:
                self.intervals.append(Interval(len(self.detectors)))
            self.arrive(step)
            self.insert(step)
            self.change_lanes()
            moves = self.processing_order()
            for move in moves:
                move.speed = self.determine_speed(move.vehicle, step)
            passing = self.move_vehicles(moves, step)
            self.pass_junctions(passing)
            for move in moves:
                self.aggregate_vehicle(move, step)
            self.aggregate_state(step)
        for source in self.sources:
            if source.queue_start != 0:
                self.record(
                    self.steps,
                    f"QUEUE {source.node} from {source.queue_start} "
                    f"max {source.queue_max} open",
                )

    def enumerate_routes(self, segment):
        if segment.junction is None:
            return [((segment.id,), Fraction(1))]
        total = sum(turn.weight for turn in segment.turns)
        routes = []
        for turn in segment.turns:
            for route, share in self.enumerate_routes(turn.target):
                routes.append(((segment.id,) + route, share * turn.weight / total))
        return routes

    def spacetime_lines(self):
        lines = []
        for diagram in self.diagrams:
            lines.append(
                f"DIAGRAM {diagram.segment.id} lane {diagram.lane} "
                f"steps {diagram.start}-{diagram.end}"
            )
            lines.extend(diagram.lines)
        return lines

    def detector_lines(self):
        lines = ["detector,interval,flow,density,speed"]
        for index, detector in enumerate(self.detectors):
            capacity = self.interval_length * detector.width * detector.segment.lanes
            for number, interval in enumerate(self.intervals, 1):
                occupancy = interval.occupancy[index]
                lines.append(
                    f"{detector.name},{number},{interval.passing[index]},"
                    f"{dec(occupancy, capacity, 4)},"
                    f"{dec(interval.occupancy_speed[index], occupancy, 2)}"
                )
        return lines

    def travel_block(self, heading, vehicles):
        times = sorted(vehicle.travel_time() for vehicle in vehicles)
        if not times:
            return [f"{heading} exited 0"]
        lines = [
            f"{heading} exited {len(times)} min {times[0]} p50 {percentile(times, 50)} "
            f"p90 {percentile(times, 90)} max {times[-1]} "
            f"mean {dec(sum(times), len(times), 2)}"
        ]
        lines.extend(histogram_lines(times, self.bin_width))
        return lines

    def outcome_text(self, vehicles, exited_count):
        count = len(vehicles)
        total = sum(vehicle.travel_time() for vehicle in vehicles)
        return (
            f"vehicles {count} share {frac(count, exited_count)} "
            f"mean {dec(total, count, 2)}"
        )

    def source_lines(self, source, exited):
        group = [vehicle for vehicle in exited if vehicle.source == source.node]
        lines = [f"SOURCE {source.node} exited {len(group)}"]
        routes = self.enumerate_routes(source.segment)
        for route, share in routes:
            matched = [vehicle for vehicle in group if tuple(vehicle.route) == route]
            lines.append(
                f"  ROUTE {','.join(route)} expected {share_text(share)} "
                + self.outcome_text(matched, len(group))
            )
        for sink in self.sinks:
            shares = [
                share for route, share in routes
                if self.segment_by_id[route[-1]].end == sink
            ]
            if not shares:
                continue
            matched = [vehicle for vehicle in group if vehicle.sink == sink]
            lines.append(
                f"  SINK {sink} expected {share_text(sum(shares))} "
                + self.outcome_text(matched, len(group))
            )
        return lines

    def travel_time_lines(self):
        exited = [vehicle for vehicle in self.vehicles if vehicle.exited is not None]
        lines = []
        for vehicle_class in self.classes:
            lines.extend(self.travel_block(
                "CLASS " + vehicle_class.name,
                [vehicle for vehicle in exited if vehicle.vehicle_class is vehicle_class],
            ))
        lines.extend(self.travel_block("ALL", exited))
        for source in self.sources:
            lines.extend(self.source_lines(source, exited))
        return lines

    def class_block(self, heading, vehicles):
        inserted = sum(1 for vehicle in vehicles if vehicle.inserted is not None)
        exited = [vehicle for vehicle in vehicles if vehicle.exited is not None]
        count = len(exited)
        steps = sum(vehicle.steps for vehicle in vehicles)
        distance = sum(vehicle.distance for vehicle in vehicles)
        travel = sum(vehicle.travel_time() for vehicle in exited)
        delay = sum(vehicle.inserted - vehicle.arrival for vehicle in exited)
        stopped = sum(vehicle.stopped_steps for vehicle in exited)
        stops = sum(vehicle.stop_count for vehicle in exited)
        changes = sum(vehicle.lane_changes for vehicle in exited)
        return [
            heading,
            f"  generated {len(vehicles)} inserted {inserted} exited {count} "
            f"in_network {inserted - count} queued {len(vehicles) - inserted}",
            f"  vehicle_steps {steps} distance {distance} "
            f"mean_speed {frac(distance, steps)} = {dec(distance, steps, 3)}",
            f"  travel {dec(travel, count, 2)} entry_delay {dec(delay, count, 2)} "
            f"stopped {dec(stopped, count, 2)} stops {dec(stops, count, 2)} "
            f"lane_changes {dec(changes, count, 2)}",
        ]

    def class_stats_lines(self):
        lines = []
        for vehicle_class in self.classes:
            heading = (
                f"CLASS {vehicle_class.name} vmax {vehicle_class.vmax} "
                f"weight {vehicle_class.weight} "
                f"overtake {flag_text(vehicle_class.overtakes)} "
                f"stops {flag_text(vehicle_class.stops)}"
            )
            members = [
                vehicle for vehicle in self.vehicles if vehicle.vehicle_class is vehicle_class
            ]
            lines.extend(self.class_block(heading, members))
        lines.extend(self.class_block("ALL", self.vehicles))
        return lines

    def segment_line(self, segment):
        cells = self.steps * segment.length * segment.lanes
        changes = "/".join(str(segment.changes[kind]) for kind in CHANGE_KINDS)
        return (
            f"SEGMENT {segment.id} {segment.start} {segment.end} "
            f"length {segment.length} lanes {segment.lanes} limit {segment.limit} "
            f"entered {segment.entered} "
            f"mean_vehicles {dec(segment.vehicle_sum, self.steps, 3)} "
            f"density {dec(segment.vehicle_sum, cells, 4)} "
            f"mean_speed {dec(segment.speed_sum, segment.vehicle_sum, 2)} "
            f"max_vehicles {segment.max_vehicles} changes {changes}"
        )

    def junction_lines(self, junction):
        lines = junction.plan_lines()
        for segment in junction.incoming:
            lines.append(
                f"  IN {segment.id} green {segment.green_steps} passed {segment.passed} "
                f"blocked {segment.blocked} max_queue {segment.max_queue} "
                f"mean_queue {dec(segment.queue_sum, self.steps, 3)} "
                f"failures {segment.failures}"
            )
            for turn in segment.turns:
                lines.append(
                    f"    TURN {turn.target.id} weight {turn.weight} vehicles {turn.vehicles}"
                )
        return lines

    def network_stats_lines(self):
        lines = [self.segment_line(segment) for segment in self.segments]
        for junction in self.junctions:
            lines.extend(self.junction_lines(junction))
        for stop in self.stops:
            lines.append(
                f"STOP {stop.segment.id} cell {stop.cell} dwell {stop.dwell} "
                f"buses {stop.buses}"
            )
        for incident in self.incidents:
            if incident.active_start is None:
                active = "none"
            else:
                active = f"{incident.active_start}-{incident.active_end}"
            lines.append(
                f"INCIDENT {incident.segment.id} lane {incident.lane} "
                f"cell {incident.cell} planned {incident.start}-{incident.end} "
                f"active {active}"
            )
        return lines

    def timeline_lines(self):
        lines = ["interval,arrived,inserted,exited,in_network,queued,mean_speed"]
        arrived = 0
        inserted = 0
        exited = 0
        for number, interval in enumerate(self.intervals, 1):
            arrived += interval.arrivals
            inserted += interval.insertions
            exited += interval.exits
            lines.append(
                f"{number},{interval.arrivals},{interval.insertions},{interval.exits},"
                f"{inserted - exited},{arrived - inserted},"
                f"{dec(interval.speed_sum, interval.vehicle_steps, 2)}"
            )
        return lines

    def track_lines(self):
        lines = []
        for number in self.track_numbers:
            if number > len(self.vehicles):
                lines.append(f"VEHICLE {number} none")
                continue
            vehicle = self.vehicles[number - 1]
            lines.append(
                f"VEHICLE {number} class {vehicle.vehicle_class.name} "
                f"source {vehicle.source} arrival {vehicle.arrival} "
                f"inserted {optional_text(vehicle.inserted)} "
                f"exited {optional_text(vehicle.exited)} "
                f"sink {optional_text(vehicle.sink)}"
            )
            lines.append("ROUTE " + (" ".join(vehicle.route) if vehicle.route else "-"))
            lines.extend(self.tracks[number])
        return lines

    def fundamental_lines(self):
        lines = ["ring,vehicles,density,flow,speed"]
        for ring in self.rings:
            for count in ring.counts:
                total = run_ring(ring, count, self.dawdle, self.dawdle_stopped)
                lines.append(
                    f"{ring.number},{count},{dec(count, ring.length, 4)},"
                    f"{dec(total, ring.length * ring.measure, 4)},"
                    f"{dec(total, count * ring.measure, 3)}"
                )
        return lines


def main():
    simulation = Simulation()
    simulation.load([read_lines(name) for name in INPUT_FILES])
    simulation.run()
    outputs = {
        "spacetime.txt": simulation.spacetime_lines(),
        "detectors.csv": simulation.detector_lines(),
        "travel_times.txt": simulation.travel_time_lines(),
        "class_stats.txt": simulation.class_stats_lines(),
        "network_stats.txt": simulation.network_stats_lines(),
        "timeline.csv": simulation.timeline_lines(),
        "tracks.txt": simulation.track_lines(),
        "fundamental.csv": simulation.fundamental_lines(),
        "events.txt": simulation.events,
    }
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for name, lines in outputs.items():
        write_lines(name, lines)


if __name__ == "__main__":
    main()
