"""Integer Canny, circle/line Hough, polygon and Harris feature analyzer.

Read the image, integer trigonometry table and parameters from input/.
The nine required outputs are written to output/, with no console output.
"""

from collections import Counter, defaultdict
from functools import cmp_to_key

from canny import components, directions, hysteresis, suppress
from corners import harris_corners
from filters import gradient, smoothing
from hough import (
    circle_peaks, circle_votes, line_peaks, line_votes, rho, vote_image,
)
from pgm_io import read_params, read_pgm, read_trig, write_lines, write_pgm


POLYGON_KINDS = (
    "equilateral_triangle", "right_triangle", "triangle", "square",
    "rectangle", "parallelogram", "trapezoid", "quadrilateral",
)


def cross(first, second):
    return first[0] * second[1] - first[1] * second[0]


def dot(first, second):
    return first[0] * second[0] + first[1] * second[1]


def difference(first, second):
    return first[0] - second[0], first[1] - second[1]


def chebyshev(first, second):
    return max(abs(first[0] - second[0]), abs(first[1] - second[1]))


def angle_difference(first, second):
    gap = abs(first - second)
    return min(gap, 180 - gap)


def nearest_integer(numerator, denominator):
    """Round a signed ratio to the nearest integer; ties go upward."""
    if denominator < 0:
        numerator, denominator = -numerator, -denominator
    return (2 * numerator + denominator) // (2 * denominator)


def bresenham(start, end):
    """Rasterize a segment using the specified coupled error updates."""
    x, y = start
    x1, y1 = end
    dx = abs(x1 - x)
    dy = -abs(y1 - y)
    sx = 1 if x < x1 else -1
    sy = 1 if y < y1 else -1
    error = dx + dy
    points = []
    while True:
        points.append((x, y))
        if x == x1 and y == y1:
            break
        doubled = 2 * error
        if doubled >= dy:
            error += dy
            x += sx
        if doubled <= dx:
            error += dx
            y += sy
    return points


def sort_circle_offsets(offsets):
    """Sort midpoint-circle points by half-plane and positive cross product."""
    def half(point):
        x, y = point
        return 0 if y > 0 or (y == 0 and x > 0) else 1

    def compare(a, b):
        ha, hb = half(a), half(b)
        if ha != hb:
            return -1 if ha < hb else 1
        sign = cross(a, b)
        if sign:
            return -1 if sign > 0 else 1
        return (a > b) - (a < b)

    return sorted(offsets, key=cmp_to_key(compare))


def analyze_circle_gaps(circle, edges):
    """Count hits, circular missing runs, and arcs on the circumference."""
    outline = sort_circle_offsets(circle["outline"])
    cx, cy = circle["center"]
    hits = [(cx + dx, cy + dy) in edges for dx, dy in outline]
    count = len(hits)
    if all(hits):
        return 0, 1
    if not any(hits):
        return count, 0
    arcs = sum(hits[i] and not hits[i - 1] for i in range(count))
    maximum = 0
    run = 0
    for hit in hits + hits:
        if hit:
            run = 0
        else:
            run += 1
            maximum = max(maximum, run)
    return min(maximum, count), arcs


def selected_circles(circle_cells, outlines, peaks, edges, count):
    """Choose highest relative votes and remove edge pixels near circumferences."""
    circles = []
    for radius, x, y, votes in peaks[:count]:
        circle = {
            "number": len(circles) + 1,
            "center": (x, y), "radius": radius,
            "votes": votes, "outline": outlines[radius],
            "outline_count": len(outlines[radius]),
        }
        circle["gap"], circle["arcs"] = analyze_circle_gaps(circle, edges)
        circles.append(circle)
    circ_pixels = set()
    for p in edges:
        for circle in circles:
            cx, cy = circle["center"]
            radius = circle["radius"]
            squared_distance = (p[0] - cx) ** 2 + (p[1] - cy) ** 2
            if (radius - 1) ** 2 <= squared_distance <= (radius + 1) ** 2:
                circ_pixels.add(p)
                break
    return circles, circ_pixels, edges - circ_pixels


