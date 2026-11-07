import os
from fractions import Fraction

from bom import cumulative_lead_times, low_level_codes, need, read_bom
from capacity import level_loads, operation_week, read_routings, read_workcenters
from costing import abc_classes, standard_costs
from items import read_items
from lot_sizing import lot_size
from report import money, percent, table_row, write_report


INPUT_DIR = "input"
PARAMS_FILE = "params.txt"
MPS_FILE = "mps.csv"
RECEIPTS_FILE = "receipts.csv"
ORDERS_FILE = "orders.csv"
DEMAND_KINDS = ("MPS", "ORDER", "DEPENDENT")
ROOT_KINDS = ("MPS", "ORDER", "SAFETY")
SUPPLY_KINDS = ("STOCK", "RECEIPT", "ORDER")
GRID_WIDTH = 6
CAPACITY_WIDTH = 7
MESSAGE_KINDS = (
    "BELOW_SAFETY", "PAST_DUE", "RELEASE", "EXPEDITE", "DEFER",
    "CANCEL", "NO_ROUTING", "NO_DEMAND", "OVERLOAD",
)


class ScheduleRow:
    def __init__(self, fields, line):
        self.item = fields[0]
        self.week = int(fields[1])
        self.quantity = int(fields[2])
        self.line = line


class Inquiry:
    def __init__(self, fields, line):
        self.id = fields[0]
        self.item = fields[1]
        self.quantity = int(fields[2])
        self.week = int(fields[3])
        self.line = line


class Demand:
    def __init__(self, item, kind, week, quantity, order_id="", line=0, parent="", parent_number=0):
        self.item = item
        self.kind = kind
        self.week = week
        self.quantity = quantity
        self.order_id = order_id
        self.line = line
        self.parent = parent
        self.parent_number = parent_number

    def sort_key(self):
        rank = DEMAND_KINDS.index(self.kind)
        return self.week, rank, self.line, self.parent, self.parent_number

    def root_key(self):
        return self.item, ROOT_KINDS.index(self.kind), self.week, self.order_id

    def text(self):
        if self.kind == "SAFETY":
            return f"SAFETY {self.item}"
        if self.kind == "MPS":
            return f"MPS {self.item} week {self.week}"
        if self.kind == "ORDER":
            return f"ORDER {self.order_id} {self.item} week {self.week}"
        return f"{self.parent} order {self.parent_number} week {self.week}"


class PlannedOrder:
    def __init__(self, item, number, receipt, quantity, lead_time):
        self.item = item
        self.number = number
        self.receipt = receipt
        self.quantity = quantity
        self.original_release = receipt - lead_time
        self.release = max(1, self.original_release)

    def is_past_due(self):
        return self.original_release < 1


class ItemPlan:
    def __init__(self, item, horizon, receipts):
        self.item = item
        self.receipts = receipts
        self.demands = []
        self.gross = [0] * (horizon + 1)
        self.on_hand = [0] * (horizon + 1)
        self.net = [0] * (horizon + 1)
        self.planned_receipts = [0] * (horizon + 1)
        self.planned_releases = [0] * (horizon + 1)
        self.orders = []
        self.supplies = []
        self.order_supplies = []

    def past_due_quantity(self):
        return sum(order.quantity for order in self.orders if order.is_past_due())


class Plan:
    def __init__(self, items, loads, centers):
        self.items = items
        self.loads = loads
        self.overloads = {}
        for center_id, week_loads in loads.items():
            available = centers[center_id].available
            self.overloads[center_id] = [max(0, load - available) for load in week_loads]


class Supply:
    def __init__(self, kind, week, quantity, line=0, order=None):
        self.kind = kind
        self.week = week
        self.quantity = quantity
        self.line = line
        self.order = order
        self.remaining = quantity
        self.allocations = []
        self.roots = []

    def sort_key(self):
        return self.week, SUPPLY_KINDS.index(self.kind), self.line

    def header(self):
        if self.kind == "STOCK":
            return f"STOCK quantity {self.quantity}"
        if self.kind == "RECEIPT":
            return f"RECEIPT line {self.line} week {self.week} quantity {self.quantity}"
        order = self.order
        return (
            f"ORDER {order.number} receipt {order.receipt} "
            f"release {order.release} quantity {order.quantity}"
        )

    def serves(self, order_id):
        return any(root.kind == "ORDER" and root.order_id == order_id for root in self.roots)


