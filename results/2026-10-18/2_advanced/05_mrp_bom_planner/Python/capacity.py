import os


CENTERS_FILE = "workcenters.csv"
ROUTINGS_FILE = "routings.csv"
MIN_EFFICIENCY = 50
MAX_EFFICIENCY = 150


class WorkCenter:
    def __init__(self, fields):
        self.id = fields[0]
        self.minutes = int(fields[1])
        self.efficiency = int(fields[2])
        self.description = fields[3]
        self.available = self.minutes * self.efficiency // 100


class Operation:
    def __init__(self, fields):
        self.item = fields[0]
        self.number = int(fields[1])
        self.center = fields[2]
        self.setup = int(fields[3])
        self.run = int(fields[4])

    def minutes(self, quantity):
        return self.setup + quantity * self.run


def center_error(fields, centers):
    center_id, efficiency = fields[0], int(fields[2])
    if center_id in centers:
        return f"duplicate center {center_id}"
    if efficiency < MIN_EFFICIENCY or efficiency > MAX_EFFICIENCY:
        return f"bad efficiency {efficiency}"
    return None


def read_workcenters(directory, errors):
    centers = {}
    with open(os.path.join(directory, CENTERS_FILE)) as file:
        lines = file.read().splitlines()
    for number, line in enumerate(lines[1:], 2):
        fields = line.split(",")
        message = center_error(fields, centers)
        if message is None:
            centers[fields[0]] = WorkCenter(fields)
        else:
            errors.append(f"{CENTERS_FILE} line {number}: {message}")
    return centers


def routing_error(fields, items, centers, bom, routings):
    item_id, number, center_id, run = fields[0], int(fields[1]), fields[2], int(fields[4])
    if item_id not in items:
        return f"unknown item {item_id}"
    if center_id not in centers:
        return f"unknown center {center_id}"
    if not bom.is_manufactured(item_id):
        return f"purchased item {item_id}"
    if run < 1:
        return f"bad run time {run}"
    if any(operation.number == number for operation in routings.get(item_id, [])):
        return f"duplicate {item_id} operation {number}"
    return None


def read_routings(directory, items, centers, bom, errors):
    routings = {}
    with open(os.path.join(directory, ROUTINGS_FILE)) as file:
        lines = file.read().splitlines()
    for number, line in enumerate(lines[1:], 2):
        fields = line.split(",")
        message = routing_error(fields, items, centers, bom, routings)
        if message is None:
            routings.setdefault(fields[0], []).append(Operation(fields))
        else:
            errors.append(f"{ROUTINGS_FILE} line {number}: {message}")
    for operations in routings.values():
        operations.sort(key=lambda operation: operation.number)
    return routings


def operation_week(receipt, lead_time, index, count):
    return max(receipt - lead_time + index * lead_time // count, 1)


def level_loads(loads, available):
    horizon = len(loads) - 1
    leveled = [0] * (horizon + 1)
    carry = 0
    for week in range(horizon, 1, -1):
        total = loads[week] + carry
        leveled[week] = min(total, available)
        carry = total - leveled[week]
    leveled[1] = loads[1] + carry
    return leveled
