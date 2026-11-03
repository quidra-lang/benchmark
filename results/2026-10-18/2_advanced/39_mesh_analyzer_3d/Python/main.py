"""Analyze, repair and report an integer-coordinate triangle mesh.

The input is input/model.obj and input/params.txt. All four outputs
are written under output/; no standard output is produced.
"""

from collections import Counter, defaultdict, deque
from fractions import Fraction
from pathlib import Path

from measure import (
    area, bbox, centroid, cross, determinant, dot, edge_length_squared,
    format_fraction, format_real, normal, subtract, triangle_angle,
    volume6, winding_number,
)
from obj_io import read_obj, write_repaired_obj
from orientation import (
    flip, has_directed, inconsistent_edges,
    orientable_components, repair_orientation,
)
from repair import (
    cleaned_faces, fill_loops, remap_vertices, representatives,
    snapped_vertices, split_polygons,
)
from topology import (
    analyze_mesh, boundary_loops, key_edge, triangle_edges,
)


REPORT_SECTIONS = (
    "summary", "warnings", "cleanup", "components", "groups",
    "contacts", "edges", "valence", "queries",
)


def read_parameters(path="input/params.txt"):
    """Read switches, ordered report sections and six kinds of queries."""
    parameters = {
        "snap": 1,
        "merge": True,
        "degenerate": True,
        "duplicates": True,
        "orient": True,
        "outward": True,
        "fill_holes": 0,
        "keep_unused": True,
        "sections": ("summary", "components"),
        "queries": [],
    }
    for text in Path(path).read_text(encoding="ascii").splitlines():
        if not text or text.startswith("#"):
            continue
        words = text.split(" ")
        key, arguments = words[0], words[1:]
        if key == "query":
            parameters["queries"].append((arguments[0],
                                          tuple(map(int, arguments[1:]))))
        elif key == "sections":
            parameters["sections"] = tuple(arguments)
        elif key in ("snap", "fill_holes"):
            parameters[key] = int(arguments[0])
        else:
            parameters[key] = arguments[0] == "on"
    return parameters


def polygon_is_nonplanar(polygon, snapped):
    """Use the unmerged snapped vertex coordinates in the exact fan-normal test."""
    corners = polygon["vertices"]
    first = snapped[corners[0]]
    normal_sum = (0, 0, 0)
    for i in range(1, len(corners) - 1):
        first_edge = subtract(snapped[corners[i]], first)
        second_edge = subtract(snapped[corners[i + 1]], first)
        triangle_normal = cross(first_edge, second_edge)
        normal_sum = tuple(
            normal_sum[axis] + triangle_normal[axis] for axis in range(3)
        )
    return any(
        dot(subtract(snapped[v], first), normal_sum) != 0 for v in corners
    )


def list_groups(polygons, final_faces):
    """Maintain groups in first-polygon order, with filling placed last."""
    seen = set()
    order = []
    for polygon in polygons:
        if polygon["group"] not in seen:
            seen.add(polygon["group"])
            order.append(polygon["group"])
    if any(face["group"] == "fill" for face in final_faces):
        order.append("fill")
    return order


def face_records_by_group(faces):
    groups = defaultdict(list)
    for index, face in enumerate(faces, 1):
        groups[face["group"]].append(index)
    return groups


