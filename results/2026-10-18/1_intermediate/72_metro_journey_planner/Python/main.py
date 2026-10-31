from collections import namedtuple
from itertools import accumulate
import sys


END_OF_SERVICE = 24 * 60
FARE_CLASSES = ("ADULT", "CHILD")

Ride = namedtuple("Ride", "line terminal board start alight end stops")
Walk = namedtuple("Walk", "origin start destination end")
Stay = namedtuple("Stay", "station start end")


class CommandError(Exception):
    pass


def parse_time(text):
    return int(text[:2]) * 60 + int(text[3:])


def clock(minutes):
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def half(amount):
    return -(-amount // 20) * 10


def segment(first, second):
    return (first, second) if first < second else (second, first)


def improves(labels, station_id, time):
    return station_id not in labels or labels[station_id][0] > time


def ride_count(journey):
    return sum(isinstance(leg, Ride) for leg in journey)


def walk_count(journey):
    return sum(isinstance(leg, Walk) for leg in journey)


def leg_text(leg, previous_end):
    if isinstance(leg, Ride):
        return (
            f"RIDE {leg.line} toward {leg.terminal} {leg.board} {clock(leg.start)} -> "
            f"{leg.alight} {clock(leg.end)} wait {leg.start - previous_end} stops {leg.stops}"
        )
    if isinstance(leg, Walk):
        return f"WALK {leg.origin} {clock(leg.start)} -> {leg.destination} {clock(leg.end)}"
    return f"STAY {leg.station} {clock(leg.start)} -> {clock(leg.end)}"


class Station:
    def __init__(self, station_id, zone, name):
        self.id = station_id
        self.zone = zone
        self.name = name
        self.transfer = 0
        self.closed = False
        self.walks = {}


class Direction:
    def __init__(self, line, stops, offsets):
        self.line = line
        self.stops = stops
        self.offsets = offsets
        self.start = stops[0]
        self.terminal = stops[-1]
        self.index = {station_id: j for j, station_id in enumerate(stops)}

    def time(self, train, j):
        line = self.line
        return line.first + line.delay + train * line.headway + self.offsets[j]

    def first_train(self, j, ready):
        train = max(0, -((self.time(0, j) - ready) // self.line.headway))
        return train if train < self.line.trips else None

    def upcoming(self, j, time, count):
        first = self.first_train(j, time)
        if first is None:
            return range(0)
        return range(first, min(first + count, self.line.trips))

    def ride(self, train, board, alight):
        return Ride(
            self.line.id,
            self.terminal,
            self.stops[board],
            self.time(train, board),
            self.stops[alight],
            self.time(train, alight),
            alight - board,
        )


class Line:
    def __init__(self, line_id, first, last, headway, stops, offsets):
        self.id = line_id
        self.first = first
        self.last = last
        self.headway = headway
        self.stops = stops
        self.offsets = offsets
        self.total = offsets[-1]
        self.trips = (last - first) // headway + 1
        self.delay = 0
        self.suspended = False
        self.segments = {segment(a, b) for a, b in zip(stops, stops[1:])}
        self.directions = (
            Direction(self, stops, offsets),
            Direction(self, stops[::-1], [self.total - offset for offset in reversed(offsets)]),
        )

    def toward(self, terminal):
        for direction in self.directions:
            if direction.terminal == terminal:
                return direction
        return None


class MetroPlanner:
    def __init__(self):
        self.stations = {}
        self.lines = {}
        self.closed_segments = set()
        self.tariff = None
        self.output = []
        self.handlers = {
            "STATION": self.add_station,
            "LINE": self.add_line,
            "TRANSFER": self.set_transfer,
            "WALK": self.add_walk,
            "TARIFF": self.set_tariff,
            "CLOSE": self.close,
            "OPEN": self.open,
            "DELAY": self.delay,
            "SUSPEND": self.suspend,
            "RESUME": self.resume,
            "ROUTE": self.route,
            "VIA": self.via,
            "FEWEST": self.fewest,
            "PARETO": self.pareto,
            "FARE": self.fare,
            "LASTTRAIN": self.last_train,
            "ARRIVEBY": self.arrive_by,
            "PROFILE": self.profile,
            "REACH": self.reach,
            "TIMETABLE": self.timetable,
            "DEPARTURES": self.departures,
            "ARRIVALS": self.arrivals,
            "TRIP": self.trip,
            "SHOWLINE": self.show_line,
            "INFO": self.info,
            "STATUS": self.status,
        }

    def emit(self, text):
        self.output.append(text)

    def execute(self, line):
        command, *arguments = line.split()
        try:
            self.handlers[command](arguments)
        except CommandError as error:
            self.emit(f"ERROR {error}")

    def station(self, station_id):
        if station_id not in self.stations:
            raise CommandError(f"unknown station {station_id}")
        return self.stations[station_id]

    def line(self, line_id):
        if line_id not in self.lines:
            raise CommandError(f"unknown line {line_id}")
        return self.lines[line_id]

    def require_open(self, station_id):
        if self.stations[station_id].closed:
            raise CommandError(f"station {station_id} is closed")

    def check_endpoints(self, origin, destination):
        self.station(origin)
        self.station(destination)
        if origin == destination:
            raise CommandError("origin and destination are the same")
        self.require_open(origin)
        self.require_open(destination)

    def terminal_direction(self, line, toward):
        direction = line.toward(toward)
        if direction is None:
            raise CommandError(f"{toward} is not a terminal of line {line.id}")
        return direction

    def sorted_lines(self):
        return [self.lines[line_id] for line_id in sorted(self.lines)]

    def active_lines(self):
        return [line for line in self.sorted_lines() if not line.suspended]

    def blocked(self, first, second):
        return segment(first, second) in self.closed_segments

    def stop_flags(self, stops, j):
        flags = ""
        if self.stations[stops[j]].closed:
            flags += " closed"
        if j >= 1 and self.blocked(stops[j - 1], stops[j]):
            flags += " blocked"
        return flags

    def ready_time(self, origin, station_id, arrival):
        if station_id == origin:
            return arrival
        return arrival + self.stations[station_id].transfer

    def walk_from(self, labels, station_id, arrival, journey):
        reached = []
        for neighbor, minutes in sorted(self.stations[station_id].walks.items()):
            time = arrival + minutes
            if (
                not self.stations[neighbor].closed
                and time <= END_OF_SERVICE
                and improves(labels, neighbor, time)
            ):
                leg = Walk(station_id, arrival, neighbor, time)
                labels[neighbor] = (time, journey + (leg,))
                reached.append(neighbor)
        return reached

    def ride_from(self, labels, direction, station_id, ready, journey):
        i = direction.index.get(station_id)
        if i is None or i == len(direction.stops) - 1:
            return
        train = direction.first_train(i, ready)
        if train is None:
            return
        for j in range(i + 1, len(direction.stops)):
            stop = direction.stops[j]
            if self.blocked(direction.stops[j - 1], stop):
                return
            if self.stations[stop].closed:
                continue
            time = direction.time(train, j)
            if improves(labels, stop, time):
                labels[stop] = (time, journey + (direction.ride(train, i, j),))

    def earliest_arrival(self, origin, departure):
        lines = self.active_lines()
        labels = {origin: (departure, ())}
        settled = set()
        while True:
            pending = [(labels[key][0], key) for key in labels if key not in settled]
            if not pending:
                return labels
            arrival, current = min(pending)
            settled.add(current)
            journey = labels[current][1]
            ready = self.ready_time(origin, current, arrival)
            for line in lines:
                for direction in line.directions:
                    self.ride_from(labels, direction, current, ready, journey)
            self.walk_from(labels, current, arrival, journey)

    def walk_step(self, labels, starts, marked):
        recorded = {station_id: labels[station_id] for station_id in starts}
        for station_id in sorted(starts):
            arrival, journey = recorded[station_id]
            marked.update(self.walk_from(labels, station_id, arrival, journey))

    def ride_round(self, origin, direction, previous, previous_marked, labels, marked):
        boarded = None
        last = len(direction.stops) - 1
        for j, stop in enumerate(direction.stops):
            if j >= 1 and self.blocked(direction.stops[j - 1], stop):
                boarded = None
            if self.stations[stop].closed:
                continue
            if boarded is not None:
                train, board, journey = boarded
                time = direction.time(train, j)
                if improves(labels, stop, time):
                    labels[stop] = (time, journey + (direction.ride(train, board, j),))
                    marked.add(stop)
            if j < last and stop in previous_marked:
                arrival, journey = previous[stop]
                train = direction.first_train(j, self.ready_time(origin, stop, arrival))
                if train is not None and (boarded is None or train < boarded[0]):
                    boarded = (train, j, journey)

    def round_search(self, origin, departure):
        labels = {origin: (departure, ())}
        marked = {origin}
        self.walk_step(labels, {origin}, marked)
        rounds = [labels]
        lines = self.active_lines()
        while marked:
            previous, previous_marked = labels, marked
            labels = dict(previous)
            ridden = set()
            for line in lines:
                for direction in line.directions:
                    self.ride_round(origin, direction, previous, previous_marked, labels, ridden)
            marked = set(ridden)
            self.walk_step(labels, ridden, marked)
            rounds.append(labels)
        return rounds

    def emit_journey(self, heading, departure, arrival, journey):
        self.emit(
            f"{heading} {clock(departure)} -> {clock(arrival)} total {arrival - departure} "
            f"rides {ride_count(journey)} walks {walk_count(journey)}"
        )
        previous_end = departure
        for leg in journey:
            self.emit(leg_text(leg, previous_end))
            previous_end = leg.end

    def tickets(self, journey, child):
        cap, window, prices = self.tariff
        if child:
            cap = half(cap)
        tickets = []
        previous = None
        for leg in journey:
            if not isinstance(leg, Ride):
                continue
            direction = self.lines[leg.line].toward(leg.terminal)
            start = direction.index[leg.board]
            covered = direction.stops[start:start + leg.stops + 1]
            zones = len({self.stations[stop].zone for stop in covered})
            price = prices[min(zones, len(prices)) - 1]
            if child:
                price = half(price)
            discount = 0
            if previous is not None and leg.start - previous.end <= window:
                discount = min(cap, price)
            tickets.append((leg, zones, price, discount))
            previous = leg
        return tickets

    def add_station(self, arguments):
        station_id, zone, name = arguments
        if station_id in self.stations:
            raise CommandError(f"station {station_id} already exists")
        self.stations[station_id] = Station(station_id, int(zone), name)
        self.emit(f"STATION {station_id} zone {zone} {name}")

    def add_line(self, arguments):
        line_id, first_text, last_text, headway, *route = arguments
        if line_id in self.lines:
            raise CommandError(f"line {line_id} already exists")
        stops = route[::2]
        for stop in stops:
            self.station(stop)
        seen = set()
        for stop in stops:
            if stop in seen:
                raise CommandError(f"station {stop} appears twice on line {line_id}")
            seen.add(stop)
        first = parse_time(first_text)
        last = parse_time(last_text)
        if first > last:
            raise CommandError(f"line {line_id} first departure is after last departure")
        offsets = [0, *accumulate(int(minutes) for minutes in route[1::2])]
        if last + offsets[-1] > END_OF_SERVICE:
            raise CommandError(f"line {line_id} runs past 24:00")
        line = Line(line_id, first, last, int(headway), stops, offsets)
        self.lines[line_id] = line
        self.emit(f"LINE {line_id} stops {len(stops)} time {line.total} trips {line.trips}")

    def set_transfer(self, arguments):
        station_id, minutes = arguments
        self.station(station_id).transfer = int(minutes)
        self.emit(f"TRANSFER {station_id} {minutes}")

    def add_walk(self, arguments):
        first_id, second_id, minutes_text = arguments
        first = self.station(first_id)
        second = self.station(second_id)
        if first_id == second_id:
            raise CommandError(f"walk from {first_id} to itself")
        minutes = int(minutes_text)
        previous = first.walks.get(second_id)
        first.walks[second_id] = minutes
        second.walks[first_id] = minutes
        text = f"WALK {first_id} {second_id} {minutes}"
        if previous is not None:
            text += f" was {previous}"
        self.emit(text)

    def set_tariff(self, arguments):
        discount, window, *prices = map(int, arguments)
        if any(later < earlier for earlier, later in zip(prices, prices[1:])):
            raise CommandError("tariff prices must not decrease")
        self.tariff = (discount, window, prices)
        self.emit(f"TARIFF zones {len(prices)} discount {discount} window {window}")

    def close(self, arguments):
        if len(arguments) == 1:
            self.close_station(*arguments)
        else:
            self.close_segment(*arguments)

    def open(self, arguments):
        if len(arguments) == 1:
            self.open_station(*arguments)
        else:
            self.open_segment(*arguments)

    def close_station(self, station_id):
        station = self.station(station_id)
        if station.closed:
            raise CommandError(f"station {station_id} is already closed")
        station.closed = True
        self.emit(f"CLOSE {station_id}")

    def close_segment(self, first, second):
        self.station(first)
        self.station(second)
        name = f"{first}-{second}"
        key = segment(first, second)
        line_ids = [line.id for line in self.sorted_lines() if key in line.segments]
        if not line_ids:
            raise CommandError(f"no segment {name}")
        if key in self.closed_segments:
            raise CommandError(f"segment {name} is already closed")
        self.closed_segments.add(key)
        self.emit(f"CLOSE {name} lines {' '.join(line_ids)}")

    def open_station(self, station_id):
        station = self.station(station_id)
        if not station.closed:
            raise CommandError(f"station {station_id} is not closed")
        station.closed = False
        self.emit(f"OPEN {station_id}")

    def open_segment(self, first, second):
        self.station(first)
        self.station(second)
        name = f"{first}-{second}"
        key = segment(first, second)
        if key not in self.closed_segments:
            raise CommandError(f"segment {name} is not closed")
        self.closed_segments.remove(key)
        self.emit(f"OPEN {name}")

    def delay(self, arguments):
        line_id, minutes_text = arguments
        line = self.line(line_id)
        minutes = int(minutes_text)
        if line.last + minutes + line.total > END_OF_SERVICE:
            raise CommandError(f"line {line_id} runs past 24:00")
        line.delay = minutes
        self.emit(f"DELAY {line_id} {minutes}")

    def suspend(self, arguments):
        line_id = arguments[0]
        line = self.line(line_id)
        if line.suspended:
            raise CommandError(f"line {line_id} is already suspended")
        line.suspended = True
        self.emit(f"SUSPEND {line_id}")

    def resume(self, arguments):
        line_id = arguments[0]
        line = self.line(line_id)
        if not line.suspended:
            raise CommandError(f"line {line_id} is not suspended")
        line.suspended = False
        self.emit(f"RESUME {line_id}")

    def route(self, arguments):
        origin, destination, time_text = arguments
        self.check_endpoints(origin, destination)
        departure = parse_time(time_text)
        labels = self.earliest_arrival(origin, departure)
        if destination not in labels:
            self.emit(f"ROUTE {origin} {destination} {time_text} unreachable")
            return
        arrival, journey = labels[destination]
        self.emit_journey(f"ROUTE {origin} {destination}", departure, arrival, journey)

    def via(self, arguments):
        origin, via, destination, time_text = arguments
        self.station(origin)
        self.station(via)
        self.station(destination)
        if origin == destination:
            raise CommandError("origin and destination are the same")
        if via in (origin, destination):
            raise CommandError(f"via station {via} must differ from origin and destination")
        for station_id in (origin, via, destination):
            self.require_open(station_id)
        departure = parse_time(time_text)
        heading = f"VIA {origin} {via} {destination}"
        first_labels = self.earliest_arrival(origin, departure)
        if via in first_labels:
            reached, first_journey = first_labels[via]
            resumed = reached + self.stations[via].transfer
            second_labels = self.earliest_arrival(via, resumed)
            if destination in second_labels:
                arrival, second_journey = second_labels[destination]
                journey = first_journey + (Stay(via, reached, resumed),) + second_journey
                self.emit_journey(heading, departure, arrival, journey)
                return
        self.emit(f"{heading} {time_text} unreachable")

    def fewest(self, arguments):
        origin, destination, time_text = arguments
        self.check_endpoints(origin, destination)
        departure = parse_time(time_text)
        for rides, labels in enumerate(self.round_search(origin, departure)):
            if destination in labels:
                arrival, journey = labels[destination]
                heading = f"FEWEST {origin} {destination} trips {rides}"
                self.emit_journey(heading, departure, arrival, journey)
                return
        self.emit(f"FEWEST {origin} {destination} {time_text} unreachable")

    def pareto(self, arguments):
        origin, destination, time_text = arguments
        self.check_endpoints(origin, destination)
        departure = parse_time(time_text)
        options = []
        previous = {}
        for rides, labels in enumerate(self.round_search(origin, departure)):
            if destination in labels and improves(previous, destination, labels[destination][0]):
                options.append((rides, *labels[destination]))
            previous = labels
        self.emit(f"PARETO {origin} {destination} {time_text} options {len(options)}")
        for rides, arrival, journey in options:
            self.emit_journey(f"OPTION trips {rides}", departure, arrival, journey)

    def fare(self, arguments):
        origin, destination, time_text, fare_class = arguments
        self.check_endpoints(origin, destination)
        if fare_class not in FARE_CLASSES:
            raise CommandError(f"unknown fare class {fare_class}")
        if self.tariff is None:
            raise CommandError("no tariff")
        labels = self.earliest_arrival(origin, parse_time(time_text))
        heading = f"FARE {origin} {destination} {time_text} {fare_class}"
        if destination not in labels:
            self.emit(f"{heading} unreachable")
            return
        tickets = self.tickets(labels[destination][1], fare_class == "CHILD")
        total = sum(price - discount for _, _, price, discount in tickets)
        self.emit(f"{heading} rides {len(tickets)} total {total}")
        for leg, zones, price, discount in tickets:
            self.emit(
                f"TICKET {leg.line} {leg.board} {leg.alight} zones {zones} "
                f"price {price} discount {discount} pay {price - discount}"
            )

    def last_train(self, arguments):
        origin, destination = arguments
        self.check_endpoints(origin, destination)
        for departure in range(END_OF_SERVICE - 1, -1, -1):
            labels = self.earliest_arrival(origin, departure)
            if destination in labels:
                arrival, journey = labels[destination]
                heading = f"LASTTRAIN {origin} {destination}"
                self.emit_journey(heading, departure, arrival, journey)
                return
        self.emit(f"LASTTRAIN {origin} {destination} none")

    def arrive_by(self, arguments):
        origin, destination, time_text = arguments
        self.check_endpoints(origin, destination)
        deadline = parse_time(time_text)
        heading = f"ARRIVEBY {origin} {destination} by {time_text}"
        for departure in range(deadline - 1, -1, -1):
            labels = self.earliest_arrival(origin, departure)
            if destination in labels and labels[destination][0] <= deadline:
                arrival, journey = labels[destination]
                self.emit_journey(heading, departure, arrival, journey)
                return
        self.emit(f"{heading} none")

    def profile(self, arguments):
        origin, destination, start_text, end_text = arguments
        self.check_endpoints(origin, destination)
        start = parse_time(start_text)
        end = parse_time(end_text)
        if start > end:
            raise CommandError(f"empty interval {start_text} {end_text}")
        arrivals = {}
        for departure in range(start, end + 1):
            labels = self.earliest_arrival(origin, departure)
            if destination in labels:
                arrivals[departure] = labels[destination][0]
        selected = [
            departure
            for departure, arrival in arrivals.items()
            if departure == end
            or departure + 1 not in arrivals
            or arrival < arrivals[departure + 1]
        ]
        self.emit(
            f"PROFILE {origin} {destination} {start_text} {end_text} count {len(selected)}"
        )
        for departure in selected:
            arrival = arrivals[departure]
            self.emit(f"{clock(departure)} -> {clock(arrival)} total {arrival - departure}")

    def reach(self, arguments):
        station_id, time_text, minutes = arguments
        self.station(station_id)
        self.require_open(station_id)
        departure = parse_time(time_text)
        limit = departure + int(minutes)
        labels = self.earliest_arrival(station_id, departure)
        reached = sorted(
            (arrival, reached_id)
            for reached_id, (arrival, _) in labels.items()
            if arrival <= limit
        )
        self.emit(f"REACH {station_id} {time_text} {minutes} count {len(reached)}")
        for arrival, reached_id in reached:
            name = self.stations[reached_id].name
            rides = ride_count(labels[reached_id][1])
            self.emit(
                f"{reached_id} {name} {clock(arrival)} {arrival - departure} rides {rides}"
            )

    def timetable(self, arguments):
        station_id, line_id, toward, time_text, count = arguments
        self.station(station_id)
        line = self.line(line_id)
        if station_id not in line.stops:
            raise CommandError(f"station {station_id} is not on line {line_id}")
        direction = self.terminal_direction(line, toward)
        if station_id == toward:
            raise CommandError(f"no departures from {station_id} toward {toward}")
        if line.suspended:
            raise CommandError(f"line {line_id} is suspended")
        self.require_open(station_id)
        j = direction.index[station_id]
        trains = direction.upcoming(j, parse_time(time_text), int(count))
        times = [clock(direction.time(train, j)) for train in trains]
        heading = f"TIMETABLE {station_id} {line_id} toward {toward} {time_text} next {len(times)}"
        self.emit(" ".join([heading, *times]))

    def passing_trains(self, station_id, time, count, arriving):
        trains = []
        for line in self.active_lines():
            if station_id not in line.stops:
                continue
            for direction in line.directions:
                j = direction.index[station_id]
                if j == (0 if arriving else len(direction.stops) - 1):
                    continue
                for train in direction.upcoming(j, time, count):
                    trains.append((direction.time(train, j), direction))
        trains.sort(key=lambda entry: entry[0])
        return trains[:count]

    def departures(self, arguments):
        station_id, time_text, count = arguments
        self.station(station_id)
        self.require_open(station_id)
        trains = self.passing_trains(station_id, parse_time(time_text), int(count), False)
        self.emit(f"DEPARTURES {station_id} {time_text} count {len(trains)}")
        for time, direction in trains:
            self.emit(f"{clock(time)} {direction.line.id} toward {direction.terminal}")

    def arrivals(self, arguments):
        station_id, time_text, count = arguments
        self.station(station_id)
        self.require_open(station_id)
        trains = self.passing_trains(station_id, parse_time(time_text), int(count), True)
        self.emit(f"ARRIVALS {station_id} {time_text} count {len(trains)}")
        for time, direction in trains:
            self.emit(f"{clock(time)} {direction.line.id} from {direction.start}")

    def trip(self, arguments):
        line_id, toward, time_text = arguments
        line = self.line(line_id)
        direction = self.terminal_direction(line, toward)
        if line.suspended:
            raise CommandError(f"line {line_id} is suspended")
        train = direction.first_train(0, parse_time(time_text))
        heading = f"TRIP {line_id} toward {toward} {time_text}"
        if train is None:
            self.emit(f"{heading} none")
            return
        self.emit(f"{heading} trip {train + 1} departs {clock(direction.time(train, 0))}")
        for j, stop in enumerate(direction.stops):
            flags = self.stop_flags(direction.stops, j)
            self.emit(f"{clock(direction.time(train, j))} {stop}{flags}")

    def show_line(self, arguments):
        line = self.line(arguments[0])
        state = "suspended" if line.suspended else "running"
        self.emit(
            f"SHOWLINE {line.id} {state} first {clock(line.first)} last {clock(line.last)} "
            f"headway {line.headway} delay {line.delay} trips {line.trips}"
        )
        for i, stop in enumerate(line.stops):
            zone = self.stations[stop].zone
            flags = self.stop_flags(line.stops, i)
            self.emit(f"{line.offsets[i]} {stop} zone {zone}{flags}")

    def info(self, arguments):
        station = self.station(arguments[0])
        state = "closed" if station.closed else "open"
        self.emit(
            f"INFO {station.id} {station.name} zone {station.zone} "
            f"transfer {station.transfer} {state}"
        )
        line_ids = [line.id for line in self.sorted_lines() if station.id in line.stops]
        self.emit("LINES " + (" ".join(line_ids) or "none"))
        walks = [f"{neighbor} {minutes}" for neighbor, minutes in sorted(station.walks.items())]
        self.emit("WALKS " + (" ".join(walks) or "none"))

    def status(self, arguments):
        walks = sum(len(station.walks) for station in self.stations.values()) // 2
        self.emit(f"STATUS stations {len(self.stations)} lines {len(self.lines)} walks {walks}")
        for station_id in sorted(self.stations):
            if self.stations[station_id].closed:
                self.emit(f"CLOSED {station_id}")
        for first, second in sorted(self.closed_segments):
            self.emit(f"CLOSED {first}-{second}")
        lines = self.sorted_lines()
        for line in lines:
            if line.suspended:
                self.emit(f"SUSPENDED {line.id}")
        for line in lines:
            if line.delay:
                self.emit(f"DELAYED {line.id} {line.delay}")


def main():
    planner = MetroPlanner()
    count = int(sys.stdin.readline())
    for _ in range(count):
        planner.execute(sys.stdin.readline())
    sys.stdout.write("\n".join(planner.output) + "\n")


if __name__ == "__main__":
    main()
