import sys


CLASSES = ("F", "J", "Y")
TIER_ORDER = {"PLATINUM": 0, "GOLD": 1, "SILVER": 2, "NONE": 3}
KIND_ORDER = {"W": 0, "M": 1, "A": 2}


class CommandError(Exception):
    pass


class Seat:
    def __init__(self, cabin, row, block, position, letter, kind):
        self.cabin = cabin
        self.row = row
        self.block = block
        self.position = position
        self.letter = letter
        self.kind = kind
        self.code = str(row) + letter

    def order(self):
        return self.row, self.letter


class Cabin:
    def __init__(self, name, first, last, blocks):
        self.name = name
        self.first = first
        self.last = last
        self.blocks = blocks
        self.rows = {}
        self.seats = []
        for row in range(first, last + 1):
            row_blocks = []
            for block_number, letters in enumerate(blocks):
                seats = []
                for position, letter in enumerate(letters):
                    at_left_window = block_number == 0 and position == 0
                    at_right_window = (
                        block_number == len(blocks) - 1
                        and position == len(letters) - 1
                    )
                    if at_left_window or at_right_window:
                        kind = "W"
                    elif position == 0 or position == len(letters) - 1:
                        kind = "A"
                    else:
                        kind = "M"
                    seat = Seat(name, row, block_number, position, letter, kind)
                    seats.append(seat)
                    self.seats.append(seat)
                row_blocks.append(seats)
            self.rows[row] = row_blocks

    def candidates(self, count):
        for blocks in self.rows.values():
            for block in blocks:
                for start in range(len(block) - count + 1):
                    yield "BLOCK", block[start:start + count]
        for blocks in self.rows.values():
            row_seats = [seat for block in blocks for seat in block]
            for start in range(len(row_seats) - count + 1):
                yield "ROW", row_seats[start:start + count]
        for height in range(2, count + 1):
            width = (count + height - 1) // height
            used_rows = (count + width - 1) // width
            for first_row, blocks in self.rows.items():
                if first_row + used_rows - 1 > self.last:
                    continue
                for block_number, block in enumerate(blocks):
                    for start in range(len(block) - width + 1):
                        candidate = []
                        for index in range(count):
                            row = first_row + index // width
                            column = start + index % width
                            candidate.append(self.rows[row][block_number][column])
                        yield "STACK", candidate


class Aircraft:
    def __init__(self, model, base_row, limit):
        self.model = model
        self.base_row = base_row
        self.limit = limit
        self.cabins = {}
        self.seats = {}
        self.exit_rows = set()
        self.blocked = set()
        self.capacities = {}

    def add_cabin(self, name, first, last, blocks):
        cabin = Cabin(name, first, last, blocks)
        self.cabins[name] = cabin
        for seat in cabin.seats:
            self.seats[seat.code] = seat

    def finish(self):
        for name in CLASSES:
            if name in self.cabins:
                self.capacities[name] = sum(
                    seat.code not in self.blocked
                    for seat in self.cabins[name].seats
                )

    def class_order(self):
        return [name for name in CLASSES if name in self.cabins]


class Passenger:
    def __init__(self, booking, descriptor, cabin):
        parts = descriptor.split(":")
        self.booking = booking
        self.name = parts[0]
        self.kind = parts[1]
        self.preference = parts[2] if len(parts) == 3 else None
        self.cabin = cabin
        self.seat = None
        self.infant = None
        self.adult = None

    def needs_seat(self):
        return self.kind != "INFANT"

    def result(self):
        if not self.needs_seat():
            return "LAP"
        if self.seat is None:
            return "UNASSIGNED"
        return self.seat.code


