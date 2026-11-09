BLACK = "#"
EMPTY = "."


class Grid:
    def __init__(self, rows):
        self.rows = rows
        self.height = len(rows)
        self.width = len(rows[0])
        self.cells = "".join(rows)

    def size(self):
        return self.height * self.width

    def cell(self, row, column):
        return row * self.width + column

    def location(self, cell):
        row, column = divmod(cell, self.width)
        return row + 1, column + 1

    def is_open(self, row, column):
        if row < 0 or row >= self.height or column < 0 or column >= self.width:
            return False
        return self.rows[row][column] != BLACK

    def is_given(self, cell):
        return self.cells[cell] not in (BLACK, EMPTY)

    def white_cells(self):
        return [cell for cell in range(self.size()) if self.cells[cell] != BLACK]

    def partner(self, row, column, symmetry):
        if symmetry == "rot180":
            return self.height - 1 - row, self.width - 1 - column
        return row, self.width - 1 - column

    def asymmetric_cell(self, symmetry):
        for row in range(self.height):
            for column in range(self.width):
                other_row, other_column = self.partner(row, column, symmetry)
                if self.is_open(row, column) != self.is_open(other_row, other_column):
                    return self.cell(row, column)
        return None

    def component_count(self):
        seen = [False] * self.size()
        count = 0
        for start in self.white_cells():
            if seen[start]:
                continue
            count += 1
            seen[start] = True
            stack = [start]
            while stack:
                row, column = divmod(stack.pop(), self.width)
                for next_row, next_column in (
                    (row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1),
                ):
                    if self.is_open(next_row, next_column):
                        neighbor = self.cell(next_row, next_column)
                        if not seen[neighbor]:
                            seen[neighbor] = True
                            stack.append(neighbor)
        return count
