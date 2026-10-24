import sys


ROOM_TYPES = ("SINGLE", "DOUBLE", "SUITE")
WEEKDAYS = ("SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI")


class CommandError(Exception):
    pass


def leap(year):
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


def month_lengths(year):
    return (31, 29 if leap(year) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)


def date_number(text):
    year, month, day = (int(part) for part in text.split("-"))
    if not (2000 <= year <= 2099 and 1 <= month <= 12):
        raise CommandError(f"invalid date {text}")
    lengths = month_lengths(year)
    if not 1 <= day <= lengths[month - 1]:
        raise CommandError(f"invalid date {text}")
    years = sum(366 if leap(previous) else 365 for previous in range(2000, year))
    return years + sum(lengths[:month - 1]) + day - 1


def date_text(number):
    year = 2000
    while number >= (366 if leap(year) else 365):
        number -= 366 if leap(year) else 365
        year += 1
    month = 1
    for length in month_lengths(year):
        if number < length:
            break
        number -= length
        month += 1
    return f"{year:04d}-{month:02d}-{number + 1:02d}"


def date_weekday(number):
    return date_text(number) + " " + WEEKDAYS[number % 7]


def cents(text):
    whole, fraction = text.split(".")
    return int(whole) * 100 + int(fraction)


def money(value):
    return f"{value // 100}.{value % 100:02d}"


class Room:
    def __init__(self, number, kind, rate):
        self.number = number
        self.kind = kind
        self.rate = rate
        self.clean = True


class Reservation:
    def __init__(self, identifier, guest, room, arrival, departure, nights):
        self.identifier = identifier
        self.guest = guest
        self.room = room
        self.arrival = arrival
        self.departure = departure
        self.nights = nights
        self.status = "booked"
        self.extras = []
        self.deposit = 0
        self.paid = 0
        self.posting = None
        self.fee = 0
        self.penalty = None
        self.bill = None

    def lodging(self):
        return sum(rate for _, _, rate in self.nights)

    def first_rate(self):
        return self.nights[0][2]


class WaitingEntry:
    def __init__(self, identifier, guest, kind, arrival, departure):
        self.identifier = identifier
        self.guest = guest
        self.kind = kind
        self.arrival = arrival
        self.departure = departure


