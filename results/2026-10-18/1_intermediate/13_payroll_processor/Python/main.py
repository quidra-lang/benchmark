import sys


RATE_SETTINGS = (
    "STATE", "SUPP", "SSRATE", "MEDRATE", "ADDMED",
    "UIRATE", "MATCH", "MATCHMAX", "GARNCAP",
)
INITIAL_SETTINGS = {
    "STATE": 500, "SUPP": 2200, "SSRATE": 620, "MEDRATE": 145,
    "ADDMED": 90, "UIRATE": 270, "MATCH": 5000, "MATCHMAX": 600,
    "GARNCAP": 2500, "SSBASE": 16860000, "ADDBASE": 20000000,
    "UIBASE": 700000, "RETIRECAP": 2300000, "ALLOWANCE": 15000, "NIGHT": 100,
}
FIELDS = (
    "R", "O", "D", "N", "P", "accrued", "salary", "leave", "deduction",
    "sales", "commission", "earnings", "bonus", "gross", "retirement", "health",
    "federal", "supplemental", "state", "social", "medicare", "garnishment", "net",
    "employer_social", "employer_medicare", "unemployment", "match", "employer",
    "W", "Y", "F", "J",
)
WEEKDAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")


class CommandError(Exception):
    pass


def cents(text):
    whole, fraction = text.split(".")
    return int(whole) * 100 + int(fraction)


def money(value):
    return f"{value // 100}.{value % 100:02d}"


def rate_text(value):
    return money(value) + "%"


def duration(value):
    return f"{value // 60}:{value % 60:02d}"


def clock(value):
    return f"{value // 60:02d}:{value % 60:02d}"


def weekday(day):
    return WEEKDAYS[(day - 1) % 7]


def period_of(day):
    return (day - 1) // 14 + 1


def empty_totals():
    return dict.fromkeys(FIELDS, 0)


def sum_stubs(stubs):
    result = empty_totals()
    for stub in stubs:
        for field in FIELDS:
            result[field] += stub[field]
    return result


def progressive(table, amount):
    pairs = sorted(table.items())
    numerator = 0
    for index, (lower, rate) in enumerate(pairs):
        if lower >= amount:
            break
        upper = pairs[index + 1][0] if index + 1 < len(pairs) else amount
        numerator += rate * (min(amount, upper) - lower)
    return numerator // 10000


class Employee:
    def __init__(self, identifier, department, kind, base):
        self.identifier = identifier
        self.department = department
        self.kind = kind
        self.base = base
        self.active = True
        self.retirement = 0
        self.health = 0
        self.allowances = 0
        self.extra = 0
        self.garnishments = []
        self.bonus = 0
        self.pto_balance = 0
        self.shifts = {}
        self.pto = {}
        self.leave = set()
        self.sales = {}
        self.stubs = {}
        self.ytd = empty_totals()
        self.periods = 0

    def garnishment_balance(self):
        return sum(balance for _, balance in self.garnishments)


