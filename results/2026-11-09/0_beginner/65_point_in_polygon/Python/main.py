vertices = [(1, 1), (11, 2), (13, 9), (9, 7), (7, 12), (5, 6), (2, 10), (3, 5)]
points = [(4, 8), (6, 4), (10, 8), (7, 11), (14, 3), (12, 8)]
for px, py in points:
    crossings = 0
    for i, (x1, y1) in enumerate(vertices):
        x2, y2 = vertices[(i + 1) % len(vertices)]
        if (y1 > py) != (y2 > py):
            intersection = x1 + (x2 - x1) * (py - y1) / (y2 - y1)
            if intersection > px:
                crossings += 1
    result = "inside" if crossings % 2 else "outside"
    print(f"({px}, {py}): {result}")
