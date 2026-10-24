from functools import cmp_to_key
from itertools import pairwise
import sys


DEPOT = 0
DEFAULT_START = 8 * 60
EXACT_LIMIT = 10
SEGMENT_SIZES = (1, 2, 3)


class CommandError(Exception):
    pass


class Stop:
    def __init__(self, number, x, y, demand, service, window):
        self.number = number
        self.x = x
        self.y = y
        self.demand = demand
        self.service = service
        self.window = window


class Plan:
    def __init__(self, capacity, routes):
        self.capacity = capacity
        self.routes = routes
        self.normalize()

    def normalize(self):
        routes = [route if route[0] <= route[-1] else route[::-1] for route in self.routes if route]
        self.routes = sorted(routes, key=min)


class Run:
    def __init__(self):
        self.visits = []
        self.return_time = 0
        self.travel = 0
        self.wait = 0
        self.service = 0
        self.violations = 0
        self.lateness = 0


def parse_time(text):
    hours, minutes = text.split(":")
    return int(hours) * 60 + int(minutes)


def format_time(minutes):
    hours, rest = divmod(minutes, 60)
    return f"{hours:02d}:{rest:02d}"


def window_text(window):
    if window is None:
        return "none"
    opening, closing = window
    return f"{format_time(opening)}-{format_time(closing)}"


def place_name(place):
    return "D" if place == DEPOT else str(place)


def name_at(sequence, index):
    return str(sequence[index - 1]) if index > 0 else "D"


def notation(sequence):
    return "-".join(["D", *map(str, sequence), "D"])


def tenths(value):
    return f"{value // 10}.{value % 10}"


def half_plane(dx, dy):
    return 0 if dy > 0 or (dy == 0 and dx > 0) else 1


