"""Run the deterministic spatial-index laboratory from input/ to output/."""

from collections import Counter, defaultdict
from heapq import heappop, heappush

import dataset
import grid
import kdtree
import quadtree
import report
import rtree


POINT_STRUCTURES = ("kdtree", "quadtree", "rtree", "str", "grid")
RECTANGLE_STRUCTURES = ("rtree_rect", "str_rect")
RTREE_STRUCTURES = ("rtree", "str", "rtree_rect", "str_rect")
SEARCH_COMMANDS = (
    "RANGE", "RADIUS", "KNN", "WINDOWCOUNT", "CONTAINS", "NEAREST", "JOIN"
)


class NodeView:
    """One search node, with the exact region and ordered contents of section 8."""

    def __init__(self, region, held, children, source, mark="root", depth=0):
        self.region = region
        self.held = tuple(held)
        self.children = tuple(children)
        self.source = source
        self.mark = mark
        self.depth = depth
        self.count = len(self.held) + sum(child.count for child in self.children)


def kd_child_regions(node, region):
    x1, y1, x2, y2 = region
    if node.axis == 0:
        split = node.point[1]
        return (x1, y1, split, y2), (split, y1, x2, y2)
    split = node.point[2]
    return (x1, y1, x2, split), (x1, split, x2, y2)


def kd_view(root, world):
    views = {}
    pending = [(root, (0, 0, world - 1, world - 1), "root", 0, False)]
    while pending:
        node, region, mark, depth, ready = pending.pop()
        if ready:
            children = [
                views[child] for child in (node.left, node.right) if child is not None
            ]
            views[node] = NodeView(region, [node.point], children, node, mark, depth)
            continue
        pending.append((node, region, mark, depth, True))
        left_region, right_region = kd_child_regions(node, region)
        if node.right is not None:
            pending.append((node.right, right_region, "R", depth + 1, False))
        if node.left is not None:
            pending.append((node.left, left_region, "L", depth + 1, False))
    return views[root]


def quad_view(node, mark="root", depth=0):
    region = node.x, node.y, node.x + node.size - 1, node.y + node.size - 1
    children = [
        quad_view(child, name, depth + 1)
        for name, child in zip(quadtree.CHILD_NAMES, node.children)
    ]
    return NodeView(region, node.points, children, node, mark, depth)


def rtree_view(node, objects, depth=0):
    if node.level == 0:
        held = [objects[entry.object_id] for entry in node.entries]
        children = []
    else:
        held = []
        children = [rtree_view(entry.child, objects, depth + 1) for entry in node.entries]
    return NodeView(node.box, held, children, node, depth=depth)


def grid_view(directory):
    cells = [
        NodeView(cell.box, cell.points, [], cell, depth=1)
        for cell in directory.cells
    ]
    world = directory.world
    return NodeView((0, 0, world - 1, world - 1), [], cells, directory)


def preorder(root):
    pending = [root]
    while pending:
        node = pending.pop()
        yield node
        pending.extend(reversed(node.children))


def object_box(obj):
    return rtree.point_box(obj) if len(obj) == 3 else obj[1:]


def point_distance(query, point):
    dx = point[1] - query[0]
    dy = point[2] - query[1]
    return dx * dx + dy * dy


def minimum_distance(query, box):
    x, y = query
    if x < box[0]:
        dx = box[0] - x
    elif x > box[2]:
        dx = x - box[2]
    else:
        dx = 0
    if y < box[1]:
        dy = box[1] - y
    elif y > box[3]:
        dy = y - box[3]
    else:
        dy = 0
    return dx * dx + dy * dy


def object_distance(query, obj):
    if len(obj) == 3:
        return point_distance(query, obj)
    return minimum_distance(query, object_box(obj))


def search_conditions(command, values):
    if command == "RANGE":
        box = values
        return (
            lambda region: rtree.intersects(region, box),
            lambda point: rtree.contains(box, rtree.point_box(point)),
        )
    if command == "RADIUS":
        x, y, radius = values
        query = x, y
        limit = radius * radius
        return (
            lambda region: minimum_distance(query, region) <= limit,
            lambda point: point_distance(query, point) <= limit,
        )
    x, y = values
    query_box = x, y, x, y
    return (
        lambda region: rtree.contains(region, query_box),
        lambda rectangle: rtree.contains(object_box(rectangle), query_box),
    )


