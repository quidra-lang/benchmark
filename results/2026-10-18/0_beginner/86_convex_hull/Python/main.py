points = [
    (3, 2),
    (-6, 1),
    (8, 4),
    (0, 0),
    (-3, 7),
    (4, -3),
    (1, -5),
    (-2, 1),
    (5, 6),
    (-6, -2),
    (2, -2),
    (7, -1),
    (-3, 4),
    (2, 8),
    (-6, 3),
]


def cross(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def chain(ordered):
    result = []
    for point in ordered:
        while len(result) >= 2 and cross(result[-2], result[-1], point) <= 0:
            result.pop()
        result.append(point)
    return result


ordered = sorted(points)
hull = chain(ordered)[:-1] + chain(reversed(ordered))[:-1]
area_twice = sum(
    x * next_y - next_x * y
    for (x, y), (next_x, next_y) in zip(hull, hull[1:] + hull[:1])
)
print(f"hull: {len(hull)} points")
for x, y in hull:
    print(f"({x}, {y})")
print(f"area: {area_twice / 2:.1f}")
