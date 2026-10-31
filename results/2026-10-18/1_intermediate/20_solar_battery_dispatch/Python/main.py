import sys
from collections import Counter
from itertools import groupby
from math import gcd


SETTING_RANGES = {
    "CAPACITY": (1, 100000),
    "INITIAL": (0, 100),
    "CHARGE": (1, 20000),
    "DISCHARGE": (1, 20000),
    "CEFF": (1, 100),
    "DEFF": (1, 100),
    "RESERVE": (0, 100),
    "COST": (0, 100000),
    "EXPORT": (0, 100000),
    "FEEDIN": (0, 10000),
    "FIXED": (0, 100000),
    "DEMAND": (0, 100000),
    "PVSCALE": (0, 300),
}
STRATEGY_RANGES = {
    "TOU": (1, 100),
    "PEAKSHAVE": (0, 100000),
    "BACKUP": (0, 100),
}
FLOW_NAMES = (
    "PV>LOAD", "PV>BATTERY", "PV>GRID", "PV>CURTAIL",
    "BATTERY>LOAD", "BATTERY>GRID", "GRID>LOAD", "GRID>BATTERY",
)
TOTAL_FIELDS = (
    "load", "pv", "charge", "discharge", "imported", "exported",
    "curtailed", "drawn", "loss", "shortfall", "import_cost", "export_income",
)
DAY_NAMES = ("MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN")


class CommandError(Exception):
    pass


def money(value):
    sign = "-" if value < 0 else ""
    whole, fraction = divmod(abs(value), 100)
    return f"{sign}{whole}.{fraction:02d}"


def percentage(numerator, denominator):
    value = 10000 * numerator // denominator if denominator else 0
    return f"{value // 100}.{value % 100:02d}"


def ceiling(numerator, denominator):
    return (numerator + denominator - 1) // denominator


def truncate_divide(value, divisor):
    quotient = abs(value) // divisor
    return -quotient if value < 0 else quotient


def table_row(values, widths):
    return "".join(str(value).rjust(width) for value, width in zip(values, widths))


def bar(width):
    return "|" + "#" * width + "." * (20 - width) + "|"


def tariff_extremes(prices):
    return min(prices, key=prices.get), max(prices, key=prices.get)


def strategy_text(strategy):
    name, parameter = strategy
    return name if parameter is None else f"{name} {parameter}"


def read_strategies(tokens):
    strategies = []
    index = 0
    while index < len(tokens):
        name = tokens[index]
        index += 1
        if name in ("SELF", "EXPORTPEAK"):
            strategies.append((name, None))
            continue
        if name not in STRATEGY_RANGES:
            raise CommandError(f"unknown strategy {name}")
        if index == len(tokens):
            raise CommandError(f"missing parameter for {name}")
        parameter = int(tokens[index])
        index += 1
        low, high = STRATEGY_RANGES[name]
        if not low <= parameter <= high:
            raise CommandError(f"invalid parameter for {name}")
        strategies.append((name, parameter))
    return strategies


def one_strategy(tokens):
    strategies = read_strategies(tokens)
    require_count(strategies, 1)
    return strategies[0]


def require_count(arguments, count):
    if len(arguments) != count:
        raise CommandError("wrong number of arguments")


def checked_range(low, high, step, bounds):
    minimum, maximum = bounds
    if low < minimum or high > maximum or high < low or step < 1:
        raise CommandError("invalid range")
    if (high - low) // step + 1 > 20:
        raise CommandError("invalid range")
    return range(low, high + 1, step)