def build_component_descriptors(faces, points, mesh, loop_counts,
                                orientability, inside):
    """Compute exact topology and final geometry of every component."""
    descriptors = []
    edges = mesh["edges"]
    for comp in mesh["components"]:
        number = comp["number"]
        face_ids = comp["faces"]
        vertices = comp["vertices"]
        component_edges = comp["edges"]
        closed = not comp["boundary"]
        manifold = not comp["nonmanifold"] and not comp["nonmanifold_vertices"]
        inconsistent = set(inconsistent_edges(faces, edges))
        consistent = not any(edge in inconsistent for edge in component_edges)
        solid = closed and manifold and consistent
        orientable = orientability[number]
        loop_count = loop_counts.get(number, 0)
        chi = len(vertices) - len(component_edges) + len(face_ids)
        genus = ((2 - chi - loop_count) // 2 if manifold and orientable else None)
        crosscaps = (2 - chi - loop_count if manifold and not orientable else None)
        six_volume = volume6(face_ids, faces, points)
        center = (centroid(face_ids, faces, points, six_volume)
                  if solid and six_volume != 0 else None)
        total_normal = [0, 0, 0]
        for face_index in face_ids:
            n = normal(faces[face_index - 1], points)
            for axis in range(3):
                total_normal[axis] += n[axis]
        degree = Counter()
        for u, v in component_edges:
            degree[u] += 1
            degree[v] += 1
        squared_lengths = [
            edge_length_squared(edge, points) for edge in component_edges
        ]
        angles = Counter(
            triangle_angle(faces[i - 1], points) for i in face_ids
        )
        descriptors.append({
            **comp,
            "closed": closed, "manifold": manifold,
            "consistent": consistent, "orientable": orientable,
            "solid": solid, "euler": chi,
            "genus": genus, "crosscaps": crosscaps,
            "loops": loop_count, "volume6": six_volume,
            "centroid": center, "area": area(
                [faces[i - 1] for i in face_ids], points
            ),
            "normal_sum": tuple(total_normal),
            "bbox": bbox(vertices, points),
            "inside": inside.get(number, []) if solid else [],
            "angle_counts": angles,
            "edge_min": min(squared_lengths),
            "edge_max": max(squared_lengths),
            "valence_min": min(degree.values()),
            "valence_max": max(degree.values()),
        })
    return descriptors


def edge_shape(edge, faces, points, adjacent):
    """Classify a manifold edge by face winding and exact signed normal."""
    if len(adjacent) != 2:
        return "-"
    a, b = edge
    first = faces[adjacent[0] - 1]
    second = faces[adjacent[1] - 1]
    if has_directed(first["vertices"], a, b) == has_directed(
            second["vertices"], a, b):
        return "inconsistent"
    third = next(v for v in second["vertices"] if v != a and v != b)
    origin = points[first["vertices"][0]]
    signed = dot(subtract(points[third], origin), normal(first, points))
    return "convex" if signed < 0 else "concave" if signed > 0 else "flat"


def shape_counts(component, mesh, faces, points):
    counter = Counter()
    for edge in component["edges"]:
        counter[edge_shape(edge, faces, points, mesh["edges"][edge])] += 1
    return counter


def all_edge_statistics(faces, points, mesh):
    edges = mesh["edges"]
    counts = Counter()
    shapes = Counter()
    lengths = []
    for edge, adjacent in edges.items():
        category = ("boundary" if len(adjacent) == 1
                    else "manifold" if len(adjacent) == 2 else "nonmanifold")
        counts[category] += 1
        shape = edge_shape(edge, faces, points, adjacent)
        shapes[shape] += 1
        lengths.append((edge_length_squared(edge, points), edge))
    shortest = min(lengths)
    longest = min(lengths, key=lambda record: (-record[0], record[1]))
    return {
        "counts": counts, "shapes": shapes,
        "shortest": shortest, "longest": longest,
        "max_faces": max(len(group) for group in edges.values()),
    }


def find_nesting(components, mesh, faces, points):
    """Determine which solid shells lie within other shells by winding."""
    solids = [comp for comp in components if comp["solid"]]
    inside = {}
    for comp in solids:
        contained_by = []
        for other in solids:
            if other is comp:
                continue
            other_vertices = set(other["vertices"])
            test_vertex = next(
                (v for v in comp["vertices"] if v not in other_vertices), None
            )
            if test_vertex is not None:
                winding = winding_number(
                    other["faces"], faces, points, points[test_vertex]
                )
                if winding != 0:
                    contained_by.append(other["number"])
        inside[comp["number"]] = sorted(contained_by)
    return inside


def preliminary_solids(faces, mesh):
    """Topology-only solid tests, before outward orientation is applied."""
    inconsistent = set(inconsistent_edges(faces, mesh["edges"]))
    result = []
    for comp in mesh["components"]:
        solid = (
            not comp["boundary"]
            and not comp["nonmanifold"]
            and not comp["nonmanifold_vertices"]
            and not any(edge in inconsistent for edge in comp["edges"])
        )
        result.append({**comp, "solid": solid})
    return result


def apply_outward_orientation(faces, points, solids, nesting, enabled):
    flipped_components = 0
    if not enabled:
        return flipped_components
    for comp in solids:
        if not comp["solid"]:
            continue
        number = comp["number"]
        signed = volume6(comp["faces"], faces, points)
        depth = len(nesting.get(number, []))
        wrong_orientation = (
            signed != 0
            and ((depth % 2 == 0 and signed < 0)
                 or (depth % 2 == 1 and signed > 0))
        )
        if wrong_orientation:
            for index in comp["faces"]:
                flip(faces[index - 1])
            flipped_components += 1
    return flipped_components


def analyze_source(source, settings):
    """All cleanup, topology repair, nesting and measurements in order."""
    snapped, snapped_list = snapped_vertices(
        source["vertices"], settings["snap"]
    )
    representative = representatives(snapped, settings["merge"])
    triangles = split_polygons(source["polygons"])
    kept, removed = cleaned_faces(
        triangles, snapped, representative,
        settings["degenerate"], settings["duplicates"]
    )
    points, cleaned, renumber = remap_vertices(
        source["vertices"], snapped, representative, kept,
        settings["keep_unused"],
    )
    initial_orientations = [face["vertices"] for face in cleaned]
    mesh_before = analyze_mesh(cleaned)
    initial_inconsistent = inconsistent_edges(cleaned, mesh_before["edges"])
    if settings["orient"]:
        repair_orientation(cleaned, mesh_before["edges"])
    consistent_after = inconsistent_edges(cleaned, mesh_before["edges"])
    loops_before = boundary_loops(
        cleaned, mesh_before, has_directed
    )

    permitted = set()
    for component in mesh_before["components"]:
        if (not component["nonmanifold"]
                and not any(edge in consistent_after
                            for edge in component["edges"])):
            permitted.add(component["number"])
    faces, added = fill_loops(
        cleaned, loops_before, settings["fill_holes"], permitted
    )
    final_mesh = analyze_mesh(faces)
    preliminary = preliminary_solids(faces, final_mesh)
    nesting = find_nesting(preliminary, final_mesh, faces, points)
    outward_components = apply_outward_orientation(
        faces, points, preliminary, nesting, settings["outward"]
    )
    flipped_faces = sum(
        face["vertices"] != original
        for face, original in zip(faces[:len(cleaned)], initial_orientations)
    )
    orientable = orientable_components(faces, final_mesh)
    loops_final = boundary_loops(faces, final_mesh, has_directed)
    loop_counts = Counter(loop["component"] for loop in loops_final)
    components = build_component_descriptors(
        faces, points, final_mesh, loop_counts, orientable, nesting
    )
    nonplanar = {
        polygon["number"] for polygon in source["polygons"]
        if polygon_is_nonplanar(polygon, snapped)
    }
    original_to_reps = defaultdict(list)
    for number in range(1, len(source["vertices"])):
        original_to_reps[representative[number]].append(number)
    group_order = list_groups(source["polygons"], faces)
    group_faces = face_records_by_group(faces)
    return {
        "source": source, "settings": settings,
        "original_points": source["vertices"],
        "snapped_points": snapped, "snapped_list": snapped_list,
        "representative": representative, "original_to_reps": original_to_reps,
        "triangles": triangles, "removed": removed,
        "points": points, "faces": faces, "renumber": renumber,
        "initial_faces": len(cleaned), "mesh_before": mesh_before,
        "initial_inconsistent": initial_inconsistent,
        "inconsistent_after": consistent_after,
        "loops_before": loops_before, "added": added,
        "mesh": final_mesh, "loops_final": loops_final,
        "components": components, "nesting": nesting,
        "outward_components": outward_components,
        "flipped_faces": flipped_faces, "nonplanar": nonplanar,
        "group_order": group_order, "group_faces": group_faces,
    }


def yes(value):
    return "yes" if value else "no"


def listing(items):
    return " ".join(map(str, items)) if items else "-"


def section_summary(data):
    """The exact ordered scalar summary of OBJ parsing and repair."""
    source = data["source"]
    groups = Counter(len(p["vertices"]) for p in source["polygons"])
    removals = Counter(item["reason"] for item in data["removed"])
    total_area = area(data["faces"], data["points"])
    volume_six = sum(
        comp["volume6"] for comp in data["components"] if comp["solid"]
    )
    lines = [
        "[summary]",
        f"lines {source['lines']}",
        f"vertices {len(source['vertices']) - 1}",
        f"polygons {len(source['polygons'])}",
        f"errors {len(source['errors'])}",
        f"ignored {source['ignored']}",
        f"nonplanar_polygons {len(data['nonplanar'])}",
    ]
    lines.extend(
        f"polygon_size {size} {groups[size]}" for size in sorted(groups)
    )
    lines.extend([
        f"triangles {len(data['triangles'])}",
        f"snapped {len(data['snapped_list'])}",
        f"merged {sum(i != data['representative'][i] for i in
                      range(1, len(source['vertices'])))}",
        f"removed_repeated {removals['repeated']}",
        f"removed_zero_area {removals['zero_area']}",
        f"removed_duplicate {removals['duplicate']}",
        f"faces {data['initial_faces']}",
        f"inconsistent_before {len(data['initial_inconsistent'])}",
        f"flipped_faces {data['flipped_faces']}",
        f"outward_components {data['outward_components']}",
        f"boundary_loops {len(data['loops_before'])}",
        f"holes_filled {sum(loop['filled'] for loop in data['loops_before'])}",
        f"fill_faces {len(data['added'])}",
        f"final_vertices {len(data['points']) - 1}",
        f"final_faces {len(data['faces'])}",
        f"components {len(data['components'])}",
        f"solids {sum(comp['solid'] for comp in data['components'])}",
        f"total_area {format_real(total_area)}",
        f"total_volume {format_fraction(Fraction(volume_six, 6))}",
    ])
    return lines


