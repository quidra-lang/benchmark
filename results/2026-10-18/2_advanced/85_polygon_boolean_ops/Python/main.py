"""Validate polygon definitions and execute exact Boolean geometry operations."""

from pathlib import Path

import greiner_hormann
import intersections
import render
import rings
from rational import cross, divide, point_key, point_text, real, segment_text


KINDS = ("UNION", "INTERSECTION", "DIFFERENCE", "XOR", "CLIP", "AREA",
         "MOVE", "ROTATE", "MIRROR", "SNAP", "LOCATE", "RENDER")
BINARY = frozenset(KINDS[:5])
DEFINITIONS = frozenset(("MOVE", "ROTATE", "MIRROR", "SNAP"))
WORD_COUNTS = {
    "UNION": 3, "INTERSECTION": 3, "DIFFERENCE": 3, "XOR": 3, "CLIP": 3,
    "AREA": 2, "MOVE": 5, "ROTATE": 6, "MIRROR": 5, "SNAP": 3,
    "LOCATE": 4, "RENDER": 8,
}


class Rejected(Exception):
    pass


class Polygon:
    def __init__(self, name, input_rings):
        self.name = name
        self.input_rings = input_rings
        outer = rings.normalize(input_rings[0], True)
        holes = [rings.normalize(ring, False) for ring in input_rings[1:]]
        holes.sort(key=lambda ring: point_key(ring[0]))
        self.rings = [outer, *holes]


class Region:
    def __init__(self, polygons, operands=None):
        self.polygons = polygons
        self.operands = operands


def digits(word):
    return 1 <= len(word) <= 9 and all("0" <= character <= "9" for character in word)


def integer_word(word):
    return digits(word[1:] if word.startswith("-") else word)


def valid_name(word):
    return (1 <= len(word) <= 16
            and all("a" <= character <= "z" or "0" <= character <= "9" or character == "_"
                    for character in word))


def records(filename):
    result = []
    with Path("input", filename).open("r", encoding="ascii", newline="\n") as source:
        for number, raw in enumerate(source, 1):
            line = raw.removesuffix("\n")
            if line and not line.startswith("#"):
                result.append((number, line))
    return result


def parse_rings(content, end_line):
    result = []
    position = 0
    while position < len(content):
        number, line = content[position]
        words = line.split(" ")
        if (len(words) != 2 or words[0] not in ("OUTER", "HOLE")
                or not digits(words[1]) or int(words[1]) < 1):
            return None, number
        if words[0] == "OUTER" and result or words[0] == "HOLE" and not result:
            return None, number
        count = int(words[1])
        position += 1
        vertices = []
        for vertex in range(count):
            if position == len(content):
                return None, end_line
            number, line = content[position]
            coordinates = line.split(" ")
            if len(coordinates) != 2 or not all(integer_word(word) for word in coordinates):
                return None, number
            vertices.append(tuple(int(word) for word in coordinates))
            position += 1
        result.append(vertices)
    return (result, None) if result else (None, end_line)


def check_ring(ring, number):
    count = len(ring)
    if count < 3:
        return f"too_few_vertices ring {number}"
    for point in ring:
        if not (0 <= point[0] <= 1000 and 0 <= point[1] <= 1000):
            return f"out_of_range ring {number} {point_text(point)}"
    seen = set()
    for point in ring:
        if point in seen:
            return f"duplicate_vertex ring {number} {point_text(point)}"
        seen.add(point)
    for index, point in enumerate(ring):
        if cross(ring[index - 1], point, ring[(index + 1) % count]) == 0:
            return f"collinear ring {number} {point_text(point)}"
    edges = list(rings.edges(ring))
    for first in range(count):
        for second in range(first + 2, count):
            if first == 0 and second == count - 1:
                continue
            a, b = edges[first]
            c, d = edges[second]
            if intersections.touch(a, b, c, d):
                return (f"self_intersection ring {number} "
                        f"{segment_text(a, b)} {segment_text(c, d)}")
    return None