class Allocation:
    def __init__(self, demand, share):
        self.demand = demand
        self.share = share


class Promise:
    def __init__(self, inquiry):
        self.inquiry = inquiry
        self.week = 0
        self.material_week = 0
        self.reason = ""

    def status(self):
        if self.week == 0:
            return "rejected"
        if self.week == self.inquiry.week:
            return "on_time"
        return "late"


def read_rows(name):
    with open(os.path.join(INPUT_DIR, name)) as file:
        lines = file.read().splitlines()
    return [(number, line.split(",")) for number, line in enumerate(lines[1:], 2)]


def read_params():
    horizon = 0
    peg_items = []
    tree_quantity = 0
    with open(os.path.join(INPUT_DIR, PARAMS_FILE)) as file:
        for line in file.read().splitlines():
            key, *values = line.split(" ")
            if key == "horizon":
                horizon = int(values[0])
            elif key == "peg":
                peg_items = values
            elif key == "tree_quantity":
                tree_quantity = int(values[0])
    return horizon, peg_items, tree_quantity


def schedule_error(row, items, horizon):
    if row.item not in items:
        return f"unknown item {row.item}"
    if row.week < 1 or row.week > horizon:
        return f"week {row.week} outside horizon"
    if row.quantity < 1:
        return f"bad quantity {row.quantity}"
    return None


def read_schedule(name, items, horizon, errors, unique_weeks):
    rows = []
    seen = set()
    for number, fields in read_rows(name):
        row = ScheduleRow(fields, number)
        message = schedule_error(row, items, horizon)
        if message is None and unique_weeks and (row.item, row.week) in seen:
            message = f"duplicate {row.item} week {row.week}"
        if message is None:
            rows.append(row)
            seen.add((row.item, row.week))
        else:
            errors.append(f"{name} line {number}: {message}")
    return rows


def read_inquiries(items, horizon, errors):
    inquiries = []
    for number, fields in read_rows(ORDERS_FILE):
        inquiry = Inquiry(fields, number)
        if any(other.id == inquiry.id for other in inquiries):
            message = f"duplicate order {inquiry.id}"
        else:
            message = schedule_error(inquiry, items, horizon)
        if message is None:
            inquiries.append(inquiry)
        else:
            errors.append(f"{ORDERS_FILE} line {number}: {message}")
    return inquiries


class PlanningData:
    def __init__(self):
        self.errors = []
        self.horizon, self.peg_items, self.tree_quantity = read_params()
        self.items = read_items(INPUT_DIR, self.errors)
        self.bom = read_bom(INPUT_DIR, self.items, self.errors)
        self.centers = read_workcenters(INPUT_DIR, self.errors)
        self.routings = read_routings(INPUT_DIR, self.items, self.centers, self.bom, self.errors)
        mps = read_schedule(MPS_FILE, self.items, self.horizon, self.errors, True)
        receipts = read_schedule(RECEIPTS_FILE, self.items, self.horizon, self.errors, False)
        self.inquiries = read_inquiries(self.items, self.horizon, self.errors)
        self.mps_demands = [Demand(row.item, "MPS", row.week, row.quantity) for row in mps]
        self.codes = low_level_codes(self.bom, self.items)
        self.cumulative = cumulative_lead_times(self.bom, self.items)
        self.planning_order = sorted(self.items, key=lambda item_id: (self.codes[item_id], item_id))
        self.center_order = sorted(self.centers)
        self.weeks = list(range(1, self.horizon + 1))
        self.receipts = {item_id: [] for item_id in self.items}
        self.scheduled = {item_id: [0] * (self.horizon + 1) for item_id in self.items}
        for row in sorted(receipts, key=lambda receipt: (receipt.week, receipt.line)):
            self.receipts[row.item].append(row)
            self.scheduled[row.item][row.week] += row.quantity


