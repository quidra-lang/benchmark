from math import sqrt

polygons = [[(0, 0), (5, 0), (6, 4), (1, 3)], [(2, 1), (0, 4), (3, 7), (7, 6), (8, 2)], [(0, 0), (8, 0), (8, 6), (5, 6), (4, 3), (3, 6), (0, 6)]]
for index, vertices in enumerate(polygons, 1):
    cross_sum = 0
    perimeter = 0.0
    for i, (x, y) in enumerate(vertices):
        next_x, next_y = vertices[(i + 1) % len(vertices)]
        cross_sum += x * next_y - next_x * y
        dx, dy = x - next_x, y - next_y
        perimeter += sqrt(dx * dx + dy * dy)
    print(f"polygon {index}: area={abs(cross_sum) / 2:.1f} perimeter={perimeter:.3f}")
