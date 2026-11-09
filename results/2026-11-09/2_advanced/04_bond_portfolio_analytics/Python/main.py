from bisect import bisect_right
import os

from curve import DAYS_PER_YEAR, bootstrap, flat_curve, z_spread
from dates_calendar import (
    BUSINESS_DAY_RULES, Calendar, civil_date, format_date, is_valid_date, parse_date,
)
from daycount import DAY_COUNTS, year_fraction
from pricing import BASIS_POINT, HIGHEST_YIELD, LOWEST_YIELD, YieldPricer, bisection
from schedule import coupon_schedule


INPUT_DIR = "input"
OUTPUT_DIR = "output"
BOND_TYPES = ("FIXED", "ZERO", "AMORT", "FRN")
FREQUENCIES = (1, 2, 4, 12)
OPTION_KEYS = {
    "FIXED": ("EOM", "LONG", "CALL"),
    "ZERO": ("EOM", "LONG"),
    "AMORT": ("EOM", "LONG", "SINK"),
    "FRN": ("EOM", "LONG", "LAG", "CAP", "FLOOR"),
}
REPEATABLE_KEYS = ("SINK", "CALL")
MAX_RATE = 1200
MIN_LAG = 1
MAX_LAG = 5
FACE_STEP = 100000
MAX_FACE = 10000000
MIN_CALL_PRICE = 100000
MAX_CALL_PRICE = 110000
BUCKET_NAMES = ("0-1Y", "1-3Y", "3-5Y", "5-10Y", "10Y+")
BUCKET_LIMITS = (365, 1095, 1825, 3650)
LOSER_COUNT = 3
CASHFLOWS_HEADER = "bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal"
ANALYTICS_HEADER = (
    "bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,"
    "macaulay,modified,convexity,dv01,curve_clean,zspread"
)
SCENARIOS_HEADER = "portfolio,scenario,bond,value,pnl"


class InputError(Exception):
    pass


def round_half_up(numerator, denominator):
    return (2 * numerator + denominator) // (2 * denominator)


def hundredths(value):
    if value < 0:
        return "-" + hundredths(-value)
    return f"{value // 100}.{value % 100:02d}"


def decimals(value, digits):
    text = f"{value:.{digits}f}"
    if float(text) == 0:
        return text.lstrip("-")
    return text


def percent(value):
    return decimals(value * 100, 4)


def amount(cents):
    return decimals(cents / 100, 2)


def thousandths(price):
    whole, fraction = price.split(".")
    return int(whole) * 1000 + int(fraction)


def join_words(*parts):
    return " ".join(str(part) for part in parts)


def read_lines(name):
    with open(os.path.join(INPUT_DIR, name)) as handle:
        return handle.read().splitlines()


def read_rows(name):
    lines = read_lines(name)
    return [(number, line.split(",")) for number, line in enumerate(lines[1:], 2)]


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w") as handle:
        handle.write("".join(line + "\n" for line in lines))


class ErrorLog:
    def __init__(self):
        self.lines = []

    def add(self, file_name, number, key, error):
        self.lines.append(f"{file_name}:{number}: {key}: {error}")


class Params:
    def __init__(self, lines):
        self.valuation_date = None
        self.settlement_days = 0
        self.scenario_lines = []
        self.limits = []
        for number, line in enumerate(lines, 1):
            kind, *words = line.split(" ")
            if kind == "valuation_date":
                self.valuation_date = parse_date(words[0])
            elif kind == "settlement_days":
                self.settlement_days = int(words[0])
            elif kind == "scenario":
                shifts = [int(word) for word in words[1:]]
                self.scenario_lines.append((number, words[0], shifts))
            else:
                self.limits.append(words)


class Fixings:
    def __init__(self, rows):
        self.dates = [parse_date(fields[0]) for _, fields in rows]
        self.rates = [int(fields[1]) for _, fields in rows]

    def latest(self, day):
        index = bisect_right(self.dates, day)
        if index == 0:
            return None
        return self.rates[index - 1]


