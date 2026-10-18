import os


BOM_FILE = "bom.csv"
MAX_SCRAP = 50


class BomRow:
    def __init__(self, fields):
        self.parent = fields[0]
        self.child = fields[1]
        self.qty_per = int(fields[2])
        self.scrap = int(fields[3])


def need(row, quantity):
    return (quantity * row.qty_per * (100 + row.scrap) + 99) // 100


class Bom:
    def __init__(self, items):
        self.children = {item_id: [] for item_id in items}
        self.parents = {item_id: [] for item_id in items}

    def add(self, row):
        self.children[row.parent].append(row)
        self.children[row.parent].sort(key=lambda other: other.child)
        self.parents[row.child].append(row)
        self.parents[row.child].sort(key=lambda other: other.parent)

    def contains(self, parent, child):
        return any(row.child == child for row in self.children[parent])

    def is_manufactured(self, item_id):
        return len(self.children[item_id]) > 0

    def is_top_level(self, item_id):
        return self.is_manufactured(item_id) and not self.parents[item_id]

    def path(self, item_id, target, visited):
        if item_id == target:
            return [item_id]
        visited.add(item_id)
        for row in self.children[item_id]:
            if row.child not in visited:
                rest = self.path(row.child, target, visited)
                if rest is not None:
                    return [item_id] + rest
        return None

    def low_level_code(self, item_id, codes):
        if item_id not in codes:
            code = 0
            for row in self.parents[item_id]:
                code = max(code, self.low_level_code(row.parent, codes) + 1)
            codes[item_id] = code
        return codes[item_id]

    def cumulative_lead_time(self, items, item_id, times):
        if item_id not in times:
            longest = 0
            for row in self.children[item_id]:
                longest = max(longest, self.cumulative_lead_time(items, row.child, times))
            times[item_id] = items[item_id].lead_time + longest
        return times[item_id]


def bom_error(fields, items, bom):
    parent, child = fields[0], fields[1]
    qty_per, scrap = int(fields[2]), int(fields[3])
    if parent not in items:
        return f"unknown item {parent}"
    if child not in items:
        return f"unknown item {child}"
    if qty_per < 1:
        return f"bad quantity {qty_per}"
    if scrap > MAX_SCRAP:
        return f"bad scrap {scrap}"
    if parent == child:
        return f"cycle {parent} -> {parent}"
    if bom.contains(parent, child):
        return f"duplicate {parent} -> {child}"
    path = bom.path(child, parent, set())
    if path is not None:
        return f"cycle {parent} -> " + " -> ".join(path)
    return None


def read_bom(directory, items, errors):
    bom = Bom(items)
    with open(os.path.join(directory, BOM_FILE)) as file:
        lines = file.read().splitlines()
    for number, line in enumerate(lines[1:], 2):
        fields = line.split(",")
        message = bom_error(fields, items, bom)
        if message is None:
            bom.add(BomRow(fields))
        else:
            errors.append(f"{BOM_FILE} line {number}: {message}")
    return bom


def low_level_codes(bom, items):
    codes = {}
    for item_id in items:
        bom.low_level_code(item_id, codes)
    return codes


def cumulative_lead_times(bom, items):
    times = {}
    for item_id in items:
        bom.cumulative_lead_time(items, item_id, times)
    return times