class Booking:
    def __init__(self, pnr, flight, cabin, descriptors):
        self.pnr = pnr
        self.flight = flight
        self.checked = False
        self.passengers = [Passenger(self, item, cabin) for item in descriptors]
        adults = [p for p in self.passengers if p.kind == "ADULT"]
        infants = [p for p in self.passengers if p.kind == "INFANT"]
        for adult, infant in zip(adults, infants):
            adult.infant = infant
            infant.adult = adult

    def passenger(self, name):
        for passenger in self.passengers:
            if passenger.name == name:
                return passenger
        raise CommandError(f"no passenger {name} in {self.pnr}")

    def has_infant(self):
        return any(p.kind == "INFANT" for p in self.passengers)

    def state(self):
        return "CHECKED" if self.checked else "NOT-CHECKED"


class Flight:
    def __init__(self, name, aircraft, overbook):
        self.name = name
        self.aircraft = aircraft
        self.blocked = set(aircraft.blocked)
        self.limits = {
            cabin: count * (100 + overbook) // 100
            for cabin, count in aircraft.capacities.items()
        }
        self.bookings = []
        self.occupants = {}
        self.volunteers = []
        self.closed = False

    def require_open(self):
        if self.closed:
            raise CommandError(f"flight {self.name} is closed")

    def require_cabin(self, cabin):
        if cabin not in self.aircraft.cabins:
            raise CommandError(f"no cabin {cabin} on {self.name}")
        return self.aircraft.cabins[cabin]

    def passengers(self):
        return [p for booking in self.bookings for p in booking.passengers]

    def booked_count(self, cabin):
        return sum(p.needs_seat() and p.cabin == cabin for p in self.passengers())

    def unassigned(self):
        return [p for p in self.passengers() if p.needs_seat() and p.seat is None]

    def infant_conflict(self, passenger, seat, ignored=(), proposed=()):
        if passenger.infant is None:
            return False
        cabin = self.aircraft.cabins[seat.cabin]
        for neighbor in cabin.rows[seat.row][seat.block]:
            other = self.occupants.get(neighbor.code)
            if other is None:
                continue
            if other is passenger or other in ignored or other.infant is None:
                continue
            return True
        for other, destination in proposed:
            if other is passenger or other.infant is None:
                continue
            if destination.row == seat.row and destination.block == seat.block:
                return True
        return False

    def can_sit(self, passenger, seat, cabin=None, ignored=(), proposed=()):
        if seat.cabin != (passenger.cabin if cabin is None else cabin):
            return False
        if seat.code in self.blocked:
            return False
        occupant = self.occupants.get(seat.code)
        if occupant is not None and occupant not in ignored:
            return False
        if passenger.kind == "CHILD" or passenger.infant is not None:
            if seat.row in self.aircraft.exit_rows:
                return False
        return not self.infant_conflict(passenger, seat, ignored, proposed)

    def choose_seat(self, passenger, cabin=None):
        name = passenger.cabin if cabin is None else cabin
        candidates = [
            seat for seat in self.aircraft.cabins[name].seats
            if self.can_sit(passenger, seat, name)
        ]
        if passenger.preference is not None:
            preferred = [s for s in candidates if s.kind == passenger.preference]
            if preferred:
                return preferred[0]
        return candidates[0] if candidates else None

    def vacate(self, passenger):
        if passenger.seat is not None:
            del self.occupants[passenger.seat.code]
            passenger.seat = None

    def place(self, passenger, seat):
        self.vacate(passenger)
        passenger.seat = seat
        if seat is not None:
            self.occupants[seat.code] = passenger

    def assign_booking(self, booking, cabin):
        people = [p for p in booking.passengers if p.needs_seat()]
        if len(people) == 1:
            self.place(people[0], self.choose_seat(people[0]))
            return "SINGLE"
        for method, seats in self.aircraft.cabins[cabin].candidates(len(people)):
            proposed = list(zip(people, seats))
            if all(self.can_sit(p, s, proposed=proposed) for p, s in proposed):
                for passenger, seat in proposed:
                    self.place(passenger, seat)
                return method
        for passenger in people:
            self.place(passenger, self.choose_seat(passenger))
        return "SPLIT"

    def reassign(self, emit):
        for passenger in self.unassigned():
            seat = self.choose_seat(passenger)
            if seat is not None:
                self.place(passenger, seat)
                emit("REASSIGNED", passenger.booking.pnr, passenger.name, seat.code)

    def removal_targets(self, booking, passenger=None):
        if passenger is None:
            return list(booking.passengers)
        targets = {passenger}
        if passenger.infant is not None:
            targets.add(passenger.infant)
        return [p for p in booking.passengers if p in targets]

    def remove(self, booking, targets):
        removed = set(targets)
        for passenger in targets:
            self.vacate(passenger)
            if passenger.adult is not None:
                passenger.adult.infant = None
                passenger.adult = None
            if passenger.infant is not None:
                passenger.infant.adult = None
                passenger.infant = None
        booking.passengers = [p for p in booking.passengers if p not in removed]
        self.volunteers = [p for p in self.volunteers if p not in removed]


