vertices = "ABCDEFGH"
edges = [
    ("A", "B", 7), ("C", "A", 4), ("B", "C", 9), ("B", "D", 14), ("D", "C", 6),
    ("C", "E", 3), ("E", "D", 5), ("F", "D", 11), ("E", "G", 16), ("G", "F", 8),
    ("H", "F", 12), ("G", "H", 2), ("H", "E", 10),
]
parent = {vertex: vertex for vertex in vertices}


def find(vertex):
    while parent[vertex] != vertex:
        parent[vertex] = parent[parent[vertex]]
        vertex = parent[vertex]
    return vertex


accepted = skipped = total = 0
for a, b, weight in sorted(edges, key=lambda edge: edge[2]):
    root_a, root_b = find(a), find(b)
    if root_a == root_b:
        skipped += 1
        continue
    parent[root_b] = root_a
    accepted += 1
    total += weight
    first, second = sorted([a, b])
    print(f"{first}-{second} {weight}")
    if accepted == len(vertices) - 1:
        break
print(f"total weight: {total}")
print(f"skipped: {skipped}")
