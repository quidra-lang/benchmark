class Canvas:
    def __init__(self, width, height):
        self.width = width
        self.height = height
        self.rows = [[" "] * width for _ in range(height)]

    def position(self, x, y, denominator=1):
        column = (2 * x * (self.width - 1) + 1000 * denominator) // (2000 * denominator)
        row = self.height - 1 - (
            (2 * y * (self.height - 1) + 1000 * denominator) // (2000 * denominator)
        )
        return column, row

    def mark(self, point, character):
        column, row = self.position(*point)
        self.rows[row][column] = character

    def line(self, first, second, character):
        x, y = self.position(*first)
        end_x, end_y = self.position(*second)
        dx = abs(end_x - x)
        dy = -abs(end_y - y)
        step_x = 1 if x < end_x else -1
        step_y = 1 if y < end_y else -1
        error = dx + dy
        while True:
            self.rows[y][x] = character
            if x == end_x and y == end_y:
                return
            twice_error = 2 * error
            if twice_error >= dy:
                error += dy
                x += step_x
            if twice_error <= dx:
                error += dx
                y += step_y

    def draw_voronoi(self, points):
        horizontal = self.width - 1
        vertical = self.height - 1
        owners = []
        for row in range(self.height):
            row_owners = []
            for column in range(self.width):
                owner = None
                best = None
                for site in range(1, len(points)):
                    x, y = points[site]
                    dx = (column * 1000 - x * horizontal) * vertical
                    dy = ((vertical - row) * 1000 - y * vertical) * horizontal
                    distance = dx * dx + dy * dy
                    if best is None or distance < best:
                        owner = site
                        best = distance
                row_owners.append(owner)
            owners.append(row_owners)
        for row in range(self.height):
            for column in range(self.width):
                owner = owners[row][column]
                right_differs = column < horizontal and owner != owners[row][column + 1]
                below_differs = row < vertical and owner != owners[row + 1][column]
                if right_differs or below_differs:
                    self.rows[row][column] = "#"
        for point in points[1:]:
            self.mark(point, "o")

    def framed(self):
        border = "+" + "-" * self.width + "+"
        return [border, *("|" + "".join(row) + "|" for row in self.rows), border]