def check_polygon(sequence):
    for number, ring in enumerate(sequence, 1):
        error = check_ring(ring, number)
        if error is not None:
            return error
    edge_lists = [list(rings.edges(ring)) for ring in sequence]
    for first in range(len(sequence)):
        for second in range(first + 1, len(sequence)):
            for a, b in edge_lists[first]:
                for c, d in edge_lists[second]:
                    if intersections.touch(a, b, c, d):
                        return (f"rings_touch rings {first + 1} {second + 1} "
                                f"{segment_text(a, b)} {segment_text(c, d)}")
    for index, hole in enumerate(sequence[1:], 2):
        if not rings.inside(sequence[0], hole[0]):
            return f"hole_outside ring {index} {point_text(hole[0])}"
    for first in range(1, len(sequence)):
        for second in range(first + 1, len(sequence)):
            if rings.inside(sequence[first], sequence[second][0]):
                point = sequence[second][0]
            elif rings.inside(sequence[second], sequence[first][0]):
                point = sequence[first][0]
            else:
                continue
            return f"hole_in_hole rings {first + 1} {second + 1} {point_text(point)}"
    return None


class Registry:
    def __init__(self):
        self.used = set()
        self.polygons = {}
        self.invalid = []
        self.block_count = 0
        self.valid_blocks = 0
        lines = records("polygons.txt")
        position = 0
        while position < len(lines):
            start_line, header = lines[position]
            name = header.split(" ")[1]
            position += 1
            content = []
            while lines[position][1] != "END":
                content.append(lines[position])
                position += 1
            end_line = lines[position][0]
            position += 1
            self.block_count += 1
            if name in self.used:
                self.invalid.append((name, f"duplicate_name line {start_line}"))
                continue
            self.used.add(name)
            sequence, error_line = parse_rings(content, end_line)
            if error_line is not None:
                self.invalid.append((name, f"format line {error_line}"))
                continue
            error = check_polygon(sequence)
            if error is not None:
                self.invalid.append((name, error))
                continue
            self.polygons[name] = Polygon(name, sequence)
            self.valid_blocks += 1

    def resolve(self, name):
        if name not in self.used:
            raise Rejected("unknown_polygon " + name)
        if name not in self.polygons:
            raise Rejected("invalid_polygon " + name)
        return self.polygons[name]

    def define(self, polygon):
        self.used.add(polygon.name)
        self.polygons[polygon.name] = polygon


def arguments_valid(words):
    kind = words[0]
    if len(words) != WORD_COUNTS[kind]:
        return False
    if kind in BINARY or kind == "AREA":
        return True
    if kind == "SNAP":
        return valid_name(words[2])
    if kind == "LOCATE":
        return (all(integer_word(word) for word in words[2:])
                and all(0 <= int(word) <= 1000 for word in words[2:]))
    if kind == "MOVE":
        return (valid_name(words[4]) and all(integer_word(word) for word in words[2:4])
                and all(-1000 <= int(word) <= 1000 for word in words[2:4]))
    if kind == "ROTATE":
        return (valid_name(words[5]) and all(integer_word(word) for word in words[2:5])
                and 0 <= int(words[2]) <= 1000 and 0 <= int(words[3]) <= 1000
                and 1 <= int(words[4]) <= 3)
    if kind == "MIRROR":
        return (valid_name(words[4]) and words[2] in ("x", "y")
                and integer_word(words[3]) and 0 <= int(words[3]) <= 1000)
    if not all(integer_word(word) for word in words[2:]):
        return False
    x0, y0, width, height, columns, rows = (int(word) for word in words[2:])
    return (x0 >= 0 and y0 >= 0 and 1 <= width <= 100 and 1 <= height <= 100
            and 1 <= columns <= 100 and 1 <= rows <= 60
            and x0 + width * columns <= 1000 and y0 + height * rows <= 1000)


