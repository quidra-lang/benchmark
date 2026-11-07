def decimal(numerator, denominator, places):
    scale = 10 ** places
    rounded = (2 * numerator * scale + denominator) // (2 * denominator)
    whole, fraction = divmod(rounded, scale)
    return f"{whole}.{fraction:0{places}d}"


def grid_lines(grid, letters):
    return ["".join(letters[row * grid.width:(row + 1) * grid.width]) for row in range(grid.height)]


def number_lines(layout):
    grid = layout.grid
    lines = []
    for row in range(grid.height):
        marks = []
        for column in range(grid.width):
            cell = grid.cell(row, column)
            if not grid.is_open(row, column):
                marks.append("##")
            elif cell in layout.numbers:
                marks.append(f"{layout.numbers[cell]:>2}")
            else:
                marks.append(" .")
        lines.append(" ".join(marks))
    return lines


def list_line(slot, clue, entry, score, theme):
    line = f"{slot.number}. {clue} ({slot.length}) {entry} {score}"
    if theme:
        line += " theme"
    return line
