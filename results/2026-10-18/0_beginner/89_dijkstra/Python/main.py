names = "ABCDEFG"
edges = [
    (0, 1, 7),
    (0, 2, 3),
    (0, 3, 9),
    (1, 2, 2),
    (2, 4, 6),
    (1, 3, 3),
    (3, 4, 4),
    (3, 5, 5),
    (4, 5, 3),
    (4, 6, 8),
    (5, 6, 4),
]
graph = [[] for _ in names]
for a, b, weight in edges:
    graph[a].append((b, weight))
    graph[b].append((a, weight))
distances = [float("inf")] * len(names)
distances[0] = 0
done = set()
previous = [-1] * len(names)
for _ in names:
    vertex = min(
        (v for v in range(len(names)) if v not in done), key=lambda v: (distances[v], v)
    )
    done.add(vertex)
    for neighbor, weight in graph[vertex]:
        candidate = distances[vertex] + weight
        if candidate < distances[neighbor]:
            distances[neighbor] = candidate
            previous[neighbor] = vertex
for target, name in enumerate(names):
    path = []
    vertex = target
    while vertex >= 0:
        path.append(names[vertex])
        vertex = previous[vertex]
    print(f"{name}: distance={distances[target]} path={'-'.join(reversed(path))}")
