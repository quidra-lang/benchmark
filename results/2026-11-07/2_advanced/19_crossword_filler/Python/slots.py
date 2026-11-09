ACROSS = (0, 1)
DOWN = (1, 0)
MIN_SLOT_LENGTH = 3


def starts_run(grid, row, column, step):
    d_row, d_column = step
    return grid.is_open(row, column) and not grid.is_open(row - d_row, column - d_column)


def run_length(grid, row, column, step):
    d_row, d_column = step
    length = 0
    while grid.is_open(row + length * d_row, column + length * d_column):
        length += 1
    return length


def find_short_run(grid):
    for row in range(grid.height):
        for column in range(grid.width):
            for step, direction in ((ACROSS, "across"), (DOWN, "down")):
                if starts_run(grid, row, column, step) and run_length(grid, row, column, step) == 2:
                    return grid.cell(row, column), direction
    return None


class Slot:
    def __init__(self, index, number, across, cells):
        self.index = index
        self.number = number
        self.across = across
        self.cells = cells
        self.length = len(cells)
        self.label = str(number) + ("A" if across else "D")
        self.crossings = []


class Layout:
    def __init__(self, grid):
        self.grid = grid
        self.numbers = {}
        self.slots = []
        self.across_slot = [None] * grid.size()
        self.down_slot = [None] * grid.size()
        for row in range(grid.height):
            for column in range(grid.width):
                for step in (ACROSS, DOWN):
                    if starts_run(grid, row, column, step):
                        length = run_length(grid, row, column, step)
                        if length >= MIN_SLOT_LENGTH:
                            self.add_slot(row, column, step, length)
        for slot in self.slots:
            owners = self.down_slot if slot.across else self.across_slot
            crossing = [owners[cell] for cell in slot.cells if owners[cell] is not None]
            slot.crossings = sorted(crossing)

    def add_slot(self, row, column, step, length):
        start = self.grid.cell(row, column)
        if start not in self.numbers:
            self.numbers[start] = len(self.numbers) + 1
        d_row, d_column = step
        cells = [self.grid.cell(row + i * d_row, column + i * d_column) for i in range(length)]
        slot = Slot(len(self.slots), self.numbers[start], step == ACROSS, cells)
        self.slots.append(slot)
        owners = self.across_slot if slot.across else self.down_slot
        for cell in cells:
            owners[cell] = slot.index

    def owner_count(self, cell):
        return (self.across_slot[cell] is not None) + (self.down_slot[cell] is not None)

    def orphan_cell(self):
        for cell in self.grid.white_cells():
            if self.owner_count(cell) == 0:
                return cell
        return None
