import copy
from collections import Counter
from itertools import accumulate
import sys


NAMES = ("RETAILER", "WHOLESALER", "DISTRIBUTOR", "FACTORY")
PARAMETERS = {"FIXED": 1, "PASS": 0, "BASESTOCK": 1, "MINMAX": 2, "MOVAVG": 2, "SMOOTH": 2, "STERMAN": 4}
MODES = {"ORDERS": "order", "INV": "inventory", "BACK": "backlog"}


class CommandError(Exception):
    pass


def money(value):
    return f"{value // 100}.{value % 100:02d}"


def decimal(numerator, denominator, places):
    scale = 10 ** places
    value = numerator * scale // denominator
    return f"{value // scale}.{value % scale:0{places}d}"


def variation(values):
    return len(values) * sum(value * value for value in values) - sum(values) ** 2


def parse_policy(tokens):
    name = tokens[0]
    if name not in PARAMETERS:
        raise CommandError("unknown policy " + name)
    count = PARAMETERS[name]
    if len(tokens) - 1 != count:
        raise CommandError(f"{name} needs {count} parameters")
    values = [int(token.replace(".", "")) if name == "STERMAN" and index < 3 else int(token)
              for index, token in enumerate(tokens[1:])]
    if name == "FIXED":
        valid = 0 <= values[0] <= 1000
    elif name == "PASS":
        valid = True
    elif name == "BASESTOCK":
        valid = 0 <= values[0] <= 10000
    elif name == "MINMAX":
        valid = 0 <= values[0] < values[1] <= 10000
    elif name == "MOVAVG":
        valid = 1 <= values[0] <= 52 and 0 <= values[1] <= 10000
    elif name == "SMOOTH":
        valid = 1 <= values[0] <= 10 and 0 <= values[1] <= 10000
    else:
        valid = all(0 <= value <= 100 for value in values[:3]) and 0 <= values[3] <= 10000
    if not valid:
        raise CommandError("invalid parameter for " + name)
    return name, values, " ".join(tokens)


class Stage:
    def __init__(self, initial):
        self.inventory = initial["inventory"]
        self.backlog = 0
        self.shipping = [initial["quantity"]] * initial["shipping"]
        self.orders = [initial["quantity"]] * initial["orders"]
        self.policy = initial["policy"]
        self.expected = 100 * initial["quantity"]
        self.holding = initial["holding"]
        self.backlog_rate = initial["backlog"]
        self.lot = 1
        self.capacity = None
        self.records = []


