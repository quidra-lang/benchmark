GROUND = "."
ROCK = "#"
WATER = "~"
EXIT = "E"


def cell_center(cell):
    x, y = cell
    return 100 * x, 100 * y


class GridMap:
    def __init__(self, width, height, rows):
        self.width = width
        self.height = height
        self.rows = rows
        self.exit = None
        found = {}
        for y, row in enumerate(rows):
            for x, terrain in enumerate(row):
                if terrain.isdigit():
                    found[int(terrain)] = (x, y)
                elif terrain == EXIT:
                    self.exit = (x, y)
        self.spawns = [found[number] for number in range(1, len(found) + 1)]

    def inside(self, cell):
        x, y = cell
        return 0 <= x < self.width and 0 <= y < self.height

    def terrain(self, cell):
        x, y = cell
        return self.rows[y][x]

    def is_rock(self, cell):
        return self.terrain(cell) == ROCK

    def is_water(self, cell):
        return self.terrain(cell) == WATER

    def buildable(self, cell):
        return self.terrain(cell) == GROUND


def read_map(path):
    with open(path) as file:
        lines = file.read().splitlines()
    width, height = (int(value) for value in lines[0].split())
    return GridMap(width, height, lines[1:height + 1])
