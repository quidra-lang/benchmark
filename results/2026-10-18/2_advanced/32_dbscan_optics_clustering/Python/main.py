import math
import string
from collections import Counter

from dataset import read_params, read_points
from dbscan import NOISE, dbscan
from grid_index import GridIndex, brute_force_counts, squared_distance
from optics import INF, core_distances, optics_ordering
from report import ari_text, fraction_text, framed, root_text, write_lines


LETTERS = string.ascii_uppercase + string.ascii_lowercase
DBSCAN_KIND = "dbscan"
EXTRACT_KIND = "extract"
XI_KIND = "xi"


def label_char(label):
    if label == NOISE:
        return "."
    if label < len(LETTERS):
        return LETTERS[label]
    return "#"


def value_text(value):
    return "-" if value == INF else str(value)


def optional_root(value):
    return "-" if value == INF else root_text(value)


def optional_text(value):
    return "-" if value is None else str(value)


def joined(values):
    return " ".join(str(value) for value in values)


def check_text(passed):
    return "ok" if passed else "mismatch"


def condition_text(passed):
    return "ok" if passed else "fail"


def suggested_radius(value):
    radius = math.isqrt(value)
    if radius * radius < value:
        radius += 1
    return max(radius, 1)


def pair_count(count):
    return count * (count - 1) // 2


def join_parts(parts):
    lines = []
    for part in parts:
        if lines:
            lines.append("")
        lines.extend(part)
    return lines


def neighbor_distances(points, count):
    rows = []
    for point in points:
        distances = sorted(
            squared_distance(point, other) for other in points if other is not point
        )
        rows.append(distances[:count])
    return rows


class Curve:
    def __init__(self, points, values):
        count = len(points)
        self.order = sorted(range(count), key=lambda index: (-values[index], points[index].id))
        self.values = [values[index] for index in self.order]
        first = self.values[0]
        last = self.values[-1]
        crosses = [
            abs((count - 1) * (value - first) - (last - first) * rank)
            for rank, value in enumerate(self.values)
        ]
        self.cross = max(crosses)
        self.knee = crosses.index(self.cross)
        self.eps = suggested_radius(self.values[self.knee])


class GridSummary:
    def __init__(self, points, eps):
        grid = GridIndex(points, eps)
        self.eps = eps
        self.neighborhoods = []
        self.candidates = 0
        for index in range(len(points)):
            neighbors, candidates = grid.neighborhood(index)
            self.neighborhoods.append(neighbors)
            self.candidates += candidates
        brute = brute_force_counts(points, eps)
        total = sum(len(neighbors) for neighbors in self.neighborhoods)
        self.cells = len(grid.cells)
        self.busiest = grid.busiest_cell()
        self.pairs = (total - len(points)) // 2
        self.brute_pairs = (sum(brute) - len(points)) // 2
        self.consistent = all(
            len(neighbors) == count for neighbors, count in zip(self.neighborhoods, brute)
        )
        sizes = Counter(len(members) for members in grid.cells.values())
        self.occupancy = sorted(sizes.items())

    def lines(self):
        gx, gy, size = self.busiest
        occupancy = " ".join(f"{size}:{count}" for size, count in self.occupancy)
        return [
            f"eps {self.eps} cells {self.cells} busiest {gx} {gy} {size}"
            f" candidates {self.candidates} pairs {self.pairs}"
            f" brute_pairs {self.brute_pairs} {check_text(self.consistent)}",
            "  occupancy " + occupancy,
        ]


class Setting:
    def __init__(self, name, kind, radius, labels, core):
        self.name = name
        self.kind = kind
        self.radius = radius
        self.labels = labels
        self.core = core
        self.count = max(labels) + 1
        self.members = [[] for _ in range(self.count)]
        for index, label in enumerate(labels):
            if label != NOISE:
                self.members[label].append(index)
        self.noise = labels.count(NOISE)
        self.core_count = sum(
            1 for label, is_core in zip(labels, core) if label != NOISE and is_core
        )
        self.border_count = len(labels) - self.noise - self.core_count


