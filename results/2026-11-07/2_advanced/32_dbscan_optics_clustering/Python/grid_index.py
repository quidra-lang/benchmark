def squared_distance(first, second):
    dx = first.x - second.x
    dy = first.y - second.y
    return dx * dx + dy * dy


class GridIndex:
    def __init__(self, points, eps):
        self.points = points
        self.eps = eps
        self.limit = eps * eps
        self.cells = {}
        for index, point in enumerate(points):
            self.cells.setdefault(self.cell_of(point), []).append(index)

    def cell_of(self, point):
        return point.x // self.eps, point.y // self.eps

    def neighborhood(self, index):
        point = self.points[index]
        column, row = self.cell_of(point)
        neighbors = []
        candidates = 0
        for gy in (row - 1, row, row + 1):
            for gx in (column - 1, column, column + 1):
                for other in self.cells.get((gx, gy), []):
                    candidates += 1
                    if squared_distance(point, self.points[other]) <= self.limit:
                        neighbors.append(other)
        return neighbors, candidates

    def busiest_cell(self):
        gx, gy = min(self.cells, key=lambda cell: (-len(self.cells[cell]), cell[1], cell[0]))
        return gx, gy, len(self.cells[(gx, gy)])


def brute_force_counts(points, eps):
    limit = eps * eps
    return [
        sum(1 for other in points if squared_distance(point, other) <= limit)
        for point in points
    ]
