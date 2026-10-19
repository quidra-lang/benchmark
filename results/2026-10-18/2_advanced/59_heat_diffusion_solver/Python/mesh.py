"""Read the plate and enumerate cells and faces in the prescribed orders."""

from pathlib import Path


LEFT, RIGHT, TOP, BOTTOM = range(4)
EDGE_FACES = {"left": LEFT, "right": RIGHT, "top": TOP, "bottom": BOTTOM}


class Mesh:
    def __init__(self, width, height, dx, thickness, rows):
        self.width = width
        self.height = height
        self.dx = dx
        self.thickness = thickness
        self.count = width * height
        self.codes = [code for row in rows for code in row]
        self.neighbors = []
        for row in range(height):
            for column in range(width):
                point = self.cell(row, column)
                self.neighbors.append((
                    point - 1 if column > 0 else -1,
                    point + 1 if column + 1 < width else -1,
                    point - width if row > 0 else -1,
                    point + width if row + 1 < height else -1,
                ))

    def cell(self, row, column):
        return row * self.width + column

    def coordinates(self, point):
        return divmod(point, self.width)

    def segment_faces(self, edge, start, end):
        face = EDGE_FACES[edge]
        if edge in ("top", "bottom"):
            row = 0 if edge == "top" else self.height - 1
            return [(self.cell(row, column), face) for column in range(start, end + 1)]
        column = 0 if edge == "left" else self.width - 1
        return [(self.cell(row, column), face) for row in range(start, end + 1)]

    def source_cells(self, first_row, first_column, last_row, last_column):
        return [
            self.cell(row, column)
            for row in range(first_row, last_row + 1)
            for column in range(first_column, last_column + 1)
        ]


def read_plate(path="input/plate.txt"):
    with Path(path).open(encoding="ascii") as source:
        width, height, dx, thickness = source.readline().split()
        rows = [line.rstrip("\n") for line in source]
    return Mesh(int(width), int(height), float(dx), float(thickness), rows)
