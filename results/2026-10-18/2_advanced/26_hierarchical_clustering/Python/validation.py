import math

from distances import sequential_sum


def correlation(xs, ys):
    mean_x = sequential_sum(xs) / len(xs)
    mean_y = sequential_sum(ys) / len(ys)
    sxy = sequential_sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    sxx = sequential_sum((x - mean_x) * (x - mean_x) for x in xs)
    syy = sequential_sum((y - mean_y) * (y - mean_y) for y in ys)
    return sxy / math.sqrt(sxx * syy)


def contingency_table(first, second, rows, columns):
    table = [[0] * columns for _ in range(rows)]
    for a, b in zip(first, second):
        table[a][b] += 1
    return table


def pair_count(r):
    return r * (r - 1) // 2


def adjusted_rand_index(table):
    count = sum(sum(row) for row in table)
    same = sum(pair_count(cell) for row in table for cell in row)
    row_pairs = sum(pair_count(sum(row)) for row in table)
    column_pairs = sum(pair_count(sum(column)) for column in zip(*table))
    total = pair_count(count)
    numerator = 2 * (total * same - row_pairs * column_pairs)
    denominator = total * (row_pairs + column_pairs) - 2 * row_pairs * column_pairs
    if denominator == 0:
        return 1, 1
    divisor = math.gcd(abs(numerator), denominator)
    return numerator // divisor, denominator // divisor


def silhouette_values(partition, groups, delta):
    sizes = [0] * (groups + 1)
    for number in partition:
        sizes[number] += 1
    values = []
    for i, own in enumerate(partition):
        if sizes[own] == 1:
            values.append(0.0)
            continue
        sums = [0.0] * (groups + 1)
        for j, other in enumerate(partition):
            if j != i:
                sums[other] += delta[i][j]
        inner = sums[own] / (sizes[own] - 1)
        outer = min(sums[g] / sizes[g] for g in range(1, groups + 1) if g != own)
        values.append((outer - inner) / max(inner, outer))
    return values
