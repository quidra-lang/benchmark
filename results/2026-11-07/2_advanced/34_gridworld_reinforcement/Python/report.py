from environment import ACTION_LETTERS

POLICY_SYMBOLS = "^>v<"


def fixed_text(value):
    sign = "-" if value < 0 else ""
    whole, fraction = divmod(abs(value), 10000)
    return f"{sign}{whole}.{fraction:04d}"


def average_text(total, count):
    return fixed_text(10000 * total // count)


def cell_text(world, cell):
    row, col = divmod(cell, world.cols)
    return f"{row},{col}"


def cells_text(world, cells):
    return " ".join(cell_text(world, cell) for cell in cells)


def grid_lines(world, fields, separator):
    lines = []
    for row in range(world.rows):
        parts = []
        for cell in range(row * world.cols, (row + 1) * world.cols):
            state = world.state_index[cell]
            parts.append(world.kinds[cell] if state is None else fields[state])
        lines.append(separator.join(parts))
    return lines


def value_grid(world, values):
    return grid_lines(world, [fixed_text(value) for value in values], " ")


def policy_grid(world, policy):
    return grid_lines(world, [POLICY_SYMBOLS[action] for action in policy], "")


def symbol_grid(world, symbols):
    return grid_lines(world, symbols, "")


def q_table_rows(world, name, q_values, visits):
    rows = []
    for state, cell in enumerate(world.states):
        row, col = divmod(cell, world.cols)
        for action, letter in enumerate(ACTION_LETTERS):
            count = "-" if visits is None else str(visits[state][action])
            value = fixed_text(q_values[state][action])
            rows.append(f"{name},{row},{col},{letter},{value},{count}")
    return rows


def join_parts(parts):
    lines = []
    for part in parts:
        if lines:
            lines.append("")
        lines.extend(part)
    return lines


def write_lines(path, lines):
    with open(path, "w", newline="\n") as file:
        file.write("\n".join(lines) + "\n")
