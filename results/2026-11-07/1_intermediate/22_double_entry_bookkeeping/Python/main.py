import sys


ACCOUNT_CLASSES = {
    "ASSET": "ASSET",
    "CONTRA_ASSET": "ASSET",
    "LIABILITY": "LIABILITY",
    "EQUITY": "EQUITY",
    "REVENUE": "REVENUE",
    "EXPENSE": "EXPENSE",
}
DEBIT_NORMAL = ("ASSET", "EXPENSE")
INCOME_TYPES = ("REVENUE", "EXPENSE")
MONTH_DAYS = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
FIRST_DAY = 0
LAST_DAY = 36524
NO_PARTNER = "none"
IRREVERSIBLE = ("reversal", "closing", "reopen")
CLOSING_CATEGORIES = ("closing", "reopen")
AGING_LABELS = ("0-30", "31-60", "61-90", "91+")
AGING_LIMITS = (30, 60, 90)
INTEREST_DIVISOR = 3650000


class CommandError(Exception):
    pass


def leap_year(year):
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


def month_length(year, month):
    if month == 2 and leap_year(year):
        return 29
    return MONTH_DAYS[month - 1]


def year_length(year):
    return 366 if leap_year(year) else 365


def day_number(year, month, day):
    number = day - 1
    for earlier in range(2000, year):
        number += year_length(earlier)
    for earlier in range(1, month):
        number += month_length(year, earlier)
    return number


def calendar_date(number):
    year = 2000
    while number >= year_length(year):
        number -= year_length(year)
        year += 1
    month = 1
    while number >= month_length(year, month):
        number -= month_length(year, month)
        month += 1
    return year, month, number + 1


def date_text(number):
    year, month, day = calendar_date(number)
    return f"{year:04d}-{month:02d}-{day:02d}"


def checked_date(text):
    year, month, day = int(text[0:4]), int(text[5:7]), int(text[8:10])
    valid = 2000 <= year <= 2099 and 1 <= month <= 12 and 1 <= day <= month_length(year, month)
    if not valid:
        raise CommandError(f"invalid date {text}")
    return day_number(year, month, day)


def checked_range(first_text, last_text):
    first = checked_date(first_text)
    last = checked_date(last_text)
    if first > last:
        raise CommandError(f"invalid range {first_text} {last_text}")
    return first, last


def months_after(number, months):
    year, month, day = calendar_date(number)
    total = month - 1 + months
    year += total // 12
    month = total % 12 + 1
    return day_number(year, month, min(day, month_length(year, month)))


def cents(text):
    whole, fraction = text.split(".")
    return int(whole) * 100 + int(fraction)


def money(value):
    sign = "-" if value < 0 else ""
    value = abs(value)
    return f"{sign}{value // 100}.{value % 100:02d}"


def truncated_division(value, divisor):
    quotient = abs(value) // divisor
    return -quotient if value < 0 else quotient


def side_total(lines, side):
    return sum(line.amount for line in lines if line.side == side)


def aging_bucket(age):
    for index, limit in enumerate(AGING_LIMITS):
        if age <= limit:
            return index
    return len(AGING_LIMITS)


def aging_columns(buckets, unapplied):
    parts = []
    for label, value in zip(AGING_LABELS, buckets):
        parts.extend((label, money(value)))
    parts.extend(("unapplied", money(unapplied), "balance", money(sum(buckets) - unapplied)))
    return parts


class Account:
    def __init__(self, code, kind, name):
        self.code = code
        self.kind = kind
        self.name = name
        self.active = True
        self.sign = 1 if kind in DEBIT_NORMAL else -1


class Line:
    def __init__(self, side, account, amount, partner):
        self.side = side
        self.account = account
        self.amount = amount
        self.partner = partner

    def difference(self):
        return self.amount if self.side == "DR" else -self.amount

    def swapped(self):
        side = "CR" if self.side == "DR" else "DR"
        return Line(side, self.account, self.amount, self.partner)


