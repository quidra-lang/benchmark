from line_solver import UNKNOWN, solve_line


class Step:
    def __init__(self, is_row, index, gain, contradiction):
        self.is_row = is_row
        self.index = index
        self.gain = gain
        self.contradiction = contradiction

    def label(self):
        return line_label(self.is_row, self.index)

    def text(self):
        if self.contradiction:
            return self.label() + "!"
        return f"{self.label()}+{self.gain}"


class Propagation:
    def __init__(self):
        self.steps = []
        self.conflict = None

    def line_solves(self):
        return len(self.steps)

    def record(self):
        return " ".join(step.text() for step in self.steps)


def line_label(is_row, index):
    return ("R" if is_row else "C") + str(index + 1)


def line_cells(grid, is_row, index):
    if is_row:
        return list(grid[index])
    return [row[index] for row in grid]


def determined_count(grid):
    return sum(1 for row in grid for state in row if state != UNKNOWN)


def next_line(row_marks, column_marks):
    if True in row_marks:
        return True, row_marks.index(True)
    if True in column_marks:
        return False, column_marks.index(True)
    return None


def propagate(grid, row_clues, column_clues, precise, row_marks, column_marks):
    propagation = Propagation()
    while True:
        chosen = next_line(row_marks, column_marks)
        if chosen is None:
            return propagation
        is_row, index = chosen
        if is_row:
            row_marks[index] = False
            clue = row_clues[index]
        else:
            column_marks[index] = False
            clue = column_clues[index]
        cells = line_cells(grid, is_row, index)
        solved = solve_line(cells, clue, precise)
        if solved is None:
            step = Step(is_row, index, 0, True)
            propagation.steps.append(step)
            propagation.conflict = step
            return propagation
        gain = 0
        for position, state in enumerate(solved):
            if cells[position] != UNKNOWN or state == UNKNOWN:
                continue
            gain += 1
            if is_row:
                grid[index][position] = state
                column_marks[position] = True
            else:
                grid[position][index] = state
                row_marks[position] = True
        propagation.steps.append(Step(is_row, index, gain, False))
