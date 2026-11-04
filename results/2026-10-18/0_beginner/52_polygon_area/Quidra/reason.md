# Task B selection: 52_polygon_area / Quidra

## Common answer requirements

Find polygon 2 from its source position and trace the closing edge contribution, absolute area, and perimeter accumulation order.

## Source evidence

The second polygon begins at (2, 1) and ends at (8, 2). The wrapped next-vertex index uses (i + 1) modulo the vertex count, so its closing edge contributes 8 × 1 − 2 × 2 = 4 to the shoelace sum and sqrt((8 − 2)² + (2 − 1)²) = sqrt(37) to the perimeter. The edge loop adds distances in source vertex order. The area expression takes the absolute cross sum and halves it.

## Minimization

The first polygon establishes the second polygon’s ordinal position. Neither the list terminator nor later polygons supply evidence. The area appears in the Python output expression and in separate Quidra statements. Selected complete lines of `main.qui`: 1, 3, 4, 5, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19.
