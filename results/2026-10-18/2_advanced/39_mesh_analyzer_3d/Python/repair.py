"""Fan triangulation, exact grid snapping, deduplication and hole filling."""

from measure import cross, subtract


def split_polygons(polygons):
    triangles = []
    for polygon in polygons:
        corners = polygon["vertices"]
        for i in range(1, len(corners) - 1):
            triangles.append({
                "triangle": len(triangles) + 1,
                "polygon": polygon["number"],
                "line": polygon["line"],
                "group": polygon["group"],
                "vertices": (corners[0], corners[i], corners[i + 1]),
            })
    return triangles


def snapped_vertices(vertices, spacing):
    result = [None]
    changed = []
    for i, point in enumerate(vertices[1:], 1):
        rounded = tuple(
            spacing * ((2 * coordinate + spacing) // (2 * spacing))
            for coordinate in point
        )
        result.append(rounded)
        if rounded != point:
            changed.append((i, point, rounded))
    return result, changed


def representatives(points, merge):
    owner = {}
    result = [0]
    for i, point in enumerate(points[1:], 1):
        if not merge:
            result.append(i)
        else:
            owner.setdefault(point, i)
            result.append(owner[point])
    return result


def cleaned_faces(triangles, points, representative, remove_zero, remove_duplicate):
    faces = []
    removed = []
    seen = set()
    for triangle in triangles:
        a, b, c = (representative[v] for v in triangle["vertices"])
        reason = None
        if len({a, b, c}) < 3:
            reason = "repeated"
        elif remove_zero:
            p, q, r = points[a], points[b], points[c]
            if cross(subtract(q, p), subtract(r, p)) == (0, 0, 0):
                reason = "zero_area"
        if reason is None:
            identifier = tuple(sorted((a, b, c)))
            if remove_duplicate and identifier in seen:
                reason = "duplicate"
            else:
                seen.add(identifier)
        if reason is not None:
            removed.append({**triangle, "reason": reason})
        else:
            faces.append({**triangle, "vertices": (a, b, c)})
    return faces, removed


def remap_vertices(original, snapped, representative, faces, keep_unused):
    if keep_unused:
        present = {
            i for i in range(1, len(original))
            if representative[i] == i
        }
    else:
        present = {
            vertex for face in faces for vertex in face["vertices"]
        }
    old_numbers = sorted(present)
    new_numbers = {
        original_number: index
        for index, original_number in enumerate(old_numbers, 1)
    }
    points = [None] + [snapped[number] for number in old_numbers]
    mapped = [
        {**face, "vertices": tuple(new_numbers[v] for v in face["vertices"])}
        for face in faces
    ]
    return points, mapped, new_numbers


def fill_loops(faces, loops, max_length, permitted_components):
    added = []
    for loop in loops:
        loop["filled"] = False
        corners = loop["vertices"]
        length = loop["length"]
        if (loop["kind"] != "coherent" or not 3 <= length <= max_length
                or len(set(corners)) != length
                or loop["component"] not in permitted_components):
            continue
        for i in range(2, length):
            added.append({
                "triangle": None, "polygon": None, "line": None,
                "group": "fill",
                "vertices": (corners[0], corners[i], corners[i - 1]),
            })
        loop["filled"] = True
    return faces + added, added
