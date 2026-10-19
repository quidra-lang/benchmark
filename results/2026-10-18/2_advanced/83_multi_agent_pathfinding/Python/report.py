"""Path actions, conflict strings, exact cost fractions and ASCII files."""

from math import gcd
from pathlib import Path


DIRECTIONS = {
    (0, 0): ".", (0, -1): "N", (1, 0): "E",
    (0, 1): "S", (-1, 0): "W",
}


def cell_text(cell):
    return f"{cell[0]},{cell[1]}"


def agent_name(number):
    return chr(65 + number)


def action_string(path):
    return "".join(
        DIRECTIONS[(v[0] - u[0], v[1] - u[1])]
        for u, v in zip(path, path[1:])
    )


def conflict_text(conflict):
    time, a, b = (conflict[key] for key in ("time", "a", "b"))
    names = f"{agent_name(a)} {agent_name(b)}"
    if conflict["kind"] == "vertex":
        return f"vertex t {time} {names} at {cell_text(conflict['cell'])}"
    return (f"edge t {time} {names} from {cell_text(conflict['u'])} "
            f"to {cell_text(conflict['v'])}")


def fraction(numerator, denominator):
    divisor = gcd(numerator, denominator)
    return f"{numerator // divisor}/{denominator // divisor}"


def csv_line(values):
    return ",".join(map(str, values))


def save_file(name, lines):
    target = Path("output") / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines) + "\n", encoding="ascii")


def framed_picture(rows):
    return list(rows)


def picture(grid, placements):
    return [
        "".join(placements.get((x, y), character)
                for x, character in enumerate(row))
        for y, row in enumerate(grid["rows"])
    ]