def segment_groups(pixels, cosine, sine, gap_limit):
    """Sort by line projection, then split at large projection gaps."""
    ordered = sorted(
        pixels, key=lambda p: (p[1] * cosine - p[0] * sine, p[0], p[1])
    )
    grouped = []
    current = []
    previous_u = None
    for point in ordered:
        value = point[1] * cosine - point[0] * sine
        if (previous_u is not None
                and value - previous_u > gap_limit * 16384):
            grouped.append(current)
            current = []
        current.append(point)
        previous_u = value
    if current:
        grouped.append(current)
    return grouped


def extract_segments(line_peaks_list, line_edges, trig, params):
    """Claim only the pixels from accepted straight-line segments."""
    step = params["hough_rho_step"]
    tolerance = params["segment_tolerance"]
    minimum = params["segment_min_length"]
    used = set()
    lines = []
    segments = []
    for angle, radial, votes in line_peaks_list:
        if len(lines) >= params["hough_max_lines"]:
            break
        cosine, sine = trig[angle]
        available = [
            point for point in line_edges
            if point not in used and
            abs(rho(point, angle, trig, step) - radial) <= tolerance
        ]
        groups = segment_groups(
            available, cosine, sine, params["segment_max_gap"]
        )
        pending = []
        for group in groups:
            start, end = group[0], group[-1]
            length = chebyshev(start, end) + 1
            if length < minimum:
                continue
            pending.append({
                "start": start, "end": end,
                "length": length, "pixels": len(group), "points": group,
                "theta": angle,
            })
        if not pending:
            continue
        line_number = len(lines) + 1
        segment_numbers = []
        for segment in pending:
            segment["number"] = len(segments) + 1
            segment["line"] = line_number
            segments.append(segment)
            segment_numbers.append(segment["number"])
            used.update(segment["points"])
        lines.append({
            "number": line_number, "theta": angle, "rho": radial,
            "votes": votes, "segments": segment_numbers,
        })
    return lines, segments, used


def choose_junction_end(segment, intersection):
    start = chebyshev(segment["start"], intersection)
    end = chebyshev(segment["end"], intersection)
    if start <= end:
        return "start", start
    return "end", end


def build_junctions(segments, minimum_angle, maximum_distance):
    """Intersect line extensions exactly with rational integer rounding."""
    joins = {}
    for i, a in enumerate(segments):
        for b in segments[i + 1:]:
            if angle_difference(a["theta"], b["theta"]) < minimum_angle:
                continue
            da = difference(a["end"], a["start"])
            db = difference(b["end"], b["start"])
            den = cross(da, db)
            if den == 0:
                continue
            lam = cross(difference(b["start"], a["start"]), db)
            x = nearest_integer(a["start"][0] * den + lam * da[0], den)
            y = nearest_integer(a["start"][1] * den + lam * da[1], den)
            point = x, y
            end_a, dist_a = choose_junction_end(a, point)
            end_b, dist_b = choose_junction_end(b, point)
            if max(dist_a, dist_b) > maximum_distance:
                continue
            joins[(a["number"], b["number"])] = {
                "point": point,
                "ends": {a["number"]: end_a, b["number"]: end_b},
            }
    return joins


def joined(first, second, junctions):
    return junctions.get((min(first, second), max(first, second)))


def polygon_cycles(segments, junctions):
    """Enumerate unique convex cycles of three or four segments."""
    graph = defaultdict(set)
    for a, b in junctions:
        graph[a].add(b)
        graph[b].add(a)
    polygons = []
    for count in (3, 4):
        found = []
        for first in sorted(graph):
            def extend(sequence):
                if len(sequence) == count:
                    if sequence[1] >= sequence[-1]:
                        return
                    if joined(sequence[-1], first, junctions) is None:
                        return
                    vertices = []
                    for i, current in enumerate(sequence):
                        previous = sequence[i - 1]
                        following = sequence[(i + 1) % count]
                        entry = joined(previous, current, junctions)
                        exit_ = joined(current, following, junctions)
                        if entry["ends"][current] == exit_["ends"][current]:
                            return
                        vertices.append(entry["point"])
                    turns = [
                        cross(
                            difference(vertices[(i + 1) % count], vertices[i]),
                            difference(vertices[(i + 2) % count],
                                       vertices[(i + 1) % count]),
                        )
                        for i in range(count)
                    ]
                    if not (all(value > 0 for value in turns)
                            or all(value < 0 for value in turns)):
                        return
                    found.append({
                        "segments": tuple(sequence),
                        "vertices": vertices,
                    })
                    return
                for candidate in sorted(graph[sequence[-1]]):
                    if candidate <= first or candidate in sequence:
                        continue
                    extend(sequence + [candidate])

            extend([first])
        found.sort(key=lambda item: item["segments"])
        for item in found:
            item["number"] = len(polygons) + 1
            polygons.append(item)
    return polygons


