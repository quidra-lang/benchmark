"""Directed triangle edges, consistency tests and breadth-first winding repair."""

from collections import deque

from topology import key_edge, triangle_edges


def has_directed(triangle, start, end):
    return (start, end) in triangle_edges(triangle)


def flip(face):
    a, b, c = face["vertices"]
    face["vertices"] = (a, c, b)


def inconsistent_edges(faces, edges):
    result = []
    for (a, b), adjacent in edges.items():
        if len(adjacent) != 2:
            continue
        first = has_directed(faces[adjacent[0] - 1]["vertices"], a, b)
        second = has_directed(faces[adjacent[1] - 1]["vertices"], a, b)
        if first == second:
            result.append((a, b))
    return result


def repair_orientation(faces, edges):
    """BFS examines each edge in the current face's winding order."""
    adjacency = {}
    for edge, indices in edges.items():
        if len(indices) == 2:
            a, b = indices
            adjacency[(a, edge)] = b
            adjacency[(b, edge)] = a
    visited = set()
    for seed in range(1, len(faces) + 1):
        if seed in visited:
            continue
        visited.add(seed)
        queue = deque([seed])
        while queue:
            current = queue.popleft()
            for u, v in triangle_edges(faces[current - 1]["vertices"]):
                edge = key_edge(u, v)
                other = adjacency.get((current, edge))
                if other is None or other in visited:
                    continue
                if has_directed(faces[other - 1]["vertices"], u, v):
                    flip(faces[other - 1])
                visited.add(other)
                queue.append(other)


def orientable_components(faces, mesh):
    """Simulate winding repair without changing the actual final triangles."""
    copied = [{**face} for face in faces]
    repair_orientation(copied, mesh["edges"])
    violations = inconsistent_edges(copied, mesh["edges"])
    return {
        comp["number"]: not any(edge in comp["edges"] for edge in violations)
        for comp in mesh["components"]
    }