class Pillar:
    def __init__(self, maturity, coupon, frequency):
        self.maturity = maturity
        self.coupon = coupon
        self.frequency = frequency


class Scenario:
    def __init__(self, name, deltas):
        self.name = name
        self.deltas = deltas


class Options:
    def __init__(self):
        self.end_of_month = False
        self.long_stub = False
        self.lag = None
        self.cap = None
        self.floor = None
        self.sinks = []
        self.calls = []


class Period:
    def __init__(self, number, start, end, payment, fraction, rate, opening, principal):
        self.number = number
        self.start = start
        self.end = end
        self.payment = payment
        self.numerator, self.denominator = fraction
        self.rate = rate
        self.opening = opening
        self.principal = principal
        self.coupon = round_half_up(
            opening * rate * self.numerator, 10000 * self.denominator
        )
        self.cash_flow = self.coupon + principal


class Bond:
    def __init__(self, code, kind, issue, maturity, coupon, frequency, daycount, bdc, face):
        self.code = code
        self.kind = kind
        self.issue = issue
        self.maturity = maturity
        self.coupon = coupon
        self.frequency = frequency
        self.daycount = daycount
        self.bdc = bdc
        self.face = face
        self.options = Options()
        self.schedule = []
        self.sinks = {}
        self.calls = []
        self.periods = []


def parse_pillar(fields, seen, settlement):
    maturity_text = fields[0]
    coupon = int(fields[1])
    frequency = int(fields[2])
    if maturity_text in seen:
        raise InputError("duplicate pillar")
    if not is_valid_date(maturity_text):
        raise InputError("invalid date")
    maturity = parse_date(maturity_text)
    if maturity <= settlement:
        raise InputError("pillar not after settlement")
    if frequency not in FREQUENCIES:
        raise InputError("invalid frequency")
    return Pillar(maturity, coupon, frequency)


def validate_pillars(rows, settlement, errors):
    seen = set()
    pillars = []
    for number, fields in rows:
        try:
            pillars.append(parse_pillar(fields, seen, settlement))
        except InputError as error:
            errors.add("curve_quotes.csv", number, fields[0], error)
        seen.add(fields[0])
    pillars.sort(key=lambda pillar: pillar.maturity)
    return pillars


def validate_scenarios(scenario_lines, pillar_count, errors):
    seen = set()
    scenarios = []
    for number, name, shifts in scenario_lines:
        if name in seen:
            errors.add("params.txt", number, name, "duplicate scenario")
        elif len(shifts) != pillar_count:
            errors.add("params.txt", number, name, "wrong number of shifts")
        else:
            scenarios.append(Scenario(name, [shift * BASIS_POINT for shift in shifts]))
        seen.add(name)
    return scenarios


def option_items(text):
    if text == "-":
        return []
    items = []
    for item in text.split(";"):
        key, _, value = item.partition("=")
        items.append((key, value))
    return items


def valid_rate_options(options):
    cap = MAX_RATE if options.cap is None else options.cap
    if options.lag is None or not MIN_LAG <= options.lag <= MAX_LAG:
        return False
    if cap > MAX_RATE:
        return False
    return options.floor is None or options.floor <= cap


def parse_options(kind, text):
    options = Options()
    seen = set()
    for key, value in option_items(text):
        if key not in OPTION_KEYS[kind] or (key in seen and key not in REPEATABLE_KEYS):
            raise InputError("invalid option")
        seen.add(key)
        if key == "EOM":
            options.end_of_month = True
        elif key == "LONG":
            options.long_stub = True
        elif key == "LAG":
            options.lag = int(value)
        elif key == "CAP":
            options.cap = int(value)
        elif key == "FLOOR":
            options.floor = int(value)
        elif key == "SINK":
            date, cents = value.split(":")
            options.sinks.append((date, int(cents)))
        else:
            date, price = value.split(":")
            options.calls.append((date, thousandths(price)))
    if kind == "FRN" and not valid_rate_options(options):
        raise InputError("invalid option")
    return options