def section_warnings(data):
    result = ["[warnings]"]
    for number, kind in data["source"]["errors"]:
        result.append(f"line {number} {kind}")
    return result


def section_cleanup(data):
    result = ["[cleanup]", f"snapped {len(data['snapped_list'])}"]
    for number, before, after in data["snapped_list"]:
        result.append(
            f"snap {number} {listing(before)} to {listing(after)}"
        )
    merged = sum(i != data["representative"][i]
                 for i in range(1, len(data["representative"])))
    result.append(f"merged {merged}")
    for original, members in sorted(data["original_to_reps"].items()):
        if len(members) > 1:
            new = data["renumber"].get(original, "-")
            result.append(f"merge {new} {listing(members)}")
    result.append(f"removed {len(data['removed'])}")
    for face in data["removed"]:
        result.append(
            f"remove {face['triangle']} polygon {face['polygon']} "
            f"line {face['line']} {face['reason']}"
        )
    return result


def section_components(data):
    result = []
    points, faces, mesh = data["points"], data["faces"], data["mesh"]
    for component in data["components"]:
        number = component["number"]
        face_groups = {faces[i - 1]["group"] for i in component["faces"]}
        groups = [group for group in data["group_order"] if group in face_groups]
        shapes = shape_counts(component, mesh, faces, points)
        result.extend([
            f"[component {number}]",
            f"groups {listing(groups)}",
            f"faces {len(component['faces'])}",
            f"vertices {len(component['vertices'])}",
            f"edges {len(component['edges'])}",
            f"boundary_edges {len(component['boundary'])}",
            f"nonmanifold_edges {len(component['nonmanifold'])}",
            f"nonmanifold_vertices {len(component['nonmanifold_vertices'])}",
            f"boundary_loops {component['loops']}",
            f"closed {yes(component['closed'])}",
            f"manifold {yes(component['manifold'])}",
            f"orientable {yes(component['orientable'])}",
            f"consistent {yes(component['consistent'])}",
            f"solid {yes(component['solid'])}",
            f"euler {component['euler']}",
        ])
        if component["genus"] is not None:
            result.append(f"genus {component['genus']}")
        elif component["crosscaps"] is not None:
            result.append(f"crosscaps {component['crosscaps']}")
        else:
            result.append("genus -")
        volume_notation = (format_fraction(Fraction(component["volume6"], 6))
                           if component["solid"] else "-")
        result.extend([
            f"volume {volume_notation}",
            f"area {format_real(component['area'])}",
            f"normal_sum {listing(component['normal_sum'])}",
            f"bbox {listing(component['bbox'])}",
            f"inside {listing(component['inside'])}",
        ])
        center = component["centroid"]
        result.append(
            "centroid " + (listing(map(format_fraction, center))
                           if center is not None else "-")
        )
        result.extend([
            f"convex {shapes['convex']}",
            f"concave {shapes['concave']}",
            f"flat {shapes['flat']}",
            f"acute {component['angle_counts']['acute']}",
            f"right {component['angle_counts']['right']}",
            f"obtuse {component['angle_counts']['obtuse']}",
            f"edge_len2 {component['edge_min']} {component['edge_max']}",
            f"valence {component['valence_min']} {component['valence_max']}",
        ])
    return result