def plan_item(plan, horizon):
    item = plan.item
    for demand in plan.demands:
        plan.gross[demand.week] += demand.quantity
    projected = item.on_hand
    for week in range(1, horizon + 1):
        available = projected + plan.receipts[week] - plan.gross[week]
        projected = available
        if available < item.safety_stock:
            quantity = lot_size(item, week, available, plan.receipts, plan.gross, horizon)
            order = PlannedOrder(item.id, len(plan.orders) + 1, week, quantity, item.lead_time)
            plan.orders.append(order)
            plan.net[week] = item.safety_stock - available
            plan.planned_receipts[week] = quantity
            plan.planned_releases[order.release] += quantity
            projected = available + quantity
        plan.on_hand[week] = projected


def explode_orders(data, plans, plan):
    for order in plan.orders:
        for row in data.bom.children[order.item]:
            demand = Demand(
                row.child, "DEPENDENT", order.release, need(row, order.quantity),
                parent=order.item, parent_number=order.number,
            )
            plans[row.child].demands.append(demand)


def work_center_loads(data, plans):
    loads = {center_id: [0] * (data.horizon + 1) for center_id in data.centers}
    for item_id, operations in data.routings.items():
        lead_time = data.items[item_id].lead_time
        for order in plans[item_id].orders:
            for index, operation in enumerate(operations):
                week = operation_week(order.receipt, lead_time, index, len(operations))
                loads[operation.center][week] += operation.minutes(order.quantity)
    return loads


def run_mrp(data, order_demands):
    plans = {}
    for item_id in data.planning_order:
        plans[item_id] = ItemPlan(data.items[item_id], data.horizon, data.scheduled[item_id])
    for demand in data.mps_demands + order_demands:
        plans[demand.item].demands.append(demand)
    for item_id in data.planning_order:
        plan_item(plans[item_id], data.horizon)
        explode_orders(data, plans, plans[item_id])
    return Plan(plans, work_center_loads(data, plans), data.centers)


def material_reason(data, current, trial):
    for item_id in data.planning_order:
        if trial.items[item_id].past_due_quantity() > current.items[item_id].past_due_quantity():
            return item_id
    return None


def capacity_reason(data, current, trial):
    for center_id in data.center_order:
        for week in data.weeks:
            if trial.overloads[center_id][week] > current.overloads[center_id][week]:
                return f"{center_id} week {week}"
    return None


def promise_inquiries(data, base):
    current = base
    promised = []
    promises = []
    for inquiry in data.inquiries:
        promise = Promise(inquiry)
        for week in range(inquiry.week, data.horizon + 1):
            demand = Demand(
                inquiry.item, "ORDER", week, inquiry.quantity,
                order_id=inquiry.id, line=inquiry.line,
            )
            trial = run_mrp(data, promised + [demand])
            reason = material_reason(data, current, trial)
            if reason is None:
                if promise.material_week == 0:
                    promise.material_week = week
                reason = capacity_reason(data, current, trial)
            if reason is None:
                promise.week = week
                promised.append(demand)
                current = trial
                break
            if week == inquiry.week:
                promise.reason = reason
        promises.append(promise)
    return promises, current


def demand_list(plan):
    item = plan.item
    demands = []
    if item.safety_stock > 0:
        demands.append(Demand(item.id, "SAFETY", 0, item.safety_stock))
    demands.extend(sorted(plan.demands, key=Demand.sort_key))
    return demands


def supply_list(data, plan):
    item = plan.item
    supplies = []
    if item.on_hand > 0:
        supplies.append(Supply("STOCK", 0, item.on_hand))
    for receipt in data.receipts[item.id]:
        supplies.append(Supply("RECEIPT", receipt.week, receipt.quantity, line=receipt.line))
    for order in plan.orders:
        supplies.append(Supply("ORDER", order.receipt, order.quantity, order=order))
    supplies.sort(key=Supply.sort_key)
    return supplies


def allocate(demands, supplies):
    index = 0
    for demand in demands:
        remaining = demand.quantity
        while remaining > 0:
            while supplies[index].remaining == 0:
                index += 1
            supply = supplies[index]
            share = min(remaining, supply.remaining)
            supply.allocations.append(Allocation(demand, share))
            supply.remaining -= share
            remaining -= share


