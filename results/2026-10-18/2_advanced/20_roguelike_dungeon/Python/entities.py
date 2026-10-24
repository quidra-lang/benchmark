from combat import parse_dice


ITEM_SYMBOLS = {
    "weapon": ")",
    "armor": "[",
    "potion": "!",
    "scroll": "?",
    "food": "%",
    "gold": "$",
    "amulet": '"',
}


class MonsterType:
    def __init__(self, tokens):
        self.name = tokens[0]
        self.symbol = tokens[1]
        self.min_depth = int(tokens[2])
        self.max_depth = int(tokens[3])
        self.weight = int(tokens[4])
        self.hp = parse_dice(tokens[5])
        self.to_hit = int(tokens[6])
        self.defense = int(tokens[7])
        self.damage = parse_dice(tokens[8])
        self.speed = int(tokens[9])
        self.xp = int(tokens[10])
        traits = tokens[11]
        self.erratic = "E" in traits
        self.stationary = "S" in traits
        self.regenerates = "R" in traits
        self.poisonous = "P" in traits


class ItemType:
    def __init__(self, category, name, min_depth, max_depth, weight):
        self.category = category
        self.name = name
        self.min_depth = min_depth
        self.max_depth = max_depth
        self.weight = weight
        self.dice = None
        self.to_hit = 0
        self.armor = 0
        self.effect = None
        self.poison_turns = 0
        self.nutrition = 0


def parse_item_type(tokens):
    category = tokens[0]
    kind = ItemType(category, tokens[1], int(tokens[2]), int(tokens[3]), int(tokens[4]))
    arguments = tokens[5:]
    if category == "weapon":
        kind.dice = parse_dice(arguments[0])
        kind.to_hit = int(arguments[1])
    elif category == "armor":
        kind.armor = int(arguments[0])
    elif category == "potion":
        kind.effect = arguments[0]
        if kind.effect == "heal":
            kind.dice = parse_dice(arguments[1])
        elif kind.effect == "poison":
            kind.poison_turns = int(arguments[1])
    elif category == "scroll":
        kind.effect = arguments[0]
    elif category == "food":
        kind.nutrition = int(arguments[0])
    elif category == "gold":
        kind.dice = parse_dice(arguments[0])
    return kind


def amulet_type():
    return ItemType("amulet", "amulet", 0, 0, 0)


class Monster:
    def __init__(self, number, kind, x, y, hp, asleep):
        self.number = number
        self.kind = kind
        self.x = x
        self.y = y
        self.hp = hp
        self.max_hp = hp
        self.asleep = asleep
        self.energy = 0
        self.was_visible = False


class Item:
    def __init__(self, kind, x, y, amount=0):
        self.kind = kind
        self.x = x
        self.y = y
        self.amount = amount
        self.bonus = 0

    def symbol(self):
        return ITEM_SYMBOLS[self.kind.category]

    def display_name(self):
        name = self.kind.name.replace("_", " ")
        if self.kind.category in ("weapon", "armor"):
            return f"+{self.bonus} {name}"
        if self.kind.category == "gold":
            return f"{self.amount} gold"
        return name

    def reference_name(self):
        if self.kind.category == "gold":
            return self.display_name()
        return "the " + self.display_name()