class InputData:
    def __init__(self, source):
        battery = list(map(int, source.readline().split()[1:]))
        grid = list(map(int, source.readline().split()[1:]))
        self.initial_settings = dict(zip(SETTING_RANGES, battery + grid + [100]))
        period_count = int(source.readline().split()[1])
        self.initial_prices = {}
        for _ in range(period_count):
            name, price = source.readline().split()
            self.initial_prices[name] = int(price)
        weekday = self.read_period_hours(source.readline().split()[1:])
        weekend = self.read_period_hours(source.readline().split()[1:])
        profile_count = int(source.readline().split()[1])
        profiles = {}
        for _ in range(profile_count):
            kind, name, *values = source.readline().split()
            profiles[kind, name] = tuple(map(int, values))
        self.day_count = int(source.readline().split()[1])
        loads = []
        base_pv = []
        for _ in range(self.day_count):
            load_name, load_pct, pv_name, pv_pct = source.readline().split()
            loads.extend(value * int(load_pct) // 100
                         for value in profiles["LOAD", load_name])
            base_pv.extend(value * int(pv_pct) // 100
                           for value in profiles["PV", pv_name])
        holidays = set(map(int, source.readline().split()[2:]))
        override_count = int(source.readline().split()[1])
        for _ in range(override_count):
            day, hour, load, pv = map(int, source.readline().split())
            index = (day - 1) * 24 + hour
            loads[index] = load
            base_pv[index] = pv
        self.loads = tuple(loads)
        self.base_pv = tuple(base_pv)
        self.day_names = tuple(
            "HOL" if day in holidays else DAY_NAMES[(day - 1) % 7]
            for day in range(1, self.day_count + 1)
        )
        self.weekend_days = tuple(
            day in holidays or (day - 1) % 7 >= 5
            for day in range(1, self.day_count + 1)
        )
        self.periods = tuple(
            period
            for is_weekend in self.weekend_days
            for period in (weekend if is_weekend else weekday)
        )

    @staticmethod
    def read_period_hours(tokens):
        hours = []
        for index in range(0, len(tokens), 2):
            start = int(tokens[index])
            end = int(tokens[index + 2]) if index + 2 < len(tokens) else 24
            hours.extend([tokens[index + 1]] * (end - start))
        return tuple(hours)


class HourRecord:
    def __init__(self, index, period, load, pv, soc, flows, drawn,
                 shortfall, loss, price, feedin):
        self.index = index
        self.day = index // 24 + 1
        self.hour = index % 24
        self.period = period
        self.load = load
        self.pv = pv
        self.soc = soc
        self.flows = flows
        self.charge = flows[1] + flows[7]
        self.discharge = flows[4] + flows[5]
        self.imported = flows[6] + flows[7]
        self.exported = flows[2] + flows[5]
        self.curtailed = flows[3]
        self.drawn = drawn
        self.shortfall = shortfall
        self.loss = loss
        self.import_cost = self.imported * price // 100000
        self.export_income = self.exported * feedin // 100000
        self.net_cost = self.import_cost - self.export_income


class Totals:
    def __init__(self, records):
        self.count = len(records)
        for field in TOTAL_FIELDS:
            setattr(self, field, sum(getattr(record, field) for record in records))
        self.flows = tuple(sum(record.flows[index] for record in records)
                           for index in range(len(FLOW_NAMES)))
        self.net_cost = self.import_cost - self.export_income


class SimulationResult:
    def __init__(self, strategy, settings, prices, start_soc, reserve, records):
        self.strategy = strategy
        self.settings = settings.copy()
        self.prices = prices.copy()
        self.start_soc = start_soc
        self.reserve = reserve
        self.hours = tuple(records)
        self.days = tuple(self.hours[start:start + 24]
                          for start in range(0, len(records), 24))
        self.daily = tuple(Totals(day) for day in self.days)
        self.by_period = {
            period: Totals(tuple(record for record in records if record.period == period))
            for period in prices
        }
        self.total = Totals(self.hours)
        self.peak = max(record.imported for record in self.hours)
        self.demand_charge = self.peak * settings["DEMAND"] // 1000
        self.bill = self.total.net_cost + settings["FIXED"] + self.demand_charge
        self.end_soc = self.hours[-1].soc
        self.sufficiency = percentage(
            max(0, self.total.load - self.total.imported), self.total.load
        )


