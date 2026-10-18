import sys


STATIONS = ("GRILL", "FRY", "COLD", "BAR")
COURSES = ("DRINK", "STARTER", "MAIN", "DESSERT")


class CommandError(Exception):
    pass


def cents(text):
    whole, fraction = text.split(".")
    return int(whole) * 100 + int(fraction)


def money(value):
    return f"{value // 100}.{value % 100:02d}"


def clock(value):
    minutes = 660 + value
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def rounded(value, rate):
    return (value * rate + 50) // 100


class Table:
    def __init__(self, number, seats):
        self.number = number
        self.seats = seats
        self.check = None


class Server:
    def __init__(self, name):
        self.name = name
        self.load = 0
        self.parties = 0
        self.sales = 0
        self.tips = 0


class MenuItem:
    def __init__(self, name, station, prep, price, course):
        self.name = name
        self.station = station
        self.prep = prep
        self.price = price
        self.course = course
        self.stock = None


class Check:
    def __init__(self, party, size, table, server, since):
        self.party = party
        self.size = size
        self.table = table
        self.server = server
        self.since = since
        self.lines = []
        self.paid = 0
        self.discount = 0
        self.closed = False

    def active(self):
        return [line for line in self.lines if line.state != "VOID"]

    def amounts(self):
        subtotal = sum(line.amount() for line in self.active())
        discount = rounded(subtotal, self.discount)
        after_discount = subtotal - discount
        service = rounded(after_discount, 18) if self.size >= 6 else 0
        tax = rounded(after_discount, 8)
        total = after_discount + service + tax
        return subtotal, discount, service, tax, total, total - self.paid


class OrderLine:
    def __init__(self, number, check, seat, item, quantity, price):
        self.number = number
        self.check = check
        self.seat = seat
        self.name = item.name
        self.quantity = quantity
        self.station = item.station
        self.prep = item.prep
        self.price = price
        self.course = item.course
        self.state = "ORDERED"
        self.comp = None
        self.fire = None
        self.ready = None
        self.started = False

    def amount(self):
        return 0 if self.comp is not None else self.price * self.quantity

    def tag(self):
        return "#" + str(self.number)


class Station:
    def __init__(self, name):
        self.name = name
        self.capacity = 2 if name == "BAR" else 1
        self.up = True
        self.queue = []
        self.cooking = []
        self.tickets = 0
        self.ticket_total = 0
        self.ticket_max = 0
        self.remakes = 0