class HotelDesk:
    def __init__(self):
        self.today = date_number("2026-01-01")
        self.rooms = {}
        self.seasons = []
        self.blocks = set()
        self.reservations = {}
        self.waitlist = []
        self.used_ids = set()
        self.occupied = {}
        self.output = []

    def emit(self, *parts, indent=0):
        self.output.append(" " * indent + " ".join(str(part) for part in parts))

    def require_room(self, text):
        number = int(text)
        if number not in self.rooms:
            raise CommandError(f"unknown room {text}")
        return self.rooms[number]

    def require_type(self, kind):
        if kind not in ROOM_TYPES:
            raise CommandError(f"invalid type {kind}")

    def require_unused(self, identifier):
        if identifier in self.used_ids:
            raise CommandError(f"duplicate reservation {identifier}")

    def reservation(self, identifier, status=None):
        if identifier not in self.reservations:
            raise CommandError(f"unknown reservation {identifier}")
        reservation = self.reservations[identifier]
        if status is not None and reservation.status != status:
            raise CommandError(f"invalid status {identifier} {reservation.status}")
        return reservation

    def stay(self, first, last):
        arrival, departure = date_number(first), date_number(last)
        if arrival < self.today:
            raise CommandError(f"past date {first}")
        if departure <= arrival:
            raise CommandError(f"invalid range {first} {last}")
        if departure - arrival > 30:
            raise CommandError(f"too long {departure - arrival}")
        return arrival, departure

    def period(self, first, last, past_restricted=False, limited=True):
        start, end = date_number(first), date_number(last)
        if past_restricted and start < self.today:
            raise CommandError(f"past date {first}")
        if end < start:
            raise CommandError(f"invalid range {first} {last}")
        if limited and end - start + 1 > 31:
            raise CommandError(f"too long {end - start + 1}")
        return start, end

    def night_rate(self, room, day):
        percentage = next(
            (value for start, end, value in reversed(self.seasons) if start <= day <= end),
            100,
        )
        return room.rate * percentage // 100

    def price(self, room, arrival, departure):
        return [(day, room.number, self.night_rate(room, day)) for day in range(arrival, departure)]

    def first_unavailable(self, room, arrival, departure, except_for=None):
        for day in range(arrival, departure):
            key = day, room.number
            if key in self.blocks:
                return day
            occupied = self.occupied.get(key)
            if occupied is not None and occupied[0] is not except_for:
                return day
        return None

    def free_room(self, kind, arrival, departure, except_for=None):
        for number in sorted(self.rooms):
            room = self.rooms[number]
            if room.kind == kind and self.first_unavailable(room, arrival, departure, except_for) is None:
                return room
        return None

    def inhouse(self, room):
        return next((r for r in self.reservations.values() if r.status == "inhouse" and r.room is room), None)

    def occupy(self, reservation, nights):
        for day, room, rate in nights:
            self.occupied[day, room] = reservation, rate

    def release(self, reservation, first=None):
        for day, room, _ in reservation.nights:
            if first is None or day >= first:
                del self.occupied[day, room]

    def create_reservation(self, identifier, guest, room, arrival, departure, indent=0):
        nights = self.price(room, arrival, departure)
        reservation = Reservation(identifier, guest, room, arrival, departure, nights)
        self.reservations[identifier] = reservation
        self.used_ids.add(identifier)
        self.occupy(reservation, nights)
        self.emit(
            "BOOK", identifier, guest, "room", room.number, room.kind,
            date_text(arrival), "->", date_text(departure), "nights", departure - arrival,
            "total", money(reservation.lodging()), indent=indent,
        )

    def guest_total(self, guest):
        return sum(reservation.paid for reservation in self.reservations.values() if reservation.guest == guest)

    def tier(self, guest):
        points = self.guest_total(guest) // 100
        return "GOLD" if points >= 2000 else "SILVER" if points >= 500 else "BRONZE"

    def calculate_bill(self, reservation):
        lodging = reservation.lodging()
        percentage = {"GOLD": 10, "SILVER": 5, "BRONZE": 0}[self.tier(reservation.guest)]
        discount = lodging * percentage // 100
        penalty = 0 if reservation.penalty is None else reservation.penalty[1]
        extras = sum(amount for _, amount in reservation.extras)
        subtotal = lodging - discount + penalty + extras
        tax = subtotal // 10
        return lodging, discount, penalty, extras, tax, subtotal + tax

    def deposit_parts(self, reservation, total):
        if total >= reservation.deposit:
            return "deposit", money(reservation.deposit), "due", money(total - reservation.deposit)
        return "deposit", money(reservation.deposit), "refund", money(reservation.deposit - total)

    def check_out(self, reservation, day, indent=0):
        if day < reservation.departure:
            rate = next(rate for date, _, rate in reservation.nights if date == day)
            reservation.penalty = day, rate
            self.release(reservation, day)
            reservation.nights = [night for night in reservation.nights if night[0] < day]
            reservation.departure = day
        lodging, discount, penalty, extras, tax, total = self.calculate_bill(reservation)
        reservation.bill = lodging, discount, penalty, extras, tax, total
        reservation.paid = total
        reservation.status = "checkedout"
        reservation.posting = day
        reservation.room.clean = False
        self.emit(
            "CHECKOUT", reservation.identifier, "nights", len(reservation.nights),
            "lodging", money(lodging), "discount", money(discount), "penalty", money(penalty),
            "extras", money(extras), "tax", money(tax), "total", money(total),
            *self.deposit_parts(reservation, total), indent=indent,
        )

    def process_waitlist(self):
        remaining = []
        for entry in self.waitlist:
            if entry.arrival < self.today:
                self.emit("WAITLIST", entry.identifier, "expired", indent=2)
                continue
            room = self.free_room(entry.kind, entry.arrival, entry.departure)
            if room is None:
                remaining.append(entry)
            else:
                self.create_reservation(entry.identifier, entry.guest, room, entry.arrival, entry.departure, 2)
        self.waitlist = remaining

    def cmd_room(self, number, kind, amount):
        if int(number) in self.rooms:
            raise CommandError(f"duplicate room {number}")
        self.require_type(kind)
        room = Room(int(number), kind, cents(amount))
        self.rooms[room.number] = room
        self.emit("ROOM", number, kind, amount)

    def cmd_rate(self, number, amount):
        room = self.require_room(number)
        previous = room.rate
        room.rate = cents(amount)
        self.emit("RATE", number, money(previous), "->", amount)

    def cmd_season(self, first, last, percentage):
        start, end = self.period(first, last, limited=False)
        self.seasons.append((start, end, int(percentage)))
        self.emit("SEASON", len(self.seasons), first, "->", last, percentage + "%")

    def cmd_block(self, number, first, last):
        room = self.require_room(number)
        start, end = self.period(first, last, past_restricted=True)
        for day in range(start, end + 1):
            if (day, room.number) in self.occupied:
                raise CommandError(f"room unavailable {number} {date_text(day)}")
        nights = {(day, room.number) for day in range(start, end + 1)}
        added = len(nights - self.blocks)
        self.blocks.update(nights)
        self.emit("BLOCK", number, first, "->", last, "added", added)

    def cmd_unblock(self, number, first, last):
        room = self.require_room(number)
        start, end = self.period(first, last, past_restricted=True)
        nights = {(day, room.number) for day in range(start, end + 1)}
        removed = len(nights & self.blocks)
        self.blocks.difference_update(nights)
        self.emit("UNBLOCK", number, first, "->", last, "removed", removed)

    def cmd_clean(self, number):
        room = self.require_room(number)
        if room.clean:
            raise CommandError(f"already clean {number}")
        room.clean = True
        self.emit("CLEAN", number)

    def cmd_today(self, text):
        day = date_number(text)
        if day < self.today:
            raise CommandError(f"past date {text}")
        self.emit("TODAY", date_weekday(day))
        departing = sorted(
            (r for r in self.reservations.values() if r.status == "inhouse" and r.departure < day),
            key=lambda r: (r.departure, r.identifier),
        )
        for reservation in departing:
            self.check_out(reservation, reservation.departure, 2)
        absent = sorted(
            (r for r in self.reservations.values() if r.status == "booked" and r.arrival < day),
            key=lambda r: (r.arrival, r.identifier),
        )
        for reservation in absent:
            self.release(reservation)
            reservation.fee = reservation.first_rate()
            reservation.paid = reservation.fee
            reservation.status = "noshow"
            reservation.posting = reservation.arrival
            self.emit(
                "NOSHOW", reservation.identifier, reservation.guest, "fee", money(reservation.fee),
                *self.deposit_parts(reservation, reservation.fee), indent=2,
            )
        self.today = day

    def cmd_book(self, identifier, guest, kind, first, last):
        self.require_unused(identifier)
        self.require_type(kind)
        arrival, departure = self.stay(first, last)
        room = self.free_room(kind, arrival, departure)
        if room is None:
            raise CommandError(f"no availability {kind} {first} {last}")
        self.create_reservation(identifier, guest, room, arrival, departure)

    def cmd_bookroom(self, identifier, guest, number, first, last):
        self.require_unused(identifier)
        room = self.require_room(number)
        arrival, departure = self.stay(first, last)
        unavailable = self.first_unavailable(room, arrival, departure)
        if unavailable is not None:
            raise CommandError(f"room unavailable {number} {date_text(unavailable)}")
        self.create_reservation(identifier, guest, room, arrival, departure)

    def cmd_waitlist(self, identifier, guest, kind, first, last):
        self.require_unused(identifier)
        self.require_type(kind)
        arrival, departure = self.stay(first, last)
        room = self.free_room(kind, arrival, departure)
        if room is not None:
            self.create_reservation(identifier, guest, room, arrival, departure)
        else:
            self.waitlist.append(WaitingEntry(identifier, guest, kind, arrival, departure))
            self.used_ids.add(identifier)
            self.emit("WAITLIST", identifier, "queued position", len(self.waitlist))

    def cmd_modify(self, identifier, first, last):
        reservation = self.reservation(identifier, "booked")
        arrival, departure = self.stay(first, last)
        room = reservation.room
        choice = "kept"
        if self.first_unavailable(room, arrival, departure, reservation) is not None:
            room = self.free_room(room.kind, arrival, departure, reservation)
            if room is None:
                raise CommandError(f"no availability {reservation.room.kind} {first} {last}")
            choice = "reassigned"
        nights = self.price(room, arrival, departure)
        self.release(reservation)
        reservation.room = room
        reservation.arrival = arrival
        reservation.departure = departure
        reservation.nights = nights
        self.occupy(reservation, nights)
        self.emit(
            "MODIFY", identifier, "room", room.number, choice, first, "->", last,
            "nights", departure - arrival, "total", money(reservation.lodging()),
        )

    def cmd_cancel(self, identifier):
        for index, entry in enumerate(self.waitlist):
            if entry.identifier == identifier:
                del self.waitlist[index]
                self.emit("CANCEL", identifier, "waitlist removed")
                return
        reservation = self.reservation(identifier, "booked")
        days = reservation.arrival - self.today
        first_rate = reservation.first_rate()
        fee = 0 if days >= 7 else first_rate // 2 if days >= 1 else first_rate
        self.release(reservation)
        reservation.fee = fee
        reservation.paid = fee
        reservation.status = "cancelled"
        reservation.posting = self.today
        self.emit("CANCEL", identifier, "days", days, "fee", money(fee), *self.deposit_parts(reservation, fee))

    def cmd_checkin(self, identifier):
        reservation = self.reservation(identifier, "booked")
        if reservation.arrival != self.today:
            raise CommandError(f"not arrival date {identifier} {date_text(reservation.arrival)}")
        occupant = self.inhouse(reservation.room)
        if occupant is not None:
            raise CommandError(f"room occupied {reservation.room.number} {occupant.identifier}")
        if not reservation.room.clean:
            raise CommandError(f"room dirty {reservation.room.number}")
        reservation.status = "inhouse"
        self.emit("CHECKIN", identifier, reservation.guest, "room", reservation.room.number, "until", date_text(reservation.departure))

    def cmd_move(self, identifier, number):
        reservation = self.reservation(identifier, "inhouse")
        room = self.require_room(number)
        previous = reservation.room
        if room is previous:
            raise CommandError(f"same room {number}")
        remaining = [night for night in reservation.nights if night[0] >= self.today]
        if not remaining:
            raise CommandError(f"no remaining nights {identifier}")
        unavailable = self.first_unavailable(room, remaining[0][0], reservation.departure, reservation)
        if unavailable is not None:
            raise CommandError(f"room unavailable {number} {date_text(unavailable)}")
        occupant = self.inhouse(room)
        if occupant is not None:
            raise CommandError(f"room occupied {number} {occupant.identifier}")
        if not room.clean:
            raise CommandError(f"room dirty {number}")
        self.release(reservation, self.today)
        reservation.nights = [
            (day, room.number if day >= self.today else old_room, rate)
            for day, old_room, rate in reservation.nights
        ]
        self.occupy(reservation, [night for night in reservation.nights if night[0] >= self.today])
        previous.clean = False
        reservation.room = room
        self.emit("MOVE", identifier, previous.number, "->", number, "nights", len(remaining))

    def cmd_extend(self, identifier, text):
        reservation = self.reservation(identifier, "inhouse")
        departure = date_number(text)
        if departure <= reservation.departure:
            raise CommandError(f"invalid range {date_text(reservation.departure)} {text}")
        if departure - reservation.arrival > 30:
            raise CommandError(f"too long {departure - reservation.arrival}")
        unavailable = self.first_unavailable(reservation.room, reservation.departure, departure, reservation)
        if unavailable is not None:
            raise CommandError(f"room unavailable {reservation.room.number} {date_text(unavailable)}")
        nights = self.price(reservation.room, reservation.departure, departure)
        reservation.nights.extend(nights)
        self.occupy(reservation, nights)
        reservation.departure = departure
        self.emit("EXTEND", identifier, "until", text, "nights", len(reservation.nights), "total", money(reservation.lodging()))

    def cmd_charge(self, identifier, amount, item):
        reservation = self.reservation(identifier, "inhouse")
        value = cents(amount)
        if value == 0:
            raise CommandError("invalid amount")
        reservation.extras.append((item, value))
        extras = sum(value for _, value in reservation.extras)
        self.emit("CHARGE", identifier, item, amount, "extras", money(extras))

    def cmd_pay(self, identifier, amount):
        reservation = self.reservation(identifier)
        if reservation.status not in ("booked", "inhouse"):
            raise CommandError(f"invalid status {identifier} {reservation.status}")
        value = cents(amount)
        if value == 0:
            raise CommandError("invalid amount")
        reservation.deposit += value
        self.emit("PAY", identifier, amount, "deposit", money(reservation.deposit))

    def cmd_checkout(self, identifier):
        self.check_out(self.reservation(identifier, "inhouse"), self.today)

    def cmd_invoice(self, identifier):
        reservation = self.reservation(identifier)
        self.emit(
            "INVOICE", identifier, reservation.guest, "room", reservation.room.number,
            reservation.room.kind, reservation.status,
        )
        if reservation.status in ("cancelled", "noshow"):
            label = "cancellation" if reservation.status == "cancelled" else "noshow"
            self.emit(label, "fee", money(reservation.fee), indent=2)
            self.emit("total", money(reservation.fee), indent=2)
            self.emit(*self.deposit_parts(reservation, reservation.fee), indent=2)
            return
        for day, number, rate in reservation.nights:
            self.emit(date_weekday(day), "room", number, money(rate), indent=2)
        bill = reservation.bill if reservation.status == "checkedout" else self.calculate_bill(reservation)
        lodging, discount, penalty, _, tax, total = bill
        self.emit("lodging", money(lodging), indent=2)
        self.emit("discount", money(discount), indent=2)
        if reservation.penalty is not None:
            self.emit("penalty", date_weekday(reservation.penalty[0]), money(penalty), indent=2)
        for item, value in reservation.extras:
            self.emit("extra", item, money(value), indent=2)
        self.emit("tax", money(tax), indent=2)
        self.emit("total", money(total), indent=2)
        self.emit(*self.deposit_parts(reservation, total), indent=2)

    def cmd_avail(self, kind, first, last):
        self.require_type(kind)
        start, end = self.period(first, last)
        rooms = sorted(number for number, room in self.rooms.items() if room.kind == kind)
        self.emit("AVAIL", kind, first, "->", last)
        for day in range(start, end + 1):
            free = [number for number in rooms if (day, number) not in self.blocks and (day, number) not in self.occupied]
            self.emit(date_weekday(day), "free", len(free), *free, indent=2)

    def occupancy_parts(self, numbers, day):
        blocked = sum((day, number) in self.blocks for number in numbers)
        occupied = sum((day, number) in self.occupied for number in numbers)
        available = len(numbers) - blocked
        rate = str(occupied * 100 // available) + "%" if available else "n/a"
        return "rooms", len(numbers), "blocked", blocked, "occupied", occupied, "rate", rate

    def cmd_occupancy(self, text):
        day = date_number(text)
        self.emit("OCCUPANCY", date_weekday(day), *self.occupancy_parts(list(self.rooms), day))
        for kind in ROOM_TYPES:
            numbers = [number for number, room in self.rooms.items() if room.kind == kind]
            if numbers:
                self.emit(kind, *self.occupancy_parts(numbers, day), indent=2)

    def daily_values(self, day):
        available = len(self.rooms) - sum((day, number) in self.blocks for number in self.rooms)
        nights = [self.occupied[day, number] for number in self.rooms if (day, number) in self.occupied]
        return available, len(nights), sum(rate for _, rate in nights)

    def metrics_parts(self, available, occupied, revenue):
        rate = str(occupied * 100 // available) + "%" if available else "n/a"
        average = money(revenue // occupied) if occupied else "n/a"
        revpar = money(revenue // available) if available else "n/a"
        return "sold", f"{occupied}/{available}", "rate", rate, "revenue", money(revenue), "adr", average, "revpar", revpar

    def cmd_stats(self, first, last):
        start, end = self.period(first, last)
        totals = [0, 0, 0]
        self.emit("STATS", first, "->", last)
        for day in range(start, end + 1):
            values = self.daily_values(day)
            for index, value in enumerate(values):
                totals[index] += value
            self.emit(date_weekday(day), *self.metrics_parts(*values), indent=2)
        self.emit("total", *self.metrics_parts(*totals), indent=2)

    def cmd_rooms(self):
        self.emit("ROOMS", date_weekday(self.today), "rooms", len(self.rooms))
        for number in sorted(self.rooms):
            room = self.rooms[number]
            parts = [
                number, room.kind, "base", money(room.rate), "tonight", money(self.night_rate(room, self.today)),
                "clean" if room.clean else "dirty",
            ]
            occupant = self.inhouse(room)
            if occupant is not None:
                parts.extend(("occupied", occupant.identifier))
            elif (self.today, number) in self.blocks:
                parts.append("blocked")
            else:
                parts.append("vacant")
            upcoming = min(
                (r for r in self.reservations.values() if r.status == "booked" and r.room is room),
                key=lambda r: r.arrival, default=None,
            )
            if upcoming is not None:
                parts.extend(("next", upcoming.identifier, date_text(upcoming.arrival)))
            self.emit(*parts, indent=2)

    def cmd_list(self, status):
        reservations = sorted(
            (r for r in self.reservations.values() if r.status == status),
            key=lambda r: (r.arrival, r.identifier),
        )
        self.emit("LIST", status, len(reservations))
        for reservation in reservations:
            self.emit(
                reservation.identifier, reservation.guest, "room", reservation.room.number,
                date_text(reservation.arrival), "->", date_text(reservation.departure), indent=2,
            )

    def cmd_queue(self):
        self.emit("QUEUE", len(self.waitlist))
        for position, entry in enumerate(self.waitlist, 1):
            self.emit(
                position, entry.identifier, entry.guest, entry.kind,
                date_text(entry.arrival), "->", date_text(entry.departure), indent=2,
            )

    def cmd_schedule(self, text):
        day = date_number(text)
        arrivals = sorted(
            (r for r in self.reservations.values() if r.arrival == day and r.status != "cancelled"),
            key=lambda r: r.identifier,
        )
        departures = sorted(
            (r for r in self.reservations.values() if r.departure == day and r.status in ("booked", "inhouse", "checkedout")),
            key=lambda r: r.identifier,
        )
        self.emit("SCHEDULE", date_weekday(day), "arrivals", len(arrivals), "departures", len(departures))
        for label, reservations in (("arrival", arrivals), ("departure", departures)):
            for reservation in reservations:
                self.emit(label, reservation.identifier, reservation.guest, "room", reservation.room.number, reservation.status, indent=2)

    def cmd_guest(self, guest):
        reservations = [r for r in self.reservations.values() if r.guest == guest]
        if not reservations:
            raise CommandError(f"unknown guest {guest}")
        self.emit("GUEST", guest)
        for reservation in reservations:
            amount = ("deposit", reservation.deposit) if reservation.status in ("booked", "inhouse") else ("paid", reservation.paid)
            self.emit(
                reservation.identifier, "room", reservation.room.number, reservation.room.kind,
                date_text(reservation.arrival), "->", date_text(reservation.departure), reservation.status,
                amount[0], money(amount[1]), indent=2,
            )
        total = self.guest_total(guest)
        self.emit("total paid", money(total), "points", total // 100, "tier", self.tier(guest), indent=2)

    def cmd_revenue(self, first, last):
        start, end = self.period(first, last, limited=False)
        posted = [r for r in self.reservations.values() if r.posting is not None and start <= r.posting <= end]
        checked_out = [r for r in posted if r.status == "checkedout"]
        cancelled = [r for r in posted if r.status == "cancelled"]
        absent = [r for r in posted if r.status == "noshow"]
        lodging, discount, penalty, extras, tax = [sum(r.bill[index] for r in checked_out) for index in range(5)]
        cancellations = sum(r.fee for r in cancelled)
        noshows = sum(r.fee for r in absent)
        self.emit("REVENUE", first, "->", last)
        for label, amount in (
            ("lodging", lodging), ("discount", discount), ("penalty", penalty), ("extras", extras),
            ("tax", tax), ("cancellation", cancellations), ("noshow", noshows),
        ):
            self.emit(label, money(amount), indent=2)
        self.emit("total", money(lodging - discount + penalty + extras + tax + cancellations + noshows), indent=2)
        self.emit("checkouts", len(checked_out), "cancellations", len(cancelled), "noshows", len(absent), indent=2)

    def execute(self, line):
        command, *arguments = line.split()
        try:
            getattr(self, "cmd_" + command.lower())(*arguments)
        except CommandError as error:
            self.emit("ERROR", str(error))
        self.process_waitlist()


def main():
    count = int(sys.stdin.readline())
    desk = HotelDesk()
    for _ in range(count):
        desk.execute(sys.stdin.readline())
    sys.stdout.write("\n".join(desk.output) + "\n")


if __name__ == "__main__":
    main()
