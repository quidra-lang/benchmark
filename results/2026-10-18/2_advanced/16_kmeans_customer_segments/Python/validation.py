from math import sqrt

from kmeans import mean_point, squared_distance


def distance_table(points):
    count = len(points)
    table = [[0.0] * count for _ in range(count)]
    for i in range(count):
        for j in range(i + 1, count):
            distance = sqrt(squared_distance(points[i], points[j]))
            table[i][j] = distance
            table[j][i] = distance
    return table


def silhouettes(table, labels, sizes):
    k = len(sizes)
    values = []
    for i, row in enumerate(table):
        own = labels[i]
        if sizes[own] == 1:
            values.append(0.0)
            continue
        totals = [0.0] * k
        for j, distance in enumerate(row):
            if j != i:
                totals[labels[j]] += distance
        inner = totals[own] / (sizes[own] - 1)
        outer = None
        for segment in range(k):
            if segment != own:
                value = totals[segment] / sizes[segment]
                if outer is None or value < outer:
                    outer = value
        largest = max(inner, outer)
        values.append(0.0 if largest == 0 else (outer - inner) / largest)
    return values


def calinski_harabasz(points, centers, sizes, within):
    overall = mean_point(points)
    between = 0.0
    for center, size in zip(centers, sizes):
        between += size * squared_distance(center, overall)
    k = len(centers)
    return (between / (k - 1)) / (within / (len(points) - k))


def davies_bouldin(points, labels, centers, sizes):
    k = len(centers)
    spreads = [0.0] * k
    for point, label in zip(points, labels):
        spreads[label] += sqrt(squared_distance(point, centers[label]))
    spreads = [spread / size for spread, size in zip(spreads, sizes)]
    total = 0.0
    for a in range(k):
        worst = None
        for e in range(k):
            if e != a:
                value = (spreads[a] + spreads[e]) / sqrt(squared_distance(centers[a], centers[e]))
                if worst is None or value > worst:
                    worst = value
        total += worst
    return total / k


def elbow(k, k_min, k_max, within, within_min, within_max):
    x = (k - k_min) / (k_max - k_min)
    y = (within - within_max) / (within_min - within_max)
    return ((1 - x) - y) / sqrt(2)


def hartigan(within, within_next, count, k):
    return (within / within_next - 1) * (count - k - 1)


def pair_count(size):
    return size * (size - 1) // 2


def adjusted_rand_index(first, second):
    joint = {}
    first_sizes = {}
    second_sizes = {}
    for a, b in zip(first, second):
        joint[(a, b)] = joint.get((a, b), 0) + 1
        first_sizes[a] = first_sizes.get(a, 0) + 1
        second_sizes[b] = second_sizes.get(b, 0) + 1
    total = pair_count(len(first))
    shared = sum(pair_count(size) for size in joint.values())
    first_pairs = sum(pair_count(size) for size in first_sizes.values())
    second_pairs = sum(pair_count(size) for size in second_sizes.values())
    numerator = 2 * (total * shared - first_pairs * second_pairs)
    denominator = total * (first_pairs + second_pairs) - 2 * first_pairs * second_pairs
    if denominator == 0:
        return 1.0
    return numerator / denominator