class Restaurant:
    def __init__(self):
        self.time = 0
        self.tables = {}
        self.servers = []
        self.server_names = set()
        self.waiting = []
        self.seated = {}
        self.menu = {}
        self.lines = []
        self.stations = {name: Station(name) for name in STATIONS}
        self.happy_rate = 0
        self.happy_until = None
        self.guests = 0
        self.parties = 0
        self.closed = 0
        self.stay_total = 0
        self.sales = {course: 0 for course in COURSES}
        self.totals = [0] * 5
        self.payments = {"CASH": 0, "CARD": 0}
        self.tips = 0
        self.comps = 0
        self.comp_amount = 0
        self.voids = 0
        self.served = {}
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def table(self, text, occupied=False):
        number = int(text)
        if number not in self.tables:
            raise CommandError(f"unknown table {text}")
        table = self.tables[number]
        if occupied and table.check is None:
            raise CommandError(f"table {text} is free")
        return table

    def line(self, text):
        number = int(text)
        if not 1 <= number <= len(self.lines):
            raise CommandError(f"unknown line {text}")
        return self.lines[number - 1]

    def unlocked(self, check):
        if check.paid:
            raise CommandError(f"check for table {check.table.number} is locked")

    def modification(self, line):
        if line.state == "VOID":
            raise CommandError(f"{line.tag()} is void")
        if line.check.closed:
            raise CommandError(f"{line.tag()} is on a closed check")
        self.unlocked(line.check)

    def all_served(self, check):
        count = sum(line.state != "SERVED" for line in check.active())
        if count:
            raise CommandError(f"table {check.table.number} has {count} unserved items")

    def select_table(self, size):
        return min(
            (table for table in self.tables.values() if table.check is None and table.seats >= size),
            key=lambda table: (table.seats, table.number), default=None,
        )

    def seat_party(self, party, size, table):
        server = min(self.servers, key=lambda server: server.load)
        check = Check(party, size, table, server, self.time)
        table.check = check
        self.seated[party] = check
        server.load += 1
        server.parties += 1
        self.guests += size
        self.parties += 1
        return check

    def process_waitlist(self):
        remaining = []
        for party, size, joined in self.waiting:
            table = self.select_table(size)
            if table is None:
                remaining.append((party, size, joined))
            else:
                check = self.seat_party(party, size, table)
                self.emit("SEATED", party, size, "table", table.number, "server", check.server.name, "waited", self.time - joined)
        self.waiting = remaining

    def close_check(self, check):
        amounts = check.amounts()
        for line in check.active():
            self.sales[line.course] += line.amount()
        for index in range(5):
            self.totals[index] += amounts[index]
        stay = self.time - check.since
        self.closed += 1
        self.stay_total += stay
        check.server.sales += amounts[4]
        check.server.load -= 1
        check.closed = True
        check.table.check = None
        del self.seated[check.party]
        self.emit("FREE", "table", check.table.number, check.party, "stayed", stay)
        self.process_waitlist()

    def start_station(self, name, when):
        station = self.stations[name]
        while station.up and station.queue and len(station.cooking) < station.capacity:
            line = station.queue.pop(0)
            line.state = "COOKING"
            line.started = True
            line.ready = when + line.prep
            station.cooking.append(line)

    def start_all(self, when):
        for name in STATIONS:
            self.start_station(name, when)

    def seat_subtotals(self, check):
        values = {}
        for line in check.active():
            values[line.seat] = values.get(line.seat, 0) + line.amount()
        return values

    def allocate(self, values, rate):
        amounts = {seat: value * rate // 100 for seat, value in values.items()}
        extra = rounded(sum(values.values()), rate) - sum(amounts.values())
        ranked = sorted(values, key=lambda seat: (-(values[seat] * rate % 100), seat))
        for seat in ranked[:extra]:
            amounts[seat] += 1
        return amounts

    def cmd_table(self, number, seats):
        number, seats = int(number), int(seats)
        if number in self.tables:
            raise CommandError(f"table {number} already exists")
        self.tables[number] = Table(number, seats)
        self.emit("TABLE", number, "seats", seats)
        self.process_waitlist()

    def cmd_staff(self, name):
        if name in self.server_names:
            raise CommandError(f"{name} is already on duty")
        self.servers.append(Server(name))
        self.server_names.add(name)
        self.emit("STAFF", name)

    def cmd_seat(self, party, size):
        size = int(size)
        if party in self.seated:
            raise CommandError(f"{party} is already seated at table {self.seated[party].table.number}")
        if any(name == party for name, _, _ in self.waiting):
            raise CommandError(f"{party} is already waiting")
        if not any(table.seats >= size for table in self.tables.values()):
            raise CommandError(f"no table for party of {size}")
        if not self.servers:
            raise CommandError("no server on duty")
        table = self.select_table(size)
        if table is None:
            self.waiting.append((party, size, self.time))
            self.emit("WAIT", party, size, "position", len(self.waiting))
        else:
            check = self.seat_party(party, size, table)
            self.emit("SEAT", party, size, "table", table.number, "server", check.server.name)

    def cmd_cancel(self, party):
        for index, (name, size, joined) in enumerate(self.waiting):
            if name == party:
                self.waiting.pop(index)
                self.emit("CANCEL", party, size, "waited", self.time - joined)
                return
        raise CommandError(f"{party} is not waiting")

    def cmd_move(self, first, second):
        source = self.table(first)
        destination = self.table(second)
        if source.check is None:
            raise CommandError(f"table {first} is free")
        if destination.check is not None:
            raise CommandError(f"table {second} is occupied")
        check = source.check
        if destination.seats < check.size:
            raise CommandError(f"table {second} is too small for {check.party}")
        source.check = None
        destination.check = check
        check.table = destination
        self.emit("MOVE", check.party, "table", first, "->", second)
        self.process_waitlist()

    def cmd_menu(self, name, station, prep, price, course):
        if station not in STATIONS:
            raise CommandError(f"unknown station {station}")
        if course not in COURSES:
            raise CommandError(f"unknown course {course}")
        action = "UPDATE" if name in self.menu else "ADD"
        if name in self.menu:
            item = self.menu[name]
            item.station, item.prep, item.price, item.course = station, int(prep), cents(price), course
        else:
            self.menu[name] = MenuItem(name, station, int(prep), cents(price), course)
        self.emit("MENU", action, name, station, prep, price, course)

    def cmd_stock(self, name, quantity):
        if name not in self.menu:
            raise CommandError(f"unknown item {name}")
        self.menu[name].stock = int(quantity)
        self.emit("STOCK", name, quantity)

    def cmd_happy(self, rate, minutes):
        self.happy_rate = int(rate)
        self.happy_until = self.time + int(minutes)
        self.emit("HAPPY", rate + "%", "until", clock(self.happy_until))

    def cmd_items(self):
        self.emit("ITEMS", len(self.menu))
        for item in sorted(self.menu.values(), key=lambda item: (COURSES.index(item.course), item.name)):
            stock = "-" if item.stock is None else item.stock
            self.emit(item.course, item.name, item.station, item.prep, money(item.price), stock)

    def cmd_order(self, number, seat, name, quantity):
        check = self.table(number, occupied=True).check
        self.unlocked(check)
        seat, quantity = int(seat), int(quantity)
        if seat > check.size:
            raise CommandError(f"seat {seat} out of range for table {number}")
        if name not in self.menu:
            raise CommandError(f"unknown item {name}")
        item = self.menu[name]
        if item.stock is not None and item.stock < quantity:
            raise CommandError(f"only {item.stock} {name} left")
        happy = item.course == "DRINK" and self.happy_until is not None and self.time < self.happy_until
        price = item.price - rounded(item.price, self.happy_rate) if happy else item.price
        line = OrderLine(len(self.lines) + 1, check, seat, item, quantity, price)
        self.lines.append(line)
        check.lines.append(line)
        parts = ["ORDER", line.tag(), "table", number, "seat", seat, name, "x" + str(quantity), money(line.amount())]
        if happy:
            parts.append("HAPPY")
        self.emit(*parts)
        if item.stock is not None:
            item.stock -= quantity
            if item.stock == 0:
                self.emit("SOLDOUT", name)

    def cmd_fire(self, number, course):
        check = self.table(number, occupied=True).check
        if course not in COURSES:
            raise CommandError(f"unknown course {course}")
        selected = [line for line in check.lines if line.course == course and line.state == "ORDERED"]
        if not selected:
            raise CommandError(f"nothing to fire for {course} at table {number}")
        if course in ("MAIN", "DESSERT"):
            for earlier in COURSES[1:COURSES.index(course)]:
                if any(line.course == earlier and line.state == "ORDERED" for line in check.lines):
                    raise CommandError(f"fire {earlier} first")
        for line in selected:
            line.state = "QUEUED"
            line.fire = self.time
            self.stations[line.station].queue.append(line)
        self.emit("FIRE", "table", number, course, *(line.tag() for line in selected))
        self.start_all(self.time)

    def cmd_tick(self, minutes):
        target = self.time + int(minutes)
        self.emit("TICK", clock(target))
        while True:
            cooking = [line for station in self.stations.values() for line in station.cooking]
            if not cooking:
                break
            completion = min(line.ready for line in cooking)
            if completion > target:
                break
            for name in STATIONS:
                station = self.stations[name]
                finished = sorted((line for line in station.cooking if line.ready == completion), key=lambda line: line.number)
                for line in finished:
                    station.cooking.remove(line)
                    line.state = "READY"
                    ticket = completion - line.fire
                    station.tickets += 1
                    station.ticket_total += ticket
                    station.ticket_max = max(station.ticket_max, ticket)
                    self.emit(
                        "READY", clock(completion), name, line.tag(), line.name, "x" + str(line.quantity),
                        "table", line.check.table.number, "seat", line.seat,
                    )
            self.start_all(completion)
        self.time = target

    def cmd_serve(self, number):
        check = self.table(number, occupied=True).check
        selected = [line for line in check.lines if line.state == "READY"]
        if not selected:
            raise CommandError(f"nothing ready for table {number}")
        for line in selected:
            line.state = "SERVED"
            self.served[line.name] = self.served.get(line.name, 0) + line.quantity
        self.emit("SERVE", "table", number, *(line.tag() for line in selected))

    def cmd_rush(self, number):
        line = self.line(number)
        if line.state != "QUEUED":
            raise CommandError(f"{line.tag()} is not queued")
        queue = self.stations[line.station].queue
        queue.remove(line)
        queue.insert(0, line)
        self.emit("RUSH", line.tag(), line.station)

    def cmd_remake(self, number):
        line = self.line(number)
        if line.check.closed:
            raise CommandError(f"{line.tag()} is on a closed check")
        if line.state not in ("READY", "SERVED"):
            raise CommandError(f"{line.tag()} is not ready or served")
        station = self.stations[line.station]
        line.state = "QUEUED"
        line.fire = self.time
        station.queue.insert(0, line)
        station.remakes += 1
        self.emit("REMAKE", line.tag(), line.name, line.station)
        self.start_station(line.station, self.time)

    def cmd_void(self, number):
        line = self.line(number)
        if line.state == "VOID":
            raise CommandError(f"{line.tag()} is already void")
        if line.started:
            raise CommandError(f"{line.tag()} has already started")
        if line.state == "QUEUED":
            self.stations[line.station].queue.remove(line)
        line.state = "VOID"
        item = self.menu[line.name]
        if item.stock is not None:
            item.stock += line.quantity
        self.voids += 1
        self.emit("VOID", line.tag(), line.name, "x" + str(line.quantity))

    def cmd_station(self, name, operation):
        if name not in STATIONS:
            raise CommandError(f"unknown station {name}")
        station = self.stations[name]
        if operation == "DOWN" and not station.up:
            raise CommandError(f"station {name} is already down")
        if operation == "UP" and station.up:
            raise CommandError(f"station {name} is not down")
        station.up = operation == "UP"
        if station.up:
            self.start_station(name, self.time)
        self.emit("STATION", name, operation)

    def cmd_comp(self, number, reason):
        line = self.line(number)
        self.modification(line)
        if line.comp is not None:
            raise CommandError(f"{line.tag()} is already comped")
        amount = line.amount()
        self.emit("COMP", line.tag(), line.name, money(amount), reason)
        self.comps += 1
        self.comp_amount += amount
        line.comp = reason

    def cmd_transfer(self, number, seat):
        line = self.line(number)
        self.modification(line)
        seat = int(seat)
        if seat > line.check.size:
            raise CommandError(f"seat {seat} out of range for table {line.check.table.number}")
        if seat == line.seat:
            raise CommandError(f"{line.tag()} is already on seat {seat}")
        self.emit("TRANSFER", line.tag(), "seat", line.seat, "->", seat)
        line.seat = seat

    def cmd_discount(self, number, rate):
        check = self.table(number, occupied=True).check
        self.unlocked(check)
        check.discount = int(rate)
        self.emit("DISCOUNT", "table", number, rate + "%")

    def cmd_bill(self, number):
        check = self.table(number, occupied=True).check
        self.emit("BILL", "table", number, check.party, "guests", check.size)
        subtotals = self.seat_subtotals(check)
        for seat in sorted(subtotals):
            self.emit("SEAT", seat, money(subtotals[seat]))
            for line in check.active():
                if line.seat == seat:
                    parts = [line.tag(), line.name, "x" + str(line.quantity), money(line.amount())]
                    if line.comp is not None:
                        parts.extend(("COMP", line.comp))
                    self.emit(*parts)
        subtotal, discount, service, tax, total, due = check.amounts()
        self.emit("SUBTOTAL", money(subtotal))
        if check.discount:
            self.emit("DISCOUNT", str(check.discount) + "%", money(discount))
        if check.size >= 6:
            self.emit("SERVICE", money(service))
        self.emit("TAX", money(tax))
        self.emit("TOTAL", money(total))
        if check.paid:
            self.emit("PAID", money(check.paid))
            self.emit("DUE", money(due))

    def cmd_split(self, number, mode, *arguments):
        check = self.table(number, occupied=True).check
        due = check.amounts()[5]
        if due == 0:
            raise CommandError(f"nothing to split for table {number}")
        if mode == "EVEN":
            count = int(arguments[0])
            if count > check.size:
                raise CommandError(f"cannot split table {number} {count} ways")
            self.emit("SPLIT", "table", number, "EVEN", count, "due", money(due))
            quotient, remainder = divmod(due, count)
            for payer in range(1, count + 1):
                self.emit("PAYER", payer, money(quotient + (payer <= remainder)))
            return
        if check.paid:
            raise CommandError(f"table {number} has payments")
        subtotals = self.seat_subtotals(check)
        discounts = self.allocate(subtotals, check.discount)
        after = {seat: subtotal - discounts[seat] for seat, subtotal in subtotals.items()}
        services = self.allocate(after, 18) if check.size >= 6 else {seat: 0 for seat in subtotals}
        taxes = self.allocate(after, 8)
        self.emit("SPLIT", "table", number, "BYSEAT", "total", money(check.amounts()[4]))
        for seat in sorted(subtotals):
            total = after[seat] + services[seat] + taxes[seat]
            self.emit(
                "SEAT", seat, "subtotal", money(subtotals[seat]), "discount", money(discounts[seat]),
                "service", money(services[seat]), "tax", money(taxes[seat]), "total", money(total),
            )

    def cmd_pay(self, number, method, amount):
        check = self.table(number, occupied=True).check
        if method not in self.payments:
            raise CommandError(f"unknown method {method}")
        self.all_served(check)
        due = check.amounts()[5]
        if due == 0:
            raise CommandError(f"nothing to pay for table {number}")
        value = cents(amount)
        applied = min(value, due)
        check.paid += applied
        self.payments[method] += applied
        if value < due:
            self.emit("PAY", "table", number, method, amount, "remaining", money(due - value))
        else:
            excess = value - due
            label = "change" if method == "CASH" else "tip"
            self.emit("PAY", "table", number, method, amount, label, money(excess))
            if method == "CARD":
                self.tips += excess
                check.server.tips += excess
            self.close_check(check)

    def cmd_close(self, number):
        check = self.table(number, occupied=True).check
        self.all_served(check)
        due = check.amounts()[5]
        if due:
            raise CommandError(f"table {number} still owes {money(due)}")
        self.close_check(check)

    def cmd_status(self, number):
        check = self.table(number, occupied=True).check
        self.emit("STATUS", "table", number, check.party, "guests", check.size, "since", clock(check.since))
        for line in check.lines:
            parts = [line.tag(), "seat", line.seat, line.name, "x" + str(line.quantity), line.course, line.state]
            if line.state == "COOKING":
                parts.extend(("until", clock(line.ready)))
            if line.comp is not None:
                parts.extend(("COMP", line.comp))
            self.emit(*parts)

    def cmd_kitchen(self):
        self.emit("KITCHEN", clock(self.time))
        for name in STATIONS:
            station = self.stations[name]
            cooking = sorted(station.cooking, key=lambda line: (line.ready, line.number))
            cooking_text = " ".join(line.tag() + "@" + clock(line.ready) for line in cooking) or "-"
            queue_text = " ".join(line.tag() for line in station.queue) or "-"
            self.emit(name, "up" if station.up else "down", "cooking", cooking_text, "queue", queue_text)

    def cmd_floor(self):
        occupied = sum(table.check is not None for table in self.tables.values())
        self.emit("FLOOR", clock(self.time), "free", len(self.tables) - occupied, "seated", occupied, "waiting", len(self.waiting))
        for number in sorted(self.tables):
            table = self.tables[number]
            if table.check is None:
                self.emit("table", number, "seats", table.seats, "free")
                continue
            check = table.check
            parts = [
                "table", number, "seats", table.seats, check.party, "guests", check.size,
                "server", check.server.name, "since", clock(check.since), "items", len(check.active()), "total", money(check.amounts()[4]),
            ]
            if check.paid:
                parts.extend(("paid", money(check.paid)))
            self.emit(*parts)
        for position, (party, size, joined) in enumerate(self.waiting, 1):
            self.emit("WAITING", position, party, size, "since", clock(joined))

    def cmd_report(self):
        self.emit("REPORT", clock(self.time))
        self.emit("COVERS", self.guests, "parties", self.parties)
        self.emit("TURNS", self.closed, "avg_stay", self.stay_total // self.closed if self.closed else "-")
        self.emit("SALES", *(part for course in COURSES for part in (course, money(self.sales[course]))))
        subtotal, discount, service, tax, total = self.totals
        self.emit(
            "TOTALS", "subtotal", money(subtotal), "discount", money(discount), "service", money(service),
            "tax", money(tax), "total", money(total),
        )
        self.emit("PAYMENTS", "cash", money(self.payments["CASH"]), "card", money(self.payments["CARD"]), "tips", money(self.tips))
        self.emit("COMPS", self.comps, money(self.comp_amount), "VOIDS", self.voids)
        top = sorted(self.served, key=lambda name: (-self.served[name], name))[:3]
        for rank, name in enumerate(top, 1):
            self.emit("TOP", rank, name, self.served[name])
        for name in STATIONS:
            station = self.stations[name]
            average = station.ticket_total // station.tickets if station.tickets else "-"
            maximum = station.ticket_max if station.tickets else "-"
            self.emit(name, "tickets", station.tickets, "avg", average, "max", maximum, "remakes", station.remakes)
        for server in self.servers:
            self.emit(
                "SERVER", server.name, "tables", server.load, "parties", server.parties,
                "sales", money(server.sales), "tips", money(server.tips),
            )

    def execute(self, text):
        command, *arguments = text.split()
        try:
            getattr(self, "cmd_" + command.lower())(*arguments)
        except CommandError as error:
            self.emit("ERROR", str(error))


def main():
    count = int(sys.stdin.readline())
    restaurant = Restaurant()
    for _ in range(count):
        restaurant.execute(sys.stdin.readline())
    sys.stdout.write("\n".join(restaurant.output) + "\n")


if __name__ == "__main__":
    main()