def extract_clusters(ordering, reach, core, radius):
    limit = radius * radius
    labels = [NOISE] * len(ordering)
    cluster = -1
    for index in ordering:
        if reach[index] > limit:
            if core[index] <= limit:
                cluster += 1
                labels[index] = cluster
        else:
            labels[index] = cluster
    return labels, [value <= limit for value in core]


class DownArea:
    def __init__(self, start, end):
        self.start = start
        self.end = end
        self.high = 0


class XiMethod:
    def __init__(self, reach, params):
        self.reach = reach
        self.size = len(reach) - 1
        self.alpha = (params.xi_v - params.xi_u) ** 2
        self.beta = params.xi_v ** 2
        self.min_pts = params.min_pts
        self.min_size = params.xi_min_size
        self.steep_up = []
        self.steep_down = []
        self.up = []
        self.down = []
        for position in range(self.size):
            current = reach[position]
            following = reach[position + 1]
            defined = current != INF or following != INF
            self.steep_up.append(defined and self.xle(current, following))
            self.steep_down.append(defined and self.xle(following, current))
            self.up.append(current < following)
            self.down.append(current > following)
        self.areas = []
        self.clusters = []
        self.scan()
        self.position_labels, self.cluster_labels = self.assign_labels()
        self.parents = [self.parent(number) for number in range(len(self.clusters))]

    def xle(self, a, b):
        if b == INF:
            return True
        if a == INF:
            return False
        return self.beta * a <= self.alpha * b

    def region_end(self, start, steep, reverse):
        end = start
        flat = 0
        for position in range(start, self.size):
            if steep[position]:
                end = position
                flat = 0
            elif reverse[position]:
                break
            else:
                flat += 1
                if flat > self.min_pts:
                    break
        return end

    def scan(self):
        reach = self.reach
        down_areas = []
        index = 0
        mib = 0
        for start in range(self.size):
            if start < index or not (self.steep_up[start] or self.steep_down[start]):
                continue
            mib = max(mib, max(reach[index:start + 1]))
            if mib == INF:
                down_areas = []
            else:
                down_areas = [area for area in down_areas if self.xle(mib, reach[area.start])]
                for area in down_areas:
                    area.high = max(area.high, mib)
            if self.steep_down[start]:
                end = self.region_end(start, self.steep_down, self.up)
                self.areas.append(("down", start, end))
                down_areas.append(DownArea(start, end))
                index = end + 1
                mib = reach[index]
            else:
                end = self.region_end(start, self.steep_up, self.down)
                self.areas.append(("up", start, end))
                index = end + 1
                mib = reach[index]
                candidates = []
                for area in down_areas:
                    candidate = self.candidate(area, start, end)
                    if candidate is not None:
                        candidates.append(candidate)
                self.clusters.extend(reversed(candidates))

    def candidate(self, area, up_start, up_end):
        reach = self.reach
        start = area.start
        end = up_end
        if not self.xle(area.high, reach[end + 1]):
            return None
        top = reach[area.start]
        if self.xle(reach[end + 1], top):
            while reach[start + 1] > reach[end + 1] and start < area.end:
                start += 1
        elif self.xle(top, reach[end + 1]):
            while reach[end - 1] > top and end > up_start:
                end -= 1
        if end - start + 1 >= self.min_size and start <= area.end and end >= up_start:
            return start, end
        return None

    def assign_labels(self):
        position_labels = [NOISE] * self.size
        cluster_labels = []
        next_label = 0
        for start, end in self.clusters:
            if all(label == NOISE for label in position_labels[start:end + 1]):
                for position in range(start, end + 1):
                    position_labels[position] = next_label
                cluster_labels.append(next_label)
                next_label += 1
            else:
                cluster_labels.append(None)
        return position_labels, cluster_labels

    def parent(self, number):
        start, end = self.clusters[number]
        size = end - start + 1
        best = None
        best_size = 0
        for other, (other_start, other_end) in enumerate(self.clusters):
            other_size = other_end - other_start + 1
            if other == number or other_start > start or end > other_end:
                continue
            if other_size < size or (other_size == size and other < number):
                continue
            if best is None or other_size < best_size:
                best = other
                best_size = other_size
        return best

    def walls(self, number):
        start, end = self.clusters[number]
        inner = [value for value in self.reach[start + 1:end + 1] if value != INF]
        valley = min(inner) if inner else INF
        return self.reach[start], self.reach[end + 1], valley


