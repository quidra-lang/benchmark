import sys


VEHICLE_TYPES = ("MOTORCYCLE", "CAR", "ECAR", "VAN", "BUS")
SPOT_KINDS = ("MOTO", "COMPACT", "LARGE", "EV")
PREFERENCES = {
    "MOTORCYCLE": ("MOTO", "COMPACT", "LARGE"),
    "CAR": ("COMPACT", "LARGE"),
    "ECAR": ("EV", "COMPACT", "LARGE"),
    "VAN": ("LARGE",),
}
TOTAL_FIELDS = (
    "entries", "exits", "refused", "stay", "parking", "night", "lost", "charge", "total"
)


def empty_totals():
    return dict.fromkeys(TOTAL_FIELDS, 0)


def sum_totals(rows):
    return {field: sum(row[field] for row in rows) for field in TOTAL_FIELDS}


def date_of(time):
    return time // 1440 + 1


def time_text(time):
    day, minutes = divmod(time, 1440)
    hour, minute = divmod(minutes, 60)
    return f"{day + 1}-{hour:02d}:{minute:02d}"


def duration_text(minutes):
    return f"{minutes // 60}:{minutes % 60:02d}"


class CommandError(Exception):
    pass


class Spot:
    def __init__(self, level, number, kind):
        self.level = level
        self.number = number
        self.kind = kind
        self.code = f"L{level}-{number}"
        self.closed = False
        self.vehicle = None

    def free(self):
        return not self.closed and self.vehicle is None

    def order(self):
        return self.level, self.number


class Level:
    def __init__(self, number, counts):
        self.number = number
        self.spots = []
        for kind, count in zip(SPOT_KINDS, counts):
            for _ in range(count):
                self.spots.append(Spot(number, len(self.spots) + 1, kind))

    def bus_assignment(self):
        for start in range(len(self.spots) - 2):
            triple = self.spots[start:start + 3]
            if all(spot.kind == "LARGE" and spot.free() for spot in triple):
                return triple
        return None

    def bus_capacity(self):
        count = 0
        run = 0
        for spot in self.spots:
            if spot.kind == "LARGE" and spot.free():
                run += 1
            else:
                count += run // 3
                run = 0
        return count + run // 3

    def occupancy(self):
        used = {kind: 0 for kind in SPOT_KINDS}
        available = {kind: 0 for kind in SPOT_KINDS}
        closed = 0
        for spot in self.spots:
            if spot.closed:
                closed += 1
            else:
                available[spot.kind] += 1
            if spot.vehicle is not None:
                used[spot.kind] += 1
        return used, available, closed


class Vehicle:
    def __init__(self, plate, kind, spots, entered):
        self.plate = plate
        self.kind = kind
        self.spots = spots
        self.entered = entered
        self.energy = 0
        self.charge_cost = 0
        self.validation = 0
        self.payment = None

    def location(self):
        first = self.spots[0]
        if self.kind == "BUS":
            return first.code + ".." + str(self.spots[-1].number)
        return first.code

    def order(self):
        return self.spots[0].order()


class WaitingVehicle:
    def __init__(self, plate, kind, joined):
        self.plate = plate
        self.kind = kind
        self.joined = joined


class ExitRecord:
    def __init__(self, vehicle, exited, total, lost):
        self.entered = vehicle.entered
        self.exited = exited
        self.location = vehicle.location()
        self.kind = vehicle.kind
        self.total = total
        self.lost = lost


