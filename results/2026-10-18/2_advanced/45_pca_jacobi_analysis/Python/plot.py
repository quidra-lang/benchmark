import math


def new_grid(rows, columns):
    return [[" "] * columns for _ in range(rows)]


def framed(grid):
    border = "+" + "-" * len(grid[0]) + "+"
    return [border] + ["|" + "".join(row) + "|" for row in grid] + [border]


def grid_index(fraction, size):
    return min(math.floor(fraction * size), size - 1)


def rounded_position(fraction, size):
    return math.floor(fraction * size + 0.5)


def biplot_cell(x, y, x_limit, y_limit, width, height):
    row = grid_index((y_limit - y) / (2 * y_limit), height)
    col = grid_index((x + x_limit) / (2 * x_limit), width)
    return row, col


def circle_cell(first, second, radius):
    row = radius // 2 + 1 - rounded_position(second, radius / 2)
    col = radius + 1 + rounded_position(first, radius)
    return row, col


def diagnostic_cell(t2, spe, t2_max, spe_max, width, height):
    row = height - 1 - grid_index(spe / spe_max, height)
    col = grid_index(t2 / t2_max, width)
    return row, col


def sign(value):
    return (value > 0) - (value < 0)


def shaft_cells(origin, tip):
    dr = tip[0] - origin[0]
    dc = tip[1] - origin[1]
    steps = max(abs(dc), abs(dr))
    cells = []
    for s in range(1, steps):
        row = origin[0] + sign(dr) * ((2 * s * abs(dr) + steps) // (2 * steps))
        col = origin[1] + sign(dc) * ((2 * s * abs(dc) + steps) // (2 * steps))
        cells.append((row, col))
    return cells


def shaft_character(origin, tip):
    dr = tip[0] - origin[0]
    dc = tip[1] - origin[1]
    if 2 * abs(dr) <= abs(dc):
        return "-"
    if 2 * abs(dc) <= abs(dr):
        return "|"
    if dc * dr < 0:
        return "/"
    return "\\"


def scree_line(length, kaiser, broken, width):
    characters = []
    for position in range(1, width + 1):
        if position == broken:
            characters.append("o")
        elif position == kaiser:
            characters.append(":")
        elif position <= length:
            characters.append("#")
        else:
            characters.append(" ")
    return "|" + "".join(characters) + "|"