class Simulator:
    def __init__(self, data, strategy, settings, prices, outage=None):
        self.data = data
        self.strategy = strategy
        self.name, self.parameter = strategy
        self.settings = settings.copy()
        self.prices = prices.copy()
        self.outage = outage
        self.capacity = settings["CAPACITY"]
        self.ceff = settings["CEFF"]
        self.deff = settings["DEFF"]
        reserve_pct = settings["RESERVE"]
        if self.name == "BACKUP":
            reserve_pct = max(reserve_pct, self.parameter)
        self.reserve = self.capacity * reserve_pct // 100
        self.start_soc = self.capacity * settings["INITIAL"] // 100
        self.soc = self.start_soc
        self.cheapest, self.peak = tariff_extremes(prices)
        self.arbitrage = (self.name == "EXPORTPEAK"
                          and settings["FEEDIN"] > prices[self.cheapest])

    def discharge_target(self, deficit, period):
        if self.name == "TOU":
            return deficit if period == self.peak else 0
        if self.name == "PEAKSHAVE":
            return max(0, deficit - self.parameter)
        if (self.arbitrage and period == self.cheapest
                and period != self.peak):
            return 0
        return deficit

    def grid_charge(self, period, pv_charge, grid_load):
        headroom = self.settings["CHARGE"] - pv_charge
        target = None
        if self.name == "TOU" and period == self.cheapest and period != self.peak:
            target = self.capacity * self.parameter // 100
        elif self.name == "PEAKSHAVE" and period == self.cheapest:
            target = self.capacity
            headroom = min(headroom, max(0, self.parameter - grid_load))
        elif self.name == "BACKUP" and period == self.cheapest:
            target = self.reserve
        elif self.arbitrage and period == self.cheapest and period != self.peak:
            target = self.capacity
        if target is None:
            return 0
        amount = min(headroom, ceiling(100 * max(0, target - self.soc), self.ceff))
        self.soc += amount * self.ceff // 100
        return amount

    def run_hour(self, index):
        settings = self.settings
        load = self.data.loads[index]
        pv = self.data.base_pv[index] * settings["PVSCALE"] // 100
        period = self.data.periods[index]
        direct = min(load, pv)
        surplus = pv - direct
        deficit = load - direct
        pv_charge = min(surplus, settings["CHARGE"],
                        ceiling(100 * (self.capacity - self.soc), self.ceff))
        self.soc += pv_charge * self.ceff // 100
        surplus -= pv_charge
        is_outage = (self.outage is not None
                     and self.outage[0] <= index <= self.outage[1])
        target = deficit if is_outage else self.discharge_target(deficit, period)
        lower_bound = 0 if is_outage else self.reserve
        load_drawn = min(ceiling(100 * target, self.deff), settings["DISCHARGE"],
                         max(0, self.soc - lower_bound))
        load_discharge = load_drawn * self.deff // 100
        self.soc -= load_drawn
        deficit -= load_discharge
        if is_outage:
            grid_load = 0
            shortfall = deficit
            pv_export = 0
            curtailed = surplus
            grid_charge = 0
            export_drawn = 0
            battery_export = 0
        else:
            grid_load = deficit
            shortfall = 0
            pv_export = min(surplus, settings["EXPORT"])
            curtailed = surplus - pv_export
            grid_charge = self.grid_charge(period, pv_charge, grid_load)
            export_drawn = 0
            battery_export = 0
            if self.arbitrage and period == self.peak and pv_charge == 0:
                export_drawn = min(
                    ceiling(100 * (settings["EXPORT"] - pv_export), self.deff),
                    settings["DISCHARGE"] - load_drawn,
                    max(0, self.soc - self.reserve),
                )
                battery_export = export_drawn * self.deff // 100
                self.soc -= export_drawn
        loss = (pv_charge - pv_charge * self.ceff // 100
                + grid_charge - grid_charge * self.ceff // 100
                + load_drawn - load_discharge + export_drawn - battery_export)
        flows = (direct, pv_charge, pv_export, curtailed, load_discharge,
                 battery_export, grid_load, grid_charge)
        return HourRecord(index, period, load, pv, self.soc, flows,
                          load_drawn + export_drawn, shortfall, loss,
                          self.prices[period], settings["FEEDIN"])

    def run(self):
        records = [self.run_hour(index) for index in range(len(self.data.loads))]
        return SimulationResult(self.strategy, self.settings, self.prices,
                                self.start_soc, self.reserve, records)


