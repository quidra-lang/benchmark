from collections import deque


DIRECTIONS = ((0, -1), (1, 0), (0, 1), (-1, 0))


def neighbor(cell, direction):
    dx, dy = DIRECTIONS[direction]
    return cell[0] + dx, cell[1] + dy


class DistanceField:
    def __init__(self, grid, towers):
        self.grid = grid
        self.exit = grid.exit
        self.dist = [[None] * grid.width for _ in range(grid.height)]
        exit_x, exit_y = grid.exit
        self.dist[exit_y][exit_x] = 0
        queue = deque([grid.exit])
        while queue:
            cell = queue.popleft()
            for direction in range(len(DIRECTIONS)):
                following = neighbor(cell, direction)
                if self.passable(following, towers) and self.at(following) is None:
                    x, y = following
                    self.dist[y][x] = self.at(cell) + 1
                    queue.append(following)

    def passable(self, cell, towers):
        return self.grid.inside(cell) and not self.grid.is_rock(cell) and cell not in towers

    def at(self, cell):
        x, y = cell
        return self.dist[y][x]

    def direction(self, cell):
        best = None
        best_dist = 0
        for direction in range(len(DIRECTIONS)):
            following = neighbor(cell, direction)
            if not self.grid.inside(following) or self.at(following) is None:
                continue
            if best is None or self.at(following) < best_dist:
                best = direction
                best_dist = self.at(following)
        return best

    def next_cell(self, cell):
        return neighbor(cell, self.direction(cell))

    def path(self, start):
        cells = [start]
        while cells[-1] != self.exit:
            cells.append(self.next_cell(cells[-1]))
        return cells
