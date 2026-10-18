from decimal import Decimal, ROUND_HALF_UP
from math import sqrt

points = [(12, -7), (-33, 25), (41, 18), (-8, -44), (27, 39), (-46, -12), (5, 14), (36, -29), (-19, 47), (-2, 3)]
closest = farthest = None
for i in range(len(points)):
    for j in range(i + 1, len(points)):
        dx, dy = points[i][0] - points[j][0], points[i][1] - points[j][1]
        squared = dx * dx + dy * dy
        pair = (squared, i, j)
        if closest is None or squared < closest[0]:
            closest = pair
        if farthest is None or squared > farthest[0]:
            farthest = pair
for label, (squared, i, j) in [("closest", closest), ("farthest", farthest)]:
    distance = Decimal.from_float(sqrt(squared)).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)
    print(f"{label}: P{i} P{j} {distance}")