def general_position(first, second):
    first_vertices = [point for ring in first.rings for point in ring]
    second_vertices = [point for ring in second.rings for point in ring]
    second_set = set(second_vertices)
    for point in first_vertices:
        if point in second_set:
            return "shared_vertex " + point_text(point)
    first_edges = [edge for ring in first.rings for edge in rings.edges(ring)]
    second_edges = [edge for ring in second.rings for edge in rings.edges(ring)]
    for a, b in first_edges:
        for c, d in second_edges:
            if intersections.overlap(a, b, c, d):
                return f"overlapping_edges {segment_text(a, b)} {segment_text(c, d)}"
    checks = ((first, first_vertices, second, second_edges),
              (second, second_vertices, first, first_edges))
    for source, vertices, other, edges in checks:
        for point in vertices:
            for a, b in edges:
                if intersections.on_segment(point, a, b):
                    return (f"vertex_on_edge {source.name} {point_text(point)} "
                            f"{other.name} {segment_text(a, b)}")
    return None


def transformed_rings(polygon, words):
    kind = words[0]
    result = []
    for ring in polygon.input_rings:
        transformed = []
        for x, y in ring:
            if kind == "MOVE":
                x, y = x + int(words[2]), y + int(words[3])
            elif kind == "ROTATE":
                cx, cy, turns = (int(word) for word in words[2:5])
                for turn in range(turns):
                    x, y = cx - (y - cy), cy + (x - cx)
            elif words[2] == "x":
                x = 2 * int(words[3]) - x
            else:
                y = 2 * int(words[3]) - y
            transformed.append((x, y))
        result.append(transformed)
    return result


def rounded_coordinate(value):
    return (2 * value.numerator + value.denominator) // (2 * value.denominator)


def rounded_rings(polygon):
    return [[(rounded_coordinate(x), rounded_coordinate(y)) for x, y in ring]
            for ring in polygon]


def total_area(polygons):
    total = 0.0
    for polygon in polygons:
        for ring in polygon:
            total += rings.area(ring)
    return total


def binary_result(kind, first, second):
    graph = greiner_hormann.Graph(first.rings, second.rings)
    intersection = rings.assemble(graph.traverse(False, False))
    union = rings.assemble(graph.traverse(True, True))
    if kind == "UNION":
        polygons = union
    elif kind in ("INTERSECTION", "CLIP"):
        polygons = intersection
    else:
        polygons = rings.assemble(graph.traverse(True, False))
        if kind == "XOR":
            reverse_graph = greiner_hormann.Graph(second.rings, first.rings)
            polygons += rings.assemble(reverse_graph.traverse(True, False))
            polygons.sort(key=lambda polygon: point_key(polygon[0][0]))
    if graph.crossings:
        relation = "overlap"
    elif graph.n_a == len(first.rings) and graph.n_b == 0:
        relation = "within"
    elif graph.n_b == len(second.rings) and graph.n_a == 0:
        relation = "contains"
    elif graph.n_a == 0 and graph.n_b == 0:
        relation = "disjoint"
    else:
        relation = "overlap"
    iou = total_area(intersection) / total_area(union)
    return Region(polygons, (first, second)), graph, relation, iou


def cyclic_equal(first, second):
    if len(first) != len(second):
        return False
    for start, point in enumerate(second):
        if point == first[0] and all(first[index] == second[(start + index) % len(second)]
                                     for index in range(len(first))):
            return True
    return False


def crosscheck_clip(first, window, polygons):
    clipped = []
    for ring in first.rings:
        points = list(ring)
        for edge_start, edge_end in rings.edges(window.rings[0]):
            replacement = []
            for index, current in enumerate(points):
                previous = points[index - 1]
                a = cross(edge_start, edge_end, previous)
                b = cross(edge_start, edge_end, current)
                if (a > 0) != (b > 0):
                    replacement.append(intersections.clipping_point(previous, current, a, b))
                if b > 0:
                    replacement.append(current)
            points = replacement
        deduplicated = [point for index, point in enumerate(points) if point != points[index - 1]]
        if len(deduplicated) >= 3:
            clipped.append(deduplicated)
    result_rings = [ring for polygon in polygons for ring in polygon]
    matches = (len(result_rings) == len(clipped)
               and all(any(cyclic_equal(ring, other) for other in clipped) for ring in result_rings))
    return "match" if matches else "mismatch", len(clipped), sum(len(ring) for ring in clipped)


