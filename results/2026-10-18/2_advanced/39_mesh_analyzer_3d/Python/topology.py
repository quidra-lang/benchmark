"""Mesh edges, components, non-manifold vertex fans and boundary loops."""

from collections import defaultdict, deque


def triangle_edges(vertices):
    a, b, c = vertices
    return ((a, b), (b, c), (c, a))


def key_edge(a, b):
    return (min(a, b), max(a, b))


def edge_table(faces):
    result = defaultdict(list)
    for i, face in enumerate(faces, 1):
        for u, v in triangle_edges(face["vertices"]):
            result[key_edge(u, v)].append(i)
    return dict(sorted(result.items()))


def connected_components(faces, edges):
    neighbors = {i: set() for i in range(1, len(faces) + 1)}
    for adjacent in edges.values():
        for face in adjacent:
            neighbors[face].update(other for other in adjacent if other != face)
    unseen = set(neighbors)
    components = []
    while unseen:
        start = min(unseen)
        queue = deque([start])
        unseen.remove(start)
        component = []
        while queue:
            face = queue.popleft()
            component.append(face)
            for neighbor in sorted(neighbors[face]):
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    queue.append(neighbor)
        components.append(sorted(component))
    return components


def vertex_fans(vertex, faces, edges):
    containing = [
        i for i, face in enumerate(faces, 1) if vertex in face["vertices"]
    ]
    others = set(containing)
    neighbors = defaultdict(set)
    for (u, v), participating in edges.items():
        if vertex not in (u, v):
            continue
        for first in participating:
            neighbors[first].update(
                second for second in participating if second != first
            )
    fans = []
    while others:
        seed = min(others)
        others.remove(seed)
        queue = deque([seed])
        part = []
        while queue:
            face = queue.popleft()
            part.append(face)
            for adjacent in sorted(neighbors[face]):
                if adjacent in others:
                    others.remove(adjacent)
                    queue.append(adjacent)
        fans.append(sorted(part))
    return fans


def analyze_mesh(faces):
    """Return face components and edge/vertex information for the current mesh."""
    edges = edge_table(faces)
    face_components = connected_components(faces, edges)
    face_to_component = {}
    components = []
    for number, ids in enumerate(face_components, 1):
        for face_id in ids:
            face_to_component[face_id] = number
        vertices = sorted({
            v for face_id in ids for v in faces[face_id - 1]["vertices"]
        })
        component_edges = [
            edge for edge, adjacent in edges.items()
            if any(f in ids for f in adjacent)
        ]
        boundary = [edge for edge in component_edges if len(edges[edge]) == 1]
        nonmanifold = [edge for edge in component_edges if len(edges[edge]) >= 3]
        components.append({
            "number": number, "faces": ids, "vertices": vertices,
            "edges": component_edges,
            "boundary": boundary, "nonmanifold": nonmanifold,
        })
    used_vertices = sorted({
        v for face in faces for v in face["vertices"]
    })
    fans = {v: vertex_fans(v, faces, edges) for v in used_vertices}
    nonmanifold_vertices = sorted(v for v in fans if len(fans[v]) >= 2)
    for component in components:
        number = component["number"]
        component["nonmanifold_vertices"] = [
            v for v in component["vertices"]
            if sum(
                any(face_to_component[f] == number for f in fan)
                for fan in fans[v]
            ) >= 2
        ]
    return {
        "edges": edges, "components": components,
        "face_components": face_to_component,
        "fans": fans, "nonmanifold_vertices": nonmanifold_vertices,
    }


def boundary_loops(faces, mesh, contains_directed):
    """Trace each boundary edge once, in component and edge order."""
    loops = []
    edges = mesh["edges"]
    for component in mesh["components"]:
        component_number = component["number"]
        unused = set(component["boundary"])
        for first in sorted(component["boundary"]):
            if first not in unused:
                continue
            unused.remove(first)
            a, b = first
            sequence = [a, b]
            current = b
            while current != a:
                choices = [
                    (v if u == current else u, (u, v))
                    for u, v in unused if current in (u, v)
                ]
                if not choices:
                    break
                other, chosen = min(choices)
                unused.remove(chosen)
                sequence.append(other)
                current = other
            closed = sequence[-1] == a
            if not closed:
                kind = "open"
                length = len(sequence) - 1
            else:
                sequence.pop()
                length = len(sequence)
                directed = []
                for i in range(length):
                    u = sequence[i]
                    v = sequence[(i + 1) % length]
                    edge = key_edge(u, v)
                    face = faces[edges[edge][0] - 1]
                    directed.append(contains_directed(face["vertices"], u, v))
                if all(directed):
                    kind = "coherent"
                elif not any(directed):
                    kind = "coherent"
                    sequence = [sequence[0]] + list(reversed(sequence[1:]))
                else:
                    kind = "mixed"
            loops.append({
                "number": len(loops) + 1, "component": component_number,
                "vertices": sequence, "length": length,
                "kind": kind, "filled": False,
            })
    return loops
