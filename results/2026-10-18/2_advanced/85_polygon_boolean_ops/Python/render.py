"""Exact grid centers and result/operand cell classification."""

from rational import divide
from rings import interior


def grid(polygons, operands, x0, y0, width, height, columns, rows):
    result_rings = [ring for polygon in polygons for ring in polygon]
    counts = dict.fromkeys(("#", "a", "b", "+"), 0)
    lines = []
    for row in range(rows):
        cells = []
        y = y0 + divide((2 * (rows - 1 - row) + 1) * height, 2)
        for column in range(columns):
            x = x0 + divide((2 * column + 1) * width, 2)
            point = x, y
            if interior(result_rings, point):
                character = "#"
            elif operands is not None:
                first = interior(operands[0], point)
                second = interior(operands[1], point)
                character = "+" if first and second else "a" if first else "b" if second else "."
            else:
                character = "."
            cells.append(character)
            if character in counts:
                counts[character] += 1
        lines.append("".join(cells))
    return lines, counts