def parent_supply(plans, demand):
    return plans[demand.parent].order_supplies[demand.parent_number - 1]


def root_demands(plans, supply):
    roots = {}
    for allocation in supply.allocations:
        demand = allocation.demand
        if demand.kind == "DEPENDENT":
            for root in parent_supply(plans, demand).roots:
                roots[root.root_key()] = root
        else:
            roots[demand.root_key()] = demand
    return [roots[key] for key in sorted(roots)]


def peg_plan(data, plan):
    for item_id in data.planning_order:
        item_plan = plan.items[item_id]
        item_plan.supplies = supply_list(data, item_plan)
        allocate(demand_list(item_plan), item_plan.supplies)
        item_plan.order_supplies = [
            supply for supply in item_plan.supplies if supply.kind == "ORDER"
        ]
        for supply in item_plan.order_supplies:
            supply.roots = root_demands(plan.items, supply)


def depth_label(depth):
    return "." * depth + str(depth)


def grid_lines(data, plan):
    lines = []
    for item_id in data.planning_order:
        item_plan = plan.items[item_id]
        item = item_plan.item
        lines.append(
            f"ITEM {item_id} LLC {data.codes[item_id]} LT {item.lead_time} "
            f"LOT {item.lot_label()} SS {item.safety_stock} OH {item.on_hand} "
            f"{item.description}"
        )
        lines.append(table_row("WEEK", data.weeks, GRID_WIDTH))
        lines.append(table_row("GROSS", item_plan.gross[1:], GRID_WIDTH))
        lines.append(table_row("RECEIPTS", item_plan.receipts[1:], GRID_WIDTH))
        lines.append(table_row("ON_HAND", item_plan.on_hand[1:], GRID_WIDTH))
        lines.append(table_row("NET", item_plan.net[1:], GRID_WIDTH))
        lines.append(table_row("PLAN_RCPT", item_plan.planned_receipts[1:], GRID_WIDTH))
        lines.append(table_row("PLAN_REL", item_plan.planned_releases[1:], GRID_WIDTH))
        lines.append(
            f"TOTAL gross {sum(item_plan.gross)} receipts {sum(item_plan.receipts)} "
            f"planned {sum(item_plan.planned_receipts)} orders {len(item_plan.orders)} "
            f"ending {item_plan.on_hand[data.horizon]}"
        )
    return lines


def where_used_lines(bom, item_id, depth, extension, lines):
    for row in bom.parents[item_id]:
        parent_extension = extension * row.qty_per
        lines.append(
            f"{depth_label(depth)} {row.parent} qty {row.qty_per} ext {parent_extension}"
        )
        where_used_lines(bom, row.parent, depth + 1, parent_extension, lines)


def allocation_lines(plans, supply, depth, lines):
    for allocation in supply.allocations:
        demand = allocation.demand
        lines.append(" " * (2 * depth) + f"ALLOC {allocation.share} {demand.text()}")
        if supply.kind == "ORDER" and demand.kind == "DEPENDENT":
            allocation_lines(plans, parent_supply(plans, demand), depth + 1, lines)


def pegging_lines(data, plan):
    lines = []
    for item_id in data.peg_items:
        item_plan = plan.items[item_id]
        lines.append(f"PEG {item_id} orders {len(item_plan.orders)}")
        where_used_lines(data.bom, item_id, 1, 1, lines)
        for kind in SUPPLY_KINDS:
            for supply in item_plan.supplies:
                if supply.kind != kind:
                    continue
                lines.append(supply.header())
                allocation_lines(plan.items, supply, 1, lines)
                if supply.remaining > 0:
                    lines.append(f"  EXCESS {supply.remaining}")
                for root in supply.roots:
                    lines.append(f"  ROOT {root.text()}")
    return lines