def condition_search(root, region_condition, object_condition):
    answer = []
    nodes = tests = 0
    pending = [root]
    while pending:
        node = pending.pop()
        nodes += 1
        tests += len(node.held)
        for obj in node.held:
            if object_condition(obj):
                answer.append(obj[0])
        children = [child for child in node.children if region_condition(child.region)]
        pending.extend(reversed(children))
    answer.sort()
    return answer, nodes, tests


def window_count(root, window):
    answer = nodes = tests = 0
    pending = [root]
    while pending:
        node = pending.pop()
        nodes += 1
        if rtree.contains(window, node.region):
            answer += node.count
            continue
        tests += len(node.held)
        for point in node.held:
            if rtree.contains(window, rtree.point_box(point)):
                answer += 1
        children = [
            child for child in node.children if rtree.intersects(child.region, window)
        ]
        pending.extend(reversed(children))
    return answer, nodes, tests


def best_first(root, query, count):
    pending = [(minimum_distance(query, root.region), 0, 0, root)]
    next_serial = 1
    answer = []
    nodes = tests = 0
    while pending:
        distance, kind, tie, element = heappop(pending)
        if kind == 1:
            answer.append((element[0], distance))
            if len(answer) == count:
                break
            continue
        nodes += 1
        tests += len(element.held)
        for obj in element.held:
            heappush(pending, (object_distance(query, obj), 1, obj[0], obj))
        for child in element.children:
            key = minimum_distance(query, child.region), 0, next_serial, child
            heappush(pending, key)
            next_serial += 1
    return answer, nodes, tests


def spatial_join(point_root, rectangle_root):
    answer = []
    nodes = tests = 0
    pending = [(point_root, rectangle_root)]
    while pending:
        points, rectangles = pending.pop()
        nodes += 1
        if not points.children and not rectangles.children:
            tests += len(points.held) * len(rectangles.held)
            for point in points.held:
                for rectangle in rectangles.held:
                    if rtree.contains(object_box(rectangle), rtree.point_box(point)):
                        answer.append((rectangle[0], point[0]))
            continue
        if not points.children:
            children = [
                (points, child)
                for child in rectangles.children
                if rtree.intersects(points.region, child.region)
            ]
        elif not rectangles.children:
            children = [
                (child, rectangles)
                for child in points.children
                if rtree.intersects(child.region, rectangles.region)
            ]
        else:
            children = [
                (point_child, rectangle_child)
                for point_child in points.children
                for rectangle_child in rectangles.children
                if rtree.intersects(point_child.region, rectangle_child.region)
            ]
        pending.extend(reversed(children))
    answer.sort()
    return answer, nodes, tests


def brute_force(command, values, points, rectangles):
    if command in ("RANGE", "RADIUS", "CONTAINS"):
        region_condition, object_condition = search_conditions(command, values)
        objects = rectangles if command == "CONTAINS" else points
        return sorted(obj[0] for obj in objects if object_condition(obj))
    if command == "WINDOWCOUNT":
        return sum(rtree.contains(values, rtree.point_box(point)) for point in points)
    if command in ("KNN", "NEAREST"):
        x, y, count = values
        objects = rectangles if command == "NEAREST" else points
        ordered = sorted((object_distance((x, y), obj), obj[0]) for obj in objects)
        return [(identifier, distance) for distance, identifier in ordered[:count]]
    return sorted(
        (rectangle[0], point[0])
        for rectangle in rectangles
        for point in points
        if rtree.contains(object_box(rectangle), rtree.point_box(point))
    )


def structures_for(command):
    if command == "JOIN":
        return "rtree", "str"
    if command in ("CONTAINS", "NEAREST"):
        return RECTANGLE_STRUCTURES
    return POINT_STRUCTURES


def locate_kd(root, point):
    path = []
    node = root
    while node.point[0] != point[0]:
        if kdtree.key(point, node.axis) < kdtree.key(node.point, node.axis):
            path.append("L")
            node = node.left
        else:
            path.append("R")
            node = node.right
    return "".join(path) or "-"


def locate_quad(root, point):
    path = []
    node = root
    while node.children:
        destination = quadtree.destination(node, point)
        path.append(quadtree.CHILD_NAMES[destination])
        node = node.children[destination]
    return "/".join(path) or "-"