class DispatchDesk:
    def __init__(self, data):
        self.data = data
        self.settings = data.initial_settings.copy()
        self.prices = data.initial_prices.copy()
        self.current = None
        self.handlers = {
            "RUN": self.run, "SET": self.set_value, "PRICE": self.price,
            "RESET": self.reset, "CONFIG": self.config, "NOBATTERY": self.no_battery,
            "COMPARE": self.compare, "SIZE": self.size, "SWEEP": self.sweep,
            "OUTAGE": self.outage, "DIFF": self.diff, "HOURLY": self.hourly,
            "DAILY": self.daily, "BILL": self.bill, "SAVINGS": self.savings,
            "BYPERIOD": self.by_period, "DAYTYPE": self.day_type, "PEAKS": self.peaks,
            "PROFILE": self.profile, "FLOWS": self.flows, "SELFSUFF": self.self_suff,
            "CYCLES": self.cycles, "USAGE": self.usage, "HISTOGRAM": self.histogram,
            "CHART": self.chart,
        }

    def execute(self, tokens):
        command, *arguments = tokens
        if command not in self.handlers:
            return [f"ERROR unknown command {command}"]
        try:
            return self.handlers[command](arguments)
        except CommandError as error:
            return [f"ERROR {error}"]

    def require_result(self):
        if self.current is None:
            raise CommandError("no run")
        return self.current

    def checked_day(self, token):
        day = int(token)
        if not 1 <= day <= self.data.day_count:
            raise CommandError("invalid day")
        return day

    def result_without_arguments(self, arguments):
        require_count(arguments, 0)
        return self.require_result()

    def result_for_day(self, arguments):
        require_count(arguments, 1)
        day = self.checked_day(arguments[0])
        return day, self.require_result()

    def simulate(self, strategy, settings=None, prices=None, outage=None):
        if settings is None:
            settings = self.settings
        if prices is None:
            prices = self.prices
        return Simulator(self.data, strategy, settings, prices, outage).run()

    def baseline(self, settings, prices):
        without_battery = settings.copy()
        without_battery["CAPACITY"] = 0
        return self.simulate(("SELF", None), without_battery, prices)

    def run(self, arguments):
        strategy = one_strategy(arguments)
        result = self.simulate(strategy)
        self.current = result
        total = result.total
        return [f"RUN {strategy_text(strategy)} bill {money(result.bill)} "
                f"import {total.imported} export {total.exported} soc {result.end_soc}"]

    def set_value(self, arguments):
        require_count(arguments, 2)
        item, token = arguments
        if item not in SETTING_RANGES:
            raise CommandError(f"unknown parameter {item}")
        value = int(token)
        low, high = SETTING_RANGES[item]
        if not low <= value <= high:
            raise CommandError(f"invalid value for {item}")
        previous = self.settings[item]
        self.settings[item] = value
        return [f"SET {item} {previous} -> {value}"]

    def price(self, arguments):
        require_count(arguments, 2)
        period, token = arguments
        if period not in self.prices:
            raise CommandError(f"unknown period {period}")
        value = int(token)
        if not 0 <= value <= 10000:
            raise CommandError(f"invalid value for {period}")
        previous = self.prices[period]
        self.prices[period] = value
        cheapest, peak = tariff_extremes(self.prices)
        return [f"PRICE {period} {previous} -> {value} cheapest {cheapest} peak {peak}"]

    def reset(self, arguments):
        require_count(arguments, 0)
        self.settings = self.data.initial_settings.copy()
        self.prices = self.data.initial_prices.copy()
        return ["RESET"]

    def config(self, arguments):
        require_count(arguments, 0)
        settings = self.settings
        battery = " ".join(f"{item.lower()} {settings[item]}"
                           for item in tuple(SETTING_RANGES)[:8])
        grid = " ".join(f"{item.lower()} {settings[item]}"
                        for item in tuple(SETTING_RANGES)[8:12])
        tariff = " ".join(f"{period} {price}" for period, price in self.prices.items())
        cheapest, peak = tariff_extremes(self.prices)
        return [f"BATTERY {battery}", f"GRID {grid}",
                f"SOLAR pvscale {settings['PVSCALE']}",
                f"TARIFF {tariff} cheapest {cheapest} peak {peak}"]

    def no_battery(self, arguments):
        require_count(arguments, 0)
        result = self.baseline(self.settings, self.prices)
        total = result.total
        return [f"NOBATTERY bill {money(result.bill)} import {total.imported} "
                f"export {total.exported} curtailed {total.curtailed} peak {result.peak}"]

    def compare(self, arguments):
        strategies = read_strategies(arguments)
        if not strategies:
            raise CommandError("wrong number of arguments")
        baseline = self.baseline(self.settings, self.prices)
        trials = [self.simulate(strategy) for strategy in strategies]
        trials.sort(key=lambda result: result.bill)
        output = [f"COMPARE baseline {money(baseline.bill)}"]
        for rank, result in enumerate(trials, 1):
            output.append(f"{rank}. {strategy_text(result.strategy)} "
                          f"bill {money(result.bill)} saving {money(baseline.bill - result.bill)} "
                          f"sufficiency {result.sufficiency}%")
        return output

    def size(self, arguments):
        require_count(arguments, 3)
        capacities = checked_range(*map(int, arguments), SETTING_RANGES["CAPACITY"])
        baseline = self.baseline(self.settings, self.prices)
        output = []
        best = None
        for capacity in capacities:
            settings = self.settings.copy()
            settings["CAPACITY"] = capacity
            result = self.simulate(("SELF", None), settings)
            saving = baseline.bill - result.bill
            cost = capacity * settings["COST"] // 1000
            payback = "never"
            if saving > 0:
                tenths = 10 * cost // saving
                payback = f"{tenths // 10}.{tenths % 10}"
                if best is None or cost * best[2] < best[1] * saving:
                    best = (capacity, cost, saving)
            output.append(f"SIZE {capacity} bill {money(result.bill)} saving {money(saving)} "
                          f"cost {money(cost)} payback {payback}")
        output.append(f"BEST {best[0]}" if best is not None else "BEST none")
        return output

    def sweep(self, arguments):
        if len(arguments) < 5:
            raise CommandError("wrong number of arguments")
        item = arguments[0]
        if item not in SETTING_RANGES:
            raise CommandError(f"unknown parameter {item}")
        values = checked_range(*map(int, arguments[1:4]), SETTING_RANGES[item])
        strategy = one_strategy(arguments[4:])
        output = []
        best = None
        for value in values:
            settings = self.settings.copy()
            settings[item] = value
            result = self.simulate(strategy, settings)
            baseline = self.baseline(settings, self.prices)
            if best is None or result.bill < best[1]:
                best = (value, result.bill)
            output.append(f"SWEEP {item} {value} bill {money(result.bill)} "
                          f"saving {money(baseline.bill - result.bill)} "
                          f"sufficiency {result.sufficiency}%")
        output.append(f"BEST {best[0]}")
        return output

    def outage(self, arguments):
        require_count(arguments, 3)
        day = self.checked_day(arguments[0])
        start, end = map(int, arguments[1:])
        if not 0 <= start <= end <= 23:
            raise CommandError("invalid hours")
        current = self.require_result()
        first = (day - 1) * 24 + start
        last = (day - 1) * 24 + end
        result = self.simulate(current.strategy, current.settings, current.prices,
                               (first, last))
        before = result.hours[first - 1].soc if first else result.start_soc
        output = [f"OUTAGE day {day} hours {start}-{end} "
                  f"strategy {strategy_text(result.strategy)} soc {before}",
                  "hour   load     pv  disch    soc  short   curt"]
        records = result.hours[first:last + 1]
        for record in records:
            output.append(table_row(
                (record.hour, record.load, record.pv, record.discharge,
                 record.soc, record.shortfall, record.curtailed), (4,) + (7,) * 6
            ))
        total = Totals(records)
        served = percentage(total.load - total.shortfall, total.load) if total.load else "100.00"
        output.append(f"TOTAL load {total.load} unserved {total.shortfall} "
                      f"served {served}% bill {money(result.bill)}")
        return output

    def diff(self, arguments):
        if len(arguments) < 2:
            raise CommandError("wrong number of arguments")
        day = self.checked_day(arguments[0])
        strategy = one_strategy(arguments[1:])
        current = self.require_result()
        comparison = self.simulate(strategy, current.settings, current.prices)
        output = [f"DIFF day {day} {self.data.day_names[day - 1]} "
                  f"{strategy_text(current.strategy)} vs {strategy_text(strategy)}",
                  "hour   imp1   imp2   exp1   exp2   soc1   soc2"]
        for first, second in zip(current.days[day - 1], comparison.days[day - 1]):
            output.append(table_row(
                (first.hour, first.imported, second.imported, first.exported,
                 second.exported, first.soc, second.soc), (4,) + (7,) * 6
            ))
        cost1 = current.daily[day - 1].net_cost
        cost2 = comparison.daily[day - 1].net_cost
        output.append(f"TOTAL cost1 {money(cost1)} cost2 {money(cost2)} "
                      f"difference {money(cost2 - cost1)}")
        return output

    def hourly(self, arguments):
        day, result = self.result_for_day(arguments)
        output = [f"HOURLY day {day} {self.data.day_names[day - 1]} "
                  f"strategy {strategy_text(result.strategy)}",
                  "hour   load     pv charge  disch    soc import export   curt"]
        widths = (4,) + (7,) * 8
        for record in result.days[day - 1]:
            output.append(table_row(
                (record.hour, record.load, record.pv, record.charge, record.discharge,
                 record.soc, record.imported, record.exported, record.curtailed), widths
            ))
        total = result.daily[day - 1]
        output.append(table_row(
            ("sum", total.load, total.pv, total.charge, total.discharge,
             "", total.imported, total.exported, total.curtailed), widths
        ))
        return output

    def daily(self, arguments):
        result = self.result_without_arguments(arguments)
        output = [f"DAILY strategy {strategy_text(result.strategy)}",
                  "day name    load      pv  import  export    curt     soc      cost"]
        for day, total in enumerate(result.daily, 1):
            output.append(table_row(
                (day, self.data.day_names[day - 1], total.load, total.pv,
                 total.imported, total.exported, total.curtailed,
                 result.days[day - 1][-1].soc, money(total.net_cost)),
                (3, 5, 8, 8, 8, 8, 8, 8, 10),
            ))
        total = result.total
        output.append(f"TOTAL load {total.load} pv {total.pv} import {total.imported} "
                      f"export {total.exported} curtailed {total.curtailed} "
                      f"cost {money(total.net_cost)}")
        return output

    def bill(self, arguments):
        result = self.result_without_arguments(arguments)
        output = [f"BILL strategy {strategy_text(result.strategy)} days {self.data.day_count}"]
        for period, total in result.by_period.items():
            output.append(f"IMPORT {period} {total.imported} Wh {money(total.import_cost)}")
        output.extend([
            f"EXPORT {result.total.exported} Wh {money(-result.total.export_income)}",
            f"FIXED {money(result.settings['FIXED'])}",
            f"DEMAND {result.peak} Wh {money(result.demand_charge)}",
            f"TOTAL {money(result.bill)}",
        ])
        return output

    def savings(self, arguments):
        result = self.result_without_arguments(arguments)
        baseline = self.baseline(result.settings, result.prices)
        pairs = [(period, baseline.by_period[period].import_cost, total.import_cost)
                 for period, total in result.by_period.items()]
        pairs.extend([
            ("EXPORT", -baseline.total.export_income, -result.total.export_income),
            ("DEMAND", baseline.demand_charge, result.demand_charge),
            ("TOTAL", baseline.bill, result.bill),
        ])
        output = [f"SAVINGS strategy {strategy_text(result.strategy)}"]
        for name, before, after in pairs:
            output.append(f"{name} {money(before)} -> {money(after)} "
                          f"saving {money(before - after)}")
        return output

    def by_period(self, arguments):
        result = self.result_without_arguments(arguments)
        output = [f"BYPERIOD strategy {strategy_text(result.strategy)}"]
        for period, total in result.by_period.items():
            output.append(f"{period} hours {total.count} load {total.load} pv {total.pv} "
                          f"charge {total.charge} discharge {total.discharge} "
                          f"import {total.imported} export {total.exported}")
        return output

    def day_type(self, arguments):
        result = self.result_without_arguments(arguments)
        output = [f"DAYTYPE strategy {strategy_text(result.strategy)}"]
        for label, is_weekend in (("WEEKDAY", False), ("WEEKEND", True)):
            days = [day for day, flag in enumerate(self.data.weekend_days) if flag == is_weekend]
            records = tuple(record for day in days for record in result.days[day])
            total = Totals(records)
            count = len(days)
            output.append(f"{label} days {count} load {total.load // count} "
                          f"pv {total.pv // count} import {total.imported // count} "
                          f"export {total.exported // count} "
                          f"cost {money(truncate_divide(total.net_cost, count))}")
        return output

    def peaks(self, arguments):
        require_count(arguments, 1)
        count = int(arguments[0])
        if count < 1:
            raise CommandError("invalid count")
        result = self.require_result()
        records = [record for record in result.hours if record.imported > 0]
        records.sort(key=lambda record: (-record.imported, record.index))
        output = [f"PEAKS strategy {strategy_text(result.strategy)}"]
        for rank, record in enumerate(records[:count], 1):
            output.append(f"{rank}. day {record.day} hour {record.hour} {record.period} "
                          f"import {record.imported} load {record.load} soc {record.soc}")
        if not records:
            output.append("none")
        return output

    def profile(self, arguments):
        result = self.result_without_arguments(arguments)
        count = self.data.day_count
        output = [f"PROFILE strategy {strategy_text(result.strategy)} days {count}",
                  "hour   load     pv import export    soc"]
        for hour in range(24):
            records = result.hours[hour::24]
            averages = [sum(getattr(record, field) for record in records) // count
                        for field in ("load", "pv", "imported", "exported", "soc")]
            output.append(table_row((hour, *averages), (4,) + (7,) * 5))
        return output

    def flows(self, arguments):
        result = self.result_without_arguments(arguments)
        output = [f"FLOWS strategy {strategy_text(result.strategy)}"]
        output.extend(f"{name} {amount}" for name, amount in zip(FLOW_NAMES, result.total.flows))
        output.append(f"LOSSES {result.total.loss}")
        output.append(f"STORED {result.end_soc - result.start_soc}")
        return output

    def self_suff(self, arguments):
        result = self.result_without_arguments(arguments)
        flows = result.total.flows
        consumption = percentage(flows[0] + flows[1], result.total.pv)
        return [f"SELFSUFF sufficiency {result.sufficiency}% consumption {consumption}%"]

    def cycles(self, arguments):
        result = self.result_without_arguments(arguments)
        drawn = result.total.drawn
        capacity = result.settings["CAPACITY"]
        common = gcd(drawn, capacity)
        numerator, denominator = drawn // common, capacity // common
        thousandths = 1000 * drawn // capacity
        decimal = f"{thousandths // 1000}.{thousandths % 1000:03d}"
        return [f"CYCLES {numerator}/{denominator} {decimal} "
                f"drawn {drawn} losses {result.total.loss}"]

    def usage(self, arguments):
        result = self.result_without_arguments(arguments)
        charging = sum(record.charge > 0 for record in result.hours)
        discharging = sum(record.drawn > 0 for record in result.hours)
        idle = sum(record.charge == 0 and record.drawn == 0 for record in result.hours)
        full = sum(record.soc == result.settings["CAPACITY"] for record in result.hours)
        low_runs = [list(records) for is_low, records in groupby(
            result.hours, key=lambda record: record.soc <= result.reserve
        ) if is_low]
        low = sum(map(len, low_runs))
        longest = max(low_runs, key=len, default=[])
        line = (f"USAGE charging {charging} discharging {discharging} idle {idle} "
                f"full {full} low {low} longest {len(longest)}")
        if longest:
            line += f" from day {longest[0].day} hour {longest[0].hour}"
        return [line]

    def histogram(self, arguments):
        result = self.result_without_arguments(arguments)
        capacity = result.settings["CAPACITY"]
        bands = Counter(min(9, 10 * record.soc // capacity) for record in result.hours)
        output = [f"HISTOGRAM strategy {strategy_text(result.strategy)}"]
        for index in range(10):
            count = bands[index]
            width = 20 * count // len(result.hours)
            output.append(f"{10 * index:3d}% {bar(width)} {count}")
        return output

    def chart(self, arguments):
        day, result = self.result_for_day(arguments)
        capacity = result.settings["CAPACITY"]
        output = [f"CHART day {day} {self.data.day_names[day - 1]} "
                  f"strategy {strategy_text(result.strategy)}"]
        for record in result.days[day - 1]:
            width = 20 * record.soc // capacity
            output.append(f"{record.hour:2d} {bar(width)} {percentage(record.soc, capacity)}%")
        return output


def main():
    data = InputData(sys.stdin)
    desk = DispatchDesk(data)
    output = []
    for line in sys.stdin:
        tokens = line.split()
        if tokens[0] == "END":
            break
        output.extend(desk.execute(tokens))
    if output:
        sys.stdout.write("\n".join(output) + "\n")


if __name__ == "__main__":
    main()