def schedule_days(items, schedule):
    inner_dates = set(schedule[1:-1])
    days = []
    for text, _ in items:
        if not is_valid_date(text):
            return None
        day = parse_date(text)
        if day not in inner_dates or (days and day <= days[-1]):
            return None
        days.append(day)
    return days


def sinking_fund(bond):
    items = bond.options.sinks
    days = schedule_days(items, bond.schedule)
    amounts = [cents for _, cents in items]
    if days is None or 0 in amounts:
        raise InputError("invalid sinking fund")
    total = sum(amounts)
    if bond.kind == "AMORT" and (total == 0 or total >= bond.face):
        raise InputError("invalid sinking fund")
    return dict(zip(days, amounts))


def call_schedule(bond):
    items = bond.options.calls
    days = schedule_days(items, bond.schedule)
    prices = [price for _, price in items]
    if days is None or any(not MIN_CALL_PRICE <= price <= MAX_CALL_PRICE for price in prices):
        raise InputError("invalid call schedule")
    return list(zip(days, prices))


def period_rate(bond, start, calendar, fixings):
    if bond.kind == "ZERO":
        return 0
    if bond.kind != "FRN":
        return bond.coupon
    options = bond.options
    reset = calendar.adjust(start, bond.bdc)
    index_rate = fixings.latest(calendar.business_days_before(reset, options.lag))
    if index_rate is None:
        raise InputError("missing fixing")
    rate = index_rate + bond.coupon
    if options.floor is not None:
        rate = max(rate, options.floor)
    if options.cap is not None:
        rate = min(rate, options.cap)
    return rate


def build_periods(bond, calendar, fixings):
    periods = []
    opening = bond.face
    last = len(bond.schedule) - 1
    for number in range(1, last + 1):
        start = bond.schedule[number - 1]
        end = bond.schedule[number]
        principal = opening if number == last else bond.sinks.get(end, 0)
        periods.append(Period(
            number, start, end, calendar.adjust(end, bond.bdc),
            year_fraction(bond.daycount, start, end),
            period_rate(bond, start, calendar, fixings), opening, principal,
        ))
        opening -= principal
    return periods


def parse_bond(fields, seen, calendar, fixings):
    code, kind, issue_text, maturity_text = fields[0:4]
    coupon = int(fields[4])
    frequency = int(fields[5])
    daycount = fields[6]
    bdc = fields[7]
    face = int(fields[8])
    if code in seen:
        raise InputError("duplicate id")
    if kind not in BOND_TYPES:
        raise InputError("unknown type")
    if not is_valid_date(issue_text) or not is_valid_date(maturity_text):
        raise InputError("invalid date")
    issue = parse_date(issue_text)
    maturity = parse_date(maturity_text)
    if maturity <= issue:
        raise InputError("maturity not after issue")
    if frequency not in FREQUENCIES:
        raise InputError("invalid frequency")
    if daycount not in DAY_COUNTS:
        raise InputError("unknown day count")
    if bdc not in BUSINESS_DAY_RULES:
        raise InputError("unknown business day rule")
    if face % FACE_STEP != 0 or face > MAX_FACE:
        raise InputError("invalid face")
    if coupon > MAX_RATE or (kind == "ZERO" and coupon != 0):
        raise InputError("invalid coupon")
    bond = Bond(code, kind, issue, maturity, coupon, frequency, daycount, bdc, face)
    bond.options = parse_options(kind, fields[9])
    bond.schedule = coupon_schedule(
        issue, maturity, frequency, bond.options.end_of_month, bond.options.long_stub
    )
    bond.sinks = sinking_fund(bond)
    bond.calls = call_schedule(bond)
    bond.periods = build_periods(bond, calendar, fixings)
    return bond


def validate_bonds(rows, calendar, fixings, errors):
    seen = set()
    bonds = {}
    for number, fields in rows:
        try:
            bond = parse_bond(fields, seen, calendar, fixings)
            bonds[bond.code] = bond
        except InputError as error:
            errors.add("bonds.csv", number, fields[0], error)
        seen.add(fields[0])
    return bonds


