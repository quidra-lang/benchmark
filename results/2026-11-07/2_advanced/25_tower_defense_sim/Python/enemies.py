from math import isqrt

from combat import Effect, squared_distance
from grid_map import cell_center


class EnemyType:
    def __init__(self, fields, known):
        self.name = fields[1]
        self.symbol = fields[2]
        self.movement = fields[3]
        self.hp = int(fields[4])
        self.armor = int(fields[5])
        self.speed = int(fields[6])
        self.bounty = int(fields[7])
        self.lives = int(fields[8])
        self.regen = int(fields[9])
        self.split_into = None if fields[10] == "-" else known[fields[10]]
        self.split_count = int(fields[11])
        self.spawned = 0
        self.kills = 0
        self.leaks = 0
        self.damage = 0


class Group:
    def __init__(self, fields, known):
        self.kind = known[fields[1]]
        self.spawn = int(fields[2])
        self.count = int(fields[3])
        self.delay = int(fields[4])
        self.interval = int(fields[5])
        self.multiplier = int(fields[6])

    def spawn_tick(self, start, index):
        return start + self.delay + index * self.interval


class Wave:
    def __init__(self, reward):
        self.reward = reward
        self.groups = []

    def enemy_count(self):
        return sum(group.count for group in self.groups)


def parse_waves(lines):
    types = {}
    waves = []
    for line in lines:
        fields = line.split()
        if fields[0] == "enemy":
            kind = EnemyType(fields, types)
            types[kind.name] = kind
        elif fields[0] == "wave":
            waves.append(Wave(int(fields[1])))
        else:
            waves[-1].groups.append(Group(fields, types))
    return types, waves


class Enemy:
    def __init__(self, number, kind, multiplier):
        self.number = number
        self.kind = kind
        self.multiplier = multiplier
        self.max_hp = kind.hp * multiplier // 100
        self.hp = self.max_hp
        self.slow = Effect()
        self.burn = Effect()
        self.alive = True
        self.cell = None
        self.next_cell = None
        self.progress = 0
        self.point = None

    def flying(self):
        return self.kind.movement == "air"

    def position(self):
        if self.flying():
            return self.point
        cell_x, cell_y = self.cell
        next_x, next_y = self.next_cell
        return (
            100 * cell_x + (next_x - cell_x) * self.progress,
            100 * cell_y + (next_y - cell_y) * self.progress,
        )

    def occupied_cell(self):
        if self.flying():
            x, y = self.point
            return (x + 50) // 100, (y + 50) // 100
        return self.cell if self.progress < 50 else self.next_cell

    def remaining(self, field):
        if self.flying():
            return isqrt(squared_distance(self.point, cell_center(field.exit)))
        return 100 * field.at(self.next_cell) + 100 - self.progress

    def slowed_speed(self):
        if self.slow.active():
            return self.kind.speed * (100 - self.slow.strength) // 100
        return self.kind.speed

    def split(self, number):
        child = Enemy(number, self.kind.split_into, self.multiplier)
        child.cell = self.cell
        child.next_cell = self.next_cell
        child.progress = self.progress
        child.point = self.point
        return child