def turn(origin, first, second):
    return (first.x - origin.x) * (second.y - origin.y) - (first.y - origin.y) * (second.x - origin.x)


def half_hull(ordered):
    chain = []
    for point in ordered:
        while len(chain) >= 2 and turn(chain[-2], chain[-1], point) <= 0:
            chain.pop()
        chain.append(point)
    return chain


def convex_hull(members):
    ordered = sorted(members, key=lambda point: (point.x, point.y))
    if len(ordered) <= 2:
        return ordered
    lower = half_hull(ordered)
    upper = half_hull(reversed(ordered))
    return lower[:-1] + upper[:-1]


def doubled_area(vertices):
    total = 0
    for position, vertex in enumerate(vertices):
        following = vertices[(position + 1) % len(vertices)]
        total += vertex.x * following.y - following.x * vertex.y
    return abs(total)


def half_text(doubled):
    return f"{doubled // 2}.{5 if doubled % 2 else 0}"


def cluster_lines(points, setting, label):
    members = [points[index] for index in setting.members[label]]
    size = len(members)
    core = sum(1 for index in setting.members[label] if setting.core[index])
    sum_x = sum(point.x for point in members)
    sum_y = sum(point.y for point in members)
    medoid = min(
        members,
        key=lambda point: (
            (size * point.x - sum_x) ** 2 + (size * point.y - sum_y) ** 2, point.id
        ),
    )
    min_x = min(point.x for point in members)
    max_x = max(point.x for point in members)
    min_y = min(point.y for point in members)
    max_y = max(point.y for point in members)
    area = (max_x - min_x + 1) * (max_y - min_y + 1)
    hull = convex_hull(members)
    diameter = max(squared_distance(first, second) for first in hull for second in hull)
    return [
        f"cluster {label} {label_char(label)} size {size} core {core} border {size - core}"
        f" centroid {fraction_text(sum_x, size)} {fraction_text(sum_y, size)}"
        f" medoid {medoid.id}",
        f"  bbox {min_x} {min_y} {max_x} {max_y} area {area}"
        f" density {fraction_text(size, area)}",
        f"  hull {len(hull)} hull_area {half_text(doubled_area(hull))}"
        f" diameter_sq {diameter} diameter {root_text(diameter)}",
    ]


def adjusted_rand(first, second):
    pairs = sum(pair_count(count) for count in Counter(zip(first, second)).values())
    first_pairs = sum(pair_count(count) for count in Counter(first).values())
    second_pairs = sum(pair_count(count) for count in Counter(second).values())
    total = pair_count(len(first))
    numerator = 2 * (total * pairs - first_pairs * second_pairs)
    denominator = total * (first_pairs + second_pairs) - 2 * first_pairs * second_pairs
    if denominator == 0:
        return 1, 1
    return numerator, denominator


