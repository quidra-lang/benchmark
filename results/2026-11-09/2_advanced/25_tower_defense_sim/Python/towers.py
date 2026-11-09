from combat import squared_distance
from grid_map import cell_center


TARGET_MODES = ("FIRST", "LAST", "STRONGEST", "WEAKEST", "CLOSEST")


class Level:
    def __init__(self, fields):
        values = [int(field) for field in fields[1:]]
        self.cost = values[0]
        self.range = values[1]
        self.power = values[2]
        self.interval = values[3]
        self.shot_speed = values[4]
        self.splash = values[5]
        self.slow_rate = values[6]
        self.slow_time = values[7]
        self.burn_amount = values[8]
        self.burn_time = values[9]


class TowerType:
    def __init__(self, name, symbol, targets, levels):
        self.name = name
        self.symbol = symbol
        self.targets = targets
        self.levels = levels


def parse_tower_types(lines):
    types = []
    index = 0
    while index < len(lines):
        _, name, symbol, targets, count = lines[index].split()
        levels = [Level(line.split()) for line in lines[index + 1:index + 1 + int(count)]]
        types.append(TowerType(name, symbol, targets, levels))
        index += 1 + int(count)
    return types


def can_aim(targets, enemy):
    return targets == "both" or targets == enemy.kind.movement


class Tower:
    def __init__(self, number, kind, cell, tick):
        self.number = number
        self.kind = kind
        self.cell = cell
        self.level = 1
        self.mode = "FIRST"
        self.ready = tick
        self.investment = kind.levels[0].cost
        self.built = tick
        self.sold = None
        self.shots = 0
        self.hits = 0
        self.fizzles = 0
        self.kills = 0
        self.damage = 0

    def stats(self):
        return self.kind.levels[self.level - 1]

    def center(self):
        return cell_center(self.cell)

    def standing(self):
        return self.sold is None

    def in_range(self, point):
        reach = self.stats().range
        return squared_distance(self.center(), point) <= reach * reach

    def target_key(self, enemy, field):
        if self.mode == "FIRST":
            return enemy.remaining(field)
        if self.mode == "LAST":
            return -enemy.remaining(field)
        if self.mode == "STRONGEST":
            return -enemy.hp
        if self.mode == "WEAKEST":
            return enemy.hp
        return squared_distance(self.center(), enemy.position())

    def select_target(self, enemies, field):
        best = None
        best_key = 0
        for enemy in enemies:
            if not can_aim(self.kind.targets, enemy) or not self.in_range(enemy.position()):
                continue
            key = self.target_key(enemy, field)
            if best is None or key < best_key:
                best = enemy
                best_key = key
        return best
