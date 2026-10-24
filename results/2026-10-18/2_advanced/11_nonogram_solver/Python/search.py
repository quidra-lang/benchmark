from line_solver import EMPTY, FILLED, UNKNOWN
from propagation import determined_count, propagate


SOLUTION_LIMIT = 2
GUESS_VALUES = (FILLED, EMPTY)


def guess_cell(grid):
    row_unknowns = [row.count(UNKNOWN) for row in grid]
    column_unknowns = [
        sum(1 for row in grid if row[column] == UNKNOWN) for column in range(len(grid[0]))
    ]
    best = None
    best_score = 0
    for row, states in enumerate(grid):
        for column, state in enumerate(states):
            if state != UNKNOWN:
                continue
            score = row_unknowns[row] + column_unknowns[column]
            if best is None or score < best_score:
                best = row, column
                best_score = score
    return best


class Guess:
    def __init__(self, number, depth, row, column, value, solves, known, result):
        self.number = number
        self.depth = depth
        self.row = row
        self.column = column
        self.value = value
        self.solves = solves
        self.known = known
        self.result = result


class Search:
    def __init__(self, row_clues, column_clues):
        self.row_clues = row_clues
        self.column_clues = column_clues
        self.guesses = []
        self.solutions = []
        self.backtracks = 0

    def guess_count(self):
        return len(self.guesses)

    def max_depth(self):
        return max(guess.depth for guess in self.guesses)

    def line_solves(self):
        return sum(guess.solves for guess in self.guesses)

    def run(self, grid, depth):
        height = len(self.row_clues)
        width = len(self.column_clues)
        row, column = guess_cell(grid)
        for value in GUESS_VALUES:
            child = [list(states) for states in grid]
            child[row][column] = value
            row_marks = [False] * height
            column_marks = [False] * width
            row_marks[row] = True
            column_marks[column] = True
            propagation = propagate(
                child, self.row_clues, self.column_clues, True, row_marks, column_marks
            )
            known = determined_count(child)
            number = len(self.guesses) + 1
            if propagation.conflict is not None:
                result = "contradiction at=" + propagation.conflict.label()
                self.backtracks += 1
            elif known == height * width:
                self.solutions.append(child)
                result = f"solution{len(self.solutions)}"
            else:
                result = "open"
            self.guesses.append(
                Guess(number, depth, row, column, value, propagation.line_solves(), known, result)
            )
            if result == "open":
                if self.run(child, depth + 1):
                    return True
            elif len(self.solutions) == SOLUTION_LIMIT:
                return True
        return False