def section_groups(data):
    result = []
    source = data["source"]
    for group in data["group_order"]:
        polygons = [p for p in source["polygons"] if p["group"] == group]
        triangles = [t for t in data["triangles"] if t["group"] == group]
        assigned_faces = data["group_faces"].get(group, [])
        chosen = [data["faces"][i - 1] for i in assigned_faces]
        result.extend([
            f"[group {group}]",
            f"polygons {len(polygons)}",
            f"triangles {len(triangles)}",
            f"nonplanar {sum(p['number'] in data['nonplanar'] for p in polygons)}",
            f"faces {len(assigned_faces)}",
            f"area {format_real(area(chosen, data['points']))}",
            f"components {listing(sorted({
                data['mesh']['face_components'][i] for i in assigned_faces
            }))}",
        ])
    return result


def intersecting_boxes(first, second):
    return all(
        first[axis] <= second[axis + 3]
        and second[axis] <= first[axis + 3]
        for axis in range(3)
    )


def section_contacts(data):
    """List intersecting component bounding boxes and exact vertex gaps."""
    result = ["[contacts]"]
    points = data["points"]
    components = data["components"]
    for i, first in enumerate(components):
        for second in components[i + 1:]:
            if not intersecting_boxes(first["bbox"], second["bbox"]):
                continue
            shared = len(set(first["vertices"]) & set(second["vertices"]))
            gap = min(
                dot(subtract(points[a], points[b]),
                    subtract(points[a], points[b]))
                for a in first["vertices"] for b in second["vertices"]
                if a != b
            )
            result.append(
                f"contact {first['number']} {second['number']} "
                f"shared {shared} gap2 {gap}"
            )
    return result


