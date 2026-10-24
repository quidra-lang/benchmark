ROCK = " "
HORIZONTAL_WALL = "-"
VERTICAL_WALL = "|"
FLOOR = "."
CORRIDOR = "#"
DOOR = "+"
UP_STAIRS = "<"
DOWN_STAIRS = ">"
WALLS = (HORIZONTAL_WALL, VERTICAL_WALL)
PASSABLE = (FLOOR, CORRIDOR, DOOR, UP_STAIRS, DOWN_STAIRS)
UNSEEN = " "


class Room:
    def __init__(self, x, y, width, height):
        self.x = x
        self.y = y
        self.width = width
        self.height = height

    def center(self):
        return self.x + self.width // 2, self.y + self.height // 2


class Region:
    def __init__(self, x, y, width, height):
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.first = None
        self.second = None
        self.leaf = None


class Level:
    def __init__(self, depth, width, height):
        self.depth = depth
        self.width = width
        self.height = height
        self.terrain = [[ROCK] * width for _ in range(height)]
        self.memory = [[UNSEEN] * width for _ in range(height)]
        self.rooms = []
        self.arrival = None
        self.arrival_room = None
        self.target = None
        self.monsters = []
        self.items = []
        self.monsters_created = 0
        self.items_placed = 0
        self.kills = 0
        self.picked = 0

    def monster_at(self, x, y):
        for monster in self.monsters:
            if monster.x == x and monster.y == y:
                return monster
        return None

    def item_at(self, x, y):
        for item in self.items:
            if item.x == x and item.y == y:
                return item
        return None

    def draw_interior_cell(self, rng, index):
        room = self.rooms[index]
        x = room.x + 1 + rng.rnd(room.width - 2)
        y = room.y + 1 + rng.rnd(room.height - 2)
        return x, y

    def draw_room_cell(self, rng):
        index = rng.rnd(len(self.rooms))
        x, y = self.draw_interior_cell(rng, index)
        return index, x, y


def span(start, end):
    step = 1 if end >= start else -1
    return range(start, end + step, step)


class LevelGenerator:
    def __init__(self, rng, min_size, max_split, room_min, room_max):
        self.rng = rng
        self.min_size = min_size
        self.max_split = max_split
        self.room_min = room_min
        self.room_max = room_max

    def generate(self, depth, width, height):
        level = Level(depth, width, height)
        root = Region(0, 0, width, height)
        leaves = []
        self.split(root, 0, leaves)
        for leaf in leaves:
            level.rooms.append(self.make_room(level, leaf))
        self.connect(level, root)
        self.choose_stairs(level)
        return level

    def split(self, region, depth, leaves):
        vertical_fits = region.width >= 2 * self.min_size
        horizontal_fits = region.height >= 2 * self.min_size
        if depth == self.max_split or not (vertical_fits or horizontal_fits):
            region.leaf = len(leaves)
            leaves.append(region)
            return
        if vertical_fits and horizontal_fits:
            if 4 * region.width >= 5 * region.height:
                vertical = True
            elif 4 * region.height >= 5 * region.width:
                vertical = False
            else:
                vertical = self.rng.draw() % 2 == 0
        else:
            vertical = vertical_fits
        if vertical:
            cut = self.min_size + self.rng.rnd(region.width - 2 * self.min_size + 1)
            region.first = Region(region.x, region.y, cut, region.height)
            region.second = Region(region.x + cut, region.y, region.width - cut, region.height)
        else:
            cut = self.min_size + self.rng.rnd(region.height - 2 * self.min_size + 1)
            region.first = Region(region.x, region.y, region.width, cut)
            region.second = Region(region.x, region.y + cut, region.width, region.height - cut)
        self.split(region.first, depth + 1, leaves)
        self.split(region.second, depth + 1, leaves)

    def make_room(self, level, region):
        width = self.room_min + self.rng.rnd(min(self.room_max, region.width - 1) - self.room_min + 1)
        height = self.room_min + self.rng.rnd(min(self.room_max, region.height - 1) - self.room_min + 1)
        x = region.x + self.rng.rnd(region.width - width)
        y = region.y + self.rng.rnd(region.height - height)
        for row in range(y, y + height):
            for column in range(x, x + width):
                if row == y or row == y + height - 1:
                    level.terrain[row][column] = HORIZONTAL_WALL
                elif column == x or column == x + width - 1:
                    level.terrain[row][column] = VERTICAL_WALL
                else:
                    level.terrain[row][column] = FLOOR
        return Room(x, y, width, height)

    def connect(self, level, region):
        if region.leaf is not None:
            return [region.leaf]
        first = self.connect(level, region.first)
        second = self.connect(level, region.second)
        best = None
        best_distance = 0
        for a in first:
            ax, ay = level.rooms[a].center()
            for b in second:
                bx, by = level.rooms[b].center()
                distance = abs(ax - bx) + abs(ay - by)
                if best is None or distance < best_distance:
                    best = a, b
                    best_distance = distance
        horizontal_first = self.rng.draw() % 2 == 0
        self.dig(level, level.rooms[best[0]].center(), level.rooms[best[1]].center(), horizontal_first)
        return first + second

    def dig(self, level, start, end, horizontal_first):
        ax, ay = start
        bx, by = end
        if horizontal_first:
            path = [(x, ay) for x in span(ax, bx)] + [(bx, y) for y in span(ay, by)]
        else:
            path = [(ax, y) for y in span(ay, by)] + [(x, by) for x in span(ax, bx)]
        for x, y in path:
            if level.terrain[y][x] == ROCK:
                level.terrain[y][x] = CORRIDOR
            elif level.terrain[y][x] in WALLS:
                level.terrain[y][x] = DOOR

    def choose_stairs(self, level):
        room, x, y = level.draw_room_cell(self.rng)
        level.terrain[y][x] = UP_STAIRS
        level.arrival = x, y
        level.arrival_room = room
        other = self.rng.rnd(len(level.rooms) - 1)
        if other >= room:
            other += 1
        level.target = level.draw_interior_cell(self.rng, other)