def side_support(start, end, edges):
    """Count Bresenham points with an edge within Chebyshev distance one."""
    support = 0
    points = bresenham(start, end)
    for x, y in points:
        if any((x + dx, y + dy) in edges
               for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
            support += 1
    return 100 * support // len(points)


def polygon_properties(polygon, by_segment, edges, params):
    """Side geometry, approximate interior angles, type and edge support."""
    identifiers = polygon["segments"]
    vertices = polygon["vertices"]
    count = len(identifiers)
    theta = [by_segment[s]["theta"] for s in identifiers]
    angles = []
    lengths = []
    supports = []
    signed_area = 0
    for i in range(count):
        previous = vertices[(i - 1) % count]
        point = vertices[i]
        following = vertices[(i + 1) % count]
        phi = angle_difference(theta[i - 1], theta[i])
        if dot(difference(previous, point), difference(following, point)) < 0:
            phi = 180 - phi
        angles.append(phi)
        side = difference(following, point)
        lengths.append(dot(side, side))
        supports.append(side_support(point, following, edges))
        signed_area += cross(point, following)
    polygon["angles"] = angles
    polygon["lengths"] = lengths
    polygon["supports"] = supports
    polygon["sigma"] = signed_area
    tolerance = params["angle_tolerance"]
    if count == 3:
        if all(abs(value - 60) <= tolerance for value in angles):
            kind = "equilateral_triangle"
        elif any(abs(value - 90) <= tolerance for value in angles):
            kind = "right_triangle"
        else:
            kind = "triangle"
    else:
        first_parallel = angle_difference(theta[0], theta[2]) <= tolerance
        second_parallel = angle_difference(theta[1], theta[3]) <= tolerance
        if not first_parallel and not second_parallel:
            kind = "quadrilateral"
        elif first_parallel != second_parallel:
            kind = "trapezoid"
        elif any(abs(value - 90) > tolerance for value in angles):
            kind = "parallelogram"
        elif (100 * (max(lengths) - min(lengths))
              <= params["square_tolerance"] * max(lengths)):
            kind = "square"
        else:
            kind = "rectangle"
    polygon["kind"] = kind
    polygon["vertex_corners"] = [None] * count
    return polygon


def shape_name(shape):
    if shape is None:
        return "none"
    return f"{shape['type']} {shape['number']}"


def shape_representatives(shape):
    if shape["type"] == "polygon":
        return shape["vertices"]
    x, y = shape["center"]
    r = shape["radius"]
    return [(x + r, y), (x, y + r), (x - r, y), (x, y - r)]


def contains_pixel(shape, point):
    x, y = point
    if shape["type"] == "circle":
        cx, cy = shape["center"]
        return (x - cx) ** 2 + (y - cy) ** 2 <= shape["radius"] ** 2
    vertices = shape["vertices"]
    sign = shape["sigma"]
    for i, vertex in enumerate(vertices):
        edge = difference(vertices[(i + 1) % len(vertices)], vertex)
        offset = difference(point, vertex)
        value = cross(edge, offset)
        if value != 0 and ((value > 0) != (sign > 0)):
            return False
    return True


def measure_shapes(shapes, original, margin):
    """Pixel means and contrast inside each shape's expanded representative box."""
    height = len(original)
    width = len(original[0])
    for shape in shapes:
        representatives = shape_representatives(shape)
        x0 = max(0, min(x for x, _ in representatives) - margin)
        x1 = min(width - 1, max(x for x, _ in representatives) + margin)
        y0 = max(0, min(y for _, y in representatives) - margin)
        y1 = min(height - 1, max(y for _, y in representatives) + margin)
        inner = []
        outer = []
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if contains_pixel(shape, (x, y)):
                    inner.append(original[y][x])
                else:
                    outer.append(original[y][x])
        shape["pixel_count"] = len(inner)
        shape["mean"] = sum(inner) // len(inner) if inner else 0
        shape["contrast"] = shape["mean"] - (
            sum(outer) // len(outer) if outer else 0
        )
    for i, child in enumerate(shapes):
        parents = [
            (parent["pixel_count"], index, parent)
            for index, parent in enumerate(shapes)
            if index != i and parent["pixel_count"] > child["pixel_count"]
            and all(contains_pixel(parent, point)
                    for point in shape_representatives(child))
        ]
        child["enclosing"] = min(parents)[2] if parents else None


def match_corners(corners, polygons, segments, maximum_distance):
    """Match corners to vertices first, then nearest segment endpoints."""
    for corner in corners:
        position = corner["x"], corner["y"]
        vertices = []
        for polygon in polygons:
            for index, vertex in enumerate(polygon["vertices"], 1):
                distance = chebyshev(position, vertex)
                if distance <= maximum_distance:
                    vertices.append((distance, polygon["number"], index))
        if vertices:
            _, polygon_number, vertex_number = min(vertices)
            corner["match"] = f"polygon {polygon_number} vertex {vertex_number}"
            corner["match_kind"] = "vertex"
            continue
        ends = []
        for segment in segments:
            for rank, endpoint in enumerate(("start", "end")):
                distance = chebyshev(position, segment[endpoint])
                if distance <= maximum_distance:
                    ends.append((distance, segment["number"], rank, endpoint))
        if ends:
            _, segment_number, _, endpoint = min(ends)
            corner["match"] = f"segment {segment_number} {endpoint}"
            corner["match_kind"] = "segment"
        else:
            corner["match"] = "none"
            corner["match_kind"] = "none"

    matches = 0
    for polygon in polygons:
        for index, vertex in enumerate(polygon["vertices"]):
            candidates = [
                (chebyshev((c["x"], c["y"]), vertex), c["number"])
                for c in corners
                if chebyshev((c["x"], c["y"]), vertex) <= maximum_distance
            ]
            if candidates:
                polygon["vertex_corners"][index] = min(candidates)[1]
                matches += 1
    return matches


def shape_explanations(shape, edges):
    """Set of original Canny edge pixels explained by one polygon or circle."""
    explained = set()
    if shape["type"] == "circle":
        cx, cy = shape["center"]
        radius = shape["radius"]
        for x, y in edges:
            sq = (x - cx) ** 2 + (y - cy) ** 2
            if (radius - 1) ** 2 <= sq <= (radius + 1) ** 2:
                explained.add((x, y))
    else:
        verts = shape["vertices"]
        for index, start in enumerate(verts):
            end = verts[(index + 1) % len(verts)]
            for x, y in bresenham(start, end):
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        point = x + dx, y + dy
                        if point in edges:
                            explained.add(point)
    return explained


def match_components(components_list, shapes, edges):
    """Choose the shape explaining the most pixels of each edge component."""
    explanations = [shape_explanations(shape, edges) for shape in shapes]
    for component in components_list:
        pixels = set(component["pixels"])
        counts = [len(pixels & claimed) for claimed in explanations]
        maximum = max(counts, default=0)
        if maximum == 0:
            component["shape"] = None
            component["explained"] = 0
        else:
            component["shape"] = shapes[counts.index(maximum)]
            component["explained"] = maximum


def overlay_image(original, segments, circles, corners, divisor):
    image = [[value // divisor for value in row] for row in original]
    height = len(image)
    width = len(image[0])

    def mark(point):
        x, y = point
        if 0 <= x < width and 0 <= y < height:
            image[y][x] = 255

    for segment in segments:
        for point in bresenham(segment["start"], segment["end"]):
            mark(point)
    for circle in circles:
        cx, cy = circle["center"]
        for dx, dy in circle["outline"]:
            mark((cx + dx, cy + dy))
    for corner in corners:
        for offset in range(-2, 3):
            mark((corner["x"] + offset, corner["y"]))
            mark((corner["x"], corner["y"] + offset))
    return image


def lines_listing(lines, segments):
    result = [f"lines {len(lines)}"]
    by_number = {segment["number"]: segment for segment in segments}
    for line in lines:
        result.append(
            f"line {line['number']} theta {line['theta']} "
            f"rho {line['rho']} votes {line['votes']} "
            f"segments {len(line['segments'])}"
        )
        for number in line["segments"]:
            s = by_number[number]
            result.append(
                f"segment {number} start {s['start'][0]} {s['start'][1]} "
                f"end {s['end'][0]} {s['end'][1]} "
                f"length {s['length']} pixels {s['pixels']}"
            )
    return result


def circles_listing(circles):
    lines = [f"circles {len(circles)}"]
    for circle in circles:
        cx, cy = circle["center"]
        lines.append(
            f"circle {circle['number']} center {cx} {cy} "
            f"radius {circle['radius']} votes {circle['votes']} "
            f"points {circle['outline_count']} gap {circle['gap']} "
            f"arcs {circle['arcs']} pixels {circle['pixel_count']} "
            f"mean {circle['mean']} contrast {circle['contrast']} "
            f"inside {shape_name(circle['enclosing'])}"
        )
    return lines


def polygons_listing(polygons):
    lines = [f"polygons {len(polygons)}"]
    for polygon in polygons:
        amount = abs(polygon["sigma"])
        area = f"{amount // 2}.{'5' if amount % 2 else '0'}"
        lines.append(
            f"polygon {polygon['number']} {polygon['kind']} "
            f"segments {' '.join(map(str, polygon['segments']))} "
            f"area {area} pixels {polygon['pixel_count']} "
            f"mean {polygon['mean']} contrast {polygon['contrast']} "
            f"inside {shape_name(polygon['enclosing'])}"
        )
        for index, (x, y) in enumerate(polygon["vertices"], 1):
            corner = polygon["vertex_corners"][index - 1]
            lines.append(
                f"vertex {index} {x} {y} angle {polygon['angles'][index - 1]} "
                f"corner {corner if corner is not None else 'none'}"
            )
        for index, segment_id in enumerate(polygon["segments"], 1):
            lines.append(
                f"side {index} segment {segment_id} "
                f"length2 {polygon['lengths'][index - 1]} "
                f"support {polygon['supports'][index - 1]}"
            )
    return lines


def corners_listing(corners):
    lines = [f"corners {len(corners)}"]
    for corner in corners:
        lines.append(
            f"corner {corner['number']} {corner['x']} {corner['y']} "
            f"response {corner['response']} match {corner['match']}"
        )
    return lines


def components_listing(components_list):
    lines = [f"components {len(components_list)}"]
    for comp in components_list:
        bounds = " ".join(map(str, comp["box"]))
        lines.append(
            f"component {comp['number']} pixels {comp['size']} "
            f"box {bounds} ends {comp['ends']} "
            f"strength {comp['strength']} direction {comp['direction']} "
            f"shape {shape_name(comp['shape'])} explained {comp['explained']}"
        )
    return lines


def report_lines(image, magnitude, direction, nms, strong, weak, edges,
                 components_list, candidates, circle_peaks_list, circles,
                 circle_edge, line_edge, max_votes, line_peaks_list, lines,
                 segments, used, junctions, polygons, corner_candidates,
                 corners, vertices_with_corner):
    """All forty named scalars in the benchmark's specified order."""
    height = len(image)
    width = len(image[0])
    kinds = Counter(polygon["kind"] for polygon in polygons)
    directions_count = Counter(direction[y][x] for x, y in edges)
    match_count = Counter(corner["match_kind"] for corner in corners)
    values = [
        ("image", f"{width} {height}"),
        ("gradient_nonzero", sum(value > 0 for row in magnitude for value in row)),
        ("gradient_max", max(value for row in magnitude for value in row)),
        ("nms_kept", sum(value > 0 for row in nms for value in row)),
        ("strong", len(strong)), ("weak", len(weak)),
        ("edges", len(edges)),
        ("weak_kept", len(weak & edges)),
        ("weak_dropped", len(weak - edges)),
        ("edge_components", len(components_list)),
    ]
    for angle in (0, 45, 90, 135):
        values.append((f"direction_{angle}", directions_count[angle]))
    values.extend([
        ("circle_candidates", len(candidates)),
        ("circle_peaks", len(circle_peaks_list)),
        ("circles", len(circles)),
        ("circle_edge_pixels", len(circle_edge)),
        ("line_edge_pixels", len(line_edge)),
        ("hough_max_votes", max_votes),
        ("hough_peaks", len(line_peaks_list)),
        ("lines", len(lines)),
        ("segments", len(segments)),
        ("claimed_pixels", len(used)),
        ("junctions", len(junctions)),
        ("polygons", len(polygons)),
    ])
    for kind in POLYGON_KINDS:
        values.append((kind, kinds[kind]))
    values.extend([
        ("corner_candidates", len(corner_candidates)),
        ("corners", len(corners)),
        ("corners_on_vertices", match_count["vertex"]),
        ("corners_on_segments", match_count["segment"]),
        ("corners_unmatched", match_count["none"]),
        ("vertices_with_corner", vertices_with_corner),
    ])
    return [f"{name} {value}" for name, value in values]


def main():
    """Execute the complete shape detection workflow and write nine files."""
    image = read_pgm()
    trig = read_trig()
    params = read_params()
    height = len(image)
    width = len(image[0])

    smoothed = smoothing(image, params)
    gx, gy, magnitude = gradient(smoothed)
    direction = directions(gx, gy)
    nms = suppress(magnitude, direction)
    edges, strong, weak = hysteresis(
        nms, params["canny_low"], params["canny_high"]
    )
    components_list = components(edges, magnitude, direction)

    circle_cells, outlines = circle_votes(edges, width, height, params)
    circle_candidates, circle_peaks_list = circle_peaks(
        circle_cells, outlines, width, height, params["circle_min_percent"]
    )
    circles, circle_edge, line_edge = selected_circles(
        circle_cells, outlines, circle_peaks_list, edges,
        params["circle_max_count"],
    )
    for circle in circles:
        circle["type"] = "circle"

    votes = line_votes(line_edge, trig, params["hough_rho_step"])
    peaks = line_peaks(votes, params["hough_threshold"])
    lines, segments, used = extract_segments(peaks, line_edge, trig, params)
    segment_lookup = {s["number"]: s for s in segments}
    junctions = build_junctions(
        segments, params["junction_min_angle"], params["junction_distance"]
    )
    polygons = polygon_cycles(segments, junctions)
    for polygon in polygons:
        polygon["type"] = "polygon"
        polygon_properties(polygon, segment_lookup, edges, params)

    shapes = polygons + circles
    measure_shapes(shapes, image, params["contrast_margin"])
    _, corner_candidates, corners = harris_corners(
        gx, gy, params["harris_window"], params["harris_threshold"],
        params["harris_max_count"],
    )
    vertices_with_corner = match_corners(
        corners, polygons, segments, params["corner_match_distance"]
    )
    match_components(components_list, shapes, edges)
    overlay = overlay_image(
        image, segments, circles, corners, params["overlay_divisor"]
    )
    hough_image, max_votes = vote_image(
        votes, width, height, trig, params["hough_rho_step"]
    )

    edge_image = [
        [255 if (x, y) in edges else 0 for x in range(width)]
        for y in range(height)
    ]
    write_pgm("edges.pgm", edge_image)
    write_pgm("hough.pgm", hough_image)
    write_pgm("overlay.pgm", overlay)
    write_lines("lines.txt", lines_listing(lines, segments))
    write_lines("circles.txt", circles_listing(circles))
    write_lines("polygons.txt", polygons_listing(polygons))
    write_lines("corners.txt", corners_listing(corners))
    write_lines("components.txt", components_listing(components_list))
    write_lines("report.txt", report_lines(
        image, magnitude, direction, nms, strong, weak, edges,
        components_list, circle_candidates, circle_peaks_list,
        circles, circle_edge, line_edge, max_votes, peaks,
        lines, segments, used, junctions, polygons,
        corner_candidates, corners, vertices_with_corner,
    ))


if __name__ == "__main__":
    main()