def section_edges(data):
    stats = all_edge_statistics(data["faces"], data["points"], data["mesh"])
    count, shapes = stats["counts"], stats["shapes"]
    shortest_distance, shortest_edge = stats["shortest"]
    longest_distance, longest_edge = stats["longest"]
    return [
        "[edges]",
        f"edges {len(data['mesh']['edges'])}",
        f"boundary {count['boundary']}",
        f"manifold {count['manifold']}",
        f"nonmanifold {count['nonmanifold']}",
        f"max_faces {stats['max_faces']}",
        f"convex {shapes['convex']}",
        f"concave {shapes['concave']}",
        f"flat {shapes['flat']}",
        f"inconsistent {shapes['inconsistent']}",
        f"shortest {listing(shortest_edge)} len2 {shortest_distance}",
        f"longest {listing(longest_edge)} len2 {longest_distance}",
    ]


def section_valence(data):
    """Global vertex degrees, including count of unused output vertices."""
    degree = Counter()
    for a, b in data["mesh"]["edges"]:
        degree[a] += 1
        degree[b] += 1
    histogram = Counter(degree.values())
    used = len(degree)
    result = [
        "[valence]",
        f"used {used}",
        f"isolated {len(data['points']) - 1 - used}",
        f"min {min(degree.values())}",
        f"max {max(degree.values())}",
        f"mean {format_fraction(Fraction(sum(degree.values()), used))}",
    ]
    for value in sorted(histogram):
        result.append(f"degree {value} {histogram[value]}")
    return result