class Valuation:
    def __init__(self, bond, clean, settlement):
        self.bond = bond
        self.clean = clean
        index = 0
        while bond.periods[index].end <= settlement:
            index += 1
        current = bond.periods[index]
        self.remaining = bond.periods[index:]
        self.outstanding = current.opening
        numerator, denominator = year_fraction(bond.daycount, current.start, settlement)
        self.accrued = current.rate * numerator / (100 * denominator)
        self.accrued_amount = round_half_up(
            self.outstanding * current.rate * numerator, 10000 * denominator
        )
        self.clean_amount = round_half_up(self.outstanding * clean, 100000)
        self.unit_value = self.clean_amount + self.accrued_amount
        self.target = clean / 1000 + self.accrued
        numerator, denominator = year_fraction(bond.daycount, settlement, current.end)
        self.fraction = bond.frequency * numerator / denominator
        self.cash_flows = [period for period in self.remaining if period.cash_flow >= 1]
        self.flows = [
            (period.payment - settlement, period.cash_flow) for period in self.cash_flows
        ]
        self.pricer = YieldPricer(
            [period.cash_flow for period in self.remaining],
            self.fraction, bond.frequency, self.outstanding,
        )
        self.ytm = 0.0
        self.risk = None
        self.ytw = 0.0
        self.workout = bond.maturity
        self.wal = 0.0
        self.next_payment = self.cash_flows[0].payment
        self.curve_clean = 0.0
        self.zspread = 0.0

    def yield_to_call(self, day, price):
        flows = []
        for period in self.remaining:
            flows.append(period.coupon)
            if period.end == day:
                flows[-1] += round_half_up(period.opening * price, 100000)
                break
        pricer = YieldPricer(flows, self.fraction, self.bond.frequency, self.outstanding)
        return pricer.solve(self.target)

    def analyze(self, curve, settlement):
        self.ytm = self.pricer.solve(self.target)
        self.risk = self.pricer.risk(self.ytm)
        self.ytw = self.ytm
        for day, price in self.bond.calls:
            if day > settlement:
                call_yield = self.yield_to_call(day, price)
                if call_yield < self.ytw:
                    self.ytw = call_yield
                    self.workout = day
        principal_days = 0
        for period, (days, _) in zip(self.cash_flows, self.flows):
            principal_days += period.principal * days
        self.wal = principal_days / (DAYS_PER_YEAR * self.outstanding)
        self.curve_clean = (
            curve.present_value(self.flows, 0.0) * 100 / self.outstanding - self.accrued
        )
        self.zspread = z_spread(curve, self.flows, self.unit_value)


def parse_price(fields, bonds, seen, settlement):
    code, price = fields
    if code not in bonds:
        raise InputError("unknown bond")
    if code in seen:
        raise InputError("duplicate price")
    bond = bonds[code]
    if not bond.issue <= settlement < bond.maturity:
        raise InputError("not outstanding")
    valuation = Valuation(bond, thousandths(price), settlement)
    if not valuation.pricer.in_range(valuation.target):
        raise InputError("yield out of range")
    return valuation


def validate_prices(rows, bonds, settlement, errors):
    seen = set()
    valuations = {}
    for number, fields in rows:
        try:
            valuation = parse_price(fields, bonds, seen, settlement)
            valuations[valuation.bond.code] = valuation
        except InputError as error:
            errors.add("prices.csv", number, fields[0], error)
        seen.add(fields[0])
    return valuations


class Position:
    def __init__(self, valuation):
        self.valuation = valuation
        self.bond = valuation.bond
        self.units = 0
        self.book = 0

    def add(self, units, book_price):
        self.units += units
        self.book += round_half_up(units * self.valuation.outstanding * book_price, 100000)

    def market_value(self):
        return self.units * self.valuation.unit_value

    def face(self):
        return self.units * self.bond.face

    def outstanding(self):
        return self.units * self.valuation.outstanding

    def gain(self):
        return self.units * self.valuation.clean_amount - self.book

    def dv01(self):
        return self.valuation.risk.dv01 * self.units * self.valuation.outstanding / 10000

    def present_value(self, curve):
        valuation = self.valuation
        return self.units * curve.present_value(valuation.flows, valuation.zspread)