class Simulation:
    def __init__(self, initials, demands):
        self.initials = initials
        self.week = 0
        self.demands = list(demands)
        self.stages = [Stage(initial) for initial in initials]
        self.plant_backlog = 0
        self.plant_capacity = None
        self.plant_records = []
        self.visibility = "OFF"

    def signal(self, index, week, current=None):
        if self.visibility == "ON":
            return self.demands[week - 1]
        if current is not None and week == self.week + 1:
            return current[index]
        return self.stages[index].records[week - 1]["incoming"]

    def set_policy(self, index, policy):
        stage = self.stages[index]
        stage.policy = policy
        if policy[0] == "STERMAN":
            stage.expected = 100 * (self.signal(index, self.week) if self.week else self.initials[index]["quantity"])

    def positions(self):
        supply = []
        position = []
        for index, stage in enumerate(self.stages):
            upstream_backlog = self.stages[index + 1].backlog if index < 3 else self.plant_backlog
            line = sum(stage.orders) + upstream_backlog + sum(stage.shipping)
            supply.append(line)
            position.append(stage.inventory + line - stage.backlog)
        return supply, position

    def policy_order(self, index, incoming, line, position):
        stage = self.stages[index]
        name, args, _ = stage.policy
        week = self.week + 1
        signal = self.signal(index, week, incoming)
        if name == "FIXED":
            return args[0]
        if name == "PASS":
            return incoming[index]
        if name == "BASESTOCK":
            return max(0, args[0] - position)
        if name == "MINMAX":
            return args[1] - position if position <= args[0] else 0
        if name == "MOVAVG":
            k, target = args
            count = min(k, week)
            forecast = sum(self.signal(index, u, incoming) for u in range(week - count + 1, week + 1)) // count
            delay = self.initials[index]["shipping"] + self.initials[index]["orders"]
            return max(0, target + forecast * delay - position)
        if name == "SMOOTH":
            k, target = args
            return max(0, signal + (target - position) // k)
        theta, alpha, beta, target = args
        stage.expected = (100 * theta * signal + (100 - theta) * stage.expected) // 100
        net = stage.inventory - stage.backlog
        return max(0, (100 * stage.expected + alpha * (100 * (target - net) - beta * line)) // 10000)

    def step(self):
        received = []
        for stage in self.stages:
            quantity = stage.shipping.pop(0)
            stage.inventory += quantity
            received.append(quantity)
        incoming = [self.demands[self.week]]
        incoming.extend(self.stages[index].orders.pop(0) for index in range(3))
        plant_incoming = self.stages[3].orders.pop(0)
        records = []
        for index, stage in enumerate(self.stages):
            before = stage.backlog
            requested = before + incoming[index]
            shipped = min(stage.inventory, requested)
            if stage.capacity is not None:
                shipped = min(shipped, stage.capacity)
            stage.inventory -= shipped
            stage.backlog = requested - shipped
            if index:
                self.stages[index - 1].shipping.append(shipped)
            records.append({
                "received": received[index], "incoming": incoming[index], "shipped": shipped,
                "before": before, "ontime": min(max(0, shipped - before), incoming[index]),
                "inventory": stage.inventory, "backlog": stage.backlog,
            })
        requested = self.plant_backlog + plant_incoming
        produced = requested if self.plant_capacity is None else min(requested, self.plant_capacity)
        self.plant_backlog = requested - produced
        self.stages[3].shipping.append(produced)
        supply, positions = self.positions()
        orders = [self.policy_order(index, incoming, supply[index], positions[index]) for index in range(4)]
        for index, stage in enumerate(self.stages):
            quantity = (orders[index] + stage.lot - 1) // stage.lot * stage.lot
            stage.orders.append(quantity)
            record = records[index]
            record["order"] = quantity
            record["holding"] = stage.holding * stage.inventory
            record["backlog_cost"] = stage.backlog_rate * stage.backlog
            record["cost"] = record["holding"] + record["backlog_cost"]
            stage.records.append(record)
        self.plant_records.append({"incoming": plant_incoming, "produced": produced, "backlog": self.plant_backlog})
        self.week += 1
        return records

    def costs(self):
        return [sum(record["cost"] for record in stage.records) for stage in self.stages]


class Game:
    def __init__(self, settings):
        self.initials = []
        for tokens in settings:
            self.initials.append({
                "inventory": int(tokens[1]), "quantity": int(tokens[2]),
                "shipping": int(tokens[3]), "orders": int(tokens[4]),
                "holding": int(tokens[5]), "backlog": int(tokens[6]),
                "policy": parse_policy(tokens[7:]),
            })
        self.base = []
        self.simulation = Simulation(self.initials, [])
        self.snapshots = {}
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def stage_index(self, text):
        if text not in NAMES:
            raise CommandError("unknown stage " + text)
        return NAMES.index(text)

    def target(self, text):
        return list(range(4)) if text == "ALL" else [self.stage_index(text)]

    def require_weeks(self):
        if self.simulation.week == 0:
            raise CommandError("no weeks simulated")

    def range_check(self, arguments, limit):
        if not arguments:
            return 1, limit
        first, last = map(int, arguments)
        if not 1 <= first <= last <= limit:
            raise CommandError(f"bad range {arguments[0]} {arguments[1]}")
        return first, last

    def mode_check(self, mode):
        if mode not in ("ORDERS", "INV", "BACK", "NET"):
            raise CommandError("unknown mode " + mode)

    def values(self, index, mode):
        records = self.simulation.stages[index].records
        if mode == "NET":
            return [r["inventory"] - r["backlog"] for r in records]
        return [r[MODES[mode]] for r in records]

    def initialize(self, demands=None):
        if demands is not None:
            self.base = list(demands)
        self.simulation = Simulation(self.initials, self.base)

    def trial(self, policies):
        current = self.simulation
        trial = Simulation(self.initials, current.demands)
        trial.visibility = current.visibility
        trial.plant_capacity = current.plant_capacity
        for index, stage in enumerate(trial.stages):
            previous = current.stages[index]
            stage.lot = previous.lot
            stage.capacity = previous.capacity
            stage.holding = previous.holding
            stage.backlog_rate = previous.backlog_rate
            trial.set_policy(index, policies[index])
        while trial.week < len(trial.demands):
            trial.step()
        return trial

    def demand(self, values):
        self.initialize(values)
        self.emit("DEMAND", "weeks", len(values), "total", sum(values), "min", min(values), "max", max(values))

    def generate(self, arguments):
        weeks, base, spread, seed = map(int, arguments[:4])
        changes = [(arguments[i], int(arguments[i + 1]), int(arguments[i + 2])) for i in range(4, len(arguments), 3)]
        for _, week, _ in changes:
            if not 1 <= week <= weeks:
                raise CommandError(f"week {week} outside horizon")
        levels = []
        for week in range(1, weeks + 1):
            level = base
            for kind, start, amount in changes:
                if kind == "STEP" and week >= start:
                    level += amount
                elif kind == "PULSE" and week == start:
                    level += amount
                elif kind == "RAMP" and week >= start:
                    level += amount * (week - start + 1)
            if level < 0:
                raise CommandError(f"negative level at week {week}")
            levels.append(level)
        values = []
        for level in levels:
            seed = 48271 * seed % 2147483647
            values.append(level + seed % spread)
        self.demand(values)

    def show_status(self):
        s = self.simulation
        self.emit("STATUS", "week", s.week, "of", len(s.demands))
        supply, positions = s.positions()
        for index, stage in enumerate(s.stages):
            parts = [NAMES[index], "inv", stage.inventory, "back", stage.backlog,
                     "transit", ",".join(map(str, stage.shipping)), "pending", ",".join(map(str, stage.orders)),
                     "supply", supply[index], "position", positions[index], "policy", stage.policy[2]]
            if stage.policy[0] == "STERMAN":
                parts.extend(("expect", money(stage.expected)))
            self.emit(*parts)
        self.emit("PLANT", "back", s.plant_backlog)

    def show_week(self, week):
        s = self.simulation
        self.emit("WEEK", week, "demand", s.demands[week - 1])
        for index, stage in enumerate(s.stages):
            r = stage.records[week - 1]
            self.emit(NAMES[index], "recv", r["received"], "in", r["incoming"], "ship", r["shipped"],
                      "inv", r["inventory"], "back", r["backlog"], "order", r["order"], "cost", money(r["cost"]))
        plant = s.plant_records[week - 1]
        self.emit("PLANT", "in", plant["incoming"], "made", plant["produced"], "back", plant["backlog"])

    def table(self, index, first, last):
        s = self.simulation
        self.emit("TABLE", NAMES[index], f"{first}-{last}")
        labels = ("week", "in", "ship", "recv", "inv", "back", "order", "cost")
        widths = (4, 6, 6, 6, 6, 6, 6, 9)
        self.emit(" ".join(str(v).rjust(width) for v, width in zip(labels, widths)))
        for week in range(first, last + 1):
            r = s.stages[index].records[week - 1]
            values = (week, r["incoming"], r["shipped"], r["received"], r["inventory"], r["backlog"], r["order"], money(r["cost"]))
            self.emit(" ".join(str(v).rjust(width) for v, width in zip(values, widths)))

    def costs(self):
        self.emit("COSTS", "week", self.simulation.week)
        total_holding = total_backlog = 0
        for index, stage in enumerate(self.simulation.stages):
            holding = sum(r["holding"] for r in stage.records)
            backlog = sum(r["backlog_cost"] for r in stage.records)
            total_holding += holding
            total_backlog += backlog
            self.emit(NAMES[index], "holding", money(holding), "backlog", money(backlog), "total", money(holding + backlog))
        self.emit("TOTAL", "holding", money(total_holding), "backlog", money(total_backlog), "total", money(total_holding + total_backlog))

    def fill_text(self, records):
        ordered = sum(r["incoming"] for r in records)
        ontime = sum(r["ontime"] for r in records)
        fill = "n/a" if ordered == 0 else decimal(ontime * 100, ordered, 2) + "%"
        return ordered, ontime, fill

    def bullwhip(self):
        s = self.simulation
        n = s.week
        demands = s.demands[:n]
        demand_var = variation(demands)
        self.emit("BULLWHIP", "weeks", f"1-{n}", "demand", "mean", decimal(sum(demands), n, 4), "var", decimal(demand_var, n * n, 4))
        previous = demand_var
        for index, stage in enumerate(s.stages):
            values = [r["order"] for r in stage.records]
            v = variation(values)
            self.emit(NAMES[index], "mean", decimal(sum(values), n, 4), "var", decimal(v, n * n, 4),
                      "ratio", "n/a" if demand_var == 0 else decimal(v, demand_var, 4),
                      "step", "n/a" if previous == 0 else decimal(v, previous, 4))
            previous = v

    def peaks(self):
        s = self.simulation
        self.emit("PEAKS", "weeks", f"1-{s.week}")
        for index, stage in enumerate(s.stages):
            inventories = [r["inventory"] for r in stage.records]
            backlogs = [r["backlog"] for r in stage.records]
            max_inventory = max(inventories)
            max_backlog = max(backlogs)
            longest = run = 0
            start = best_start = best_end = 0
            for week, backlog in enumerate(backlogs, 1):
                if backlog > 0:
                    if run == 0:
                        start = week
                    run += 1
                    if run > longest:
                        longest, best_start, best_end = run, start, week
                else:
                    run = 0
            self.emit(NAMES[index], "max_inv", max_inventory, "week", inventories.index(max_inventory) + 1 if max_inventory else "-",
                      "max_back", max_backlog, "week", backlogs.index(max_backlog) + 1 if max_backlog else "-",
                      "longest_stockout", f"{longest} weeks {best_start}-{best_end}" if longest else 0)

    def leadtime(self, index):
        stage = self.simulation.stages[index]
        initial = self.initials[index]
        nominal = initial["shipping"] + initial["orders"]
        cumulative = [received - nominal * initial["quantity"]
                      for received in accumulate(r["received"] for r in stage.records)]
        ordered = count = 0
        leads = []
        for t, r in enumerate(stage.records):
            ordered += r["order"]
            if r["order"] == 0:
                continue
            count += 1
            for u in range(t + 1, len(stage.records)):
                if cumulative[u] >= ordered:
                    leads.append(u - t)
                    break
        self.emit("LEADTIME", NAMES[index], "nominal", nominal, "orders", count, "completed", len(leads),
                  "open", count - len(leads), "min", min(leads) if leads else "-",
                  "avg", decimal(sum(leads), len(leads), 2) if leads else "-", "max", max(leads) if leads else "-")

    def plot(self, index, mode, first, last):
        values = self.values(index, mode)[first - 1:last]
        maximum = max(values)
        if mode == "NET":
            self.emit("PLOT", NAMES[index], mode, f"{first}-{last}", "min", min(values), "max", maximum)
            scale = max(abs(v) for v in values)
            for week, value in enumerate(values, first):
                length = abs(value) * 25 // scale if scale else 0
                left = " " * (25 - length) + "-" * length if value < 0 else " " * 25
                right = "+" * length if value > 0 else ""
                self.emit(f"{week:3d} {left}|{right} {value}")
        else:
            self.emit("PLOT", NAMES[index], mode, f"{first}-{last}", "max", maximum)
            for week, value in enumerate(values, first):
                length = value * 50 // maximum if maximum else 0
                self.emit(f"{week:3d} |{'#' * length} {value}")

    def command(self, command, a):
        s = self.simulation
        if command == "DEMAND":
            self.demand(list(map(int, a)))
        elif command == "GENERATE":
            self.generate(a)
        elif command == "RUN":
            if s.week == len(s.demands):
                raise CommandError(f"horizon reached at week {len(s.demands)}")
            first = s.week + 1
            count = min(int(a[0]), len(s.demands) - s.week)
            cost = 0
            for _ in range(count):
                records = s.step()
                for index, r in enumerate(records):
                    cost += r["cost"]
                    if r["before"] == 0 and r["backlog"] > 0:
                        self.emit("STOCKOUT", NAMES[index], "week", s.week, "backlog", r["backlog"])
                    elif r["before"] > 0 and r["backlog"] == 0:
                        self.emit("RECOVER", NAMES[index], "week", s.week)
            self.emit("RUN", f"{first}-{s.week}", "demand", sum(s.demands[first - 1:s.week]), "cost", money(cost))
            if s.week == len(s.demands):
                self.emit("HORIZON", s.week)
        elif command == "RESET":
            self.initialize()
            self.emit("RESET", "week", 0)
        elif command == "SAVE":
            self.snapshots[a[0]] = copy.deepcopy(s)
            self.emit("SAVE", a[0], "week", s.week)
        elif command == "LOAD":
            if a[0] not in self.snapshots:
                raise CommandError("no snapshot " + a[0])
            self.simulation = copy.deepcopy(self.snapshots[a[0]])
            self.emit("LOAD", a[0], "week", self.simulation.week)
        elif command == "SET":
            indices = self.target(a[0])
            policy = parse_policy(a[1:])
            for index in indices:
                s.set_policy(index, policy)
            self.emit("SET", a[0], policy[2])
        elif command == "BATCH":
            index = self.stage_index(a[0])
            lot = int(a[1])
            if not 1 <= lot <= 100:
                raise CommandError("invalid batch size " + a[1])
            s.stages[index].lot = lot
            self.emit("BATCH", a[0], lot)
        elif command == "CAPACITY":
            index = None if a[0] == "PLANT" else self.stage_index(a[0])
            capacity = None if a[1] == "OFF" else int(a[1])
            if capacity is not None and capacity > 10000:
                raise CommandError("invalid capacity " + a[1])
            if index is None:
                s.plant_capacity = capacity
            else:
                s.stages[index].capacity = capacity
            self.emit("CAPACITY", a[0], a[1])
        elif command == "COST":
            index = self.stage_index(a[0])
            holding, backlog = map(int, a[1:])
            if holding > 1000 or backlog > 1000:
                raise CommandError("invalid cost")
            s.stages[index].holding = holding
            s.stages[index].backlog_rate = backlog
            self.emit("COST", a[0], "holding", holding, "backlog", backlog)
        elif command == "VISIBILITY":
            if a[0] not in ("ON", "OFF"):
                raise CommandError("unknown visibility " + a[0])
            s.visibility = a[0]
            self.emit("VISIBILITY", a[0])
        elif command == "SHOCK":
            week, demand = map(int, a)
            if not 1 <= week <= len(s.demands):
                raise CommandError("week " + a[0] + " outside horizon")
            if week <= s.week:
                raise CommandError("week " + a[0] + " already simulated")
            old = s.demands[week - 1]
            s.demands[week - 1] = demand
            self.emit("SHOCK", "week", week, old, "->", demand)
        elif command == "STATUS":
            self.show_status()
        elif command == "SETTINGS":
            self.emit("SETTINGS")
            for index, stage in enumerate(s.stages):
                initial = self.initials[index]
                self.emit(NAMES[index], "holding", stage.holding, "backlog", stage.backlog_rate,
                          "batch", stage.lot, "capacity", "OFF" if stage.capacity is None else stage.capacity,
                          "delays", initial["shipping"], initial["orders"])
            self.emit("PLANT", "capacity", "OFF" if s.plant_capacity is None else s.plant_capacity)
            self.emit("VISIBILITY", s.visibility)
        elif command == "WEEK":
            self.require_weeks()
            week = int(a[0])
            if not 1 <= week <= s.week:
                raise CommandError("bad week " + a[0])
            self.show_week(week)
        elif command == "TABLE":
            index = self.stage_index(a[0])
            self.require_weeks()
            self.table(index, *self.range_check(a[1:], s.week))
        elif command == "CHAIN":
            self.require_weeks()
            first, last = self.range_check(a, s.week)
            self.emit("CHAIN", f"{first}-{last}")
            self.emit(f"{'week':>4} {'demand':>6} " + " ".join(name.rjust(11) for name in NAMES))
            for week in range(first, last + 1):
                orders = [stage.records[week - 1]["order"] for stage in s.stages]
                self.emit(f"{week:4d} {s.demands[week - 1]:6d} " + " ".join(str(value).rjust(11) for value in orders))
        elif command == "DEMANDS":
            first, last = self.range_check(a, len(s.demands))
            values = s.demands[first - 1:last]
            self.emit("DEMANDS", f"{first}-{last}", "total", sum(values), "min", min(values), "max", max(values))
            self.emit(*values)
        elif command == "COSTS":
            self.costs()
        elif command == "SUMMARY":
            self.require_weeks()
            self.emit("SUMMARY", "weeks", f"1-{s.week}")
            for index, stage in enumerate(s.stages):
                orders = [r["order"] for r in stage.records]
                self.emit(NAMES[index], "avg_inv", decimal(sum(r["inventory"] for r in stage.records), s.week, 2),
                          "avg_back", decimal(sum(r["backlog"] for r in stage.records), s.week, 2),
                          "orders", sum(orders), "min", min(orders), "max", max(orders), "zero_weeks", orders.count(0))
        elif command == "BALANCE":
            self.emit("BALANCE", "week", s.week)
            for index, stage in enumerate(s.stages):
                self.emit(NAMES[index], "start", self.initials[index]["inventory"],
                          "received", sum(r["received"] for r in stage.records), "shipped", sum(r["shipped"] for r in stage.records),
                          "end", stage.inventory, "owed", stage.backlog)
            initial_goods = sum(i["inventory"] + i["quantity"] * i["shipping"] for i in self.initials)
            self.emit("SYSTEM", "initial", initial_goods, "produced", sum(r["produced"] for r in s.plant_records),
                      "delivered", sum(r["shipped"] for r in s.stages[0].records), "stock", sum(stage.inventory for stage in s.stages),
                      "transit", sum(sum(stage.shipping) for stage in s.stages))
        elif command == "FILLRATE":
            self.require_weeks()
            self.emit("FILLRATE", "weeks", f"1-{s.week}")
            for index, stage in enumerate(s.stages):
                ordered, ontime, fill = self.fill_text(stage.records)
                stockouts = sum(r["backlog"] > 0 for r in stage.records)
                self.emit(NAMES[index], "fill", fill, "ontime", ontime, "ordered", ordered, "stockout_weeks", stockouts,
                          "service", decimal((s.week - stockouts) * 100, s.week, 2) + "%")
        elif command == "BULLWHIP":
            self.require_weeks()
            self.bullwhip()
        elif command == "PEAKS":
            self.require_weeks()
            self.peaks()
        elif command == "LEADTIME":
            index = self.stage_index(a[0])
            self.require_weeks()
            self.leadtime(index)
        elif command in ("PLOT", "HISTOGRAM"):
            index = self.stage_index(a[0])
            self.mode_check(a[1])
            if command == "HISTOGRAM":
                width = int(a[2])
                if not 1 <= width <= 100:
                    raise CommandError("invalid width " + a[2])
            self.require_weeks()
            if command == "PLOT":
                self.plot(index, a[1], *self.range_check(a[2:], s.week))
            else:
                bins = Counter(value // width for value in self.values(index, a[1]))
                self.emit("HISTOGRAM", a[0], a[1], "width", width, "weeks", f"1-{s.week}")
                for bucket in range(min(bins), max(bins) + 1):
                    count = bins.get(bucket, 0)
                    self.emit(f"{bucket * width}..{bucket * width + width - 1}", count, *(["*" * count] if count else []))
        elif command == "COMPARE":
            policies = []
            start = 0
            for end in range(len(a) + 1):
                if end == len(a) or a[end] == "/":
                    policies.append(parse_policy(a[start:end]))
                    start = end + 1
            rows = []
            for index, policy in enumerate(policies):
                trial = self.trial([policy] * 4)
                cost = sum(trial.costs())
                _, _, fill = self.fill_text(trial.stages[0].records)
                demand_variation = variation(trial.demands)
                factory_variation = variation([r["order"] for r in trial.stages[3].records])
                ratio = "n/a" if demand_variation == 0 else decimal(factory_variation, demand_variation, 4)
                rows.append((cost, index, policy[2], fill, ratio))
            self.emit("COMPARE", len(policies), "weeks", len(s.demands))
            for rank, (cost, _, policy, fill, ratio) in enumerate(sorted(rows), 1):
                self.emit(rank, policy, "total", money(cost), "fill", fill, "bullwhip", ratio)
        elif command == "OPTIMIZE":
            indices = self.target(a[0])
            low, high = map(int, a[1:])
            if low > high:
                raise CommandError(f"bad range {a[1]} {a[2]}")
            if high - low > 200:
                raise CommandError("range too large")
            best = None
            for target in range(low, high + 1):
                policies = [stage.policy for stage in s.stages]
                for index in indices:
                    policies[index] = ("BASESTOCK", [target], f"BASESTOCK {target}")
                trial = self.trial(policies)
                costs = trial.costs()
                objective = sum(costs[index] for index in indices)
                row = objective, target, sum(costs)
                if best is None or row[:2] < best[:2]:
                    best = row
            self.emit("OPTIMIZE", a[0], "BASESTOCK", best[1], "cost", money(best[0]), "total", money(best[2]))
        else:
            raise CommandError("unknown command " + command)

    def execute(self, line):
        command, *arguments = line.split()
        try:
            self.command(command, arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    settings = [sys.stdin.readline().split() for _ in range(4)]
    game = Game(settings)
    for line in sys.stdin:
        line = line.rstrip("\n")
        if line == "END":
            break
        game.execute(line)
    if game.output:
        sys.stdout.write("\n".join(game.output) + "\n")


if __name__ == "__main__":
    main()