class ResultValues:
    def __init__(self, polygons, first, second=None):
        self.polygon_count = len(polygons)
        self.ring_items = []
        self.area = self.perimeter = 0.0
        self.origins = [0, 0, 0]
        first_vertices = {point for ring in first.rings for point in ring}
        second_vertices = {point for ring in second.rings for point in ring} if second else set()
        vertices = []
        sx, sy = 0.0, 0.0
        for polygon_number, polygon in enumerate(polygons, 1):
            for hole_number, ring in enumerate(polygon):
                area = rings.area(ring)
                self.area += area
                self.perimeter += rings.perimeter(ring)
                self.ring_items.append((polygon_number, hole_number, ring, area))
                vertices.extend(ring)
                for first_point, second_point in rings.edges(ring):
                    if first_point in first_vertices:
                        self.origins[0] += 1
                    elif first_point in second_vertices:
                        self.origins[1] += 1
                    else:
                        self.origins[2] += 1
                    x1, y1 = real(first_point[0]), real(first_point[1])
                    x2, y2 = real(second_point[0]), real(second_point[1])
                    c = x1 * y2 - x2 * y1
                    sx += (x1 + x2) * c
                    sy += (y1 + y2) * c
        self.ring_count = len(self.ring_items)
        self.hole_count = self.ring_count - self.polygon_count
        self.vertex_count = len(vertices)
        self.low = self.high = self.centroid = None
        if vertices:
            self.low = min(point[0] for point in vertices), min(point[1] for point in vertices)
            self.high = max(point[0] for point in vertices), max(point[1] for point in vertices)
            self.centroid = sx / (6.0 * self.area), sy / (6.0 * self.area)

    def lines(self):
        result = [f"polygons {self.polygon_count} rings {self.ring_count} holes {self.hole_count} "
                  f"vertices {self.vertex_count} area {self.area:.3f}"]
        for polygon, hole, ring, area in self.ring_items:
            prefix = f"outer {polygon}" if hole == 0 else f"hole {polygon} {hole}"
            result.append(f"{prefix} {len(ring)} {area:.3f} " + " ".join(point_text(point) for point in ring))
        if self.low is None:
            result.extend(("bbox none", "centroid none"))
        else:
            result.append(f"bbox {point_text(self.low)} {point_text(self.high)}")
            result.append(f"centroid ({self.centroid[0]:.3f},{self.centroid[1]:.3f})")
        result.append(f"perimeter {self.perimeter:.3f}")
        result.append(f"origins a {self.origins[0]} b {self.origins[1]} crossing {self.origins[2]}")
        return result


def input_orientations(polygon):
    orientations = []
    for ring in polygon.input_rings:
        double_area = 0
        for first, second in rings.edges(ring):
            double_area += first[0] * second[1] - second[0] * first[1]
        orientations.append("ccw" if double_area > 0 else "cw")
    return orientations


def convex_hull(outer):
    ordered = sorted(outer)
    chains = []
    for sequence in (ordered, list(reversed(ordered))):
        chain = []
        for point in sequence:
            while len(chain) >= 2 and cross(chain[-2], chain[-1], point) <= 0:
                chain.pop()
            chain.append(point)
        chains.append(chain)
    return chains[0][:-1] + chains[1][:-1]


def property_lines(polygon, area):
    reflex = 0
    for ring in polygon.rings:
        for index, point in enumerate(ring):
            if cross(ring[index - 1], point, ring[(index + 1) % len(ring)]) < 0:
                reflex += 1
    hull = convex_hull(polygon.rings[0])
    double_area = 0
    for first, second in rings.edges(hull):
        double_area += first[0] * second[1] - second[0] * first[1]
    hull_area = real(divide(double_area, 2))
    return ["input " + " ".join(input_orientations(polygon)), f"reflex {reflex}",
            f"hull {len(hull)} {hull_area:.3f} solidity {area / hull_area:.6f}"]