class Garage:
    def __init__(self):
        self.now = 0
        self.levels = []
        self.spots = []
        self.spot_codes = {}
        self.vehicles = {}
        self.queue = []
        self.passes = {}
        self.history = {}
        self.rates = {
            "MOTORCYCLE": (100, 800), "CAR": (200, 1600),
            "ECAR": (200, 1600), "VAN": (300, 2400), "BUS": (600, 4800),
        }
        self.fees = {"NIGHT": 300, "LOST": 2000, "KWH": 30}
        self.totals = {kind: empty_totals() for kind in VEHICLE_TYPES}
        self.daily_totals = {}
        self.peak = 0
        self.peak_time = None
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def require_vehicle(self, plate):
        if plate not in self.vehicles:
            raise CommandError(f"{plate} is not parked")
        return self.vehicles[plate]

    def require_spot(self, code):
        if code not in self.spot_codes:
            raise CommandError(f"unknown spot {code}")
        return self.spot_codes[code]

    def require_unpaid(self, vehicle):
        if vehicle.payment is not None:
            raise CommandError(f"{vehicle.plate} has already paid")

    def has_pass(self, plate, time=None):
        time = self.now if time is None else time
        return plate in self.passes and date_of(time) <= self.passes[plate]

    def day_totals(self, day):
        if day not in self.daily_totals:
            self.daily_totals[day] = {kind: empty_totals() for kind in VEHICLE_TYPES}
        return self.daily_totals[day]

    def add_count(self, kind, field, day):
        self.totals[kind][field] += 1
        self.day_totals(day)[kind][field] += 1

    def assignment(self, kind):
        if kind == "BUS":
            for level in self.levels:
                triple = level.bus_assignment()
                if triple is not None:
                    return triple
            return None
        for preferred in PREFERENCES[kind]:
            for spot in self.spots:
                if spot.kind == preferred and spot.free():
                    return [spot]
        return None

    def park(self, plate, kind, spots):
        vehicle = Vehicle(plate, kind, spots, self.now)
        self.vehicles[plate] = vehicle
        for spot in spots:
            spot.vehicle = vehicle
        self.add_count(kind, "entries", date_of(self.now))
        if len(self.vehicles) > self.peak:
            self.peak = len(self.vehicles)
            self.peak_time = self.now
        return vehicle

    def give_up(self):
        remaining = []
        for waiting in self.queue:
            deadline = waiting.joined + 30
            if deadline <= self.now:
                self.emit("GIVEUP", waiting.plate, waiting.kind, time_text(deadline))
                self.add_count(waiting.kind, "refused", date_of(deadline))
            else:
                remaining.append(waiting)
        self.queue = remaining

    def process_queue(self):
        remaining = []
        for waiting in self.queue:
            spots = self.assignment(waiting.kind)
            if spots is None:
                remaining.append(waiting)
            else:
                vehicle = self.park(waiting.plate, waiting.kind, spots)
                self.emit(
                    "ADMIT", waiting.plate, waiting.kind, vehicle.location(),
                    "waited", duration_text(self.now - waiting.joined),
                )
        self.queue = remaining

    def interval_fees(self, vehicle, start, end, free_minutes):
        stay = end - start
        if self.has_pass(vehicle.plate, end) or stay <= free_minutes:
            return 0, 0
        rate, cap = self.rates[vehicle.kind]
        parking = 0
        for offset in range(0, stay, 1440):
            minutes = min(stay - offset, 1440)
            billable = minutes - free_minutes if offset == 0 else minutes
            parking += min(((billable + 29) // 30) * rate, cap)
        night = (date_of(end) - date_of(start)) * self.fees["NIGHT"]
        return parking, night

    def exit_charges(self, vehicle, lost=False):
        if vehicle.payment is None:
            parking, night = self.interval_fees(
                vehicle, vehicle.entered, self.now, 15 + vehicle.validation
            )
            lost_fee = self.fees["LOST"] if lost else 0
            total = parking + night + lost_fee + vehicle.charge_cost
            due = total
        else:
            paid_time, paid_parking, paid_night = vehicle.payment
            additional, additional_night = self.interval_fees(vehicle, paid_time, self.now, 15)
            parking = paid_parking + additional
            night = paid_night + additional_night
            lost_fee = 0
            total = parking + night + vehicle.charge_cost
            due = additional + additional_night
        return {
            "parking": parking, "night": night, "lost": lost_fee,
            "charge": vehicle.charge_cost, "total": total, "due": due,
        }

    def fee_line(self, label, vehicle, charges):
        self.emit(
            label, vehicle.plate, vehicle.location(),
            "stay", duration_text(self.now - vehicle.entered),
            "parking", charges["parking"], "night", charges["night"],
            "lost", charges["lost"], "charge", charges["charge"],
            "total", charges["total"], "due", charges["due"],
        )

    def annotation(self, vehicle):
        parts = []
        if self.has_pass(vehicle.plate):
            parts.append("PASS")
        if vehicle.validation:
            parts.extend(("VAL", str(vehicle.validation)))
        if vehicle.energy:
            parts.extend(("KWH", str(vehicle.energy)))
        if vehicle.payment is not None:
            parts.append("PAID")
        return " " + " ".join(parts) if parts else ""

    def add_level(self, arguments):
        counts = [int(value) for value in arguments]
        level = Level(len(self.levels) + 1, counts)
        self.levels.append(level)
        self.spots.extend(level.spots)
        self.spot_codes.update((spot.code, spot) for spot in level.spots)
        parts = ["LEVEL", level.number, "spots", len(level.spots)]
        for kind, count in zip(SPOT_KINDS, counts):
            parts.extend((kind, count))
        self.emit(*parts)
        self.process_queue()

    def close_spot(self, arguments):
        spot = self.require_spot(arguments[0])
        if spot.closed:
            raise CommandError(f"spot {spot.code} is already closed")
        if spot.vehicle is not None:
            raise CommandError(f"spot {spot.code} is occupied by {spot.vehicle.plate}")
        spot.closed = True
        self.emit("CLOSE", spot.code, spot.kind)

    def open_spot(self, arguments):
        spot = self.require_spot(arguments[0])
        if not spot.closed:
            raise CommandError(f"spot {spot.code} is not closed")
        spot.closed = False
        self.emit("OPEN", spot.code, spot.kind)
        self.process_queue()

    def set_rate(self, arguments):
        kind, rate_text, cap_text = arguments
        if kind not in self.rates:
            raise CommandError(f"unknown type {kind}")
        rate, cap = int(rate_text), int(cap_text)
        if cap < rate:
            raise CommandError(f"cap below rate for {kind}")
        self.rates[kind] = rate, cap
        self.emit("RATE", kind, rate, cap)

    def set_fee(self, arguments):
        item, amount = arguments
        if item not in self.fees:
            raise CommandError(f"unknown fee {item}")
        self.fees[item] = int(amount)
        self.emit("FEE", item, int(amount))

    def enter(self, arguments):
        plate, kind = arguments
        if kind not in self.rates:
            raise CommandError(f"unknown type {kind}")
        if plate in self.vehicles:
            location = self.vehicles[plate].location()
            raise CommandError(f"{plate} is already parked at {location}")
        if any(waiting.plate == plate for waiting in self.queue):
            raise CommandError(f"{plate} is already waiting")
        spots = self.assignment(kind)
        if spots is not None:
            vehicle = self.park(plate, kind, spots)
            self.emit("ENTER", plate, kind, vehicle.location())
        elif len(self.queue) < 3:
            self.queue.append(WaitingVehicle(plate, kind, self.now))
            self.emit("WAIT", plate, kind, len(self.queue))
        else:
            self.emit("FULL", plate, kind)
            self.add_count(kind, "refused", date_of(self.now))

    def leave(self, arguments):
        plate = arguments[0]
        for index, waiting in enumerate(self.queue):
            if waiting.plate == plate:
                del self.queue[index]
                self.emit("LEAVE", plate, waiting.kind)
                return
        raise CommandError(f"{plate} is not waiting")

    def exit(self, arguments):
        vehicle = self.require_vehicle(arguments[0])
        lost = len(arguments) == 2
        if lost:
            self.require_unpaid(vehicle)
        charges = self.exit_charges(vehicle, lost)
        self.fee_line("EXIT", vehicle, charges)
        record = ExitRecord(vehicle, self.now, charges["total"], lost)
        self.history.setdefault(vehicle.plate, []).append(record)
        self.add_count(vehicle.kind, "exits", date_of(self.now))
        totals = self.totals[vehicle.kind]
        daily = self.day_totals(date_of(self.now))[vehicle.kind]
        for field in ("parking", "night", "lost", "charge", "total"):
            totals[field] += charges[field]
            daily[field] += charges[field]
        stay = self.now - vehicle.entered
        totals["stay"] += stay
        daily["stay"] += stay
        for spot in vehicle.spots:
            spot.vehicle = None
        del self.vehicles[vehicle.plate]
        self.process_queue()

    def pay(self, arguments):
        vehicle = self.require_vehicle(arguments[0])
        self.require_unpaid(vehicle)
        charges = self.exit_charges(vehicle)
        vehicle.payment = self.now, charges["parking"], charges["night"]
        self.emit(
            "PAY", vehicle.plate, "parking", charges["parking"],
            "night", charges["night"], "charge", charges["charge"],
            "total", charges["total"],
        )

    def quote(self, arguments):
        vehicle = self.require_vehicle(arguments[0])
        self.fee_line("QUOTE", vehicle, self.exit_charges(vehicle))

    def charge(self, arguments):
        vehicle = self.require_vehicle(arguments[0])
        energy = int(arguments[1])
        if vehicle.kind != "ECAR":
            raise CommandError(f"{vehicle.plate} is not an electric car")
        if vehicle.spots[0].kind != "EV":
            raise CommandError(f"{vehicle.plate} is not at a charger")
        self.require_unpaid(vehicle)
        if vehicle.energy + energy > 100:
            raise CommandError(f"charge limit exceeded for {vehicle.plate}")
        cost = energy * self.fees["KWH"]
        vehicle.energy += energy
        vehicle.charge_cost += cost
        self.emit(
            "CHARGE", vehicle.plate, "kwh", energy, "cost", cost,
            "stay_kwh", vehicle.energy, "stay_cost", vehicle.charge_cost,
        )

    def validate(self, arguments):
        vehicle = self.require_vehicle(arguments[0])
        self.require_unpaid(vehicle)
        minutes = int(arguments[1])
        if vehicle.validation + minutes > 180:
            raise CommandError(f"validation limit exceeded for {vehicle.plate}")
        vehicle.validation += minutes
        self.emit("VALIDATE", vehicle.plate, minutes, "total", vehicle.validation)

    def register_pass(self, arguments):
        plate, days = arguments
        days = int(days)
        if self.has_pass(plate):
            self.passes[plate] += days
        else:
            self.passes[plate] = date_of(self.now) + days - 1
        self.emit("PASS", plate, "until", self.passes[plate])

    def unpass(self, arguments):
        plate = arguments[0]
        if not self.has_pass(plate):
            raise CommandError(f"{plate} has no pass")
        del self.passes[plate]
        self.emit("UNPASS", plate)

    def move_vehicle(self, vehicle, spot):
        old = vehicle.location()
        vehicle.spots[0].vehicle = None
        vehicle.spots = [spot]
        spot.vehicle = vehicle
        self.emit("MOVE", vehicle.plate, old, "->", spot.code)

    def move(self, arguments):
        plate, code = arguments
        vehicle = self.require_vehicle(plate)
        if vehicle.kind == "BUS":
            raise CommandError(f"bus {plate} cannot be moved")
        spot = self.require_spot(code)
        if spot is vehicle.spots[0]:
            raise CommandError(f"{plate} is already at {code}")
        if spot.closed:
            raise CommandError(f"spot {code} is closed")
        if spot.vehicle is not None:
            raise CommandError(f"spot {code} is occupied by {spot.vehicle.plate}")
        if spot.kind not in PREFERENCES[vehicle.kind]:
            raise CommandError(f"{vehicle.kind} cannot use {spot.kind} spot {code}")
        self.move_vehicle(vehicle, spot)
        self.process_queue()

    def rebalance(self, arguments):
        targets = sorted(
            (v for v in self.vehicles.values() if v.kind != "BUS"),
            key=lambda vehicle: vehicle.order(),
        )
        moved = 0
        for vehicle in targets:
            preferences = PREFERENCES[vehicle.kind]
            rank = preferences.index(vehicle.spots[0].kind)
            if rank == 0:
                continue
            spots = self.assignment(vehicle.kind)
            if spots is not None and preferences.index(spots[0].kind) < rank:
                self.move_vehicle(vehicle, spots[0])
                moved += 1
        self.emit("REBALANCE", moved)
        self.process_queue()

    def where(self, arguments):
        plate = arguments[0]
        if plate in self.vehicles:
            vehicle = self.vehicles[plate]
            self.emit(
                "WHERE", plate, vehicle.location(), vehicle.kind,
                time_text(vehicle.entered), "stay",
                duration_text(self.now - vehicle.entered) + self.annotation(vehicle),
            )
            return
        for position, waiting in enumerate(self.queue, 1):
            if waiting.plate == plate:
                self.emit("WHERE", plate, "waiting", position)
                return
        if plate not in self.history:
            raise CommandError(f"unknown plate {plate}")
        self.emit("WHERE", plate, "gone", time_text(self.history[plate][-1].exited))

    def list_vehicles(self, arguments):
        level = int(arguments[0]) if arguments else None
        if level is not None and level > len(self.levels):
            raise CommandError(f"unknown level {level}")
        targets = [
            v for v in self.vehicles.values()
            if level is None or v.spots[0].level == level
        ]
        targets.sort(key=lambda vehicle: vehicle.order())
        self.emit("LIST", len(targets))
        for vehicle in targets:
            self.emit(
                vehicle.location(), vehicle.plate, vehicle.kind,
                time_text(vehicle.entered) + self.annotation(vehicle),
            )

    def show_map(self, arguments):
        self.emit("MAP", len(self.levels))
        for level in self.levels:
            symbols = []
            for spot in level.spots:
                if spot.closed:
                    symbols.append("#")
                elif spot.vehicle is not None:
                    symbols.append(spot.kind[0])
                else:
                    symbols.append(spot.kind[0].lower())
            text = "".join(symbols)
            self.emit("L" + str(level.number), *(text[i:i + 10] for i in range(0, len(text), 10)))

    def occupancy(self, arguments):
        self.emit("OCCUPANCY", "vehicles", len(self.vehicles), "waiting", len(self.queue))
        total_used = {kind: 0 for kind in SPOT_KINDS}
        total_available = {kind: 0 for kind in SPOT_KINDS}
        total_closed = 0
        for level in self.levels:
            used, available, closed = level.occupancy()
            parts = ["L" + str(level.number)]
            for kind in SPOT_KINDS:
                parts.extend((kind, f"{used[kind]}/{available[kind]}"))
                total_used[kind] += used[kind]
                total_available[kind] += available[kind]
            parts.extend(("closed", closed))
            total_closed += closed
            self.emit(*parts)
        parts = ["TOTAL"]
        for kind in SPOT_KINDS:
            parts.extend((kind, f"{total_used[kind]}/{total_available[kind]}"))
        available_count = sum(total_available.values())
        usage = sum(total_used.values()) * 1000 // available_count if available_count else 0
        parts.extend(("closed", total_closed, "rate", f"{usage // 10}.{usage % 10}%"))
        self.emit(*parts)

    def sign(self, arguments):
        parts = ["SIGN"]
        for kind in VEHICLE_TYPES:
            if kind == "BUS":
                count = sum(level.bus_capacity() for level in self.levels)
            else:
                count = sum(spot.free() and spot.kind in PREFERENCES[kind] for spot in self.spots)
            parts.extend((kind, count if count else "FULL"))
        self.emit(*parts)

    def show_rates(self, arguments):
        self.emit("RATES")
        for kind in VEHICLE_TYPES:
            self.emit(kind, *self.rates[kind])
        self.emit("NIGHT", self.fees["NIGHT"], "LOST", self.fees["LOST"], "KWH", self.fees["KWH"])

    def show_passes(self, arguments):
        plates = sorted(plate for plate in self.passes if self.has_pass(plate))
        self.emit("PASSES", len(plates))
        for plate in plates:
            parts = [plate, "until", self.passes[plate]]
            if plate in self.vehicles:
                parts.append("IN")
            self.emit(*parts)

    def overstay(self, arguments):
        hours = int(arguments[0])
        targets = [v for v in self.vehicles.values() if self.now - v.entered >= hours * 60]
        targets.sort(key=lambda vehicle: (vehicle.entered, vehicle.order()))
        self.emit("OVERSTAY", hours, len(targets))
        for vehicle in targets:
            self.emit(
                vehicle.location(), vehicle.plate, vehicle.kind,
                time_text(vehicle.entered), "stay", duration_text(self.now - vehicle.entered),
            )

    def show_history(self, arguments):
        plate = arguments[0]
        if plate not in self.history:
            raise CommandError(f"no history for {plate}")
        records = self.history[plate]
        self.emit("HISTORY", plate, "visits", len(records), "paid", sum(r.total for r in records))
        for record in records:
            parts = [
                time_text(record.entered), time_text(record.exited),
                record.location, record.kind, record.total,
            ]
            if record.lost:
                parts.append("LOST")
            self.emit(*parts)

    def revenue_line(self, label, totals):
        parts = [label, "exits", totals["exits"]]
        for field in ("parking", "night", "lost", "charge", "total"):
            parts.extend((field, totals[field]))
        self.emit(*parts)

    def revenue(self, arguments):
        self.emit("REVENUE")
        for kind in VEHICLE_TYPES:
            self.revenue_line(kind, self.totals[kind])
        self.revenue_line("TOTAL", sum_totals(self.totals.values()))

    def daily_line(self, prefix, totals):
        self.emit(
            *prefix, "entries", totals["entries"], "exits", totals["exits"],
            "refused", totals["refused"], "revenue", totals["total"],
        )

    def daily(self, arguments):
        day = int(arguments[0])
        totals = self.daily_totals.get(day)
        if totals is None:
            totals = {kind: empty_totals() for kind in VEHICLE_TYPES}
        self.daily_line(("DAILY", day), sum_totals(totals.values()))
        for kind in VEHICLE_TYPES:
            self.daily_line((kind,), totals[kind])

    def stats_line(self, label, totals):
        exits = totals["exits"]
        tenths = totals["stay"] * 10 // exits if exits else 0
        self.emit(
            label, "entries", totals["entries"], "exits", exits,
            "refused", totals["refused"], "avg_stay", f"{tenths // 10}.{tenths % 10}",
        )

    def stats(self, arguments):
        first_peak = "-" if self.peak_time is None else time_text(self.peak_time)
        self.emit("STATS", "parked", len(self.vehicles), "peak", self.peak, "at", first_peak)
        for kind in VEHICLE_TYPES:
            self.stats_line(kind, self.totals[kind])
        self.stats_line("ALL", sum_totals(self.totals.values()))

    def execute(self, line):
        day, clock, command, *arguments = line.split()
        hour, minute = (int(part) for part in clock.split(":"))
        self.now = (int(day) - 1) * 1440 + hour * 60 + minute
        self.give_up()
        handlers = {
            "LEVEL": self.add_level,
            "CLOSE": self.close_spot,
            "OPEN": self.open_spot,
            "RATE": self.set_rate,
            "FEE": self.set_fee,
            "ENTER": self.enter,
            "LEAVE": self.leave,
            "EXIT": self.exit,
            "PAY": self.pay,
            "QUOTE": self.quote,
            "CHARGE": self.charge,
            "VALIDATE": self.validate,
            "PASS": self.register_pass,
            "UNPASS": self.unpass,
            "MOVE": self.move,
            "REBALANCE": self.rebalance,
            "WHERE": self.where,
            "LIST": self.list_vehicles,
            "MAP": self.show_map,
            "OCCUPANCY": self.occupancy,
            "SIGN": self.sign,
            "RATES": self.show_rates,
            "PASSES": self.show_passes,
            "OVERSTAY": self.overstay,
            "HISTORY": self.show_history,
            "REVENUE": self.revenue,
            "DAILY": self.daily,
            "STATS": self.stats,
        }
        try:
            handlers[command](arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    garage = Garage()
    count = int(sys.stdin.readline())
    for _ in range(count):
        garage.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(garage.output) + "\n")


if __name__ == "__main__":
    main()