class BookingDesk:
    def __init__(self):
        self.aircraft = {}
        self.flights = {}
        self.bookings = {}
        self.tiers = {}
        self.defining = None
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def flight(self, name, must_be_open=False):
        if name not in self.flights:
            raise CommandError(f"unknown flight {name}")
        flight = self.flights[name]
        if must_be_open:
            flight.require_open()
        return flight

    def booking(self, pnr, must_be_open=False):
        booking = self.bookings.get(pnr)
        if booking is None or not booking.passengers:
            raise CommandError(f"unknown PNR {pnr}")
        if must_be_open:
            booking.flight.require_open()
        return booking

    def tier(self, passenger):
        return self.tiers.get(passenger.name, "NONE")

    def define_aircraft(self, arguments):
        model, base, limit = arguments
        self.defining = Aircraft(model, int(base), int(limit))

    def define_cabin(self, arguments):
        name, first, last, *blocks = arguments
        self.defining.add_cabin(name, int(first), int(last), blocks)

    def define_exits(self, arguments):
        self.defining.exit_rows = {int(row) for row in arguments}

    def define_blocked(self, arguments):
        self.defining.blocked = set(arguments)

    def end_aircraft(self, arguments):
        aircraft = self.defining
        aircraft.finish()
        self.aircraft[aircraft.model] = aircraft
        parts = ["AIRCRAFT", aircraft.model]
        for cabin in aircraft.class_order():
            parts.extend((cabin, aircraft.capacities[cabin]))
        self.emit(*parts)
        self.defining = None

    def book(self, arguments):
        pnr, flight_name, cabin, *descriptors = arguments
        if pnr in self.bookings:
            raise CommandError(f"duplicate PNR {pnr}")
        flight = self.flight(flight_name, True)
        flight.require_cabin(cabin)
        names = [descriptor.split(":")[0] for descriptor in descriptors]
        seen = set()
        for name in names:
            if name in seen:
                raise CommandError(f"duplicate name {name} in {pnr}")
            seen.add(name)
        existing_names = {p.name for p in flight.passengers()}
        for name in names:
            if name in existing_names:
                raise CommandError(f"{name} already on {flight_name}")
        kinds = [descriptor.split(":")[1] for descriptor in descriptors]
        adults = kinds.count("ADULT")
        infants = kinds.count("INFANT")
        if adults == 0:
            raise CommandError(f"no adult in {pnr}")
        if infants > adults:
            raise CommandError(f"too many infants in {pnr}")
        if flight.booked_count(cabin) + len(kinds) - infants > flight.limits[cabin]:
            raise CommandError(f"limit exceeded for {flight_name} {cabin}")
        booking = Booking(pnr, flight, cabin, descriptors)
        self.bookings[pnr] = booking
        flight.bookings.append(booking)
        method = flight.assign_booking(booking, cabin)
        results = [p.name + ":" + p.result() for p in booking.passengers]
        self.emit("BOOKED", pnr, flight_name, cabin, method, *results)

    def change_seat(self, arguments):
        pnr, name, code = arguments
        booking = self.booking(pnr, True)
        passenger = booking.passenger(name)
        flight = booking.flight
        if not passenger.needs_seat():
            raise CommandError(f"infant {name} has no seat")
        seat = flight.aircraft.seats.get(code)
        if seat is None or seat.cabin != passenger.cabin:
            raise CommandError(f"no seat {code} in cabin {passenger.cabin}")
        if code in flight.blocked:
            raise CommandError(f"seat {code} is blocked")
        if code in flight.occupants:
            raise CommandError(f"seat {code} is occupied")
        if passenger.kind == "CHILD" or passenger.infant is not None:
            if seat.row in flight.aircraft.exit_rows:
                raise CommandError(f"exit row {seat.row} not allowed for {name}")
        if flight.infant_conflict(passenger, seat):
            raise CommandError(f"infant limit reached at {code}")
        old = passenger.seat.code
        flight.place(passenger, seat)
        self.emit("MOVED", pnr, name, old, "->", code)
        flight.reassign(self.emit)

    def swap(self, arguments):
        pnr1, name1, pnr2, name2 = arguments
        booking1 = self.booking(pnr1, True)
        first = booking1.passenger(name1)
        booking2 = self.booking(pnr2, True)
        second = booking2.passenger(name2)
        if first is second:
            raise CommandError(f"cannot swap {name1} with itself")
        for passenger in (first, second):
            if not passenger.needs_seat():
                raise CommandError(f"infant {passenger.name} has no seat")
        if booking1.flight is not booking2.flight:
            raise CommandError(f"{pnr1} and {pnr2} are on different flights")
        if first.cabin != second.cabin:
            raise CommandError(f"{name1} and {name2} are in different cabins")
        for passenger in (first, second):
            if passenger.seat is None:
                raise CommandError(f"{passenger.name} has no seat")
        flight = booking1.flight
        first_seat, second_seat = first.seat, second.seat
        proposed = ((first, second_seat), (second, first_seat))
        ignored = (first, second)
        if not all(
            flight.can_sit(p, s, ignored=ignored, proposed=proposed)
            for p, s in proposed
        ):
            raise CommandError(f"swap of {name1} and {name2} breaks seating rules")
        flight.vacate(first)
        flight.vacate(second)
        flight.place(first, second_seat)
        flight.place(second, first_seat)
        self.emit("SWAPPED", pnr1, name1, second_seat.code, pnr2, name2, first_seat.code)
        flight.reassign(self.emit)

    def cancel(self, arguments):
        pnr = arguments[0]
        booking = self.booking(pnr, True)
        flight = booking.flight
        if len(arguments) == 2:
            passenger = booking.passenger(arguments[1])
            targets = flight.removal_targets(booking, passenger)
            remaining = [p for p in booking.passengers if p not in targets]
            if remaining and not any(p.kind == "ADULT" for p in remaining):
                raise CommandError(f"{pnr} would have no adult")
        else:
            targets = flight.removal_targets(booking)
        names = [p.name for p in targets]
        flight.remove(booking, targets)
        self.emit("CANCELLED", pnr, *names)
        flight.reassign(self.emit)

    def status(self, arguments):
        name, tier = arguments
        self.tiers[name] = tier
        self.emit("STATUS", name, tier)

    def checkin(self, arguments):
        booking = self.booking(arguments[0], True)
        if booking.checked:
            raise CommandError(f"{booking.pnr} already checked in")
        booking.checked = True
        self.emit("CHECKIN", booking.pnr, len(booking.passengers))

    def volunteer(self, arguments):
        pnr, name = arguments
        booking = self.booking(pnr, True)
        passenger = booking.passenger(name)
        if passenger.kind != "ADULT" or passenger.infant is not None:
            raise CommandError(f"{name} cannot volunteer")
        if passenger.seat is None:
            raise CommandError(f"{name} has no seat")
        if passenger in booking.flight.volunteers:
            raise CommandError(f"{name} already volunteered")
        booking.flight.volunteers.append(passenger)
        self.emit("VOLUNTEER", pnr, name, passenger.seat.code)

    def upgrade(self, arguments):
        flight = self.flight(arguments[0], True)
        cabins = flight.aircraft.class_order()
        count = 0
        for higher, lower in zip(cabins, cabins[1:]):
            targets = [
                p for p in flight.passengers()
                if p.cabin == lower and p.kind == "ADULT"
                and p.infant is None and self.tier(p) != "NONE"
            ]
            targets.sort(key=lambda p: TIER_ORDER[self.tier(p)])
            for passenger in targets:
                if flight.booked_count(higher) >= flight.limits[higher]:
                    break
                seat = flight.choose_seat(passenger, higher)
                if seat is None:
                    break
                old = passenger.result()
                passenger.cabin = higher
                flight.place(passenger, seat)
                self.emit(
                    "UPGRADED", passenger.booking.pnr, passenger.name,
                    lower, old, "->", higher, seat.code,
                )
                count += 1
        flight.reassign(self.emit)
        self.emit("UPGRADE", flight.name, count)

    def deny(self, flight, passenger, voluntary):
        compensation = {"F": 500, "J": 300, "Y": 150}[passenger.cabin]
        if not voluntary:
            compensation *= 2
        if passenger.kind == "CHILD":
            compensation //= 2
        mode = "VOLUNTARY" if voluntary else "INVOLUNTARY"
        self.emit(
            "DENIED", mode, passenger.booking.pnr, passenger.name,
            passenger.cabin, compensation,
        )
        booking = passenger.booking
        flight.remove(booking, flight.removal_targets(booking, passenger))
        return compensation

    def close(self, arguments):
        flight = self.flight(arguments[0], True)
        for booking in flight.bookings:
            if booking.passengers and not booking.checked:
                self.emit("NOSHOW", booking.pnr, len(booking.passengers))
                flight.remove(booking, flight.removal_targets(booking))
        flight.reassign(self.emit)
        denied = 0
        total = 0
        for cabin in flight.aircraft.class_order():
            volunteers = [
                p for p in flight.volunteers
                if p.seat is not None and p.cabin == cabin
            ]
            for passenger in volunteers:
                seat = passenger.seat
                can_replace = any(
                    p.cabin == cabin
                    and flight.can_sit(p, seat, ignored=(passenger,))
                    for p in flight.unassigned()
                )
                if can_replace:
                    total += self.deny(flight, passenger, True)
                    denied += 1
                    flight.reassign(self.emit)
        for passenger in flight.unassigned():
            total += self.deny(flight, passenger, False)
            denied += 1
        flight.closed = True
        self.emit("CLOSED", flight.name, "denied", denied, "compensation", total)

    def change_block(self, arguments, blocked):
        name, code = arguments
        flight = self.flight(name, True)
        seat = flight.aircraft.seats.get(code)
        if seat is None:
            raise CommandError(f"no seat {code} on {name}")
        if blocked and code in flight.blocked:
            raise CommandError(f"seat {code} is blocked")
        if not blocked and code not in flight.blocked:
            raise CommandError(f"seat {code} is not blocked")
        if blocked:
            flight.blocked.add(code)
            self.emit("BLOCK", name, code)
            passenger = flight.occupants.get(code)
            if passenger is not None:
                flight.vacate(passenger)
                flight.place(passenger, flight.choose_seat(passenger))
                self.emit(
                    "DISPLACED", passenger.booking.pnr, passenger.name,
                    code, "->", passenger.result(),
                )
        else:
            flight.blocked.remove(code)
            self.emit("UNBLOCK", name, code)
        flight.reassign(self.emit)

    def create_flight(self, arguments):
        name, model, overbook = arguments
        if name in self.flights:
            raise CommandError(f"duplicate flight {name}")
        if model not in self.aircraft:
            raise CommandError(f"unknown aircraft {model}")
        flight = Flight(name, self.aircraft[model], int(overbook))
        self.flights[name] = flight
        parts = ["FLIGHT", name, model]
        for cabin in flight.aircraft.class_order():
            parts.extend((cabin, f"{flight.aircraft.capacities[cabin]}/{flight.limits[cabin]}"))
        self.emit(*parts)

    def show_map(self, arguments):
        flight = self.flight(arguments[0])
        self.emit("MAP", flight.name)
        for name in flight.aircraft.class_order():
            cabin = flight.aircraft.cabins[name]
            self.emit("CABIN", name)
            self.output.append("   " + " ".join(cabin.blocks))
            for row, blocks in cabin.rows.items():
                display_blocks = []
                for block in blocks:
                    characters = []
                    for seat in block:
                        if seat.code in flight.blocked:
                            character = "#"
                        elif seat.code in flight.occupants:
                            character = "X"
                        elif row in flight.aircraft.exit_rows:
                            character = "E"
                        else:
                            character = "."
                        characters.append(character)
                    display_blocks.append("".join(characters))
                self.emit(f"{row:2d}", *display_blocks)

    def manifest_line(self, flight, passenger):
        seat = passenger.seat.code if passenger.seat is not None else "---"
        parts = [
            seat, passenger.cabin, passenger.booking.pnr,
            passenger.name, passenger.kind,
        ]
        if passenger.infant is not None:
            parts.append("+" + passenger.infant.name)
        tier = self.tier(passenger)
        if tier != "NONE":
            parts.append(tier)
        if passenger.booking.checked:
            parts.append("CHECKED")
        if passenger in flight.volunteers:
            parts.append("VOL")
        self.emit(*parts)

    def manifest(self, arguments):
        flight = self.flight(arguments[0])
        passengers = flight.passengers()
        seated = [p for p in passengers if p.seat is not None]
        seated.sort(key=lambda p: p.seat.order())
        unassigned = flight.unassigned()
        infants = sum(p.kind == "INFANT" for p in passengers)
        self.emit(
            "MANIFEST", flight.name, "seated", len(seated),
            "unassigned", len(unassigned), "infants", infants,
        )
        for passenger in seated + unassigned:
            self.manifest_line(flight, passenger)

    def load_percentage(self, seated, seats):
        tenths = seated * 1000 // seats
        return f"{tenths // 10}.{tenths % 10}%"

    def loadfactor(self, arguments):
        flight = self.flight(arguments[0])
        self.emit("LOADFACTOR", flight.name)
        passengers = flight.passengers()
        total_seated = 0
        total_seats = 0
        for name in flight.aircraft.class_order():
            cabin = flight.aircraft.cabins[name]
            seats = sum(seat.code not in flight.blocked for seat in cabin.seats)
            seated = sum(p.cabin == name and p.seat is not None for p in passengers)
            booked = sum(p.cabin == name and p.needs_seat() for p in passengers)
            self.emit(
                name, f"{seated}/{seats}", self.load_percentage(seated, seats),
                "booked", f"{booked}/{flight.limits[name]}",
            )
            total_seated += seated
            total_seats += seats
        self.emit(
            "ALL", f"{total_seated}/{total_seats}",
            self.load_percentage(total_seated, total_seats),
        )

    def balance(self, arguments):
        flight = self.flight(arguments[0])
        aircraft = flight.aircraft
        weight = 0
        moment = 0
        for passenger in flight.passengers():
            if passenger.seat is None:
                continue
            current = 80 if passenger.kind == "ADULT" else 40
            if passenger.infant is not None:
                current += 10
            weight += current
            moment += current * (passenger.seat.row - aircraft.base_row)
        if moment < -aircraft.limit:
            verdict = "NOSE-HEAVY"
        elif moment > aircraft.limit:
            verdict = "TAIL-HEAVY"
        else:
            verdict = "OK"
        self.emit(
            "BALANCE", flight.name, "weight", weight, "moment", moment,
            "limit", aircraft.limit, verdict,
        )

    def boarding_group(self, flight, passenger):
        seat = passenger.seat
        if passenger.booking.has_infant():
            return "PRE", (0, seat.row, seat.letter)
        if passenger.cabin in ("F", "J"):
            return "CABIN", (1, seat.row, seat.letter)
        if self.tier(passenger) in ("PLATINUM", "GOLD"):
            return "TIER", (2, seat.row, seat.letter)
        start = flight.aircraft.cabins["Y"].first
        zone = (seat.row - start) // 5 + 1
        order = (3, -zone, KIND_ORDER[seat.kind], -seat.row, seat.letter)
        return "ZONE" + str(zone), order

    def boarding(self, arguments):
        flight = self.flight(arguments[0])
        entries = []
        for passenger in flight.passengers():
            if passenger.seat is not None:
                group, order = self.boarding_group(flight, passenger)
                entries.append((order, group, passenger))
        entries.sort(key=lambda item: item[0])
        self.emit("BOARDING", flight.name, len(entries))
        for number, (_, group, passenger) in enumerate(entries, 1):
            self.emit(
                number, group, passenger.seat.code,
                passenger.booking.pnr, passenger.name,
            )

    def avail(self, arguments):
        flight = self.flight(arguments[0])
        name = arguments[1]
        cabin = flight.require_cabin(name)
        free = [
            seat for seat in cabin.seats
            if seat.code not in flight.blocked and seat.code not in flight.occupants
        ]
        counts = {kind: sum(s.kind == kind for s in free) for kind in KIND_ORDER}
        exits = sum(s.row in flight.aircraft.exit_rows for s in free)
        self.emit(
            "AVAIL", flight.name, name, "free", len(free),
            "W", counts["W"], "M", counts["M"], "A", counts["A"], "EXIT", exits,
        )

    def info(self, arguments):
        booking = self.booking(arguments[0])
        self.emit(
            "INFO", booking.pnr, booking.flight.name,
            len(booking.passengers), booking.state(),
        )
        for passenger in booking.passengers:
            self.emit(passenger.name, passenger.kind, passenger.cabin, passenger.result())

    def find(self, arguments):
        name = arguments[0]
        matches = []
        for flight in self.flights.values():
            for passenger in flight.passengers():
                if passenger.name == name:
                    state = "CLOSED" if flight.closed else "OPEN"
                    matches.append((
                        flight.name, passenger.booking.pnr, passenger.cabin,
                        passenger.result(), state,
                    ))
                    break
        self.emit("FIND", name, self.tiers.get(name, "NONE"), len(matches))
        for match in matches:
            self.emit(*match)

    def execute(self, line):
        command, *arguments = line.split()
        handlers = {
            "AIRCRAFT": self.define_aircraft,
            "CABIN": self.define_cabin,
            "EXIT": self.define_exits,
            "BLOCKED": self.define_blocked,
            "END": self.end_aircraft,
            "FLIGHT": self.create_flight,
            "BOOK": self.book,
            "SEAT": self.change_seat,
            "SWAP": self.swap,
            "CANCEL": self.cancel,
            "STATUS": self.status,
            "CHECKIN": self.checkin,
            "VOLUNTEER": self.volunteer,
            "UPGRADE": self.upgrade,
            "CLOSE": self.close,
            "MAP": self.show_map,
            "MANIFEST": self.manifest,
            "LOADFACTOR": self.loadfactor,
            "BALANCE": self.balance,
            "BOARDING": self.boarding,
            "AVAIL": self.avail,
            "INFO": self.info,
            "FIND": self.find,
        }
        try:
            if command in ("BLOCK", "UNBLOCK"):
                self.change_block(arguments, command == "BLOCK")
            else:
                handlers[command](arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    desk = BookingDesk()
    command_count = int(sys.stdin.readline())
    for _ in range(command_count):
        desk.execute(sys.stdin.readline().rstrip("\n"))
    if desk.output:
        sys.stdout.write("\n".join(desk.output) + "\n")


if __name__ == "__main__":
    main()