def find_vertex_path(start, end, mesh):
    """Breadth-first traversal examines adjacent vertices in ascending order."""
    graph = defaultdict(set)
    for a, b in mesh["edges"]:
        graph[a].add(b)
        graph[b].add(a)
    queue = deque([start])
    parent = {start: None}
    while queue:
        current = queue.popleft()
        for neighbor in sorted(graph[current]):
            if neighbor not in parent:
                parent[neighbor] = current
                queue.append(neighbor)
    if end not in parent:
        return None
    path = []
    cursor = end
    while cursor is not None:
        path.append(cursor)
        cursor = parent[cursor]
    return list(reversed(path))


def query_vertex(number, data):
    points, faces, mesh = data["points"], data["faces"], data["mesh"]
    if not 1 <= number < len(points):
        return f"vertex {number} invalid"
    containing = [
        i for i, face in enumerate(faces, 1) if number in face["vertices"]
    ]
    degree = sum(number in edge for edge in mesh["edges"])
    fans = mesh["fans"].get(number, [])
    boundary = any(
        number in edge and len(adjacent) == 1
        for edge, adjacent in mesh["edges"].items()
    )
    components = sorted({
        mesh["face_components"][face_id] for face_id in containing
    })
    return (
        f"vertex {number} at {listing(points[number])} "
        f"faces {len(containing)} valence {degree} fans {len(fans)} "
        f"boundary {yes(boundary)} components {listing(components)}"
    )


def query_face(number, data):
    points, faces, mesh = data["points"], data["faces"], data["mesh"]
    if not 1 <= number <= len(faces):
        return f"face {number} invalid"
    face = faces[number - 1]
    neighbors = []
    for a, b in triangle_edges(face["vertices"]):
        participants = mesh["edges"][key_edge(a, b)]
        if len(participants) == 1:
            neighbors.append("-")
        elif len(participants) >= 3:
            neighbors.append("*")
        else:
            neighbors.append(str(next(i for i in participants if i != number)))
    polygon = face["polygon"] if face["polygon"] is not None else "-"
    lineno = face["line"] if face["line"] is not None else "-"
    return (
        f"face {number} vertices {listing(face['vertices'])} "
        f"group {face['group']} polygon {polygon} line {lineno} "
        f"component {mesh['face_components'][number]} "
        f"normal {listing(normal(face, points))} "
        f"area {format_real(area([face], points))} "
        f"neighbors {listing(neighbors)}"
    )


def query_edge(start, end, data):
    a, b = key_edge(start, end)
    mesh = data["mesh"]
    if (a, b) not in mesh["edges"]:
        return f"edge {a} {b} none"
    faces = mesh["edges"][(a, b)]
    kind = "boundary" if len(faces) == 1 else (
        "manifold" if len(faces) == 2 else "nonmanifold"
    )
    shape = edge_shape(
        (a, b), data["faces"], data["points"], faces
    ) if len(faces) == 2 else "-"
    return (
        f"edge {a} {b} faces {listing(faces)} "
        f"kind {kind} shape {shape} "
        f"len2 {edge_length_squared((a, b), data['points'])}"
    )


def query_point(x, y, z, data):
    inside = []
    winding_sum = 0
    for component in data["components"]:
        if not component["solid"]:
            continue
        winding = winding_number(
            component["faces"], data["faces"], data["points"], (x, y, z)
        )
        if winding != 0:
            inside.append(component["number"])
            winding_sum += winding
    return (
        f"point {x} {y} {z} inside {listing(inside)} "
        f"winding {winding_sum}"
    )


def query_path(start, end, data):
    max_vertex = len(data["points"]) - 1
    if not (1 <= start <= max_vertex and 1 <= end <= max_vertex):
        return f"path {start} {end} invalid"
    path = find_vertex_path(start, end, data["mesh"])
    if path is None:
        return f"path {start} {end} none"
    return (
        f"path {start} {end} hops {len(path) - 1} "
        f"vertices {listing(path)}"
    )