def holding_units(code, face, bonds, valuations):
    if code not in bonds:
        raise InputError("unknown bond")
    if code not in valuations:
        raise InputError("no price")
    if face % bonds[code].face != 0:
        raise InputError("invalid face")
    return face // bonds[code].face


def validate_holdings(rows, bonds, valuations, errors):
    positions = {}
    for number, fields in rows:
        portfolio, code, face, book_price = fields
        try:
            units = holding_units(code, int(face), bonds, valuations)
        except InputError as error:
            errors.add("holdings.csv", number, code, error)
            continue
        key = (portfolio, code)
        if key not in positions:
            positions[key] = Position(valuations[code])
        positions[key].add(units, thousandths(book_price))
    return positions


def bucket_index(days):
    for index, limit in enumerate(BUCKET_LIMITS):
        if days < limit:
            return index
    return len(BUCKET_LIMITS)


def shift_vector(count, pillar, size):
    return [size if pillar is None or index == pillar else 0.0 for index in range(count)]


class Group:
    def __init__(self, name):
        self.name = name
        self.count = 0
        self.value = 0
        self.duration = 0.0
        self.dv01 = 0.0

    def add(self, position):
        value = position.market_value()
        self.count += 1
        self.value += value
        self.duration += value * position.valuation.risk.modified
        self.dv01 += position.dv01()


class ScenarioResult:
    def __init__(self, name, values, base_values, total, base_total):
        self.name = name
        self.values = values
        self.pnls = [value - base for value, base in zip(values, base_values)]
        self.total = total
        self.pnl = total - base_total