def locate_rtree(root, point):
    point_box = rtree.point_box(point)
    pending = [(root, ())]
    while pending:
        node, path = pending.pop()
        if node.level == 0:
            for position, entry in enumerate(node.entries, 1):
                if entry.object_id == point[0]:
                    return "/".join(map(str, path + (position,)))
        else:
            children = [
                (entry.child, path + (position,))
                for position, entry in enumerate(node.entries, 1)
                if rtree.contains(entry.box, point_box)
            ]
            pending.extend(reversed(children))
    raise ValueError("Point is absent from its R-tree")


def dump_kd(root):
    lines = []
    for view in preorder(root):
        prefix = "  " * (view.depth + 1)
        identifier, x, y = view.held[0]
        axis = "xy"[view.source.axis]
        lines.append(
            f"{prefix}{view.mark} {axis} {identifier} {x} {y} "
            f"box {report.ids(view.region)}"
        )
    return lines


def dump_quad(root):
    lines = []
    for view in preorder(root):
        node = view.source
        prefix = "  " * (view.depth + 1)
        square = f"{view.mark} {node.x} {node.y} {node.size}"
        if view.children:
            contents = f"node count {view.count}"
        else:
            contents = f"leaf {report.ids(point[0] for point in view.held)}"
        lines.append(f"{prefix}{square} {contents}")
    return lines


def dump_rtree(root):
    lines = []
    for view in preorder(root):
        prefix = "  " * (view.depth + 1)
        box = report.ids(view.region)
        if view.source.level == 0:
            entries = report.ids(obj[0] for obj in view.held)
            lines.append(f"{prefix}leaf {box} ids {entries}")
        else:
            lines.append(
                f"{prefix}node {view.source.level} {box} "
                f"entries {len(view.source.entries)}"
            )
    return lines


def kd_statistics(root):
    depths = defaultdict(lambda: [0, 0, 0])
    depth_sum = 0
    for view in preorder(root):
        row = depths[view.depth]
        row[0] += 1
        if not view.children:
            row[1] += 1
        elif len(view.children) == 1:
            row[2] += 1
        depth_sum += view.depth
    height = max(depths) + 1
    nodes = sum(row[0] for row in depths.values())
    leaves = sum(row[1] for row in depths.values())
    one_child = sum(row[2] for row in depths.values())
    average = report.fraction(depth_sum, nodes)
    lines = [
        f"kdtree height {height} ideal {nodes.bit_length()} nodes {nodes} "
        f"leaves {leaves} one_child {one_child} depth_sum {depth_sum} avg_depth {average}"
    ]
    for depth in range(height):
        count, leaf_count, single_count = depths[depth]
        lines.append(
            f"  depth {depth} nodes {count} leaves {leaf_count} one_child {single_count}"
        )
    return lines


def quad_statistics(root, capacity):
    depths = defaultdict(lambda: [0, 0, 0])
    empty = maximum = 0
    for view in preorder(root):
        row = depths[view.depth]
        if view.children:
            row[0] += 1
        else:
            count = len(view.held)
            row[1] += 1
            row[2] += count
            empty += count == 0
            maximum = max(maximum, count)
    height = max(depths) + 1
    internal = sum(row[0] for row in depths.values())
    leaves = sum(row[1] for row in depths.values())
    fill = report.fraction(root.count, leaves * capacity)
    lines = [
        f"quadtree height {height} internal {internal} leaves {leaves} "
        f"empty {empty} max_leaf {maximum} fill {fill}"
    ]
    for depth in range(height):
        internal_count, leaf_count, point_count = depths[depth]
        lines.append(
            f"  depth {depth} internal {internal_count} "
            f"leaves {leaf_count} points {point_count}"
        )
    return lines


def rtree_statistics(name, root, maximum, minimum):
    levels = defaultdict(list)
    entries = 0
    for view in preorder(root):
        levels[view.source.level].append(view)
        entries += len(view.source.entries)
    height = root.source.level + 1
    nodes = sum(len(group) for group in levels.values())
    leaves = len(levels[0])
    fill = report.fraction(entries, nodes * maximum)
    lines = [
        f"{name} height {height} nodes {nodes} leaves {leaves} entries {entries} fill {fill}"
    ]
    for level in range(height - 1, -1, -1):
        group = levels[level]
        sizes = [len(view.source.entries) for view in group]
        area_sum = sum(rtree.area(view.region) for view in group)
        overlap_sum = 0
        for first in range(len(group) - 1):
            for second in range(first + 1, len(group)):
                overlap_sum += rtree.overlap(group[first].region, group[second].region)
        under = sum(size < minimum for size in sizes)
        lines.append(
            f"  level {level} nodes {len(group)} entries {sum(sizes)} "
            f"min {min(sizes)} max {max(sizes)} under {under} "
            f"area {area_sum} overlap {overlap_sum}"
        )
    return lines


