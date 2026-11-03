"""Fixed-decimal report formatting and character plots for tidal heights."""

import math
from pathlib import Path

from predict import predict_height


def decimal(value, places):
    result = f"{value:.{places}f}"
    if result.startswith("-") and float(result) == 0.0:
        return result[1:]
    return result


def optional(value, places):
    return "none" if value is None else decimal(value, places)


def write_lines(name, lines):
    target = Path("output") / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines) + "\n", encoding="ascii")


def render_plot(model, extrema, start_hour, width, top, bottom, step):
    rows = (top - bottom) // step + 1
    grid = [[" " for _ in range(width)] for _ in range(rows)]
    zero_row = math.floor((top - 100 * model["mean_level"]) / step + 0.5)
    if 0 <= zero_row < rows:
        for column in range(width):
            grid[zero_row][column] = "-"
    marks = {}
    for item in extrema:
        column = (item["rounded"] - 60 * start_hour + 30) // 60
        if 0 <= column < width:
            marks[column] = "H" if item["kind"] == "high" else "L"
    for column in range(width):
        level = predict_height(model, start_hour + column)
        row = math.floor((top - 100 * level) / step + 0.5)
        if row < 0:
            grid[0][column] = "^"
        elif row >= rows:
            grid[-1][column] = "v"
        else:
            grid[row][column] = marks.get(column, "*")
    labels = [decimal((top - row * step) / 100, 2) for row in range(rows)]
    label_width = max(map(len, labels))
    lines = [
        f"{label:>{label_width}} |{''.join(cells)}|"
        for label, cells in zip(labels, grid)
    ]
    axis = "".join("+" if column % 6 == 0 else "-" for column in range(width))
    lines.append(" " * label_width + " +" + axis + "+")
    return lines
