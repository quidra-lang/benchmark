import math


SQUARED_LINKAGES = ("centroid", "median", "ward")


class Merge:
    def __init__(self, a, b, height, size):
        self.a = a
        self.b = b
        self.height = height
        self.size = size


class Edge:
    def __init__(self, parent, child, weight):
        self.parent = parent
        self.child = child
        self.weight = weight


def lance_williams(method, size_a, size_b, size_k):
    if method == "single":
        return 0.5, 0.5, 0.0, -0.5
    if method == "complete":
        return 0.5, 0.5, 0.0, 0.5
    if method == "average":
        return size_a / (size_a + size_b), size_b / (size_a + size_b), 0.0, 0.0
    if method == "weighted":
        return 0.5, 0.5, 0.0, 0.0
    if method == "centroid":
        merged = size_a + size_b
        return size_a / merged, size_b / merged, -(size_a * size_b) / (merged * merged), 0.0
    if method == "median":
        return 0.5, 0.5, -0.25, 0.0
    total = size_a + size_b + size_k
    return (size_a + size_k) / total, (size_b + size_k) / total, -size_k / total, 0.0


def closest_pair(values, active):
    best_a = active[0]
    best_b = active[1]
    best = values[best_a][best_b]
    for position, a in enumerate(active):
        row = values[a]
        for b in active[position + 1:]:
            if row[b] < best:
                best = row[b]
                best_a = a
                best_b = b
    return best_a, best_b


def agglomerate(delta, method):
    count = len(delta)
    squared = method in SQUARED_LINKAGES
    capacity = 2 * count - 1
    values = [[0.0] * capacity for _ in range(capacity)]
    for u in range(count):
        for w in range(count):
            values[u][w] = delta[u][w] * delta[u][w] if squared else delta[u][w]
    sizes = [1] * count + [0] * (count - 1)
    active = list(range(count))
    merges = []
    for step in range(count - 1):
        a, b = closest_pair(values, active)
        node = count + step
        sizes[node] = sizes[a] + sizes[b]
        height = math.sqrt(values[a][b]) if squared else values[a][b]
        merges.append(Merge(a, b, height, sizes[node]))
        for k in active:
            if k == a or k == b:
                continue
            alpha_a, alpha_b, beta, gamma = lance_williams(method, sizes[a], sizes[b], sizes[k])
            value = (
                alpha_a * values[a][k] + alpha_b * values[b][k] + beta * values[a][b]
                + gamma * abs(values[a][k] - values[b][k])
            )
            values[node][k] = value
            values[k][node] = value
        active.remove(a)
        active.remove(b)
        active.append(node)
    return merges


def minimum_spanning_tree(delta):
    count = len(delta)
    in_tree = [False] * count
    in_tree[0] = True
    key = list(delta[0])
    parent = [0] * count
    edges = []
    for _ in range(count - 1):
        chosen = -1
        for u in range(count):
            if not in_tree[u] and (chosen < 0 or key[u] < key[chosen]):
                chosen = u
        in_tree[chosen] = True
        edges.append(Edge(parent[chosen], chosen, key[chosen]))
        for u in range(count):
            if not in_tree[u] and delta[chosen][u] < key[u]:
                key[u] = delta[chosen][u]
                parent[u] = chosen
    return edges