def grid_statistics(root):
    occupancy = Counter(len(cell.held) for cell in root.children)
    cells = len(root.children)
    used = cells - occupancy.get(0, 0)
    sequence = " ".join(f"{count}:{occupancy[count]}" for count in sorted(occupancy))
    return [
        f"grid cells {cells} used {used} max {max(occupancy)}",
        f"  occupancy {sequence}",
    ]


def visits_summary(totals):
    lines = ["visits"]
    for command in SEARCH_COMMANDS:
        if command not in totals:
            continue
        structures = structures_for(command)
        command_totals = totals[command]
        for name in structures:
            queries, nodes, tests, maximum = command_totals[name]
            mean = report.fraction(nodes, queries)
            lines.append(
                f"{command} {name} queries {queries} nodes {nodes} tests {tests} "
                f"max_nodes {maximum} mean_nodes {mean}"
            )
        positions = {name: position for position, name in enumerate(structures)}
        ranking = sorted(
            structures,
            key=lambda name: (
                command_totals[name][1], command_totals[name][2], positions[name]
            ),
        )
        lines.append(f"rank {command} {' '.join(ranking)}")
    return lines


class Laboratory:
    def __init__(self, points, rectangles, parameters):
        self.points = {point[0]: point for point in points}
        self.rectangles = {rectangle[0]: rectangle for rectangle in rectangles}
        self.parameters = parameters
        world = parameters["world"]
        self.kd_root = kdtree.build(points)
        self.quad_root = quadtree.build(points, world, parameters["bucket"])
        self.grid = grid.Grid(world, parameters["cell_size"], points)
        self.rtrees = {}
        for name in RTREE_STRUCTURES:
            objects = rectangles if name in RECTANGLE_STRUCTURES else points
            entries = [rtree.Entry(object_box(obj), object_id=obj[0]) for obj in objects]
            self.rtrees[name] = rtree.build(
                entries,
                parameters["maximum"],
                parameters["minimum"],
                bulk=name in ("str", "str_rect"),
            )
        self.views = {}
        self.refresh_point_views()
        for name in RECTANGLE_STRUCTURES:
            self.views[name] = rtree_view(self.rtrees[name].root, self.rectangles)
        self.answers = []
        self.visits = ["query,command,structure,nodes,tests"]
        self.join_rows = ["query,rect,point"]
        self.structures = []
        self.statistics = []
        self.visit_totals = {}
        self.snapshot_number = 0
        self.record_snapshot(0)

    def refresh_point_views(self):
        self.views["kdtree"] = kd_view(self.kd_root, self.parameters["world"])
        self.views["quadtree"] = quad_view(self.quad_root)
        for name in ("rtree", "str"):
            self.views[name] = rtree_view(self.rtrees[name].root, self.points)
        self.views["grid"] = grid_view(self.grid)

    def record_snapshot(self, query):
        header = (
            f"snapshot {self.snapshot_number} query {query} "
            f"points {len(self.points)} rects {len(self.rectangles)}"
        )
        if self.structures:
            self.structures.append("")
            self.statistics.append("")
        self.structures.extend([header, "kdtree"])
        self.structures.extend(dump_kd(self.views["kdtree"]))
        self.structures.append("quadtree")
        self.structures.extend(dump_quad(self.views["quadtree"]))
        self.statistics.append(header)
        self.statistics.extend(kd_statistics(self.views["kdtree"]))
        self.statistics.extend(
            quad_statistics(self.views["quadtree"], self.parameters["bucket"])
        )
        for name in RTREE_STRUCTURES:
            self.structures.append(name)
            self.structures.extend(dump_rtree(self.views[name]))
            self.statistics.extend(
                rtree_statistics(
                    name,
                    self.views[name],
                    self.parameters["maximum"],
                    self.parameters["minimum"],
                )
            )
        self.statistics.extend(grid_statistics(self.views["grid"]))

    def search_structure(self, name, command, values):
        root = self.views[name]
        if command in ("RANGE", "RADIUS", "CONTAINS"):
            return condition_search(root, *search_conditions(command, values))
        if command == "WINDOWCOUNT":
            return window_count(root, values)
        if command == "JOIN":
            return spatial_join(root, self.views[f"{name}_rect"])
        x, y, count = values
        return best_first(root, (x, y), count)

    def record_visit(self, query, command, name, nodes, tests):
        self.visits.append(f"{query},{command},{name},{nodes},{tests}")
        totals = self.visit_totals.setdefault(command, {})
        row = totals.setdefault(name, [0, 0, 0, 0])
        row[0] += 1
        row[1] += nodes
        row[2] += tests
        row[3] = max(row[3], nodes)

    def process_search(self, query, command, values):
        expected = brute_force(
            command, values, self.points.values(), self.rectangles.values()
        )
        mismatches = []
        for name in structures_for(command):
            actual, nodes, tests = self.search_structure(name, command, values)
            self.record_visit(query, command, name, nodes, tests)
            if actual != expected:
                mismatches.append(name)
        check = "mismatch " + " ".join(mismatches) if mismatches else "ok"
        prefix = f"{query} {command} count"
        if command == "WINDOWCOUNT":
            line = f"{prefix} {expected} check {check}"
        elif command == "JOIN":
            line = f"{prefix} {len(expected)} check {check}"
            self.join_rows.extend(
                f"{query},{rectangle},{point}" for rectangle, point in expected
            )
        else:
            if command in ("KNN", "NEAREST"):
                sequence = report.distances(expected)
            else:
                sequence = report.ids(expected)
            line = f"{prefix} {len(expected)} ids {sequence} check {check}"
        self.answers.append(line)

    def process_locate(self, query, identifier):
        if identifier not in self.points:
            self.answers.append(f"{query} LOCATE {identifier} missing")
            return
        point = self.points[identifier]
        kd_position = locate_kd(self.kd_root, point)
        quad_position = locate_quad(self.quad_root, point)
        rtree_position = locate_rtree(self.rtrees["rtree"].root, point)
        str_position = locate_rtree(self.rtrees["str"].root, point)
        column, row = self.grid.position(point)
        self.answers.append(
            f"{query} LOCATE {identifier} kdtree {kd_position} quadtree {quad_position} "
            f"rtree {rtree_position} str {str_position} grid {column} {row}"
        )

    def process_insert(self, query, point):
        self.points[point[0]] = point
        self.kd_root = kdtree.insert(self.kd_root, point)
        quadtree.insert(self.quad_root, point, self.parameters["bucket"])
        for name in ("rtree", "str"):
            entry = rtree.Entry(rtree.point_box(point), object_id=point[0])
            self.rtrees[name].insert(entry)
        self.grid.insert(point)
        self.refresh_point_views()
        self.answers.append(f"{query} INSERT {point[0]} inserted points {len(self.points)}")

    def process_delete(self, query, identifier):
        point = self.points.get(identifier)
        if point is None:
            status = "missing"
        else:
            self.kd_root = kdtree.delete(self.kd_root, point)
            quadtree.delete(self.quad_root, point, self.parameters["bucket"])
            for name in ("rtree", "str"):
                self.rtrees[name].delete(point)
            self.grid.delete(point)
            del self.points[identifier]
            self.refresh_point_views()
            status = "deleted"
        self.answers.append(
            f"{query} DELETE {identifier} {status} points {len(self.points)}"
        )

    def process_commands(self, commands):
        for query, (command, values) in enumerate(commands, 1):
            if command in SEARCH_COMMANDS:
                self.process_search(query, command, values)
            elif command == "LOCATE":
                self.process_locate(query, values[0])
            elif command == "INSERT":
                self.process_insert(query, values)
            elif command == "DELETE":
                self.process_delete(query, values[0])
            elif command == "DUMP":
                self.snapshot_number += 1
                self.record_snapshot(query)
                self.answers.append(f"{query} DUMP snapshot {self.snapshot_number}")

    def write_outputs(self):
        statistics = self.statistics + [""] + visits_summary(self.visit_totals)
        files = {
            "answers.txt": self.answers,
            "visits.csv": self.visits,
            "join.csv": self.join_rows,
            "structures.txt": self.structures,
            "stats.txt": statistics,
        }
        for filename, lines in files.items():
            report.write_lines(f"output/{filename}", lines)


def main():
    points, rectangles, parameters, commands = dataset.read_dataset()
    laboratory = Laboratory(points, rectangles, parameters)
    laboratory.process_commands(commands)
    laboratory.write_outputs()


if __name__ == "__main__":
    main()