class Workbench:
    def __init__(self):
        self.depot = None
        self.start = DEFAULT_START
        self.stops = {}
        self.tour = None
        self.plan = None
        self.output = []
        self.handlers = {
            "DEPOT": self.set_depot,
            "START": self.set_start,
            "STOP": self.add_stop,
            "REMOVE": self.remove_stop,
            "LIST": self.list_state,
            "MATRIX": self.matrix,
            "ORDER": self.order,
            "NEAREST": self.nearest,
            "INSERTION": self.insertion,
            "EXACT": self.exact,
            "TOUR": self.show_tour,
            "TWOOPT": self.two_opt_tour,
            "OROPT": self.or_opt_tour,
            "SWAP": self.swap_tour,
            "TIMECHECK": self.timecheck,
            "BOUND": self.bound,
            "VRP": self.savings,
            "SPLIT": self.split,
            "SWEEP": self.sweep,
            "ROUTES": self.show_routes,
            "RELOCATE": self.relocate,
            "EXCHANGE": self.exchange,
            "CROSS": self.cross,
            "ROUTEOPT": self.route_opt,
            "REPORT": self.report,
        }

    def emit(self, line):
        self.output.append(line)

    def position(self, place):
        if place == DEPOT:
            return self.depot
        stop = self.stops[place]
        return stop.x, stop.y

    def distance(self, first, second):
        x1, y1 = self.position(first)
        x2, y2 = self.position(second)
        return abs(x1 - x2) + abs(y1 - y2)

    def detour(self, before, first, last, after):
        return (
            self.distance(before, first) + self.distance(last, after)
            - self.distance(before, after)
        )

    def length(self, sequence):
        path = [DEPOT, *sequence, DEPOT]
        return sum(self.distance(a, b) for a, b in pairwise(path))

    def load(self, sequence):
        return sum(self.stops[number].demand for number in sequence)

    def plan_length(self):
        return sum(self.length(route) for route in self.plan.routes)

    def simulate(self, sequence):
        run = Run()
        time = self.start
        previous = DEPOT
        for number in sequence:
            stop = self.stops[number]
            arrival = time + self.distance(previous, number)
            wait = 0
            lateness = 0
            if stop.window is not None:
                opening, closing = stop.window
                wait = max(opening - arrival, 0)
                lateness = max(arrival - closing, 0)
            begin = arrival + wait
            time = begin + stop.service
            run.visits.append((number, arrival, wait, begin, time, lateness))
            run.wait += wait
            run.service += stop.service
            run.lateness += lateness
            if lateness > 0:
                run.violations += 1
            previous = number
        run.return_time = time + self.distance(previous, DEPOT)
        run.travel = self.length(sequence)
        return run

    def require_depot(self):
        if self.depot is None:
            raise CommandError("no depot")

    def require_stops(self):
        if not self.stops:
            raise CommandError("no stops")

    def require_tour(self):
        if self.tour is None:
            raise CommandError("no tour")

    def require_plan(self):
        if self.plan is None:
            raise CommandError("no plan")

    def require_capacity(self, capacity):
        for number in sorted(self.stops):
            demand = self.stops[number].demand
            if demand > capacity:
                raise CommandError(f"stop {number} demand {demand} exceeds capacity {capacity}")

    def set_depot(self, arguments):
        x, y = map(int, arguments)
        self.depot = (x, y)
        self.emit(f"depot at ({x},{y})")

    def set_start(self, arguments):
        self.start = parse_time(arguments[0])
        self.emit(f"start {format_time(self.start)}")

    def add_stop(self, arguments):
        number, x, y, demand, service = map(int, arguments[:5])
        if number in self.stops:
            raise CommandError(f"stop {number} already exists")
        window = None
        if len(arguments) == 7:
            window = (parse_time(arguments[5]), parse_time(arguments[6]))
            if window[0] > window[1]:
                raise CommandError("invalid window")
        self.stops[number] = Stop(number, x, y, demand, service, window)
        self.tour = None
        self.plan = None
        self.emit(f"stop {number} added")

    def remove_stop(self, arguments):
        number = int(arguments[0])
        if number not in self.stops:
            raise CommandError(f"unknown stop {number}")
        del self.stops[number]
        if self.tour is not None:
            self.tour.remove(number)
        if self.plan is not None:
            self.plan.routes = [
                [stop for stop in route if stop != number] for route in self.plan.routes
            ]
            self.plan.normalize()
        if not self.stops:
            self.tour = None
            self.plan = None
        self.emit(f"stop {number} removed")

    def list_state(self, arguments):
        if self.depot is None:
            self.emit("depot none")
        else:
            x, y = self.depot
            self.emit(f"depot ({x},{y})")
        self.emit(f"start {format_time(self.start)}")
        self.emit(f"stops {len(self.stops)}")
        for number in sorted(self.stops):
            stop = self.stops[number]
            self.emit(
                f"{number} at ({stop.x},{stop.y}) demand {stop.demand} "
                f"service {stop.service} window {window_text(stop.window)}"
            )

    def matrix(self, arguments):
        self.require_depot()
        places = [DEPOT, *sorted(self.stops)]
        header = [place_name(place) for place in places]
        rows = [
            [place_name(origin)] + [str(self.distance(origin, target)) for target in places]
            for origin in places
        ]
        width = max(len(cell) for row in [header, *rows] for cell in row)
        self.emit(" ".join([" " * width] + [cell.rjust(width) for cell in header]))
        for row in rows:
            self.emit(" ".join(cell.rjust(width) for cell in row))

    def set_tour(self, label, tour):
        self.tour = tour
        self.emit(f"{label}: {notation(tour)} length {self.length(tour)}")

    def order(self, arguments):
        self.require_depot()
        self.require_stops()
        numbers = [int(argument) for argument in arguments]
        for number in numbers:
            if number not in self.stops:
                raise CommandError(f"unknown stop {number}")
        seen = set()
        for number in numbers:
            if number in seen:
                raise CommandError(f"duplicate stop {number}")
            seen.add(number)
        if len(numbers) != len(self.stops):
            raise CommandError(f"order has {len(numbers)} stops, expected {len(self.stops)}")
        self.set_tour("order", numbers)

    def nearest(self, arguments):
        self.require_depot()
        self.require_stops()
        remaining = sorted(self.stops)
        tour = []
        current = DEPOT
        while remaining:
            current = min(remaining, key=lambda stop: (self.distance(current, stop), stop))
            remaining.remove(current)
            tour.append(current)
        self.set_tour("nearest", tour)

    def insertion(self, arguments):
        self.require_depot()
        self.require_stops()
        remaining = sorted(self.stops)
        tour = []
        while remaining:
            path = [DEPOT, *tour, DEPOT]
            _, stop, position = min(
                (self.detour(path[j], stop, stop, path[j + 1]), stop, j)
                for stop in remaining
                for j in range(len(tour) + 1)
            )
            remaining.remove(stop)
            tour.insert(position, stop)
        self.set_tour("insertion", tour)

    def exact(self, arguments):
        self.require_depot()
        self.require_stops()
        if len(self.stops) > EXACT_LIMIT:
            raise CommandError(f"too many stops for exact ({len(self.stops)})")
        self.set_tour("exact", self.exact_tour())

    def exact_tour(self):
        numbers = sorted(self.stops)
        count = len(numbers)
        distance = self.distance
        full = (1 << count) - 1
        # rest[mask][i]: shortest path from stop i through every stop in mask and back to D
        rest = [[0] * count for _ in range(full + 1)]
        for i, number in enumerate(numbers):
            rest[0][i] = distance(number, DEPOT)
        for mask in range(1, full):
            for i in range(count):
                if not mask & (1 << i):
                    rest[mask][i] = min(
                        distance(numbers[i], numbers[j]) + rest[mask ^ (1 << j)][j]
                        for j in range(count)
                        if mask & (1 << j)
                    )
        cost = min(distance(DEPOT, numbers[i]) + rest[full ^ (1 << i)][i] for i in range(count))
        tour = []
        current = DEPOT
        mask = full
        while mask:
            choice = next(
                j for j in range(count)
                if mask & (1 << j)
                and distance(current, numbers[j]) + rest[mask ^ (1 << j)][j] == cost
            )
            mask ^= 1 << choice
            cost = rest[mask][choice]
            current = numbers[choice]
            tour.append(current)
        return tour

    def show_tour(self, arguments):
        self.require_tour()
        self.emit(f"tour: {notation(self.tour)} length {self.length(self.tour)}")

    def two_opt(self, sequence):
        moves = []
        while (move := self.first_reversal(sequence)) is not None:
            start, end, gain = move
            moves.append((sequence[start], sequence[end], gain))
            sequence[start:end + 1] = reversed(sequence[start:end + 1])
        return moves

    def first_reversal(self, sequence):
        distance = self.distance
        path = [DEPOT, *sequence, DEPOT]
        for i in range(1, len(sequence)):
            for j in range(i + 1, len(sequence) + 1):
                gain = (
                    distance(path[i - 1], path[i]) + distance(path[j], path[j + 1])
                    - distance(path[i - 1], path[j]) - distance(path[i], path[j + 1])
                )
                if gain > 0:
                    return i - 1, j - 1, gain
        return None

    def two_opt_tour(self, arguments):
        self.require_tour()
        before = self.length(self.tour)
        moves = self.two_opt(self.tour)
        for first, last, gain in moves:
            self.emit(f"reverse {first}..{last} gain {gain}")
        self.emit(f"twoopt: moves {len(moves)}, length {before} -> {self.length(self.tour)}")

    def first_segment_move(self, tour):
        count = len(tour)
        path = [DEPOT, *tour, DEPOT]
        for size in SEGMENT_SIZES:
            for i in range(1, count - size + 2):
                first, last = path[i], path[i + size - 1]
                removal = self.detour(path[i - 1], first, last, path[i + size])
                rest = [DEPOT, *tour[:i - 1], *tour[i + size - 1:], DEPOT]
                for j in range(count - size + 1):
                    if j == i - 1:
                        continue
                    gain = removal - self.detour(rest[j], first, last, rest[j + 1])
                    if gain > 0:
                        return i - 1, size, j, gain
        return None

    def or_opt_tour(self, arguments):
        self.require_tour()
        tour = self.tour
        before = self.length(tour)
        moves = 0
        while (move := self.first_segment_move(tour)) is not None:
            start, size, position, gain = move
            segment = tour[start:start + size]
            rest = tour[:start] + tour[start + size:]
            listing = "-".join(map(str, segment))
            self.emit(f"move {listing} after {name_at(rest, position)} gain {gain}")
            tour = rest[:position] + segment + rest[position:]
            moves += 1
        self.tour = tour
        self.emit(f"oropt: moves {moves}, length {before} -> {self.length(tour)}")

    def first_swap(self, tour):
        length = self.length(tour)
        for i in range(len(tour) - 1):
            for j in range(i + 1, len(tour)):
                swapped = tour.copy()
                swapped[i], swapped[j] = tour[j], tour[i]
                gain = length - self.length(swapped)
                if gain > 0:
                    return i, j, gain
        return None

    def swap_tour(self, arguments):
        self.require_tour()
        tour = self.tour
        before = self.length(tour)
        moves = 0
        while (move := self.first_swap(tour)) is not None:
            i, j, gain = move
            self.emit(f"swap {tour[i]} and {tour[j]} gain {gain}")
            tour[i], tour[j] = tour[j], tour[i]
            moves += 1
        self.emit(f"swap: moves {moves}, length {before} -> {self.length(tour)}")

    def timecheck(self, arguments):
        if arguments:
            number = int(arguments[0])
            self.require_plan()
            if number > len(self.plan.routes):
                raise CommandError(f"no route {number}")
            sequence = self.plan.routes[number - 1]
            self.emit(f"timecheck route {number} depart {format_time(self.start)}")
        else:
            self.require_tour()
            sequence = self.tour
            self.emit(f"timecheck tour depart {format_time(self.start)}")
        run = self.simulate(sequence)
        for stop, arrival, wait, begin, leave, lateness in run.visits:
            status = f"late {lateness}" if lateness > 0 else "ok"
            self.emit(
                f"{stop} arrive {format_time(arrival)} wait {wait} begin {format_time(begin)} "
                f"leave {format_time(leave)} {status}"
            )
        self.emit(
            f"return {format_time(run.return_time)}, travel {run.travel}, wait {run.wait}, "
            f"service {run.service}, violations {run.violations}, lateness {run.lateness}"
        )

    def spanning_tree(self, vertices):
        tree = vertices[:1]
        remaining = vertices[1:]
        edges = []
        while remaining:
            weight, child, _, parent = min(
                (self.distance(parent, child), child, index, parent)
                for child in remaining
                for index, parent in enumerate(tree)
            )
            edges.append((parent, child, weight))
            tree.append(child)
            remaining.remove(child)
        return edges

    def bound(self, arguments):
        self.require_depot()
        self.require_stops()
        numbers = sorted(self.stops)
        edges = self.spanning_tree([DEPOT, *numbers])
        tree_length = sum(weight for _, _, weight in edges)
        listing = " ".join(f"{place_name(parent)}-{child}" for parent, child, _ in edges)
        self.emit(f"mst: {listing} (length {tree_length})")
        depot_distances = sorted(self.distance(DEPOT, number) for number in numbers)
        if len(numbers) == 1:
            one_tree = 2 * depot_distances[0]
        else:
            stop_tree = sum(weight for _, _, weight in self.spanning_tree(numbers))
            one_tree = stop_tree + depot_distances[0] + depot_distances[1]
        best = max(tree_length, one_tree)
        self.emit(f"bound: mst {tree_length}, one-tree {one_tree}, best {best}")
        if self.tour is None:
            self.emit("gap: no tour")
            return
        length = self.length(self.tour)
        gap = (2000 * (length - best) + best) // (2 * best) if best > 0 else 0
        self.emit(f"gap: tour {length}, {tenths(gap)}%")

    def emit_plan(self, heading):
        routes = self.plan.routes
        self.emit(f"{heading}, routes {len(routes)}, length {self.plan_length()}")
        for number, route in enumerate(routes, 1):
            self.emit(
                f"route {number}: {notation(route)} load {self.load(route)} "
                f"length {self.length(route)}"
            )

    def savings(self, arguments):
        capacity = int(arguments[0])
        limit = int(arguments[1]) if len(arguments) == 2 else None
        self.require_depot()
        self.require_stops()
        self.require_capacity(capacity)
        numbers = sorted(self.stops)
        if limit is not None:
            for number in numbers:
                if 2 * self.distance(DEPOT, number) > limit:
                    raise CommandError(f"stop {number} too far for limit {limit}")
        pairs = []
        for index, i in enumerate(numbers):
            for j in numbers[index + 1:]:
                saving = self.distance(DEPOT, i) + self.distance(DEPOT, j) - self.distance(i, j)
                if saving > 0:
                    pairs.append((-saving, i, j))
        pairs.sort()
        routes = [[number] for number in numbers]
        route_of = {route[0]: route for route in routes}
        merges = 0
        for _, i, j in pairs:
            first, second = route_of[i], route_of[j]
            if (
                first is second
                or i not in (first[0], first[-1])
                or j not in (second[0], second[-1])
            ):
                continue
            if self.load(first) + self.load(second) > capacity:
                continue
            merged = (first[::-1] if first[0] == i else first) + (
                second[::-1] if second[-1] == j else second
            )
            if limit is not None and self.length(merged) > limit:
                continue
            routes.remove(first)
            routes.remove(second)
            routes.append(merged)
            for number in merged:
                route_of[number] = merged
            merges += 1
        self.plan = Plan(capacity, routes)
        self.emit_plan(f"vrp: capacity {capacity}, merges {merges}")

    def split(self, arguments):
        capacity = int(arguments[0])
        self.require_tour()
        self.require_capacity(capacity)
        tour = self.tour
        count = len(tour)
        best = [0] + [None] * count
        previous = [0] * (count + 1)
        for end in range(1, count + 1):
            for start in range(end):
                segment = tour[start:end]
                if self.load(segment) > capacity:
                    continue
                value = best[start] + self.length(segment)
                if best[end] is None or value < best[end]:
                    best[end] = value
                    previous[end] = start
        routes = []
        end = count
        while end > 0:
            routes.append(tour[previous[end]:end])
            end = previous[end]
        self.plan = Plan(capacity, routes)
        self.emit_plan(f"split: capacity {capacity}")

    def sweep_order(self):
        depot_x, depot_y = self.depot
        offsets = {
            number: (stop.x - depot_x, stop.y - depot_y) for number, stop in self.stops.items()
        }

        def compare(first, second):
            (x1, y1), (x2, y2) = offsets[first], offsets[second]
            half1, half2 = half_plane(x1, y1), half_plane(x2, y2)
            if half1 != half2:
                return half1 - half2
            cross = x1 * y2 - y1 * x2
            if cross != 0:
                return -1 if cross > 0 else 1
            distance1, distance2 = abs(x1) + abs(y1), abs(x2) + abs(y2)
            if distance1 != distance2:
                return distance1 - distance2
            return first - second

        numbers = sorted(offsets)
        at_depot = [number for number in numbers if offsets[number] == (0, 0)]
        others = [number for number in numbers if offsets[number] != (0, 0)]
        return at_depot + sorted(others, key=cmp_to_key(compare))

    def sweep(self, arguments):
        capacity = int(arguments[0])
        self.require_depot()
        self.require_stops()
        self.require_capacity(capacity)
        routes = [[]]
        load = 0
        for number in self.sweep_order():
            demand = self.stops[number].demand
            if load + demand > capacity:
                routes.append([])
                load = 0
            routes[-1].append(number)
            load += demand
        self.plan = Plan(capacity, routes)
        self.emit_plan(f"sweep: capacity {capacity}")

    def show_routes(self, arguments):
        self.require_plan()
        self.emit_plan(f"plan: capacity {self.plan.capacity}")

    def first_relocation(self):
        routes = self.plan.routes
        loads = [self.load(route) for route in routes]
        for r, source in enumerate(routes):
            path = [DEPOT, *source, DEPOT]
            for p in range(1, len(source) + 1):
                stop = path[p]
                removal = self.detour(path[p - 1], stop, stop, path[p + 1])
                demand = self.stops[stop].demand
                for t, target in enumerate(routes):
                    if t == r or loads[t] + demand > self.plan.capacity:
                        continue
                    around = [DEPOT, *target, DEPOT]
                    for j in range(len(target) + 1):
                        gain = removal - self.detour(around[j], stop, stop, around[j + 1])
                        if gain > 0:
                            return r, p - 1, t, j, gain
        return None

    def relocate(self, arguments):
        self.require_plan()
        plan = self.plan
        routes_before = len(plan.routes)
        length_before = self.plan_length()
        moves = 0
        while (move := self.first_relocation()) is not None:
            source, position, target, slot, gain = move
            routes = plan.routes
            stop = routes[source].pop(position)
            self.emit(
                f"relocate {stop} from route {source + 1} to route {target + 1} "
                f"after {name_at(routes[target], slot)} gain {gain}"
            )
            routes[target].insert(slot, stop)
            plan.normalize()
            moves += 1
        self.emit(
            f"relocate: moves {moves}, routes {routes_before} -> {len(plan.routes)}, "
            f"length {length_before} -> {self.plan_length()}"
        )

    def first_exchange(self):
        routes = self.plan.routes
        capacity = self.plan.capacity
        for r, first in enumerate(routes):
            for t in range(r + 1, len(routes)):
                second = routes[t]
                first_load = self.load(first)
                second_load = self.load(second)
                total = self.length(first) + self.length(second)
                for p, stop in enumerate(first):
                    for j, other in enumerate(second):
                        shift = self.stops[other].demand - self.stops[stop].demand
                        if first_load + shift > capacity or second_load - shift > capacity:
                            continue
                        changed_first = first[:p] + [other] + first[p + 1:]
                        changed_second = second[:j] + [stop] + second[j + 1:]
                        gain = total - self.length(changed_first) - self.length(changed_second)
                        if gain > 0:
                            return r, p, t, j, gain
        return None

    def exchange(self, arguments):
        self.require_plan()
        plan = self.plan
        length_before = self.plan_length()
        moves = 0
        while (move := self.first_exchange()) is not None:
            r, p, t, j, gain = move
            routes = plan.routes
            stop, other = routes[r][p], routes[t][j]
            self.emit(f"exchange {stop} (route {r + 1}) with {other} (route {t + 1}) gain {gain}")
            routes[r][p], routes[t][j] = other, stop
            plan.normalize()
            moves += 1
        self.emit(f"exchange: moves {moves}, length {length_before} -> {self.plan_length()}")

    def first_cross(self):
        distance = self.distance
        routes = self.plan.routes
        capacity = self.plan.capacity
        for r, first in enumerate(routes):
            for t in range(r + 1, len(routes)):
                second = routes[t]
                a = [DEPOT, *first, DEPOT]
                b = [DEPOT, *second, DEPOT]
                for i in range(len(first) + 1):
                    for j in range(len(second) + 1):
                        if (
                            self.load(first[:i] + second[j:]) > capacity
                            or self.load(second[:j] + first[i:]) > capacity
                        ):
                            continue
                        gain = (
                            distance(a[i], a[i + 1]) + distance(b[j], b[j + 1])
                            - distance(a[i], b[j + 1]) - distance(b[j], a[i + 1])
                        )
                        if gain > 0:
                            return r, i, t, j, gain
        return None

    def cross(self, arguments):
        self.require_plan()
        plan = self.plan
        routes_before = len(plan.routes)
        length_before = self.plan_length()
        moves = 0
        while (move := self.first_cross()) is not None:
            r, i, t, j, gain = move
            routes = plan.routes
            first, second = routes[r], routes[t]
            self.emit(
                f"cross route {r + 1} after {name_at(first, i)} "
                f"with route {t + 1} after {name_at(second, j)} gain {gain}"
            )
            routes[r], routes[t] = first[:i] + second[j:], second[:j] + first[i:]
            plan.normalize()
            moves += 1
        self.emit(
            f"cross: moves {moves}, routes {routes_before} -> {len(plan.routes)}, "
            f"length {length_before} -> {self.plan_length()}"
        )

    def route_opt(self, arguments):
        self.require_plan()
        length_before = self.plan_length()
        for number, route in enumerate(self.plan.routes, 1):
            before = self.length(route)
            moves = self.two_opt(route)
            self.emit(
                f"route {number}: moves {len(moves)}, length {before} -> {self.length(route)}"
            )
        self.plan.normalize()
        self.emit(f"routeopt: length {length_before} -> {self.plan_length()}")

    def report(self, arguments):
        stops = self.stops.values()
        demand = sum(stop.demand for stop in stops)
        service = sum(stop.service for stop in stops)
        windows = sum(stop.window is not None for stop in stops)
        self.emit(
            f"report: stops {len(stops)}, demand {demand}, service {service}, windows {windows}"
        )
        if self.tour is None:
            self.emit("tour: none")
        else:
            run = self.simulate(self.tour)
            self.emit(
                f"tour: length {run.travel}, return {format_time(run.return_time)}, "
                f"violations {run.violations}, lateness {run.lateness}"
            )
        if self.plan is None:
            self.emit("plan: none")
            return
        plan = self.plan
        count = len(plan.routes)
        total_load = sum(self.load(route) for route in plan.routes)
        utilization = (2000 * total_load + count * plan.capacity) // (2 * count * plan.capacity)
        runs = [self.simulate(route) for route in plan.routes]
        latest = max(run.return_time for run in runs)
        violations = sum(run.violations for run in runs)
        lateness = sum(run.lateness for run in runs)
        self.emit(
            f"plan: capacity {plan.capacity}, routes {count}, length {self.plan_length()}, "
            f"utilization {tenths(utilization)}%, return {format_time(latest)}, "
            f"violations {violations}, lateness {lateness}"
        )

    def execute(self, line):
        command, *arguments = line.split(" ")
        try:
            self.handlers[command](arguments)
        except CommandError as error:
            self.emit(f"error: {error}")


def main():
    workbench = Workbench()
    count = int(sys.stdin.readline())
    for _ in range(count):
        workbench.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(workbench.output) + "\n")


if __name__ == "__main__":
    main()