class Entry:
    def __init__(self, entry_id, date, category, memo, lines):
        self.entry_id = entry_id
        self.date = date
        self.category = category
        self.memo = memo
        self.lines = lines
        self.reversed_by = None
        self.reverses = None

    def amount(self):
        return side_total(self.lines, "DR")


class Template:
    def __init__(self, name, memo, lines):
        self.name = name
        self.memo = memo
        self.lines = lines
        self.uses = 0


class Block:
    def __init__(self, kind, key, date_token, memo):
        self.kind = kind
        self.key = key
        self.date_token = date_token
        self.memo = memo
        self.lines = []


class CloseRecord:
    def __init__(self, date, entry_id):
        self.date = date
        self.entry_id = entry_id


class OpenItem:
    def __init__(self, entry, original, remaining):
        self.entry = entry
        self.original = original
        self.remaining = remaining


class Totals:
    def __init__(self):
        self.debits = {}
        self.credits = {}

    def add(self, entry):
        for line in entry.lines:
            if line.side == "DR":
                self.debits[line.account] = self.debit(line.account) + line.amount
            else:
                self.credits[line.account] = self.credit(line.account) + line.amount

    def debit(self, code):
        return self.debits.get(code, 0)

    def credit(self, code):
        return self.credits.get(code, 0)

    def difference(self, code):
        return self.debit(code) - self.credit(code)