def query_view(direction, data):
    scores = [
        dot(normal(face, data["points"]), direction)
        for face in data["faces"]
    ]
    silhouette = 0
    for adjacent in data["mesh"]["edges"].values():
        if len(adjacent) != 2:
            continue
        a, b = (scores[i - 1] for i in adjacent)
        if (a > 0 and b < 0) or (a < 0 and b > 0):
            silhouette += 1
    return (
        f"view {listing(direction)} "
        f"front {sum(value > 0 for value in scores)} "
        f"back {sum(value < 0 for value in scores)} "
        f"side {sum(value == 0 for value in scores)} "
        f"silhouette {silhouette}"
    )


def section_queries(data):
    result = ["[queries]"]
    for kind, args in data["settings"]["queries"]:
        if kind == "vertex":
            result.append(query_vertex(args[0], data))
        elif kind == "face":
            result.append(query_face(args[0], data))
        elif kind == "edge":
            result.append(query_edge(*args, data))
        elif kind == "point":
            result.append(query_point(*args, data))
        elif kind == "path":
            result.append(query_path(*args, data))
        elif kind == "view":
            result.append(query_view(args, data))
    return result


def report_sections(data):
    actions = {
        "summary": section_summary,
        "warnings": section_warnings,
        "cleanup": section_cleanup,
        "components": section_components,
        "groups": section_groups,
        "contacts": section_contacts,
        "edges": section_edges,
        "valence": section_valence,
        "queries": section_queries,
    }
    result = []
    for section in data["settings"]["sections"]:
        result.extend(actions[section](data))
    return result


def csv_components(data):
    result = ["component,faces,vertices,closed,euler,genus,volume6,area"]
    for component in data["components"]:
        genus = component["genus"] if component["genus"] is not None else "-"
        six_volume = component["volume6"] if component["solid"] else "-"
        result.append(",".join(map(str, (
            component["number"], len(component["faces"]),
            len(component["vertices"]), yes(component["closed"]),
            component["euler"], genus, six_volume,
            format_real(component["area"]),
        ))))
    return result


def boundaries_report(data):
    """Retain the pre-fill defects and the original component numbering."""
    faces = data["faces"]
    premesh = data["mesh_before"]
    result = [f"loops {len(data['loops_before'])}"]
    for loop in data["loops_before"]:
        result.append(
            f"loop {loop['number']} component {loop['component']} "
            f"length {loop['length']} {loop['kind']} "
            f"{'filled' if loop['filled'] else 'kept'} "
            f"vertices {listing(loop['vertices'])}"
        )
    edges = premesh["edges"]
    nonmanifold = sorted(
        edge for edge in edges if len(edges[edge]) >= 3
    )
    result.append(f"nonmanifold_edges {len(nonmanifold)}")
    for edge in nonmanifold:
        result.append(
            f"edge {listing(edge)} faces {listing(edges[edge])}"
        )
    vertices = premesh["nonmanifold_vertices"]
    result.append(f"nonmanifold_vertices {len(vertices)}")
    for vertex in vertices:
        components = sorted({
            premesh["face_components"][face]
            for fan in premesh["fans"][vertex] for face in fan
        })
        result.append(
            f"vertex {vertex} fans {len(premesh['fans'][vertex])} "
            f"components {listing(components)}"
        )
    inconsistent = data["inconsistent_after"]
    result.append(f"inconsistent_edges {len(inconsistent)}")
    for edge in inconsistent:
        result.append(
            f"edge {listing(edge)} faces {listing(edges[edge])}"
        )
    return result


def main():
    """Perform the full integer geometric workflow and write the four files."""
    source = read_obj()
    settings = read_parameters()
    result = analyze_source(source, settings)
    write_ascii_lines("report.txt", report_sections(result))
    write_ascii_lines("components.csv", csv_components(result))
    write_ascii_lines("boundaries.txt", boundaries_report(result))
    write_ascii_lines("repaired.obj", write_repaired_obj(
        result["points"], result["faces"],
    ))


def write_ascii_lines(name, lines):
    target = Path("output") / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines) + "\n", encoding="ascii")


if __name__ == "__main__":
    main()
