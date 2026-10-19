"""Row-major grid cells with point sequences maintained in ID order."""

from bisect import insort


class Cell:
    __slots__ = ("column", "row", "box", "points")

    def __init__(self, column, row, size):
        self.column = column
        self.row = row
        x, y = column * size, row * size
        self.box = (x, y, x + size - 1, y + size - 1)
        self.points = []


class Grid:
    def __init__(self, world, cell_size, points):
        self.world = world
        self.cell_size = cell_size
        self.side = world // cell_size
        self.cells = [
            Cell(column, row, cell_size)
            for row in range(self.side)
            for column in range(self.side)
        ]
        for point in points:
            self.insert(point)

    def position(self, point):
        return point[1] // self.cell_size, point[2] // self.cell_size

    def cell(self, point):
        column, row = self.position(point)
        return self.cells[row * self.side + column]

    def insert(self, point):
        insort(self.cell(point).points, point)

    def delete(self, point):
        self.cell(point).points.remove(point)
