import os


ITEMS_FILE = "items.csv"
LOT_RULES = ("LFL", "FOQ", "POQ", "MIN")


class Item:
    def __init__(self, fields, lot):
        self.id = fields[0]
        self.lead_time = int(fields[1])
        self.rule = fields[2]
        self.safety_stock = int(fields[4])
        self.on_hand = int(fields[5])
        self.material = int(fields[6])
        self.labor = int(fields[7])
        self.description = fields[8]
        self.fixed_quantity = lot[0] if self.rule == "FOQ" else 0
        self.periods = lot[0] if self.rule == "POQ" else 0
        self.minimum = lot[0] if self.rule == "MIN" else 0
        self.multiple = lot[1] if self.rule == "MIN" else 0

    def lot_label(self):
        if self.rule == "FOQ":
            return f"FOQ {self.fixed_quantity}"
        if self.rule == "POQ":
            return f"POQ {self.periods}"
        if self.rule == "MIN":
            return f"MIN {self.minimum}/{self.multiple}"
        return "LFL"


def lot_values(rule, text):
    values = [int(part) for part in text.split("/")]
    if rule == "LFL":
        fits = len(values) == 1 and values[0] == 0
    elif rule == "MIN":
        fits = len(values) == 2 and values[0] >= 1 and values[1] >= 1
    else:
        fits = len(values) == 1 and values[0] >= 1
    return values if fits else None


def item_error(fields, items):
    item_id, rule, lot = fields[0], fields[2], fields[3]
    if item_id in items:
        return f"duplicate item {item_id}"
    if rule not in LOT_RULES:
        return f"unknown lot rule {rule}"
    if lot_values(rule, lot) is None:
        return f"bad lot parameter {lot} for {rule}"
    return None


def read_items(directory, errors):
    items = {}
    with open(os.path.join(directory, ITEMS_FILE)) as file:
        lines = file.read().splitlines()
    for number, line in enumerate(lines[1:], 2):
        fields = line.split(",")
        message = item_error(fields, items)
        if message is None:
            items[fields[0]] = Item(fields, lot_values(fields[2], fields[3]))
        else:
            errors.append(f"{ITEMS_FILE} line {number}: {message}")
    return items