def explosion_lines(data, item_id, gross, extension, depth, lines, totals):
    for row in data.bom.children[item_id]:
        child = data.items[row.child]
        child_extension = extension * row.qty_per
        child_gross = need(row, gross)
        totals[row.child] = totals.get(row.child, 0) + child_gross
        lines.append(
            f"{depth_label(depth)} {row.child} qty {row.qty_per} scrap {row.scrap} "
            f"ext {child_extension} gross {child_gross} lt {child.lead_time} "
            f"cum {data.cumulative[row.child]} {child.description}"
        )
        explosion_lines(data, row.child, child_gross, child_extension, depth + 1, lines, totals)


def critical_path(data, item_id):
    path = [item_id]
    while data.bom.is_manufactured(item_id):
        rows = data.bom.children[item_id]
        item_id = max(rows, key=lambda row: data.cumulative[row.child]).child
        path.append(item_id)
    return path


def bom_tree_lines(data):
    lines = []
    quantity = data.tree_quantity
    for item_id in sorted(data.items):
        if not data.bom.is_top_level(item_id):
            continue
        item = data.items[item_id]
        lines.append(f"TREE {item_id} quantity {quantity}")
        lines.append(
            f"{depth_label(0)} {item_id} ext 1 gross {quantity} lt {item.lead_time} "
            f"cum {data.cumulative[item_id]} {item.description}"
        )
        totals = {}
        explosion_lines(data, item_id, quantity, 1, 1, lines, totals)
        for child_id in sorted(totals):
            lines.append(f"SUM {child_id} {totals[child_id]}")
        path = " -> ".join(critical_path(data, item_id))
        lines.append(f"CRITICAL {path} cum {data.cumulative[item_id]}")
    return lines


def cost_lines(data, plan, costs):
    usages = {item_id: sum(plan.items[item_id].gross) for item_id in data.items}
    values = {item_id: usages[item_id] * costs[item_id].total for item_id in data.items}
    classes = abc_classes(values)
    lines = ["item,material,labor,total,usage,value,class"]
    for item_id in sorted(data.items):
        cost = costs[item_id]
        lines.append(
            f"{item_id},{money(cost.material)},{money(cost.labor)},{money(cost.total)},"
            f"{usages[item_id]},{money(values[item_id])},{classes[item_id]}"
        )
    return lines


def order_messages(item_plan):
    messages = []
    for order in item_plan.orders:
        if order.is_past_due():
            messages.append(
                f"PAST_DUE {order.item} order {order.number} receipt {order.receipt} "
                f"release {order.original_release} late {1 - order.original_release} "
                f"quantity {order.quantity}"
            )
        elif order.original_release == 1:
            messages.append(
                f"RELEASE {order.item} order {order.number} receipt {order.receipt} "
                f"quantity {order.quantity}"
            )
    return messages


def reschedule_messages(data, item_plan):
    item = item_plan.item
    balances = [0] * (data.horizon + 1)
    balance = item.on_hand
    for week in data.weeks:
        balance -= item_plan.gross[week]
        balances[week] = balance
    messages = []
    covered = 0
    for receipt in data.receipts[item.id]:
        need_week = 0
        for week in data.weeks:
            if balances[week] + covered < item.safety_stock:
                need_week = week
                break
        text = (
            f"{item.id} receipt line {receipt.line} week {receipt.week} "
            f"quantity {receipt.quantity}"
        )
        if need_week == 0:
            messages.append(f"CANCEL {text}")
        elif need_week < receipt.week:
            messages.append(f"EXPEDITE {text} to {need_week}")
        elif need_week > receipt.week:
            messages.append(f"DEFER {text} to {need_week}")
        covered += receipt.quantity
    return messages


def exception_messages(data, plan):
    messages = []
    for item_id in data.planning_order:
        item_plan = plan.items[item_id]
        item = item_plan.item
        if item.on_hand < item.safety_stock:
            messages.append(
                f"BELOW_SAFETY {item_id} on hand {item.on_hand} safety {item.safety_stock}"
            )
        messages.extend(order_messages(item_plan))
        messages.extend(reschedule_messages(data, item_plan))
        if data.bom.is_manufactured(item_id) and item_id not in data.routings:
            messages.append(f"NO_ROUTING {item_id}")
        if sum(item_plan.gross) == 0 and item.on_hand > 0:
            messages.append(f"NO_DEMAND {item_id} on hand {item.on_hand}")
    for center_id in data.center_order:
        available = data.centers[center_id].available
        for week in data.weeks:
            if plan.overloads[center_id][week] > 0:
                messages.append(
                    f"OVERLOAD {center_id} week {week} load {plan.loads[center_id][week]} "
                    f"available {available}"
                )
    return messages