class Portfolio:
    def __init__(self, name, positions):
        self.name = name
        self.positions = positions
        self.total_value = sum(position.market_value() for position in positions)
        self.ytm = 0.0
        self.modified = 0.0
        self.convexity = 0.0
        self.zspread = 0.0
        self.dv01 = 0.0
        self.cash_yield = 0.0
        self.base_values = []
        self.base_value = 0.0
        self.effective = 0.0
        self.key_rates = []
        self.types = [Group(kind) for kind in BOND_TYPES]
        self.buckets = [Group(name) for name in BUCKET_NAMES]
        self.ladder = []
        self.results = []

    def weight(self, value):
        return value * 100 / self.total_value

    def income(self):
        total = 0
        for position in self.positions:
            for period, (days, _) in zip(position.valuation.cash_flows, position.valuation.flows):
                if days <= DAYS_PER_YEAR:
                    total += position.units * period.coupon
        return total

    def measure_risk(self):
        ytm = 0.0
        modified = 0.0
        convexity = 0.0
        zspread = 0.0
        dv01 = 0.0
        for position in self.positions:
            value = position.market_value()
            valuation = position.valuation
            ytm += value * valuation.ytm
            modified += value * valuation.risk.modified
            convexity += value * valuation.risk.convexity
            zspread += value * valuation.zspread
            dv01 += position.dv01()
        self.dv01 = dv01
        self.ytm = ytm / self.total_value
        self.modified = modified / self.total_value
        self.convexity = convexity / self.total_value
        self.zspread = zspread / self.total_value

    def cash_flow_yield(self):
        flows = []
        for position in self.positions:
            for days, cash_flow in position.valuation.flows:
                flows.append((days, position.units * cash_flow))
        return bisection(
            lambda rate: flat_curve(rate).present_value(flows, 0.0),
            LOWEST_YIELD, HIGHEST_YIELD, self.total_value,
        )

    def present_value(self, curve):
        total = 0.0
        for position in self.positions:
            total += position.present_value(curve)
        return total

    def rate_duration(self, curve, pillar):
        count = len(curve.rates)
        down = self.present_value(curve.shifted(shift_vector(count, pillar, -BASIS_POINT)))
        up = self.present_value(curve.shifted(shift_vector(count, pillar, BASIS_POINT)))
        return (down - up) / (2 * BASIS_POINT * self.base_value)

    def group_positions(self, settlement):
        for position in self.positions:
            self.types[BOND_TYPES.index(position.bond.kind)].add(position)
            self.buckets[bucket_index(position.bond.maturity - settlement)].add(position)

    def build_ladder(self):
        years = {}
        for position in self.positions:
            for period in position.valuation.cash_flows:
                year = civil_date(period.payment)[0]
                coupon, principal = years.get(year, (0, 0))
                years[year] = (
                    coupon + position.units * period.coupon,
                    principal + position.units * period.principal,
                )
        self.ladder = sorted(years.items())

    def run_scenarios(self, curve, scenarios):
        base = Scenario("BASE", [0.0] * len(curve.rates))
        for scenario in [base] + scenarios:
            shifted = curve.shifted(scenario.deltas)
            values = []
            total = 0.0
            for position in self.positions:
                value = position.present_value(shifted)
                values.append(value)
                total += value
            self.results.append(ScenarioResult(
                scenario.name, values, self.base_values, total, self.base_value
            ))

    def analyze(self, curve, scenarios, settlement):
        self.measure_risk()
        self.cash_yield = self.cash_flow_yield()
        self.base_values = [position.present_value(curve) for position in self.positions]
        self.base_value = 0.0
        for value in self.base_values:
            self.base_value += value
        self.effective = self.rate_duration(curve, None)
        self.key_rates = [self.rate_duration(curve, pillar) for pillar in range(len(curve.rates))]
        self.group_positions(settlement)
        self.build_ladder()
        self.run_scenarios(curve, scenarios)

    def worst_scenario(self):
        worst = None
        for result in self.results[1:]:
            if worst is None or result.pnl < worst.pnl:
                worst = result
        return worst

    def position_line(self, position):
        valuation = position.valuation
        value = position.market_value()
        return join_words(
            "position", position.bond.code,
            "face", hundredths(position.face()),
            "outstanding", hundredths(position.outstanding()),
            "clean", decimals(valuation.clean / 1000, 6),
            "value", hundredths(value),
            "weight", decimals(self.weight(value), 4),
            "book", hundredths(position.book),
            "gain", hundredths(position.gain()),
            "ytm", percent(valuation.ytm),
            "modified", decimals(valuation.risk.modified, 4),
            "dv01", decimals(position.dv01(), 2),
        )

    def totals_line(self):
        face = 0
        outstanding = 0
        book = 0
        gain = 0
        for position in self.positions:
            face += position.face()
            outstanding += position.outstanding()
            book += position.book
            gain += position.gain()
        return join_words(
            "total", "positions", len(self.positions),
            "face", hundredths(face), "outstanding", hundredths(outstanding),
            "value", hundredths(self.total_value), "book", hundredths(book),
            "gain", hundredths(gain), "income", hundredths(self.income()),
        )

    def group_line(self, label, group):
        return join_words(
            label, group.name, "positions", group.count,
            "value", hundredths(group.value),
            "weight", decimals(self.weight(group.value), 4),
            "duration", decimals(group.duration / self.total_value, 4),
            "dv01", decimals(group.dv01, 2),
        )

    def stress_line(self, worst):
        order = sorted(range(len(self.positions)), key=lambda index: worst.pnls[index])
        parts = ["stress", "worst", worst.name, "pnl", amount(worst.pnl), "losers"]
        for index in order[:LOSER_COUNT]:
            parts.extend((self.positions[index].bond.code, amount(worst.pnls[index])))
        return join_words(*parts)

    def report_lines(self):
        lines = [join_words("portfolio", self.name)]
        lines.extend(self.position_line(position) for position in self.positions)
        lines.append(self.totals_line())
        lines.append(join_words(
            "risk", "ytm", percent(self.ytm), "yield", percent(self.cash_yield),
            "modified", decimals(self.modified, 4), "convexity", decimals(self.convexity, 4),
            "zspread", percent(self.zspread), "dv01", decimals(self.dv01, 2),
        ))
        lines.append(join_words(
            "curve", "effective", decimals(self.effective, 4),
            "krd", *(decimals(duration, 4) for duration in self.key_rates),
        ))
        lines.extend(self.group_line("type", group) for group in self.types)
        lines.extend(self.group_line("bucket", group) for group in self.buckets)
        total_coupon = 0
        total_principal = 0
        for year, (coupon, principal) in self.ladder:
            lines.append(join_words(
                "ladder", year, "coupon", hundredths(coupon),
                "principal", hundredths(principal), "total", hundredths(coupon + principal),
            ))
            total_coupon += coupon
            total_principal += principal
        lines.append(join_words(
            "ladder", "total", "coupon", hundredths(total_coupon),
            "principal", hundredths(total_principal),
            "total", hundredths(total_coupon + total_principal),
        ))
        worst = self.worst_scenario()
        if worst is not None:
            lines.append(self.stress_line(worst))
        return lines

    def scenario_lines(self):
        lines = []
        for result in self.results:
            for position, value, pnl in zip(self.positions, result.values, result.pnls):
                lines.append(",".join(
                    (self.name, result.name, position.bond.code, amount(value), amount(pnl))
                ))
            lines.append(",".join(
                (self.name, result.name, "*", amount(result.total), amount(result.pnl))
            ))
        return lines

    def largest_position(self):
        largest = self.positions[0]
        for position in self.positions:
            if position.market_value() > largest.market_value():
                largest = position
        return largest

    def check_limit(self, words, settlement):
        kind = words[0]
        if kind == "position_weight":
            limit = int(words[1])
            largest = self.largest_position()
            value = largest.market_value()
            weight = decimals(self.weight(value), 4)
            parts = [largest.bond.code, weight, "limit", hundredths(limit)]
            return parts, value * 10000 > limit * self.total_value
        if kind == "type_weight":
            limit = int(words[2])
            value = self.types[BOND_TYPES.index(words[1])].value
            parts = [words[1], decimals(self.weight(value), 4), "limit", hundredths(limit)]
            return parts, value * 10000 > limit * self.total_value
        if kind == "max_maturity":
            years = int(words[1])
            count = 0
            for position in self.positions:
                if position.bond.maturity - settlement > DAYS_PER_YEAR * years:
                    count += 1
            return [f"{years}Y", "positions", count], count >= 1
        if kind == "min_yield":
            limit = int(words[1])
            parts = [percent(self.ytm), "limit", hundredths(limit)]
            return parts, self.ytm * 10000 < limit
        if kind == "duration":
            low = int(words[1])
            high = int(words[2])
            parts = [decimals(self.modified, 4), "range", hundredths(low), hundredths(high)]
            return parts, self.modified < low / 100 or self.modified > high / 100
        limit = int(words[1])
        parts = [decimals(self.dv01, 2), "limit", hundredths(limit)]
        return parts, self.dv01 * 100 > limit

    def compliance_lines(self, limits, settlement):
        lines = []
        breaches = 0
        for words in limits:
            parts, breach = self.check_limit(words, settlement)
            if breach:
                breaches += 1
            lines.append(join_words(self.name, words[0], *parts, "BREACH" if breach else "PASS"))
        lines.append(join_words(self.name, "breaches", breaches))
        return lines