class Books:
    def __init__(self):
        self.accounts = {}
        self.entries = []
        self.entry_index = {}
        self.templates = {}
        self.block = None
        self.closes = []
        self.close_count = 0
        self.depreciation_count = 0
        self.interest_count = 0
        self.writeoff_count = 0
        self.output = []

    def emit(self, *parts, indent=0):
        self.output.append(" " * indent + " ".join(str(part) for part in parts))

    def ancestors(self, code):
        return [code[:length] for length in range(1, len(code)) if code[:length] in self.accounts]

    def parent(self, code):
        ancestors = self.ancestors(code)
        return ancestors[-1] if ancestors else "none"

    def top_level(self, code):
        ancestors = self.ancestors(code)
        return ancestors[0] if ancestors else code

    def require_account(self, code):
        if code not in self.accounts:
            raise CommandError(f"unknown account {code}")
        return self.accounts[code]

    def require_type(self, code, kind):
        account = self.require_account(code)
        if account.kind != kind:
            raise CommandError(f"wrong type {code} {kind}")
        return account

    def require_active(self, codes):
        for code in codes:
            if not self.accounts[code].active:
                raise CommandError(f"inactive account {code}")

    def require_entry(self, entry_id):
        if entry_id not in self.entry_index:
            raise CommandError(f"unknown entry {entry_id}")
        return self.entry_index[entry_id]

    def require_block(self):
        if self.block is None:
            raise CommandError("no open entry")
        return self.block

    def closed_through(self):
        return self.closes[-1].date if self.closes else None

    def closed_text(self):
        closed = self.closed_through()
        return "none" if closed is None else date_text(closed)

    def require_open_period(self, date):
        closed = self.closed_through()
        if closed is not None and date <= closed:
            raise CommandError(f"period closed {date_text(date)}")

    def totals(self, first, last, skip_closing=False):
        totals = Totals()
        for entry in self.entries:
            if first <= entry.date <= last:
                if not (skip_closing and entry.category in CLOSING_CATEGORIES):
                    totals.add(entry)
        return totals

    def current_totals(self):
        return self.totals(FIRST_DAY, LAST_DAY)

    def balance(self, code, totals):
        return self.accounts[code].sign * totals.difference(code)

    def daily_balance_sum(self, code, first, last):
        sign = self.accounts[code].sign
        total = 0
        for entry in self.entries:
            if entry.date <= last:
                days = last - max(entry.date, first) + 1
                for line in entry.lines:
                    if line.account == code:
                        total += sign * line.difference() * days
        return total

    def partners(self, code, date):
        names = set()
        for entry in self.entries:
            if entry.date <= date:
                for line in entry.lines:
                    if line.account == code and line.partner != NO_PARTNER:
                        names.add(line.partner)
        return sorted(names)

    def open_items(self, code, partner, date):
        sign = self.accounts[code].sign
        items = []
        unapplied = 0
        for entry in self.entries:
            if entry.date > date:
                break
            for line in entry.lines:
                if line.account != code or line.partner != partner:
                    continue
                value = sign * line.difference()
                if value > 0:
                    applied = min(value, unapplied)
                    unapplied -= applied
                    if value - applied > 0:
                        items.append(OpenItem(entry, value, value - applied))
                elif value < 0:
                    rest = -value
                    while rest > 0 and items:
                        first = items[0]
                        taken = min(rest, first.remaining)
                        first.remaining -= taken
                        rest -= taken
                        if first.remaining == 0:
                            del items[0]
                    unapplied += rest
        return items, unapplied

    def post(self, entry_id, date, category, memo, lines):
        entry = Entry(entry_id, date, category, memo, lines)
        position = len(self.entries)
        while position > 0 and self.entries[position - 1].date > date:
            position -= 1
        self.entries.insert(position, entry)
        self.entry_index[entry_id] = entry
        return entry

    def reverse(self, entry, entry_id, date, category, memo):
        lines = [line.swapped() for line in entry.lines]
        reversal = self.post(entry_id, date, category, memo, lines)
        entry.reversed_by = entry_id
        reversal.reverses = entry.entry_id
        return reversal

    def add_account(self, arguments):
        code, kind, name = arguments
        if code in self.accounts:
            raise CommandError(f"duplicate account {code}")
        for other in sorted(self.accounts):
            related = other.startswith(code) or code.startswith(other)
            if related and ACCOUNT_CLASSES[self.accounts[other].kind] != ACCOUNT_CLASSES[kind]:
                raise CommandError(f"class mismatch {code} {other}")
        self.accounts[code] = Account(code, kind, name)
        self.emit("ACCOUNT", code, kind, name, "parent", self.parent(code))

    def deactivate(self, arguments):
        account = self.require_account(arguments[0])
        if not account.active:
            raise CommandError(f"already inactive {account.code}")
        balance = self.balance(account.code, self.current_totals())
        if balance != 0:
            raise CommandError(f"nonzero balance {account.code} {money(balance)}")
        account.active = False
        self.emit("DEACTIVATE", account.code, account.name)

    def open_block(self, kind, key, date_token, memo):
        if self.block is not None:
            self.emit("DISCARD", self.block.key, "lines", len(self.block.lines))
        self.block = Block(kind, key, date_token, memo)

    def journal(self, arguments):
        entry_number, date_token, memo = arguments
        self.open_block("journal", entry_number, date_token, memo)

    def template(self, arguments):
        name, memo = arguments
        self.open_block("template", name, None, memo)

    def add_line(self, side, arguments):
        block = self.require_block()
        partner = arguments[2] if len(arguments) == 3 else NO_PARTNER
        block.lines.append(Line(side, arguments[0], cents(arguments[1]), partner))

    def debit(self, arguments):
        self.add_line("DR", arguments)

    def credit(self, arguments):
        self.add_line("CR", arguments)

    def check_lines(self, block, check_active):
        if len(block.lines) < 2:
            raise CommandError(f"too few lines {block.key}")
        for line in block.lines:
            if line.account not in self.accounts:
                raise CommandError(f"unknown account {line.account}")
            if check_active and not self.accounts[line.account].active:
                raise CommandError(f"inactive account {line.account}")
            if line.amount == 0:
                raise CommandError(f"zero amount {line.account}")
        debit = side_total(block.lines, "DR")
        credit = side_total(block.lines, "CR")
        if debit != credit:
            raise CommandError(
                f"unbalanced {block.key} debit {money(debit)} credit {money(credit)}"
            )

    def post_journal(self, block):
        if block.key in self.entry_index:
            raise CommandError(f"duplicate entry {block.key}")
        date = checked_date(block.date_token)
        self.require_open_period(date)
        self.check_lines(block, True)
        entry = self.post(block.key, date, "journal", block.memo, block.lines)
        self.emit(
            "POST", entry.entry_id, date_text(entry.date),
            "lines", len(entry.lines), "amount", money(entry.amount()),
        )

    def register_template(self, block):
        if block.key in self.templates:
            raise CommandError(f"duplicate template {block.key}")
        self.check_lines(block, False)
        template = Template(block.key, block.memo, block.lines)
        self.templates[template.name] = template
        self.emit(
            "TEMPLATE", template.name, "lines", len(template.lines),
            "amount", money(side_total(template.lines, "DR")),
        )

    def post_block(self, arguments):
        block = self.require_block()
        self.block = None
        if block.kind == "journal":
            self.post_journal(block)
        else:
            self.register_template(block)

    def draft(self, arguments):
        block = self.require_block()
        debit = side_total(block.lines, "DR")
        credit = side_total(block.lines, "CR")
        self.emit(
            "DRAFT", block.kind, block.key, "lines", len(block.lines),
            "debit", money(debit), "credit", money(credit), "difference", money(debit - credit),
        )

    def reverse_entry(self, arguments):
        entry_id, date_token = arguments
        entry = self.require_entry(entry_id)
        if entry.category in IRREVERSIBLE:
            raise CommandError(f"cannot reverse {entry_id}")
        if entry.reversed_by is not None:
            raise CommandError(f"already reversed {entry_id}")
        date = checked_date(date_token)
        if date < entry.date:
            raise CommandError(f"reverse before entry {entry_id} {date_text(entry.date)}")
        self.require_open_period(date)
        self.require_active(line.account for line in entry.lines)
        reversal = self.reverse(entry, entry_id + "-R", date, "reversal", entry.memo)
        self.emit(
            "REVERSE", entry_id, "entry", reversal.entry_id, date_text(date),
            "amount", money(reversal.amount()),
        )

    def recur(self, arguments):
        name, date_token, count_text = arguments
        if name not in self.templates:
            raise CommandError(f"unknown template {name}")
        template = self.templates[name]
        date = checked_date(date_token)
        count = int(count_text)
        if count == 0:
            raise CommandError("invalid count")
        self.require_open_period(date)
        self.require_active(line.account for line in template.lines)
        self.emit("RECUR", name, "count", count)
        for offset in range(count):
            template.uses += 1
            entry = self.post(
                f"{name}-{template.uses}", months_after(date, offset),
                "recurring", template.memo, list(template.lines),
            )
            self.emit(
                "POST", entry.entry_id, date_text(entry.date),
                "lines", len(entry.lines), "amount", money(entry.amount()), indent=2,
            )

    def depreciate(self, arguments):
        date_token, asset_code, contra_code, expense_code, life_text = arguments
        date = checked_date(date_token)
        self.require_open_period(date)
        self.require_type(asset_code, "ASSET")
        self.require_type(contra_code, "CONTRA_ASSET")
        self.require_type(expense_code, "EXPENSE")
        self.require_active([contra_code, expense_code])
        totals = self.totals(FIRST_DAY, date)
        cost = self.balance(asset_code, totals)
        accumulated = self.balance(contra_code, totals)
        amount = min(cost // int(life_text), cost - accumulated) if cost > 0 else 0
        if amount <= 0:
            raise CommandError(f"nothing to depreciate {asset_code}")
        self.depreciation_count += 1
        lines = [
            Line("DR", expense_code, amount, NO_PARTNER),
            Line("CR", contra_code, amount, NO_PARTNER),
        ]
        entry = self.post(
            f"DEP-{self.depreciation_count}", date, "depreciation", "depreciation", lines
        )
        self.emit(
            "DEPRECIATE", asset_code, "entry", entry.entry_id, date_text(date),
            "amount", money(amount), "accumulated", money(accumulated + amount),
            "book", money(cost - accumulated - amount),
        )

    def interest(self, arguments):
        code, offset_code, first_token, last_token, rate_text = arguments
        account = self.require_account(code)
        if account.kind not in ("ASSET", "LIABILITY"):
            raise CommandError(f"not interest bearing {code}")
        self.require_type(offset_code, "REVENUE" if account.kind == "ASSET" else "EXPENSE")
        first, last = checked_range(first_token, last_token)
        self.require_open_period(last)
        self.require_active([code, offset_code])
        total = self.daily_balance_sum(code, first, last)
        amount = truncated_division(total * int(rate_text), INTEREST_DIVISOR)
        if amount <= 0:
            raise CommandError(f"no interest {code}")
        self.interest_count += 1
        if account.kind == "ASSET":
            debit_code, credit_code = code, offset_code
        else:
            debit_code, credit_code = offset_code, code
        lines = [
            Line("DR", debit_code, amount, NO_PARTNER),
            Line("CR", credit_code, amount, NO_PARTNER),
        ]
        entry = self.post(f"INT-{self.interest_count}", last, "interest", "interest", lines)
        days = last - first + 1
        self.emit(
            "INTEREST", code, "entry", entry.entry_id, date_text(last), "days", days,
            "average", money(truncated_division(total, days)), "amount", money(amount),
        )

    def write_off(self, arguments):
        date_token, code, expense_code, days_text = arguments
        date = checked_date(date_token)
        self.require_open_period(date)
        self.require_type(code, "ASSET")
        self.require_type(expense_code, "EXPENSE")
        self.require_active([code, expense_code])
        limit = int(days_text)
        targets = []
        for partner in self.partners(code, date):
            items, _ = self.open_items(code, partner, date)
            amount = sum(item.remaining for item in items if date - item.entry.date > limit)
            if amount >= 1:
                targets.append((partner, amount))
        total = sum(amount for _, amount in targets)
        if total == 0:
            raise CommandError(f"nothing to write off {code}")
        self.writeoff_count += 1
        lines = [Line("DR", expense_code, total, NO_PARTNER)]
        for partner, amount in targets:
            lines.append(Line("CR", code, amount, partner))
        entry = self.post(f"WO-{self.writeoff_count}", date, "writeoff", "writeoff", lines)
        self.emit(
            "WRITEOFF", code, "entry", entry.entry_id, date_text(date),
            "partners", len(targets), "amount", money(total),
        )
        for partner, amount in targets:
            self.emit(partner, money(amount), indent=2)

    def close(self, arguments):
        date_token, code = arguments
        date = checked_date(date_token)
        self.require_open_period(date)
        self.require_type(code, "EQUITY")
        self.require_active([code])
        totals = self.totals(FIRST_DAY, date)
        to_close = [
            other for other in sorted(self.accounts)
            if self.accounts[other].kind in INCOME_TYPES and totals.difference(other) != 0
        ]
        self.require_active(to_close)
        lines = []
        for other in to_close:
            difference = totals.difference(other)
            if difference > 0:
                lines.append(Line("CR", other, difference, NO_PARTNER))
            else:
                lines.append(Line("DR", other, -difference, NO_PARTNER))
        income = -sum(totals.difference(other) for other in to_close)
        if income > 0:
            lines.append(Line("CR", code, income, NO_PARTNER))
        elif income < 0:
            lines.append(Line("DR", code, -income, NO_PARTNER))
        self.close_count += 1
        if not lines:
            self.closes.append(CloseRecord(date, None))
            self.emit("CLOSE", date_text(date), "no", "entry")
            return
        entry = self.post(f"CLOSE-{self.close_count}", date, "closing", "closing", lines)
        self.closes.append(CloseRecord(date, entry.entry_id))
        self.emit(
            "CLOSE", date_text(date), "entry", entry.entry_id,
            "lines", len(lines), "net", "income", money(income),
        )

    def reopen(self, arguments):
        if not self.closes:
            raise CommandError("nothing to reopen")
        record = self.closes[-1]
        entry = None
        if record.entry_id is not None:
            entry = self.entry_index[record.entry_id]
            self.require_active(line.account for line in entry.lines)
        parts = ["REOPEN", date_text(record.date)]
        if entry is None:
            parts.extend(("no", "entry"))
        else:
            reversal = self.reverse(entry, entry.entry_id + "-R", record.date, "reopen", "reopen")
            parts.extend(("entry", reversal.entry_id))
        self.closes.pop()
        parts.extend(("closed", self.closed_text()))
        self.emit(*parts)

    def ledger(self, arguments):
        code, first_token, last_token = arguments
        account = self.require_account(code)
        first, last = checked_range(first_token, last_token)
        running = self.balance(code, self.totals(FIRST_DAY, first - 1))
        self.emit("LEDGER", code, account.name, date_text(first), date_text(last))
        self.emit("opening", money(running), indent=2)
        debits = 0
        credits = 0
        for entry in self.entries:
            if not first <= entry.date <= last:
                continue
            for line in entry.lines:
                if line.account != code:
                    continue
                running += account.sign * line.difference()
                if line.side == "DR":
                    debits += line.amount
                else:
                    credits += line.amount
                self.emit(
                    date_text(entry.date), entry.entry_id, line.side, money(line.amount),
                    "balance", money(running), entry.memo, indent=2,
                )
        days = last - first + 1
        average = truncated_division(self.daily_balance_sum(code, first, last), days)
        self.emit(
            "ending", money(running), "debits", money(debits), "credits", money(credits),
            "days", days, "average", money(average), indent=2,
        )

    def activity(self, arguments):
        code, year_text = arguments
        account = self.require_account(code)
        year = int(year_text)
        self.emit("ACTIVITY", code, account.name, year)
        total_debit = 0
        total_credit = 0
        for month in range(1, 13):
            first = day_number(year, month, 1)
            last = day_number(year, month, month_length(year, month))
            period = self.totals(first, last)
            debit = period.debit(code)
            credit = period.credit(code)
            total_debit += debit
            total_credit += credit
            balance = self.balance(code, self.totals(FIRST_DAY, last))
            self.emit(
                f"{year}-{month:02d}", "debit", money(debit), "credit", money(credit),
                "balance", money(balance), indent=2,
            )
        self.emit("total", "debit", money(total_debit), "credit", money(total_credit), indent=2)

    def trial(self, arguments):
        date = checked_date(arguments[0])
        totals = self.totals(FIRST_DAY, date)
        self.emit("TRIAL", date_text(date))
        debit_total = 0
        credit_total = 0
        for code in sorted(self.accounts):
            difference = totals.difference(code)
            name = self.accounts[code].name
            if difference > 0:
                debit_total += difference
                self.emit(code, name, "debit", money(difference), indent=2)
            elif difference < 0:
                credit_total -= difference
                self.emit(code, name, "credit", money(-difference), indent=2)
        self.emit("total", "debit", money(debit_total), "credit", money(credit_total), indent=2)

    def section(self, heading, kinds, sigma, totals, extra):
        targets = [code for code in sorted(self.accounts) if self.accounts[code].kind in kinds]
        amounts = {code: sigma * totals.difference(code) for code in targets}
        total = sum(amounts.values()) + extra
        self.emit(heading, money(total), indent=2)
        groups = {}
        for code in targets:
            groups.setdefault(self.top_level(code), []).append(code)
        for top in sorted(groups):
            shown = [code for code in groups[top] if amounts[code] != 0]
            if not shown:
                continue
            group_total = sum(amounts[code] for code in shown)
            self.emit(top, self.accounts[top].name, money(group_total), indent=4)
            for code in shown:
                self.emit(code, self.accounts[code].name, money(amounts[code]), indent=6)
        return total

    def income(self, arguments):
        first, last = checked_range(arguments[0], arguments[1])
        totals = self.totals(first, last, skip_closing=True)
        self.emit("INCOME", date_text(first), date_text(last))
        revenue = self.section("REVENUE", ("REVENUE",), -1, totals, 0)
        expense = self.section("EXPENSE", ("EXPENSE",), 1, totals, 0)
        self.emit("NET", "INCOME", money(revenue - expense), indent=2)

    def balance_sheet(self, arguments):
        date = checked_date(arguments[0])
        totals = self.totals(FIRST_DAY, date)
        earnings = -sum(
            totals.difference(code) for code, account in self.accounts.items()
            if account.kind in INCOME_TYPES
        )
        self.emit("BALANCE", date_text(date))
        assets = self.section("ASSETS", ("ASSET", "CONTRA_ASSET"), 1, totals, 0)
        liabilities = self.section("LIABILITIES", ("LIABILITY",), -1, totals, 0)
        equity = self.section("EQUITY", ("EQUITY",), -1, totals, earnings)
        self.emit("current", "earnings", money(earnings), indent=4)
        mismatch = assets - (liabilities + equity)
        if mismatch == 0:
            self.emit("check", "ok", indent=2)
        else:
            self.emit("check", "mismatch", money(mismatch), indent=2)

    def rollup(self, arguments):
        prefix, date_token = arguments
        date = checked_date(date_token)
        totals = self.totals(FIRST_DAY, date)
        self.emit("ROLLUP", prefix, date_text(date))
        targets = [code for code in sorted(self.accounts) if code.startswith(prefix)]
        if not targets:
            self.emit("(none)", indent=2)
            return
        for code in targets:
            account = self.accounts[code]
            depth = sum(1 for ancestor in self.ancestors(code) if ancestor.startswith(prefix))
            subtotal = sum(totals.difference(other) for other in targets if other.startswith(code))
            self.emit(
                code, account.name, "own", money(self.balance(code, totals)),
                "total", money(account.sign * subtotal), indent=2 * (1 + depth),
            )
        debit = sum(totals.debit(code) for code in targets)
        credit = sum(totals.credit(code) for code in targets)
        self.emit("postings", "debit", money(debit), "credit", money(credit), indent=2)

    def aging(self, arguments):
        code, date_token = arguments
        account = self.require_account(code)
        date = checked_date(date_token)
        self.emit("AGING", code, account.name, date_text(date))
        total_buckets = [0] * len(AGING_LABELS)
        total_unapplied = 0
        for partner in self.partners(code, date):
            items, unapplied = self.open_items(code, partner, date)
            if not items and unapplied < 1:
                continue
            buckets = [0] * len(AGING_LABELS)
            for item in items:
                buckets[aging_bucket(date - item.entry.date)] += item.remaining
            for index, value in enumerate(buckets):
                total_buckets[index] += value
            total_unapplied += unapplied
            self.emit(partner, *aging_columns(buckets, unapplied), indent=2)
        self.emit("total", *aging_columns(total_buckets, total_unapplied), indent=2)

    def items(self, arguments):
        code, partner, date_token = arguments
        account = self.require_account(code)
        date = checked_date(date_token)
        items, unapplied = self.open_items(code, partner, date)
        self.emit("ITEMS", code, account.name, partner, date_text(date))
        for item in items:
            self.emit(
                date_text(item.entry.date), item.entry.entry_id,
                "amount", money(item.original), "open", money(item.remaining),
                "age", date - item.entry.date, indent=2,
            )
        remaining = sum(item.remaining for item in items)
        self.emit("unapplied", money(unapplied), "balance", money(remaining - unapplied), indent=2)

    def show_entry(self, arguments):
        entry = self.require_entry(arguments[0])
        self.emit("ENTRY", entry.entry_id, date_text(entry.date), entry.category, entry.memo)
        for line in entry.lines:
            parts = [line.side, line.account, self.accounts[line.account].name, money(line.amount)]
            if line.partner != NO_PARTNER:
                parts.append(line.partner)
            self.emit(*parts, indent=2)
        self.emit("total", money(entry.amount()), indent=2)
        if entry.reverses is not None:
            self.emit("reverses", entry.reverses, indent=2)
        if entry.reversed_by is not None:
            self.emit("reversed", "by", entry.reversed_by, indent=2)

    def daybook(self, arguments):
        first, last = checked_range(arguments[0], arguments[1])
        self.emit("DAYBOOK", date_text(first), date_text(last))
        count = 0
        total = 0
        for entry in self.entries:
            if first <= entry.date <= last:
                count += 1
                total += entry.amount()
                self.emit(
                    date_text(entry.date), entry.entry_id, entry.category,
                    money(entry.amount()), entry.memo, indent=2,
                )
        self.emit("total", "entries", count, "amount", money(total), indent=2)

    def list_accounts(self, arguments):
        self.emit("ACCOUNTS")
        if not self.accounts:
            self.emit("(none)", indent=2)
            return
        totals = self.current_totals()
        for code in sorted(self.accounts):
            account = self.accounts[code]
            state = "active" if account.active else "inactive"
            self.emit(
                code, account.kind, account.name, "parent", self.parent(code),
                "balance", money(self.balance(code, totals)), state, indent=2,
            )

    def list_templates(self, arguments):
        self.emit("TEMPLATES")
        if not self.templates:
            self.emit("(none)", indent=2)
            return
        for name in sorted(self.templates):
            template = self.templates[name]
            self.emit(
                name, template.memo, "lines", len(template.lines),
                "amount", money(side_total(template.lines, "DR")), "used", template.uses, indent=2,
            )

    def status(self, arguments):
        inactive = sum(1 for account in self.accounts.values() if not account.active)
        open_key = "none" if self.block is None else self.block.key
        self.emit(
            "STATUS", "accounts", len(self.accounts), "inactive", inactive,
            "entries", len(self.entries), "templates", len(self.templates),
            "closed", self.closed_text(), "open", open_key,
        )

    def execute(self, line):
        command, *arguments = line.split(" ")
        handlers = {
            "ACCOUNT": self.add_account,
            "DEACTIVATE": self.deactivate,
            "JOURNAL": self.journal,
            "TEMPLATE": self.template,
            "DR": self.debit,
            "CR": self.credit,
            "POST": self.post_block,
            "DRAFT": self.draft,
            "REVERSE": self.reverse_entry,
            "RECUR": self.recur,
            "DEPRECIATE": self.depreciate,
            "INTEREST": self.interest,
            "WRITEOFF": self.write_off,
            "CLOSE": self.close,
            "REOPEN": self.reopen,
            "LEDGER": self.ledger,
            "ACTIVITY": self.activity,
            "TRIAL": self.trial,
            "INCOME": self.income,
            "BALANCE": self.balance_sheet,
            "ROLLUP": self.rollup,
            "AGING": self.aging,
            "ITEMS": self.items,
            "ENTRY": self.show_entry,
            "DAYBOOK": self.daybook,
            "ACCOUNTS": self.list_accounts,
            "TEMPLATES": self.list_templates,
            "STATUS": self.status,
        }
        try:
            handlers[command](arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    books = Books()
    count = int(sys.stdin.readline())
    for _ in range(count):
        books.execute(sys.stdin.readline().rstrip("\n"))
    if books.output:
        sys.stdout.write("\n".join(books.output) + "\n")


if __name__ == "__main__":
    main()
