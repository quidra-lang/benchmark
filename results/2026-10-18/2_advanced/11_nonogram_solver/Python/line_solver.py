UNKNOWN = 0
FILLED = 1
EMPTY = 2


def fit_table(cells, clue):
    empties = [0]
    for state in cells:
        empties.append(empties[-1] + (1 if state == EMPTY else 0))
    table = [[False] * (len(clue) + 1) for _ in range(len(cells) + 1)]
    table[0][0] = True
    for end in range(1, len(cells) + 1):
        for count in range(len(clue) + 1):
            fits = cells[end - 1] != FILLED and table[end - 1][count]
            if not fits and count > 0:
                start = end - clue[count - 1]
                if start >= 0 and empties[end] == empties[start]:
                    if start == 0:
                        fits = count == 1
                    else:
                        fits = cells[start - 1] != FILLED and table[start - 1][count - 1]
            table[end][count] = fits
    return table


class LinePlacements:
    def __init__(self, cells, clue):
        self.cells = cells
        self.clue = clue
        self.length = len(cells)
        self.before = fit_table(cells, clue)
        self.after = fit_table(cells[::-1], clue[::-1])

    def consistent(self):
        return self.before[self.length][len(self.clue)]

    def head_fits(self, end, count):
        return self.before[end][count]

    def tail_fits(self, start, count):
        return self.after[self.length - start][count]

    def can_start(self, block, start):
        end = start + self.clue[block]
        if EMPTY in self.cells[start:end]:
            return False
        if start == 0:
            left = block == 0
        else:
            left = self.cells[start - 1] != FILLED and self.head_fits(start - 1, block)
        rest = len(self.clue) - block - 1
        if end == self.length:
            right = rest == 0
        else:
            right = self.cells[end] != FILLED and self.tail_fits(end + 1, rest)
        return left and right

    def starts(self, block):
        last = self.length - self.clue[block]
        return [start for start in range(last + 1) if self.can_start(block, start)]

    def start_range(self, block):
        starts = self.starts(block)
        return starts[0], starts[-1]

    def can_be_empty(self, index):
        if self.cells[index] == FILLED:
            return False
        count = len(self.clue)
        return any(
            self.head_fits(index, blocks) and self.tail_fits(index + 1, count - blocks)
            for blocks in range(count + 1)
        )


def has_placement(cells, clue):
    return LinePlacements(cells, clue).consistent()


def precise_solve(cells, clue):
    placements = LinePlacements(cells, clue)
    if not placements.consistent():
        return None
    fillable = [False] * len(cells)
    for block, length in enumerate(clue):
        for start in placements.starts(block):
            for index in range(start, start + length):
                fillable[index] = True
    solved = list(cells)
    for index, state in enumerate(cells):
        if state == UNKNOWN:
            emptiable = placements.can_be_empty(index)
            if fillable[index] and not emptiable:
                solved[index] = FILLED
            elif emptiable and not fillable[index]:
                solved[index] = EMPTY
    return solved


def simple_solve(cells, clue):
    placements = LinePlacements(cells, clue)
    if not placements.consistent():
        return None
    solved = list(cells)
    covered = [False] * len(cells)
    for block, length in enumerate(clue):
        lowest, highest = placements.start_range(block)
        for index in range(highest, lowest + length):
            if solved[index] == UNKNOWN:
                solved[index] = FILLED
        for index in range(lowest, highest + length):
            covered[index] = True
    for index, state in enumerate(solved):
        if state == UNKNOWN and not covered[index]:
            solved[index] = EMPTY
    return solved


def solve_line(cells, clue, precise):
    if precise:
        return precise_solve(cells, clue)
    return simple_solve(cells, clue)
