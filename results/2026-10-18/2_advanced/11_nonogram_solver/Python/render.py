from clues import spaced
from line_solver import EMPTY, FILLED, UNKNOWN


SYMBOLS = {UNKNOWN: "?", FILLED: "#", EMPTY: "."}
STATES = {"?": UNKNOWN, "#": FILLED, ".": EMPTY}
GRID_SEPARATOR = " | "


def state_char(state):
    return SYMBOLS[state]


def char_state(character):
    return STATES[character]


def state_string(cells):
    return "".join(state_char(state) for state in cells)


def grid_display(names, grids):
    lines = ["grid " + " ".join(names)]
    for row in range(len(grids[0])):
        lines.append(GRID_SEPARATOR.join(state_string(grid[row]) for grid in grids))
    return lines


def answer_sheet(row_clues, column_clues, grid):
    tokens = [spaced(clue).split(" ") for clue in column_clues]
    width = max(len(token) for column in tokens for token in column) + 1
    depth = max(len(column) for column in tokens)
    margin = max(len(spaced(clue)) for clue in row_clues)
    lines = []
    for line in range(depth):
        parts = [" " * margin]
        for column in tokens:
            skipped = depth - len(column)
            if line >= skipped:
                parts.append(column[line - skipped].rjust(width))
            else:
                parts.append(" " * width)
        lines.append("".join(parts).rstrip(" "))
    for clue, states in zip(row_clues, grid):
        cells = "".join(" " * (width - 1) + state_char(state) for state in states)
        lines.append(spaced(clue).rjust(margin) + cells)
    return lines