def build_portfolios(positions):
    names = sorted({name for name, _ in positions})
    portfolios = []
    for name in names:
        members = [positions[key] for key in sorted(positions) if key[0] == name]
        portfolios.append(Portfolio(name, members))
    return portfolios


def cashflow_lines(bonds):
    lines = [CASHFLOWS_HEADER]
    for code in sorted(bonds):
        for period in bonds[code].periods:
            if period.cash_flow >= 1:
                lines.append(",".join((
                    code, str(period.number), format_date(period.start),
                    format_date(period.end), format_date(period.payment),
                    decimals(period.numerator / period.denominator, 6), str(period.rate),
                    str(period.opening), str(period.coupon), str(period.principal),
                )))
    return lines


def analytics_lines(valuations):
    lines = [ANALYTICS_HEADER]
    for code in sorted(valuations):
        valuation = valuations[code]
        risk = valuation.risk
        lines.append(",".join((
            code,
            decimals(valuation.clean / 1000, 6),
            decimals(valuation.accrued, 6),
            decimals(valuation.target, 6),
            percent(valuation.ytm),
            percent(valuation.ytw),
            format_date(valuation.workout),
            format_date(valuation.next_payment),
            decimals(valuation.wal, 4),
            decimals(risk.macaulay, 4),
            decimals(risk.modified, 4),
            decimals(risk.convexity, 4),
            decimals(risk.dv01, 6),
            decimals(valuation.curve_clean, 6),
            percent(valuation.zspread),
        )))
    return lines