class Analysis:
    def __init__(self, points, params):
        self.points = points
        self.params = params
        self.min_pts = params.min_pts
        self.k = params.min_pts - 1
        rows = neighbor_distances(points, 2 * params.min_pts)
        self.curves = [
            Curve(points, [row[rank] for row in rows]) for rank in range(2 * params.min_pts)
        ]
        self.curve = self.curves[self.k - 1]
        self.kdist = [row[self.k - 1] for row in rows]
        radii = sorted(set(params.eps_list) | {self.curve.eps, params.max_eps})
        self.grids = [GridSummary(points, eps) for eps in radii]
        self.neighborhoods = {grid.eps: grid.neighborhoods for grid in self.grids}
        self.settings = []
        for eps in params.eps_list:
            self.add_dbscan(f"db{eps}", eps)
        self.knee = self.add_dbscan(f"knee{self.curve.eps}", self.curve.eps)
        optics_neighborhoods = self.neighborhoods[params.max_eps]
        self.core_distance = core_distances(points, optics_neighborhoods, self.min_pts)
        self.ordering, self.reach, self.predecessor = optics_ordering(
            points, optics_neighborhoods, self.core_distance
        )
        for eps in params.extract_eps:
            labels, core = extract_clusters(self.ordering, self.reach, self.core_distance, eps)
            self.settings.append(Setting(f"op{eps}", EXTRACT_KIND, eps, labels, core))
        self.positions = [self.reach[index] for index in self.ordering] + [INF]
        self.xi = XiMethod(self.positions, params)
        labels = [NOISE] * len(points)
        for position, index in enumerate(self.ordering):
            labels[index] = self.xi.position_labels[position]
        core = [value != INF for value in self.core_distance]
        self.xi_setting = Setting("xi", XI_KIND, params.max_eps, labels, core)
        self.settings.append(self.xi_setting)
        width = params.map_width
        height = params.map_height
        min_x = min(point.x for point in points)
        max_x = max(point.x for point in points)
        min_y = min(point.y for point in points)
        max_y = max(point.y for point in points)
        self.map_cells = [
            (
                (point.x - min_x) * width // (max_x - min_x + 1),
                (max_y - point.y) * height // (max_y - min_y + 1),
            )
            for point in points
        ]

    def add_dbscan(self, name, eps):
        labels, core = dbscan(self.neighborhoods[eps], self.min_pts)
        setting = Setting(name, DBSCAN_KIND, eps, labels, core)
        self.settings.append(setting)
        return setting

    def dbscan_settings(self):
        return [setting for setting in self.settings if setting.kind == DBSCAN_KIND]

    def labels_lines(self):
        lines = ["id," + ",".join(setting.name for setting in self.settings)]
        for index, point in enumerate(self.points):
            labels = [str(setting.labels[index]) for setting in self.settings]
            lines.append(",".join([str(point.id)] + labels))
        return lines

    def optics_lines(self):
        lines = ["order,id,core_sq,reach_sq,reach,predecessor"]
        for position, index in enumerate(self.ordering, 1):
            reach = self.reach[index]
            predecessor = self.predecessor[index]
            predecessor_id = None if predecessor is None else self.points[predecessor].id
            lines.append(
                f"{position},{self.points[index].id},{value_text(self.core_distance[index])},"
                f"{value_text(reach)},{optional_root(reach)},{optional_text(predecessor_id)}"
            )
        return lines

    def kdist_lines(self):
        curve = self.curve
        lines = [f"k_distance k {self.k} points {len(self.points)}", "rank id kdist_sq kdist"]
        for rank, (index, value) in enumerate(zip(curve.order, curve.values), 1):
            lines.append(f"{rank} {self.points[index].id} {value} {root_text(value)}")
        knee_value = curve.values[curve.knee]
        lines.append("")
        lines.append(
            f"knee rank {curve.knee + 1} id {self.points[curve.order[curve.knee]].id}"
            f" kdist_sq {knee_value} kdist {root_text(knee_value)} cross {curve.cross}"
        )
        lines.append(f"suggested_eps {curve.eps}")
        lines.append("")
        lines.append("knee_table")
        for rank, row in enumerate(self.curves, 1):
            lines.append(
                f"k {rank} rank {row.knee + 1} id {self.points[row.order[row.knee]].id}"
                f" kdist_sq {row.values[row.knee]} eps {row.eps}"
            )
        lines.append("")
        lines.append("core_check")
        for setting in self.dbscan_settings():
            limit = setting.radius * setting.radius
            core = sum(1 for value in self.kdist if value <= limit)
            grid_core = sum(1 for is_core in setting.core if is_core)
            lines.append(
                f"eps {setting.radius} core {core} non_core {len(self.points) - core}"
                f" grid_core {grid_core} {check_text(core == grid_core)}"
            )
        defined = [
            index for index, value in enumerate(self.core_distance) if value != INF
        ]
        consistent = all(self.core_distance[index] == self.kdist[index] for index in defined)
        lines.append(
            f"optics max_eps {self.params.max_eps} core {len(defined)} {check_text(consistent)}"
        )
        return lines

    def header_lines(self):
        return [
            f"points {len(self.points)} min_pts {self.min_pts}",
            "settings " + " ".join(setting.name for setting in self.settings),
        ]

    def grid_lines(self):
        lines = ["grid"]
        for grid in self.grids:
            lines.extend(grid.lines())
        return lines

    def setting_lines(self, setting):
        lines = [
            f"setting {setting.name} eps {setting.radius} clusters {setting.count}"
            f" noise {setting.noise} core {setting.core_count} border {setting.border_count}"
        ]
        for label in range(setting.count):
            lines.extend(cluster_lines(self.points, setting, label))
        if setting.kind == DBSCAN_KIND:
            lines.extend(self.check_lines(setting))
        return lines

    def check_lines(self, setting):
        labels = setting.labels
        core = setting.core
        linked = True
        supported = True
        separated = True
        isolated = 0
        ambiguous = []
        for index, neighbors in enumerate(self.neighborhoods[setting.radius]):
            label = labels[index]
            core_labels = [labels[other] for other in neighbors if core[other]]
            if core[index]:
                if any(other != label for other in core_labels):
                    linked = False
            elif label != NOISE:
                if label not in core_labels:
                    supported = False
                others = sorted(set(other for other in core_labels if other != label))
                if others:
                    ambiguous.append(f"  {self.points[index].id} cluster {label} also {joined(others)}")
            else:
                if core_labels:
                    separated = False
                if len(neighbors) == 1:
                    isolated += 1
        return [
            f"check {condition_text(linked)} {condition_text(supported)} {condition_text(separated)}",
            f"isolated {isolated}",
            f"ambiguous {len(ambiguous)}",
        ] + ambiguous

    def hierarchy_lines(self):
        ordered = sorted(self.dbscan_settings(), key=lambda setting: setting.radius)
        lines = ["hierarchy"]
        for smaller, larger in zip(ordered, ordered[1:]):
            lines.append(f"{smaller.name} -> {larger.name}")
            sources = [[] for _ in range(larger.count)]
            for cluster, members in enumerate(smaller.members):
                first_core = next(index for index in members if smaller.core[index])
                sources[larger.labels[first_core]].append(cluster)
            for label, clusters in enumerate(sources):
                lines.append(f"  {label} <- {joined(clusters) if clusters else '-'}")
        return lines

    def comparison_lines(self):
        lines = ["optics_vs_dbscan"]
        for extracted in self.settings:
            if extracted.kind != EXTRACT_KIND:
                continue
            matches = [
                setting for setting in self.dbscan_settings()
                if setting.radius == extracted.radius
            ]
            if not matches:
                continue
            reference = matches[0]
            labels = list(zip(extracted.labels, reference.labels))
            pairs = {
                pair for pair, is_core in zip(labels, extracted.core) if is_core
            }
            same = len(pairs) == len({first for first, _ in pairs}) == len({second for _, second in pairs})
            border_as_noise = sum(
                1 for first, second in labels if first == NOISE and second != NOISE
            )
            moved = "-"
            if same:
                mapping = dict(pairs)
                moved = sum(
                    1 for first, second in labels if first != NOISE and mapping[first] != second
                )
            lines.append(
                f"{extracted.name} {reference.name} core_partition {'same' if same else 'different'}"
                f" border_as_noise {border_as_noise} moved {moved}"
            )
        return lines

    def optics_summary_lines(self):
        components = []
        for index in self.ordering:
            if self.reach[index] == INF:
                components.append(0)
            components[-1] += 1
        core = sum(1 for value in self.core_distance if value != INF)
        return [
            f"optics max_eps {self.params.max_eps} core {core} components {len(components)}"
            f" singletons {components.count(1)} largest {max(components)}"
        ]

    def sweep_lines(self):
        max_eps = self.params.max_eps
        lines = [f"sweep max_eps {max_eps}", "eps clusters noise largest"]
        counts = []
        for eps in range(1, max_eps + 1):
            labels, _ = extract_clusters(self.ordering, self.reach, self.core_distance, eps)
            sizes = Counter(label for label in labels if label != NOISE)
            counts.append(max(labels) + 1)
            largest = max(sizes.values()) if sizes else 0
            lines.append(f"{eps} {counts[-1]} {labels.count(NOISE)} {largest}")
        stable = None
        run_start = 0
        for eps in range(1, max_eps + 1):
            if eps < max_eps and counts[eps] == counts[run_start]:
                continue
            length = eps - run_start
            if counts[run_start] >= 2 and (stable is None or length > stable[3]):
                stable = (counts[run_start], run_start + 1, eps, length)
            run_start = eps
        if stable is None:
            lines.append("stable -")
        else:
            lines.append(f"stable clusters {stable[0]} eps {stable[1]} {stable[2]} length {stable[3]}")
        return lines

    def xi_lines(self):
        xi = self.xi
        lines = [
            f"xi {self.params.xi_text} min_size {self.params.xi_min_size}"
            f" steep_areas {len(xi.areas)}"
        ]
        for kind, start, end in xi.areas:
            lines.append(f"{kind} {start + 1} {end + 1}")
        lines.append(f"xi_clusters {len(xi.clusters)}")
        for number, (start, end) in enumerate(xi.clusters):
            left, right, valley = xi.walls(number)
            lines.append(
                f"{number} start {start + 1} end {end + 1} size {end - start + 1}"
                f" label {optional_text(xi.cluster_labels[number])}"
                f" parent {optional_text(xi.parents[number])}"
                f" walls {optional_root(left)} {optional_root(right)} valley {optional_root(valley)}"
            )
        return lines

    def outlier_lines(self):
        knee = self.knee
        core_points = [index for index, is_core in enumerate(knee.core) if is_core]
        rows = []
        for index, label in enumerate(knee.labels):
            if label != NOISE:
                continue
            point = self.points[index]
            nearest = min(
                core_points,
                key=lambda other: (squared_distance(point, self.points[other]), self.points[other].id),
            )
            rows.append((squared_distance(point, self.points[nearest]), index, nearest))
        rows.sort(key=lambda row: (-row[0], self.points[row[1]].id))
        lines = [f"outliers {knee.name} count {len(rows)}"]
        for distance, index, nearest in rows:
            lines.append(
                f"{self.points[index].id} nearest_core {self.points[nearest].id}"
                f" cluster {knee.labels[nearest]} dist_sq {distance} dist {root_text(distance)}"
            )
        return lines

    def gap_lines(self):
        knee = self.knee
        lines = [f"gaps {knee.name}"]
        for first in range(knee.count):
            for second in range(first + 1, knee.count):
                best = None
                for index in knee.members[first]:
                    for other in knee.members[second]:
                        distance = squared_distance(self.points[index], self.points[other])
                        if best is None or distance < best[0]:
                            best = (distance, index, other)
                distance, index, other = best
                lines.append(
                    f"{first} {second} dist_sq {distance} dist {root_text(distance)}"
                    f" between {self.points[index].id} {self.points[other].id}"
                )
        return lines

    def contingency_lines(self):
        knee = self.knee
        xi = self.xi_setting
        table = [[0] * (xi.count + 1) for _ in range(knee.count + 1)]
        for row, column in zip(knee.labels, xi.labels):
            table[row + 1][column + 1] += 1
        lines = [f"contingency {knee.name} xi", "columns " + joined(range(-1, xi.count))]
        for row in range(-1, knee.count):
            lines.append(f"{row} {joined(table[row + 1])}")
        for column in range(xi.count):
            shared_counts = [table[row + 1][column + 1] for row in range(knee.count)]
            shared = max(shared_counts)
            row = shared_counts.index(shared)
            union = len(knee.members[row]) + len(xi.members[column]) - shared
            lines.append(
                f"match {column} {row} shared {shared} jaccard {fraction_text(shared, union)}"
            )
        return lines

    def ari_lines(self):
        lines = ["ari"]
        for position, first in enumerate(self.settings):
            for second in self.settings[position + 1:]:
                numerator, denominator = adjusted_rand(first.labels, second.labels)
                lines.append(f"{first.name} {second.name} {ari_text(numerator, denominator)}")
        return lines

    def clusters_lines(self):
        parts = [self.header_lines(), self.grid_lines()]
        parts.extend(self.setting_lines(setting) for setting in self.settings)
        parts.extend([
            self.hierarchy_lines(),
            self.comparison_lines(),
            self.optics_summary_lines(),
            self.sweep_lines(),
            self.xi_lines(),
            self.outlier_lines(),
            self.gap_lines(),
            self.contingency_lines(),
            self.ari_lines(),
        ])
        return join_parts(parts)

    def empty_grid(self):
        return [[[] for _ in range(self.params.map_width)] for _ in range(self.params.map_height)]

    def cluster_map(self, setting):
        cells = self.empty_grid()
        for index, (column, row) in enumerate(self.map_cells):
            cells[row][column].append(setting.labels[index])
        rows = []
        for cell_row in cells:
            characters = []
            for labels in cell_row:
                clusters = set(label for label in labels if label != NOISE)
                if not labels:
                    characters.append(" ")
                elif not clusters:
                    characters.append(".")
                elif len(clusters) == 1:
                    characters.append(label_char(clusters.pop()))
                else:
                    characters.append("*")
            rows.append("".join(characters))
        return rows

    def kind_map(self):
        knee = self.knee
        cells = self.empty_grid()
        for index, (column, row) in enumerate(self.map_cells):
            if knee.core[index]:
                kind = "#"
            elif knee.labels[index] != NOISE:
                kind = "+"
            else:
                kind = "."
            cells[row][column].append(kind)
        rows = []
        for cell_row in cells:
            characters = []
            for kinds in cell_row:
                if not kinds:
                    characters.append(" ")
                elif "#" in kinds:
                    characters.append("#")
                elif "+" in kinds:
                    characters.append("+")
                else:
                    characters.append(".")
            rows.append("".join(characters))
        return rows

    def kdist_plot(self):
        curve = self.curve
        width = self.params.kdist_width
        height = self.params.kdist_height
        count = len(self.points)
        top = curve.values[0]
        heights = []
        knee_column = 0
        for column in range(width):
            first = column * count // width
            last = (column + 1) * count // width
            heights.append(math.isqrt(height * height * curve.values[first] // top))
            if first <= curve.knee < last:
                knee_column = column
        rows = []
        for row in range(height):
            characters = []
            for column in range(width):
                if height - row <= heights[column]:
                    characters.append("#")
                elif column == knee_column:
                    characters.append(":")
                else:
                    characters.append(" ")
            rows.append("".join(characters))
        return rows, knee_column

    def reachability_lines(self):
        width = self.params.plot_width
        top = max(value for value in self.positions if value != INF)
        columns = [setting for setting in self.settings if setting.kind == EXTRACT_KIND]
        columns.append(self.xi_setting)
        lines = [
            f"reachability width {width} max_reach {root_text(top)}"
            f" columns {' '.join(setting.name for setting in columns)}"
        ]
        for position, index in enumerate(self.ordering, 1):
            reach = self.reach[index]
            if reach == INF:
                bar = "-" * width
            else:
                bar = "#" * math.isqrt(width * width * reach // top)
            characters = "".join(label_char(setting.labels[index]) for setting in columns)
            lines.append(
                f"{position:>4} {self.points[index].id:>5} {optional_root(reach):>7}"
                f" {characters} |{bar}"
            )
        return lines

    def maps_lines(self):
        lines = []
        for setting in self.settings:
            lines.append(f"map {setting.name} clusters {setting.count} noise {setting.noise}")
            lines.extend(framed(self.cluster_map(setting), self.params.map_width))
            legend = [
                f"{label_char(label)}={len(members)}"
                for label, members in enumerate(setting.members)
            ]
            lines.append("legend " + (" ".join(legend) if legend else "-"))
            lines.append("")
        lines.append(f"kinds {self.knee.name}")
        lines.extend(framed(self.kind_map(), self.params.map_width))
        lines.append("")
        rows, knee_column = self.kdist_plot()
        lines.append(
            f"kdist_plot k {self.k} max {root_text(self.curve.values[0])}"
            f" knee_column {knee_column + 1}"
        )
        lines.extend(framed(rows, self.params.kdist_width))
        lines.append("")
        lines.extend(self.reachability_lines())
        return lines


def main():
    points = read_points()
    params = read_params()
    analysis = Analysis(points, params)
    write_lines("labels.csv", analysis.labels_lines())
    write_lines("optics_order.csv", analysis.optics_lines())
    write_lines("kdist.txt", analysis.kdist_lines())
    write_lines("clusters.txt", analysis.clusters_lines())
    write_lines("maps.txt", analysis.maps_lines())


if __name__ == "__main__":
    main()
