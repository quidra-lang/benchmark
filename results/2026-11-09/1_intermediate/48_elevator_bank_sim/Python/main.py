from fractions import Fraction
import sys


POLICIES = ("COST", "NEAREST", "ROUND", "ETA")
CONFIG_KEYS = (
    "FLOORS", "CARS", "CAPACITY", "DOOR", "START", "POLICY", "ZONES",
    "PARK", "PATIENCE", "BYPASS", "PERIOD", "LIMIT", "COMPARE",
)
REQUIRED_KEYS = ("FLOORS", "CARS", "CAPACITY", "DOOR", "START")
ARGUMENT_COUNTS = {
    "CALL": 3, "CANCEL": 1, "OUT": 1, "IN": 1, "HOLD": 2,
    "FIRE": 1, "RESET": 0, "WHERE": 1, "STATUS": 0,
}
DIRECTION_NAMES = {1: "up", -1: "down", 0: "idle"}


class ConfigError(Exception):
    pass


def sign(value):
    if value > 0:
        return 1
    if value < 0:
        return -1
    return 0


def joined(items):
    return ",".join(items) if items else "-"


def average(total, count):
    if count == 0:
        return "-"
    hundredths = total * 100 // count
    return f"{hundredths // 100}.{hundredths % 100:02d}"


def bounded(key, text, low, high):
    value = int(text)
    if not low <= value <= high:
        raise ConfigError(f"bad value for {key}")
    return value


class Config:
    def __init__(self):
        self.floors = 0
        self.cars = 0
        self.capacity = 0
        self.door = 0
        self.starts = []
        self.policy = "COST"
        self.zones = []
        self.park_wait = None
        self.homes = []
        self.patience = None
        self.bypass = 100
        self.period = None
        self.limit = 1000
        self.compare = []

    def count_matches(self, key, count):
        if key in ("START", "ZONES"):
            return count == self.cars
        if key == "PARK":
            return count == self.cars + 1
        if key == "COMPARE":
            return 1 <= count <= 4
        return count == 1

    def zone(self, text):
        low_text, high_text = text.split(":")
        low, high = int(low_text), int(high_text)
        if not 1 <= low < high <= self.floors:
            raise ConfigError("bad value for ZONES")
        return low, high

    def apply(self, key, values):
        if not self.count_matches(key, len(values)):
            raise ConfigError(f"wrong number of values for {key}")
        if key == "FLOORS":
            self.floors = bounded(key, values[0], 2, 50)
        elif key == "CARS":
            self.cars = bounded(key, values[0], 1, 8)
        elif key == "CAPACITY":
            self.capacity = bounded(key, values[0], 1, 20)
        elif key == "DOOR":
            self.door = bounded(key, values[0], 1, 9)
        elif key == "START":
            self.starts = [bounded(key, value, 1, self.floors) for value in values]
        elif key == "POLICY":
            if values[0] not in POLICIES:
                raise ConfigError(f"bad value for {key}")
            self.policy = values[0]
        elif key == "ZONES":
            self.zones = [self.zone(value) for value in values]
        elif key == "PARK":
            self.park_wait = bounded(key, values[0], 0, 100)
            self.homes = [bounded(key, value, 1, self.floors) for value in values[1:]]
        elif key == "PATIENCE":
            self.patience = bounded(key, values[0], 1, 1000)
        elif key == "BYPASS":
            self.bypass = bounded(key, values[0], 50, 100)
        elif key == "PERIOD":
            self.period = bounded(key, values[0], 1, 1000)
        elif key == "LIMIT":
            self.limit = bounded(key, values[0], 1, 5000)
        else:
            invalid = any(value not in POLICIES for value in values)
            if invalid or len(set(values)) != len(values):
                raise ConfigError(f"bad value for {key}")
            self.compare = values

    def check_cars(self):
        for index in range(self.cars):
            low, high = self.zones[index]
            if not low <= self.starts[index] <= high:
                raise ConfigError(f"car {index + 1} starts outside its zone")
            if self.park_wait is not None and not low <= self.homes[index] <= high:
                raise ConfigError(f"car {index + 1} home outside its zone")

    def home(self, index):
        return self.homes[index] if self.park_wait is not None else None

    def served(self, landing, destination):
        return any(
            low <= landing <= high and low <= destination <= high
            for low, high in self.zones
        )

    def header_lines(self):
        park = "off" if self.park_wait is None else self.park_wait
        patience = "off" if self.patience is None else self.patience
        period = "off" if self.period is None else self.period
        lines = [
            f"config: floors={self.floors} cars={self.cars} capacity={self.capacity} "
            f"door={self.door} policy={self.policy} park={park} patience={patience} "
            f"bypass={self.bypass} period={period} limit={self.limit} "
            f"compare={joined(self.compare)}"
        ]
        for index in range(self.cars):
            low, high = self.zones[index]
            home = self.home(index)
            lines.append(
                f"E{index + 1}: start={self.starts[index]} zone={low}-{high} "
                f"home={'-' if home is None else home}"
            )
        return lines


