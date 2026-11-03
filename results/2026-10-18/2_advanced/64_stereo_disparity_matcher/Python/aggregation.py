"""Semi-global matching path recurrence and cumulative directional costs."""


DIRECTIONS = ((1, 0), (-1, 0), (0, 1), (0, -1),
              (1, 1), (-1, -1), (-1, 1), (1, -1))


def path_costs(base, left, width, height, direction, p1, p2, gamma):
    rx, ry = direction
    rows = range(height) if ry >= 0 else range(height - 1, -1, -1)
    columns = range(width) if rx >= 0 else range(width - 1, -1, -1)
    result = [None] * len(base)
    disparities = len(base[0])
    for y in rows:
        for x in columns:
            p = y * width + x
            qx, qy = x - rx, y - ry
            if not (0 <= qx < width and 0 <= qy < height):
                result[p] = list(base[p])
                continue
            q = qy * width + qx
            previous = result[q]
            minimum = min(previous)
            penalty = max(p1, p2 * gamma // (gamma + abs(left[p] - left[q])))
            values = []
            for d in range(disparities):
                best = min(previous[d], minimum + penalty)
                if d > 0:
                    best = min(best, previous[d - 1] + p1)
                if d + 1 < disparities:
                    best = min(best, previous[d + 1] + p1)
                values.append(base[p][d] + best - minimum)
            result[p] = values
    return result


def cumulative_costs(base, left, width, height, paths, p1, p2, gamma):
    total = [[0] * len(base[0]) for _ in base]
    for direction in DIRECTIONS[:paths]:
        costs = path_costs(base, left, width, height, direction, p1, p2, gamma)
        for p, row in enumerate(costs):
            for d, value in enumerate(row):
                total[p][d] += value
        yield total