def exception_lines(data, plan):
    messages = exception_messages(data, plan)
    lines = [f"ERROR {error}" for error in data.errors] + messages
    counts = [f"errors {len(data.errors)}"]
    for kind in MESSAGE_KINDS:
        count = sum(1 for message in messages if message.split(" ")[0] == kind)
        counts.append(f"{kind.lower()} {count}")
    lines.append("SUMMARY " + " ".join(counts))
    return lines


def center_lines(data, plan, center):
    loads = plan.loads[center.id][1:]
    overloads = plan.overloads[center.id][1:]
    leveled = level_loads(plan.loads[center.id], center.available)
    total = sum(loads)
    capacity_total = center.available * data.horizon
    peak = loads.index(max(loads)) + 1 if total > 0 else 0
    overloaded = sum(1 for overload in overloads if overload > 0)
    backlog = max(0, leveled[1] - center.available)
    return [
        f"CENTER {center.id} minutes {center.minutes} efficiency {center.efficiency} "
        f"available {center.available} {center.description}",
        table_row("WEEK", data.weeks, CAPACITY_WIDTH),
        table_row("LOAD", loads, CAPACITY_WIDTH),
        table_row("UTIL", [percent(load, center.available) for load in loads], CAPACITY_WIDTH),
        table_row("OVER", overloads, CAPACITY_WIDTH),
        table_row("LEVELED", leveled[1:], CAPACITY_WIDTH),
        f"TOTAL load {total} available {capacity_total} "
        f"utilization {percent(total, capacity_total)} overloaded {overloaded} "
        f"peak {peak} backlog {backlog}",
    ]


def capacity_lines(data, plan):
    lines = []
    totals = {}
    for center_id in data.center_order:
        center = data.centers[center_id]
        lines.extend(center_lines(data, plan, center))
        totals[center_id] = sum(plan.loads[center_id])
    ranked = sorted(
        data.center_order,
        key=lambda center_id: (
            -Fraction(totals[center_id], data.centers[center_id].available), center_id
        ),
    )
    for rank, center_id in enumerate(ranked, 1):
        capacity_total = data.centers[center_id].available * data.horizon
        lines.append(
            f"RANK {rank} {center_id} load {totals[center_id]} "
            f"utilization {percent(totals[center_id], capacity_total)}"
        )
    return lines


def supply_lines(data, plan, order_id):
    lines = []
    for item_id in data.planning_order:
        for supply in plan.items[item_id].order_supplies:
            if supply.serves(order_id):
                order = supply.order
                lines.append(
                    f"  SUPPLY {item_id} order {order.number} receipt {order.receipt} "
                    f"release {order.release} quantity {order.quantity}"
                )
    return lines


def change_lines(data, base, final):
    lines = []
    for item_id in data.planning_order:
        before = base.items[item_id]
        after = final.items[item_id]
        changed = [
            week for week in data.weeks
            if before.planned_receipts[week] != after.planned_receipts[week]
        ]
        if changed:
            lines.append(
                f"CHANGE {item_id} from {changed[0]} "
                f"planned {sum(before.planned_receipts)} -> {sum(after.planned_receipts)} "
                f"orders {len(before.orders)} -> {len(after.orders)}"
            )
    return lines


def promise_lines(data, promises, base, final):
    lines = []
    counts = {"on_time": 0, "late": 0, "rejected": 0}
    for promise in promises:
        inquiry = promise.inquiry
        status = promise.status()
        counts[status] += 1
        head = (
            f"ORDER {inquiry.id} {inquiry.item} quantity {inquiry.quantity} "
            f"requested {inquiry.week}"
        )
        material = str(promise.material_week) if promise.material_week > 0 else "none"
        if status == "rejected":
            lines.append(f"{head} rejected material {material} reason {promise.reason}")
            continue
        if status == "on_time":
            lines.append(f"{head} promised {promise.week}")
        else:
            lines.append(
                f"{head} promised {promise.week} late {promise.week - inquiry.week} "
                f"material {material} reason {promise.reason}"
            )
        lines.extend(supply_lines(data, final, inquiry.id))
    lines.extend(change_lines(data, base, final))
    lines.append(
        f"SUMMARY orders {len(promises)} on_time {counts['on_time']} "
        f"late {counts['late']} rejected {counts['rejected']}"
    )
    return lines