def parse_config(settings):
    entries = {}
    for key, *values in settings:
        if key not in CONFIG_KEYS:
            raise ConfigError(f"unknown key {key}")
        if key in entries:
            raise ConfigError(f"duplicate key {key}")
        entries[key] = values
    for key in REQUIRED_KEYS:
        if key not in entries:
            raise ConfigError(f"missing key {key}")
    config = Config()
    for key in CONFIG_KEYS:
        if key in entries:
            config.apply(key, entries[key])
    if not config.zones:
        config.zones = [(1, config.floors)] * config.cars
    config.check_cars()
    return config


class Event:
    def __init__(self, time, command, values):
        self.time = time
        self.command = command
        self.values = values


class EventValidator:
    def __init__(self, config):
        self.config = config
        self.last_time = 0
        self.groups = 0
        self.out_cars = set()
        self.fire = False

    def problem(self, time, command, arguments):
        if command not in ARGUMENT_COUNTS:
            return f"unknown command {command}"
        if len(arguments) != ARGUMENT_COUNTS[command]:
            return f"wrong number of arguments for {command}"
        if time < self.last_time:
            return "time goes backwards"
        values = [int(argument) for argument in arguments]
        floors = self.config.floors
        cars = self.config.cars
        if command == "CALL":
            landing, destination, count = values
            if not (1 <= landing <= floors and 1 <= destination <= floors):
                return "bad floor"
            if landing == destination:
                return "same floor"
            if not 1 <= count <= 99:
                return "bad count"
            if not self.config.served(landing, destination):
                return f"no car serves {landing}->{destination}"
            if self.fire:
                return "fire service active"
        elif command in ("CANCEL", "WHERE"):
            if not 1 <= values[0] <= self.groups:
                return "unknown group"
        elif command in ("OUT", "IN"):
            car = values[0]
            if not 1 <= car <= cars:
                return "bad car"
            if command == "OUT" and car in self.out_cars:
                return f"car {car} already out"
            if command == "IN" and car not in self.out_cars:
                return f"car {car} already in"
        elif command == "HOLD":
            car, ticks = values
            if not 1 <= car <= cars:
                return "bad car"
            if not 1 <= ticks <= 9:
                return "bad ticks"
        elif command == "FIRE":
            if not 1 <= values[0] <= floors:
                return "bad floor"
            if self.fire:
                return "fire already active"
        elif command == "RESET" and not self.fire:
            return "fire not active"
        return None

    def accept(self, event):
        self.last_time = event.time
        if event.command == "CALL":
            self.groups += 1
        elif event.command == "OUT":
            self.out_cars.add(event.values[0])
        elif event.command == "IN":
            self.out_cars.discard(event.values[0])
        elif event.command == "FIRE":
            self.fire = True
        elif event.command == "RESET":
            self.fire = False


def validate_events(config, event_lines, output):
    validator = EventValidator(config)
    accepted = []
    for line, words in event_lines:
        time, command, arguments = int(words[0]), words[1], words[2:]
        message = validator.problem(time, command, arguments)
        if message is not None:
            output.append(f"line {line}: {message}")
            continue
        event = Event(time, command, [int(argument) for argument in arguments])
        validator.accept(event)
        accepted.append(event)
    return accepted


class Group:
    def __init__(self, number, landing, destination, count, time):
        self.number = number
        self.label = f"G{number}"
        self.landing = landing
        self.destination = destination
        self.count = count
        self.time = time
        self.direction = sign(destination - landing)
        self.waiting = count
        self.car = None
        self.boarded = 0
        self.delivered = 0
        self.lost = 0
        self.last_board = 0
        self.last_alight = 0
        self.cars = set()
        self.wait_total = 0
        self.travel_total = 0