class Payroll:
    def __init__(self):
        self.settings = INITIAL_SETTINGS.copy()
        self.brackets = {}
        self.tiers = {}
        self.holidays = set()
        self.employees = {}
        self.closed = 0
        self.output = []

    def emit(self, *parts, indent=0):
        self.output.append(" " * indent + " ".join(str(part) for part in parts))

    def employee(self, text, active=False, kind=None):
        identifier = int(text)
        if identifier not in self.employees:
            raise CommandError("unknown employee " + text)
        employee = self.employees[identifier]
        if active and not employee.active:
            raise CommandError("terminated employee " + text)
        if kind is not None and employee.kind != kind:
            raise CommandError("not " + kind.lower() + " " + text)
        return employee

    def day_check(self, text):
        day = int(text)
        if not 1 <= day <= 364:
            raise CommandError("invalid day " + text)
        period = period_of(day)
        if period <= self.closed:
            raise CommandError(f"period closed {period}")
        return day

    def period_check(self, text):
        period = int(text)
        if not 1 <= period <= 26:
            raise CommandError("invalid period " + text)
        return period

    def rate_check(self, text):
        value = cents(text)
        if value > 10000:
            raise CommandError("invalid rate " + text)
        return value

    def amount_check(self, text):
        value = cents(text)
        if value == 0:
            raise CommandError("invalid amount")
        return value

    def time_check(self, text):
        hour, minute = (int(part) for part in text.split(":"))
        if hour > 23 or minute > 59:
            raise CommandError("invalid time " + text)
        return hour * 60 + minute

    def daily(self, employee, day):
        shifts = employee.shifts.get(day, [])
        worked = sum(end - start for start, end in shifts)
        night = sum(
            max(0, min(end, 360) - start) +
            max(0, end - max(start, 1320))
            for start, end in shifts
        )
        pto = employee.pto.get(day, 0)
        if day % 7 == 0 or day in self.holidays:
            regular, overtime, double = 0, 0, worked
        else:
            regular = min(worked, 480)
            overtime = min(max(worked - 480, 0), 240)
            double = max(worked - 720, 0)
        return worked, regular, overtime, double, night, pto

    def weekly(self, employee, week):
        totals = [0] * 5
        for day in range(7 * week - 6, 7 * week + 1):
            daily = self.daily(employee, day)
            for index in range(5):
                totals[index] += daily[index + 1]
        weekly_overtime = max(0, totals[0] - 2400)
        totals[0] -= weekly_overtime
        totals[1] += weekly_overtime
        return totals, weekly_overtime

    def breakdown(self, employee, period):
        first, _ = self.weekly(employee, 2 * period - 1)
        second, _ = self.weekly(employee, 2 * period)
        return [a + b for a, b in zip(first, second)]

    def calculate(self, employee, period):
        stub = empty_totals()
        settings = self.settings
        ytd = employee.ytd
        if employee.kind == "HOURLY":
            regular, overtime, double, night, pto = self.breakdown(employee, period)
            for field, amount in zip(("R", "O", "D", "N", "P"), (regular, overtime, double, night, pto)):
                stub[field] = amount
            weighted = 2 * (regular + pto) + 3 * overtime + 4 * double
            stub["earnings"] = (weighted * employee.base + 2 * night * settings["NIGHT"]) // 120
        elif employee.kind == "SALARIED":
            if employee.active:
                stub["salary"] = employee.base // 26
                stub["leave"] = sum(period_of(day) == period and day not in self.holidays for day in employee.leave)
                stub["deduction"] = stub["leave"] * (employee.base // 260)
                stub["earnings"] = stub["salary"] - stub["deduction"]
        else:
            stub["sales"] = employee.sales.get(period, 0)
            stub["commission"] = progressive(self.tiers, stub["sales"])
            stub["earnings"] = stub["commission"] + (employee.base if employee.active else 0)
        stub["bonus"] = employee.bonus
        gross = stub["earnings"] + stub["bonus"]
        if gross == 0:
            return None
        stub["gross"] = gross
        remaining = gross

        def deduct(field, amount):
            nonlocal remaining
            stub[field] = min(amount, remaining)
            remaining -= stub[field]

        retirement_room = max(0, settings["RETIRECAP"] - ytd["retirement"])
        deduct("retirement", min(gross * employee.retirement // 10000, retirement_room))
        deduct("health", employee.health)
        stub["W"] = remaining
        base_taxable = max(0, stub["earnings"] - stub["retirement"] - stub["health"])
        allowance_taxable = max(0, base_taxable - employee.allowances * settings["ALLOWANCE"])
        deduct("federal", progressive(self.brackets, allowance_taxable) + employee.extra)
        deduct("supplemental", (stub["W"] - base_taxable) * settings["SUPP"] // 10000)
        deduct("state", stub["W"] * settings["STATE"] // 10000)
        medicare_wages = gross - stub["health"]
        social_wages = min(medicare_wages, max(0, settings["SSBASE"] - ytd["Y"]))
        additional = max(0, min(medicare_wages, ytd["F"] + medicare_wages - settings["ADDBASE"]))
        stub["F"] = medicare_wages
        stub["Y"] = social_wages
        deduct("social", social_wages * settings["SSRATE"] // 10000)
        deduct("medicare", medicare_wages * settings["MEDRATE"] // 10000 + additional * settings["ADDMED"] // 10000)
        disposable = remaining
        cap = disposable * settings["GARNCAP"] // 10000
        balances = []
        garnishment = 0
        for rate, balance in employee.garnishments:
            taken = min(disposable * rate // 10000, balance, cap - garnishment)
            garnishment += taken
            balances.append(balance - taken)
        stub["garnishment"] = garnishment
        stub["garnishment_balance"] = sum(balances)
        stub["net"] = remaining - garnishment
        stub["employer_social"] = social_wages * settings["SSRATE"] // 10000
        stub["employer_medicare"] = medicare_wages * settings["MEDRATE"] // 10000
        stub["J"] = min(medicare_wages, max(0, settings["UIBASE"] - ytd["J"]))
        stub["unemployment"] = stub["J"] * settings["UIRATE"] // 10000
        eligible_match = min(stub["retirement"], gross * settings["MATCHMAX"] // 10000)
        stub["match"] = eligible_match * settings["MATCH"] // 10000
        stub["employer"] = sum(stub[field] for field in ("employer_social", "employer_medicare", "unemployment", "match"))
        if employee.kind == "HOURLY":
            stub["accrued"] = min(960 - employee.pto_balance, (stub["R"] + stub["O"] + stub["D"]) // 20)
        stub["pto_balance"] = employee.pto_balance + stub["accrued"]
        return stub, balances

    def hours_parts(self, values):
        parts = []
        for label, value in zip(("reg", "ot", "dbl", "night", "pto"), values):
            parts.extend((label, duration(value)))
        return parts

    def stub_block(self, employee, stub, indent):
        if employee.kind == "HOURLY":
            self.emit("hours", *self.hours_parts([stub[field] for field in ("R", "O", "D", "N", "P")]), indent=indent)
            self.emit("pto", "accrued", duration(stub["accrued"]), "balance", duration(stub["pto_balance"]), indent=indent)
        elif employee.kind == "SALARIED":
            self.emit("salary", money(stub["salary"]), "leave", stub["leave"], "deduction", money(stub["deduction"]), indent=indent)
        else:
            self.emit("sales", money(stub["sales"]), "commission", money(stub["commission"]), indent=indent)
        for field in ("earnings", "bonus", "gross", "retirement", "health", "federal", "supplemental", "state", "social", "medicare"):
            self.emit("social-security" if field == "social" else field, money(stub[field]), indent=indent)
        self.emit("garnishment", money(stub["garnishment"]), "balance", money(stub["garnishment_balance"]), indent=indent)
        self.emit("net", money(stub["net"]), indent=indent)
        self.emit("employer", "social-security", money(stub["employer_social"]),
                  "medicare", money(stub["employer_medicare"]), "unemployment", money(stub["unemployment"]),
                  "match", money(stub["match"]), indent=indent)

    def print_stub(self, employee, period, stub, department):
        self.emit("STUB", employee.identifier, department, employee.kind, "period", period, indent=2)
        self.stub_block(employee, stub, 4)

    def show_hours(self, employee, period):
        self.emit("HOURS", employee.identifier, "period", period)
        found = False
        for day in range(14 * period - 13, 14 * period + 1):
            shifts = sorted(employee.shifts.get(day, []))
            if not shifts and day not in employee.pto:
                continue
            worked, *values = self.daily(employee, day)
            parts = ["day", day, weekday(day)]
            if day in self.holidays:
                parts.append("holiday")
            parts.extend(f"{clock(start)}-{clock(end)}" for start, end in shifts)
            self.emit(*parts, "total", duration(worked), *self.hours_parts(values), indent=2)
            found = True
        if not found:
            self.emit("(none)", indent=2)
        for week in (2 * period - 1, 2 * period):
            values, overtime = self.weekly(employee, week)
            self.emit("week", week, *self.hours_parts(values), "weekly-ot", duration(overtime), indent=2)
        self.emit("total", *self.hours_parts(self.breakdown(employee, period)), indent=2)

    def run(self, period):
        self.closed = period
        self.emit("RUN", period, "days", f"{14 * period - 13}-{14 * period}")
        paid = skipped = 0
        stubs = []
        for identifier in sorted(self.employees):
            employee = self.employees[identifier]
            calculated = self.calculate(employee, period)
            if calculated is None:
                skipped += int(employee.active)
                continue
            stub, balances = calculated
            self.print_stub(employee, period, stub, employee.department)
            employee.bonus = 0
            employee.pto_balance = stub["pto_balance"]
            for order, balance in zip(employee.garnishments, balances):
                order[1] = balance
            for field in FIELDS:
                employee.ytd[field] += stub[field]
            employee.periods += 1
            employee.stubs[period] = (stub, employee.department)
            stubs.append(stub)
            paid += 1
        total = sum_stubs(stubs)
        self.emit("TOTAL", "paid", paid, "skipped", skipped, "gross", money(total["gross"]),
                  "deductions", money(total["gross"] - total["net"]), "net", money(total["net"]),
                  "employer", money(total["employer"]), indent=2)

    def journal(self, period):
        stubs = [employee.stubs[period][0] for employee in self.employees.values() if period in employee.stubs]
        total = sum_stubs(stubs)
        rows = (
            ("debit", "wages", total["gross"]),
            ("debit", "employer-tax", total["employer_social"] + total["employer_medicare"] + total["unemployment"]),
            ("debit", "retirement-match", total["match"]),
            ("credit", "retirement", total["retirement"] + total["match"]),
            ("credit", "health", total["health"]),
            ("credit", "federal", total["federal"] + total["supplemental"]),
            ("credit", "state", total["state"]),
            ("credit", "fica", total["social"] + total["medicare"] + total["employer_social"] + total["employer_medicare"]),
            ("credit", "unemployment", total["unemployment"]),
            ("credit", "garnishment", total["garnishment"]),
            ("credit", "net-pay", total["net"]),
        )
        self.emit("JOURNAL", period, "stubs", len(stubs))
        for side, label, amount in rows:
            self.emit(side, label, money(amount), indent=2)
        self.emit("total", "debit", money(sum(amount for side, _, amount in rows if side == "debit")),
                  "credit", money(sum(amount for side, _, amount in rows if side == "credit")), indent=2)

    def report_line(self, department, stubs):
        total = sum_stubs(stubs)
        taxes = sum(total[field] for field in ("federal", "supplemental", "state", "social", "medicare"))
        self.emit(department, "stubs", len(stubs), "gross", money(total["gross"]),
                  "pretax", money(total["retirement"] + total["health"]), "taxes", money(taxes),
                  "garnishment", money(total["garnishment"]), "net", money(total["net"]),
                  "employer", money(total["employer"]), indent=2)

    def command(self, command, a):
        if command == "SET":
            name = a[0]
            if name not in self.settings:
                raise CommandError("unknown setting " + name)
            value = self.rate_check(a[1]) if name in RATE_SETTINGS else cents(a[1])
            formatter = rate_text if name in RATE_SETTINGS else money
            old = self.settings[name]
            self.settings[name] = value
            self.emit("SET", name, formatter(old), "->", formatter(value))
        elif command in ("BRACKET", "TIER"):
            rate = self.rate_check(a[1])
            table = self.brackets if command == "BRACKET" else self.tiers
            lower = cents(a[0])
            action = "replaced" if lower in table else "added"
            table[lower] = rate
            self.emit(command, money(lower), rate_text(rate), action)
        elif command == "EMP":
            identifier = int(a[0])
            if identifier in self.employees:
                raise CommandError("duplicate employee " + a[0])
            base = self.amount_check(a[3])
            self.employees[identifier] = Employee(identifier, a[1], a[2], base)
            self.emit("EMP", identifier, a[1], a[2], money(base))
        elif command in ("RATE", "DEPT", "BENEFIT", "W4", "GARNISH", "TERM", "BONUS"):
            employee = self.employee(a[0], active=True)
            if command == "RATE":
                base = self.amount_check(a[1])
                old = employee.base
                employee.base = base
                self.emit("RATE", employee.identifier, money(old), "->", money(base))
            elif command == "DEPT":
                if a[1] == employee.department:
                    raise CommandError("same department " + a[1])
                old = employee.department
                employee.department = a[1]
                self.emit("DEPT", employee.identifier, old, "->", a[1])
            elif command == "BENEFIT":
                rate = self.rate_check(a[1])
                employee.retirement = rate
                employee.health = cents(a[2])
                self.emit("BENEFIT", employee.identifier, "retirement", rate_text(rate), "health", money(employee.health))
            elif command == "W4":
                employee.allowances = int(a[1])
                employee.extra = cents(a[2])
                self.emit("W4", employee.identifier, "allowances", employee.allowances, "extra", money(employee.extra))
            elif command == "GARNISH":
                rate = self.rate_check(a[1])
                amount = self.amount_check(a[2])
                employee.garnishments.append([rate, amount])
                self.emit("GARNISH", employee.identifier, "order", len(employee.garnishments), rate_text(rate), "balance", money(amount))
            elif command == "TERM":
                employee.active = False
                self.emit("TERM", employee.identifier)
            else:
                amount = self.amount_check(a[1])
                employee.bonus += amount
                self.emit("BONUS", employee.identifier, money(amount), "pending", money(employee.bonus))
        elif command == "HOLIDAY":
            day = self.day_check(a[0])
            if day in self.holidays:
                raise CommandError("duplicate holiday " + a[0])
            self.holidays.add(day)
            self.emit("HOLIDAY", day, weekday(day))
        elif command in ("TIME", "UNTIME", "PTO", "LEAVE", "SALES"):
            kind = "SALARIED" if command == "LEAVE" else "COMMISSION" if command == "SALES" else "HOURLY"
            employee = self.employee(a[0], active=True, kind=kind)
            day = self.day_check(a[1])
            if command == "TIME":
                start = self.time_check(a[2])
                end = self.time_check(a[3])
                if start >= end:
                    raise CommandError(f"invalid shift {a[2]}-{a[3]}")
                shifts = sorted(employee.shifts.get(day, []))
                for old_start, old_end in shifts:
                    if start < old_end and old_start < end:
                        raise CommandError(f"overlapping shift {clock(old_start)}-{clock(old_end)}")
                if sum(t - s for s, t in shifts) + end - start > 960:
                    raise CommandError(f"daily limit {a[0]} {a[1]}")
                employee.shifts.setdefault(day, []).append((start, end))
                self.emit("TIME", employee.identifier, "day", day, f"{clock(start)}-{clock(end)}", duration(end - start))
            elif command == "UNTIME":
                start = self.time_check(a[2])
                shifts = employee.shifts.get(day, [])
                found = next((shift for shift in shifts if shift[0] == start), None)
                if found is None:
                    raise CommandError(f"no shift {a[0]} {a[1]} {a[2]}")
                shifts.remove(found)
                self.emit("UNTIME", employee.identifier, "day", day, f"{clock(found[0])}-{clock(found[1])}")
            elif command == "PTO":
                hour, minute = (int(part) for part in a[2].split(":"))
                length = hour * 60 + minute
                if minute > 59 or not 1 <= length <= 480:
                    raise CommandError("invalid duration " + a[2])
                if day in employee.pto:
                    raise CommandError(f"duplicate pto {a[0]} {a[1]}")
                if length > employee.pto_balance:
                    raise CommandError(f"insufficient pto {a[0]} {duration(employee.pto_balance)}")
                employee.pto[day] = length
                employee.pto_balance -= length
                self.emit("PTO", employee.identifier, "day", day, duration(length), "balance", duration(employee.pto_balance))
            elif command == "LEAVE":
                if day % 7 in (0, 6) or day in self.holidays:
                    raise CommandError("not workday " + a[1])
                if day in employee.leave:
                    raise CommandError(f"duplicate leave {a[0]} {a[1]}")
                employee.leave.add(day)
                self.emit("LEAVE", employee.identifier, "day", day, weekday(day))
            else:
                amount = self.amount_check(a[2])
                period = period_of(day)
                employee.sales[period] = employee.sales.get(period, 0) + amount
                self.emit("SALES", employee.identifier, "day", day, money(amount),
                          "period", period, "total", money(employee.sales[period]))
        elif command == "HOURS":
            employee = self.employee(a[0], kind="HOURLY")
            period = self.period_check(a[1])
            self.show_hours(employee, period)
        elif command == "RUN":
            period = int(a[0])
            if period != self.closed + 1 or period > 26:
                raise CommandError("invalid period " + a[0])
            self.run(period)
        elif command == "PREVIEW":
            employee = self.employee(a[0])
            period = self.closed + 1
            calculated = self.calculate(employee, period)
            self.emit("PREVIEW", employee.identifier, "period", period)
            if calculated is None:
                self.emit("no pay", indent=2)
            else:
                self.print_stub(employee, period, calculated[0], employee.department)
        elif command == "REPRINT":
            employee = self.employee(a[0])
            period = self.period_check(a[1])
            if period not in employee.stubs:
                raise CommandError(f"no stub {a[0]} {a[1]}")
            stub, department = employee.stubs[period]
            self.emit("REPRINT", employee.identifier, period)
            self.print_stub(employee, period, stub, department)
        elif command == "YTD":
            employee = self.employee(a[0])
            self.emit("YTD", employee.identifier, employee.department, employee.kind,
                      "active" if employee.active else "terminated", "periods", employee.periods)
            totals = dict(employee.ytd, pto_balance=employee.pto_balance, garnishment_balance=employee.garnishment_balance())
            self.stub_block(employee, totals, 2)
            self.emit("wages", "federal", money(totals["W"]), "social-security", money(totals["Y"]),
                      "medicare", money(totals["F"]), "unemployment", money(totals["J"]), indent=2)
            self.emit("retirement-room", money(max(0, self.settings["RETIRECAP"] - totals["retirement"])),
                      "pending-bonus", money(employee.bonus), indent=2)
        elif command == "JOURNAL":
            period = int(a[0])
            if not 1 <= period <= self.closed:
                raise CommandError("no run " + a[0])
            self.journal(period)
        elif command == "REPORT":
            departments = {}
            all_stubs = []
            for employee in self.employees.values():
                for stub, department in employee.stubs.values():
                    departments.setdefault(department, []).append(stub)
                    all_stubs.append(stub)
            self.emit("REPORT", "period", self.closed)
            for department in sorted(departments):
                self.report_line(department, departments[department])
            self.report_line("total", all_stubs)
        elif command == "TOP":
            count = int(a[0])
            employees = sorted(
                (employee for employee in self.employees.values() if employee.periods),
                key=lambda employee: (-employee.ytd["gross"], employee.identifier),
            )
            self.emit("TOP", count)
            for rank, employee in enumerate(employees[:count], 1):
                self.emit(rank, employee.identifier, employee.department, "gross", money(employee.ytd["gross"]), "net", money(employee.ytd["net"]), indent=2)
            if not employees:
                self.emit("(none)", indent=2)
        elif command == "EMPLOYEES":
            self.emit("EMPLOYEES")
            for identifier in sorted(self.employees):
                employee = self.employees[identifier]
                self.emit(identifier, employee.department, employee.kind, money(employee.base),
                          "active" if employee.active else "terminated", "retirement", rate_text(employee.retirement),
                          "health", money(employee.health), "allowances", employee.allowances, "extra", money(employee.extra),
                          "bonus", money(employee.bonus), indent=2)
                for number, (rate, balance) in enumerate(employee.garnishments, 1):
                    self.emit("garnish", number, rate_text(rate), "balance", money(balance), indent=4)
            if not self.employees:
                self.emit("(none)", indent=2)
        elif command == "CONFIG":
            self.emit("CONFIG")
            for name, value in self.settings.items():
                self.emit(name, rate_text(value) if name in RATE_SETTINGS else money(value), indent=2)
            for label, table in (("bracket", self.brackets), ("tier", self.tiers)):
                for lower, rate in sorted(table.items()):
                    self.emit(label, money(lower), rate_text(rate), indent=2)

    def execute(self, line):
        command, *arguments = line.split()
        try:
            self.command(command, arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    payroll = Payroll()
    count = int(sys.stdin.readline())
    for _ in range(count):
        payroll.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(payroll.output) + "\n")


if __name__ == "__main__":
    main()