def locate(polygons, point):
    for number, polygon in enumerate(polygons, 1):
        if rings.boundary(polygon[0], point):
            return f"boundary outer {number}"
        for hole, ring in enumerate(polygon[1:], 1):
            if rings.boundary(ring, point):
                return f"boundary hole {number} {hole}"
    for number, polygon in enumerate(polygons, 1):
        if rings.inside(polygon[0], point) and not any(rings.inside(ring, point) for ring in polygon[1:]):
            return f"inside polygon {number}"
    return "outside"


def operand_location(polygon, point):
    if any(rings.boundary(ring, point) for ring in polygon.rings):
        return "boundary"
    return "inside" if rings.interior(polygon.rings, point) else "outside"


class Processor:
    def __init__(self):
        self.registry = Registry()
        self.operations = [line for number, line in records("operations.txt")]
        self.regions = {}
        self.results = []
        self.areas = ["operation,rings,holes,vertices,area"]
        self.drawings = []
        self.rejected_operations = []
        self.kind_totals = dict.fromkeys(KINDS, 0)
        self.kind_succeeded = dict.fromkeys(KINDS, 0)
        self.succeeded = self.defined = self.crossings = 0

    def resolve_target(self, word):
        if word.startswith("@"):
            if not digits(word[1:]) or int(word[1:]) not in self.regions:
                raise Rejected("bad_target " + word)
            return self.regions[int(word[1:])]
        polygon = self.registry.resolve(word)
        return Region([polygon.rings])

    def check_operation(self, words):
        kind = words[0]
        if kind not in WORD_COUNTS:
            raise Rejected("unknown_operation " + kind)
        if not arguments_valid(words):
            raise Rejected("bad_arguments")
        checked = {}
        if kind in BINARY:
            checked["a"] = self.registry.resolve(words[1])
            checked["b"] = self.registry.resolve(words[2])
        elif kind in ("AREA", "MOVE", "ROTATE", "MIRROR"):
            checked["a"] = self.registry.resolve(words[1])
        else:
            checked["target"] = self.resolve_target(words[1])
        if kind in DEFINITIONS and words[-1] in self.registry.used:
            raise Rejected("duplicate_name " + words[-1])
        if kind == "SNAP" and len(checked["target"].polygons) != 1:
            raise Rejected("not_single " + words[1])
        if kind == "CLIP":
            window = checked["b"].rings
            if len(window) > 1:
                raise Rejected("not_convex " + words[2])
            ring = window[0]
            if any(cross(ring[index - 1], point, ring[(index + 1) % len(ring)]) <= 0
                   for index, point in enumerate(ring)):
                raise Rejected("not_convex " + words[2])
        if kind in BINARY:
            error = general_position(checked["a"], checked["b"])
            if error is not None:
                raise Rejected(error)
        if kind in ("MOVE", "ROTATE", "MIRROR"):
            sequence = transformed_rings(checked["a"], words)
            if any(not (0 <= x <= 1000 and 0 <= y <= 1000) for ring in sequence for x, y in ring):
                raise Rejected("out_of_range " + words[-1])
            checked["defined"] = Polygon(words[-1], sequence)
        elif kind == "SNAP":
            sequence = rounded_rings(checked["target"].polygons[0])
            error = check_polygon(sequence)
            if error is not None:
                raise Rejected("invalid_result " + error)
            checked["defined"] = Polygon(words[-1], sequence)
        return checked

    def record_region(self, number, line, words, checked):
        kind = words[0]
        self.results.append(f"op {number} {line}")
        if kind in BINARY:
            first, second = checked["a"], checked["b"]
            region, graph, relation, iou = binary_result(kind, first, second)
            self.results.append(f"relation {relation} iou {iou:.6f}")
            self.results.append(f"crossings {len(graph.crossings)}")
            self.crossings += len(graph.crossings)
            for crossing in graph.crossings:
                direction = "in" if crossing.first.entering else "out"
                self.results.append(f"crossing {point_text(crossing.point)} {direction}")
        else:
            first = checked["defined"] if kind in DEFINITIONS else checked["a"]
            second = None
            region = Region([first.rings])
        self.regions[number] = region
        values = ResultValues(region.polygons, first, second)
        self.results.extend(values.lines())
        if kind not in BINARY:
            self.results.extend(property_lines(first, values.area))
        if kind == "CLIP":
            decision, count, vertices = crosscheck_clip(first, second, region.polygons)
            self.results.append(f"crosscheck {decision} rings {count} vertices {vertices}")
        identifier = str(number) + ":" + ":".join(words)
        self.areas.append(f"{identifier},{values.ring_count},{values.hole_count},"
                          f"{values.vertex_count},{values.area:.3f}")

    def record_location(self, number, line, words, target):
        point = int(words[2]), int(words[3])
        self.results.append(f"op {number} {line}")
        self.results.append("location " + locate(target.polygons, point))
        if target.operands is not None:
            first, second = target.operands
            self.results.append(f"operands a {operand_location(first, point)} "
                                f"b {operand_location(second, point)}")

    def record_render(self, number, words, target):
        parameters = [int(word) for word in words[2:]]
        operands = None
        if target.operands is not None:
            operands = tuple(polygon.rings for polygon in target.operands)
        lines, counts = render.grid(target.polygons, operands, *parameters)
        columns, rows = parameters[-2:]
        self.drawings.append(f"render {number} {words[1]} cols {columns} rows {rows} "
                             f"result {counts['#']} a {counts['a']} b {counts['b']} both {counts['+']}")
        self.drawings.extend(lines)

    def process(self):
        for number, line in enumerate(self.operations, 1):
            words = line.split(" ")
            kind = words[0]
            if kind in self.kind_totals:
                self.kind_totals[kind] += 1
            try:
                checked = self.check_operation(words)
            except Rejected as error:
                self.rejected_operations.append((number, str(error)))
                continue
            self.succeeded += 1
            self.kind_succeeded[kind] += 1
            if kind in DEFINITIONS:
                self.registry.define(checked["defined"])
                self.defined += 1
            if kind == "RENDER":
                self.record_render(number, words, checked["target"])
            elif kind == "LOCATE":
                self.record_location(number, line, words, checked["target"])
            else:
                self.record_region(number, line, words, checked)
        self.results.extend(self.summary_lines())

    def summary_lines(self):
        registry = self.registry
        result = [
            f"summary polygons {registry.block_count} valid {registry.valid_blocks} "
            f"invalid {len(registry.invalid)} defined {self.defined}",
            f"summary operations {len(self.operations)} succeeded {self.succeeded} "
            f"rejected {len(self.rejected_operations)}",
            f"summary crossings {self.crossings}",
        ]
        result.extend(f"kind {kind} {self.kind_totals[kind]} {self.kind_succeeded[kind]}" for kind in KINDS)
        return result

    def write(self):
        rejected = self.registry.invalid
        rejections = [f"rejections {len(rejected) + len(self.rejected_operations)}"]
        rejections.extend(f"polygon {name} {reason}" for name, reason in rejected)
        rejections.extend(f"op {number} {reason}" for number, reason in self.rejected_operations)
        directory = Path("output")
        directory.mkdir(exist_ok=True)
        outputs = (("results.txt", self.results), ("areas.csv", self.areas),
                   ("render.txt", self.drawings), ("rejections.txt", rejections))
        for filename, lines in outputs:
            with (directory / filename).open("w", encoding="ascii", newline="\n") as destination:
                for line in lines:
                    destination.write(line + "\n")


def main():
    processor = Processor()
    processor.process()
    processor.write()


if __name__ == "__main__":
    main()