def make_lines(data, order, available):
    item = data.items[order.item]
    rows = data.bom.children[order.item]
    needs = [need(row, order.quantity) for row in rows]
    ready = all(amount <= available[row.child] for row, amount in zip(rows, needs))
    lines = []
    for row, amount in zip(rows, needs):
        have = available[row.child]
        lines.append(
            f"  PICK {row.child} need {amount} available {have} short {max(0, amount - have)}"
        )
    if ready:
        for row, amount in zip(rows, needs):
            available[row.child] -= amount
    operations = data.routings.get(order.item, [])
    for index, operation in enumerate(operations):
        week = operation_week(order.receipt, item.lead_time, index, len(operations))
        lines.append(
            f"  OPERATION {operation.number} {operation.center} week {week} "
            f"minutes {operation.minutes(order.quantity)}"
        )
    return ready, lines


def release_lines(data, plan):
    orders = []
    for item_id in data.planning_order:
        orders.extend(order for order in plan.items[item_id].orders if order.release == 1)
    orders.sort(key=lambda order: (order.original_release, order.item, order.number))
    available = {
        item_id: item.on_hand + data.scheduled[item_id][1] for item_id, item in data.items.items()
    }
    lines = []
    made = 0
    ready_count = 0
    bought = 0
    purchase_total = 0
    for order in orders:
        lateness = f" late {1 - order.original_release}" if order.is_past_due() else ""
        head = (
            f"{order.item} order {order.number} receipt {order.receipt} "
            f"quantity {order.quantity}"
        )
        if not data.bom.is_manufactured(order.item):
            value = order.quantity * data.items[order.item].material
            bought += 1
            purchase_total += value
            lines.append(f"BUY {head}{lateness} value {money(value)}")
            continue
        ready, detail = make_lines(data, order, available)
        made += 1
        if ready:
            ready_count += 1
        lines.append(f"MAKE {head}{lateness} {'READY' if ready else 'SHORT'}")
        lines.extend(detail)
    lines.append(
        f"SUMMARY make {made} ready {ready_count} short {made - ready_count} "
        f"buy {bought} value {money(purchase_total)}"
    )
    return lines


def value_plan_lines(data, plan, costs):
    lines = ["week,inventory,purchases,labor"]
    for week in data.weeks:
        inventory = 0
        purchases = 0
        labor = 0
        for item_id in data.planning_order:
            item_plan = plan.items[item_id]
            released = item_plan.planned_releases[week]
            inventory += item_plan.on_hand[week] * costs[item_id].total
            if data.bom.is_manufactured(item_id):
                labor += released * item_plan.item.labor
            else:
                purchases += released * item_plan.item.material
        lines.append(f"{week},{money(inventory)},{money(purchases)},{money(labor)}")
    return lines


def main():
    data = PlanningData()
    base = run_mrp(data, [])
    promises, final = promise_inquiries(data, base)
    peg_plan(data, final)
    costs = standard_costs(data.items, data.bom, data.planning_order)
    write_report("mrp_grid.txt", grid_lines(data, final))
    write_report("pegging.txt", pegging_lines(data, final))
    write_report("bom_tree.txt", bom_tree_lines(data))
    write_report("cost_rollup.csv", cost_lines(data, final, costs))
    write_report("exceptions.txt", exception_lines(data, final))
    write_report("capacity.txt", capacity_lines(data, final))
    write_report("promises.txt", promise_lines(data, promises, base, final))
    write_report("releases.txt", release_lines(data, final))
    write_report("value_plan.csv", value_plan_lines(data, final, costs))


if __name__ == "__main__":
    main()