class PassengerEntry:
    def __init__(self, group, count, board_time):
        self.group = group
        self.count = count
        self.board_time = board_time


class Car:
    def __init__(self, number, floor, zone, home):
        self.number = number
        self.label = f"E{number}"
        self.floor = floor
        self.low, self.high = zone
        self.home = home
        self.direction = 0
        self.door = 0
        self.passengers = []
        self.calls = []
        self.in_service = True
        self.idle_start = 0
        self.distance = 0
        self.stops = 0
        self.boarded = 0
        self.busy = 0
        self.energy = 0

    def serves(self, group):
        return (
            self.low <= group.landing <= self.high
            and self.low <= group.destination <= self.high
        )

    def load(self):
        return sum(entry.count for entry in self.passengers)

    def target_floors(self):
        floors = {entry.group.destination for entry in self.passengers}
        floors.update(group.landing for group in self.calls)
        return floors


def breakdown(label, groups):
    passengers = sum(group.count for group in groups)
    delivered = sum(group.delivered for group in groups)
    wait_total = sum(group.wait_total for group in groups)
    return (
        f"{label}: groups={len(groups)} passengers={passengers} "
        f"delivered={delivered} avg_wait={average(wait_total, delivered)}"
    )


class Simulation:
    def __init__(self, config, events, policy):
        self.config = config
        self.events = events
        self.policy = policy
        self.cars = [
            Car(index + 1, config.starts[index], config.zones[index], config.home(index))
            for index in range(config.cars)
        ]
        self.groups = []
        self.pending = []
        self.fire_floor = None
        self.last_round = 0
        self.time = 0
        self.status = None
        self.log = []
        self.abandoned = 0
        self.evacuated = 0
        self.delivered = 0
        self.wait_total = 0
        self.travel_total = 0
        self.max_wait = 0

    def emit(self, *parts):
        self.log.append(" ".join(str(part) for part in (self.time, *parts)))

    def run(self):
        handlers = {
            "CALL": self.call,
            "CANCEL": self.cancel,
            "OUT": self.take_out,
            "IN": self.put_in,
            "HOLD": self.hold,
            "FIRE": self.fire,
            "RESET": self.reset,
            "WHERE": self.where,
            "STATUS": self.show_status,
        }
        index = 0
        while True:
            if self.config.patience is not None:
                for group in self.groups:
                    if group.waiting > 0 and self.time == group.time + self.config.patience:
                        self.walk_away(group, "ABANDON")
            while index < len(self.events) and self.events[index].time == self.time:
                event = self.events[index]
                handlers[event.command](event.values)
                index += 1
            for car in self.cars:
                self.advance(car)
            if index == len(self.events) and all(self.settled(car) for car in self.cars):
                self.status = "end"
                self.emit("END")
                return
            if self.time == self.config.limit:
                self.status = "abort"
                self.emit("ABORT")
                return
            self.time += 1

    def settled(self, car):
        if car.door > 0 or car.passengers or car.calls:
            return False
        if self.fire_floor is not None:
            return car.floor == self.fire_floor
        return not car.in_service or car.home is None or car.floor == car.home

    def bypassing(self, car):
        return car.load() * 100 >= self.config.capacity * self.config.bypass

    def cost(self, car, group):
        floor = car.floor
        direction = car.direction
        landing = group.landing
        if self.policy == "NEAREST" or direction == 0:
            return abs(floor - landing)
        targets = car.target_floors()
        if group.direction == direction and (landing - floor) * direction >= 0:
            distance = abs(landing - floor)
            via = sum(
                1 for target in targets
                if (target - floor) * direction > 0 and (landing - target) * direction > 0
            )
        else:
            targets_and_floor = targets | {floor}
            turn = max(targets_and_floor) if direction > 0 else min(targets_and_floor)
            distance = abs(floor - turn) + abs(turn - landing)
            via = sum(1 for target in targets if (target - floor) * direction > 0)
        if self.policy == "COST":
            return distance
        return distance + self.config.door * via + car.door

    def assign(self, group, excluded=None):
        candidates = [
            car for car in self.cars
            if car.in_service and car is not excluded and car.serves(group)
        ]
        if not candidates:
            return False
        if self.policy == "ROUND":
            chosen = next(
                (car for car in candidates if car.number > self.last_round),
                candidates[0],
            )
            self.last_round = chosen.number
            self.emit(chosen.label, "ASSIGN", group.label)
        else:
            costs = [self.cost(car, group) for car in candidates]
            best = min(costs)
            chosen = candidates[costs.index(best)]
            self.emit(chosen.label, "ASSIGN", group.label, f"cost={best}")
        if group.car is not None:
            group.car.calls.remove(group)
        chosen.calls.append(group)
        group.car = chosen
        return True

    def dispatch(self, group):
        if not self.assign(group):
            self.pending.append(group)
            self.emit("PENDING", group.label)

    def walk_away(self, group, word):
        if group.car is not None:
            group.car.calls.remove(group)
            group.car = None
        else:
            self.pending.remove(group)
        self.emit(word, group.label, f"x{group.waiting}")
        group.lost += group.waiting
        self.abandoned += group.waiting
        group.waiting = 0

    def call(self, values):
        landing, destination, count = values
        group = Group(len(self.groups) + 1, landing, destination, count, self.time)
        self.groups.append(group)
        self.emit("CALL", group.label, f"{landing}->{destination}", f"x{count}")
        self.dispatch(group)

    def cancel(self, values):
        group = self.groups[values[0] - 1]
        if group.waiting > 0:
            self.walk_away(group, "CANCEL")
        else:
            self.emit("CANCEL", group.label, "ignored")

    def take_out(self, values):
        car = self.cars[values[0] - 1]
        car.in_service = False
        self.emit(car.label, "OUT")
        calls = car.calls
        car.calls = []
        for group in calls:
            group.car = None
            self.dispatch(group)

    def put_in(self, values):
        car = self.cars[values[0] - 1]
        car.in_service = True
        car.idle_start = self.time
        self.emit(car.label, "IN")
        waiting = self.pending
        self.pending = []
        for group in waiting:
            if not self.assign(group):
                self.pending.append(group)

    def hold(self, values):
        car = self.cars[values[0] - 1]
        if car.door > 0:
            car.door += values[1]
            self.emit(car.label, "HOLD", car.door)
        else:
            self.emit(car.label, "HOLD", "ignored")

    def fire(self, values):
        self.fire_floor = values[0]
        self.emit("FIRE", self.fire_floor)
        for group in self.groups:
            if group.waiting > 0:
                self.walk_away(group, "ABANDON")

    def reset(self, values):
        self.fire_floor = None
        self.emit("RESET")
        for car in self.cars:
            car.idle_start = self.time

    def where(self, values):
        group = self.groups[values[0] - 1]
        if group.waiting == 0:
            place = "-"
        elif group.car is not None:
            place = group.car.label
        else:
            place = "pending"
        riding = []
        for car in self.cars:
            count = sum(entry.count for entry in car.passengers if entry.group is group)
            if count > 0:
                riding.append(f"{car.label}x{count}")
        self.emit(
            "WHERE", group.label, f"waiting={group.waiting}", f"car={place}",
            f"riding={joined(riding)}", f"delivered={group.delivered}",
            f"lost={group.lost}",
        )

    def show_status(self, values):
        for car in self.cars:
            stops = sorted({entry.group.destination for entry in car.passengers})
            self.emit(
                "STATUS", car.label, f"floor={car.floor}",
                f"dir={DIRECTION_NAMES[car.direction]}", f"door={car.door}",
                f"load={car.load()}", f"stops={joined([str(stop) for stop in stops])}",
                f"calls={joined([group.label for group in car.calls])}",
                f"service={'in' if car.in_service else 'out'}",
            )
        self.emit("STATUS", f"pending={joined([group.label for group in self.pending])}")

    def choose_direction(self, car):
        floor = car.floor
        direction = car.direction
        here = []
        if not self.bypassing(car):
            here = [group for group in car.calls if group.landing == floor]
        targets = car.target_floors()
        if direction != 0:
            ahead = any((target - floor) * direction > 0 for target in targets)
            if ahead or any(group.direction == direction for group in here):
                return direction
        if here:
            return here[0].direction
        if direction != 0 and any((target - floor) * direction < 0 for target in targets):
            return -direction
        if direction == 0 and car.calls:
            return sign(car.calls[0].landing - floor)
        return 0

    def should_stop(self, car, heading):
        if any(entry.group.destination == car.floor for entry in car.passengers):
            return True
        if self.bypassing(car):
            return False
        return any(
            group.landing == car.floor and group.direction == heading
            for group in car.calls
        )

    def advance(self, car):
        floor = car.floor
        if car.door > 0:
            car.door -= 1
        if car.door == 0:
            self.decide(car)
        if car.door > 0 or car.floor != floor:
            car.busy += 1

    def decide(self, car):
        if self.fire_floor is not None:
            heading = sign(self.fire_floor - car.floor)
            stopping = heading == 0 and len(car.passengers) > 0
        else:
            heading = self.choose_direction(car)
            stopping = self.should_stop(car, heading)
        if stopping:
            self.open_doors(car)
        elif heading != 0:
            car.direction = heading
            self.move(car, heading)
        else:
            if car.direction != 0:
                self.emit(car.label, "IDLE", car.floor)
                car.direction = 0
                car.idle_start = self.time
            self.park(car)

    def move(self, car, step):
        if step > 0:
            car.energy += 3 + car.load()
        else:
            car.energy += 1
        car.distance += 1
        car.floor += step

    def park(self, car):
        if self.fire_floor is not None or not car.in_service or car.home is None:
            return
        if car.floor == car.home or self.time - car.idle_start < self.config.park_wait:
            return
        self.move(car, sign(car.home - car.floor))
        if car.floor == car.home:
            self.emit(car.label, "PARK", car.home)

    def open_doors(self, car):
        self.emit(car.label, "OPEN", car.floor)
        car.door = self.config.door
        car.stops += 1
        car.energy += 2
        riding = []
        for entry in car.passengers:
            if entry.group.destination == car.floor:
                self.emit(car.label, "ALIGHT", entry.group.label, f"x{entry.count}")
                self.deliver(entry)
            elif self.fire_floor is not None:
                self.emit(car.label, "EVACUATE", entry.group.label, f"x{entry.count}")
                entry.group.lost += entry.count
                self.evacuated += entry.count
            else:
                riding.append(entry)
        car.passengers = riding
        if self.fire_floor is not None:
            return
        heading = self.choose_direction(car)
        if heading != 0:
            car.direction = heading
        boarding = [
            group for group in car.calls
            if group.landing == car.floor and group.direction == heading
        ]
        for group in boarding:
            self.board(car, group)

    def board(self, car, group):
        count = min(self.config.capacity - car.load(), group.waiting)
        if count >= 1:
            car.passengers.append(PassengerEntry(group, count, self.time))
            car.boarded += count
            group.waiting -= count
            group.boarded += count
            group.last_board = self.time
            group.cars.add(car.number)
            self.emit(car.label, "BOARD", group.label, f"x{count}")
        if group.waiting == 0:
            car.calls.remove(group)
            group.car = None
        else:
            self.emit(car.label, "LEFT", group.label, f"x{group.waiting}")
            self.assign(group, car)

    def deliver(self, entry):
        group = entry.group
        wait = entry.board_time - group.time
        travel = self.time - group.time
        group.delivered += entry.count
        group.last_alight = self.time
        group.wait_total += wait * entry.count
        group.travel_total += travel * entry.count
        self.delivered += entry.count
        self.wait_total += wait * entry.count
        self.travel_total += travel * entry.count
        self.max_wait = max(self.max_wait, wait)

    def averages(self):
        max_wait = self.max_wait if self.delivered > 0 else "-"
        return (
            f"avg_wait={average(self.wait_total, self.delivered)} "
            f"avg_travel={average(self.travel_total, self.delivered)} max_wait={max_wait}"
        )

    def report(self, output):
        for group in self.groups:
            wait = group.last_board - group.time if group.boarded == group.count else "-"
            travel = group.last_alight - group.time if group.delivered == group.count else "-"
            cars = joined([str(number) for number in sorted(group.cars)])
            output.append(
                f"{group.label} t={group.time} {group.landing}->{group.destination} "
                f"n={group.count} delivered={group.delivered} lost={group.lost} "
                f"wait={wait} travel={travel} cars={cars}"
            )
        for car in self.cars:
            tenths = car.busy * 1000 // (self.time + 1)
            output.append(
                f"{car.label} distance={car.distance} stops={car.stops} "
                f"boarded={car.boarded} busy={car.busy} "
                f"util={tenths // 10}.{tenths % 10}% energy={car.energy}"
            )
        for floor in sorted({group.landing for group in self.groups}):
            floor_groups = [group for group in self.groups if group.landing == floor]
            output.append(breakdown(f"F{floor}", floor_groups))
        width = self.config.period
        if width is not None:
            for period in sorted({group.time // width for group in self.groups}):
                period_groups = [group for group in self.groups if group.time // width == period]
                label = f"P{period} {period * width}-{period * width + width - 1}"
                output.append(breakdown(label, period_groups))
        passengers = sum(group.count for group in self.groups)
        output.append(
            f"summary: groups={len(self.groups)} passengers={passengers} "
            f"delivered={self.delivered} abandoned={self.abandoned} "
            f"evacuated={self.evacuated} {self.averages()} end={self.time}"
        )


class Scenario:
    def __init__(self, name, settings, event_lines):
        self.name = name
        self.settings = settings
        self.event_lines = event_lines
        self.config = None
        self.simulation = None

    def outcome(self):
        if self.simulation is None:
            return "invalid"
        if self.simulation.status == "abort":
            return "aborted"
        if self.simulation.delivered == 0:
            return "empty"
        return "ranked"

    def process(self, output):
        output.append(f"== {self.name} ==")
        try:
            self.config = parse_config(self.settings)
        except ConfigError as error:
            output.append(f"error: {error}")
            return
        output.extend(self.config.header_lines())
        events = validate_events(self.config, self.event_lines, output)
        self.simulation = Simulation(self.config, events, self.config.policy)
        self.simulation.run()
        output.extend(self.simulation.log)
        self.simulation.report(output)
        for policy in self.config.compare:
            rerun = Simulation(self.config, events, policy)
            rerun.run()
            output.append(
                f"compare {policy}: delivered={rerun.delivered} {rerun.averages()} "
                f"end={rerun.time} status={rerun.status}"
            )


def read_scenarios(lines):
    scenarios = []
    index = 1
    for _ in range(int(lines[0])):
        name = lines[index].split(" ")[1]
        index += 1
        settings = []
        event_lines = []
        while lines[index] != "END":
            words = lines[index].split(" ")
            if words[0][0].isdigit():
                event_lines.append((index + 1, words))
            else:
                settings.append(words)
            index += 1
        index += 1
        scenarios.append(Scenario(name, settings, event_lines))
    return scenarios


def ranking_lines(scenarios, output):
    output.append("== ranking ==")
    ranked = [scenario for scenario in scenarios if scenario.outcome() == "ranked"]
    ranked.sort(key=lambda scenario: (
        Fraction(scenario.simulation.wait_total, scenario.simulation.delivered),
        Fraction(scenario.simulation.travel_total, scenario.simulation.delivered),
    ))
    for rank, scenario in enumerate(ranked, 1):
        output.append(
            f"{rank}. {scenario.name} policy={scenario.config.policy} "
            f"{scenario.simulation.averages()}"
        )
    for scenario in scenarios:
        outcome = scenario.outcome()
        if outcome != "ranked":
            output.append(f"- {scenario.name} {outcome}")
    output.append("== policies ==")
    for policy in POLICIES:
        runs = [scenario.simulation for scenario in ranked if scenario.config.policy == policy]
        if not runs:
            continue
        delivered = sum(run.delivered for run in runs)
        wait_total = sum(run.wait_total for run in runs)
        travel_total = sum(run.travel_total for run in runs)
        output.append(
            f"{policy}: runs={len(runs)} avg_wait={average(wait_total, delivered)} "
            f"avg_travel={average(travel_total, delivered)}"
        )


def main():
    lines = sys.stdin.read().splitlines()
    scenarios = read_scenarios(lines)
    output = []
    for scenario in scenarios:
        scenario.process(output)
    ranking_lines(scenarios, output)
    sys.stdout.write("\n".join(output) + "\n")


if __name__ == "__main__":
    main()