def curve_lines(valuation_date, settlement, pillars, curve):
    lines = [join_words(
        "valuation", format_date(valuation_date), "settlement", format_date(settlement)
    )]
    previous = 0
    for pillar, days, rate in zip(pillars, curve.days, curve.rates):
        lines.append(join_words(
            "pillar", format_date(pillar.maturity), "days", days,
            "frequency", pillar.frequency, "par", hundredths(pillar.coupon),
            "zero", percent(rate), "df", decimals(curve.discount(days, 0.0), 6),
            "forward", percent(curve.forward(previous, days)),
        ))
        previous = days
    for year in range(1, curve.days[-1] // DAYS_PER_YEAR + 1):
        days = DAYS_PER_YEAR * year
        lines.append(join_words(
            "grid", f"{year}Y", "days", days, "zero", percent(curve.zero_rate(days)),
            "df", decimals(curve.discount(days, 0.0), 6),
            "forward", percent(curve.forward(days - DAYS_PER_YEAR, days)),
        ))
    return lines


def main():
    params = Params(read_lines("params.txt"))
    calendar = Calendar([parse_date(line) for line in read_lines("calendar.txt")])
    fixings = Fixings(read_rows("fixings.csv"))
    settlement = calendar.business_days_after(params.valuation_date, params.settlement_days)
    errors = ErrorLog()
    pillars = validate_pillars(read_rows("curve_quotes.csv"), settlement, errors)
    scenarios = validate_scenarios(params.scenario_lines, len(pillars), errors)
    bonds = validate_bonds(read_rows("bonds.csv"), calendar, fixings, errors)
    valuations = validate_prices(read_rows("prices.csv"), bonds, settlement, errors)
    positions = validate_holdings(read_rows("holdings.csv"), bonds, valuations, errors)
    curve = bootstrap(
        settlement, [(pillar.maturity, pillar.coupon, pillar.frequency) for pillar in pillars]
    )
    for valuation in valuations.values():
        valuation.analyze(curve, settlement)
    portfolios = build_portfolios(positions)
    for portfolio in portfolios:
        portfolio.analyze(curve, scenarios, settlement)
    report = []
    scenario_rows = [SCENARIOS_HEADER]
    compliance = []
    for portfolio in portfolios:
        report.extend(portfolio.report_lines())
        scenario_rows.extend(portfolio.scenario_lines())
        compliance.extend(portfolio.compliance_lines(params.limits, settlement))
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_lines("errors.txt", errors.lines)
    write_lines("cashflows.csv", cashflow_lines(bonds))
    write_lines("analytics.csv", analytics_lines(valuations))
    write_lines("curve.txt", curve_lines(params.valuation_date, settlement, pillars, curve))
    write_lines("portfolio.txt", report)
    write_lines("scenarios.csv", scenario_rows)
    write_lines("compliance.txt", compliance)


if __name__ == "__main__":
    main()
