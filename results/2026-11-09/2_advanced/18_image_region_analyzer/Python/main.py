import os
from fractions import Fraction
from operator import eq, ge, gt, le, lt, ne

import labeling
import morphology
import threshold
from pgm_reader import read_images
from report import decimal, hull_area_text, write_files


INPUT_DIR = "input"
OUTPUT_DIR = "output"
SYMBOLS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
ORIENTATIONS = ("none", "horizontal", "vertical", "falling", "rising")
DIRECTIONS = {
    4: ((1, 0), (0, -1), (-1, 0), (0, 1)),
    8: ((1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1)),
}
OPERATORS = {"<": lt, "<=": le, ">": gt, ">=": ge, "=": eq, "!=": ne}
OPERATIONS = {
    "erode": morphology.erode,
    "dilate": morphology.dilate,
    "open": morphology.opening,
    "close": morphology.closing,
}
MORPHOLOGY_SYMBOLS = {
    (True, True): "#",
    (False, True): "+",
    (True, False): "-",
    (False, False): ".",
}
CSV_HEADER = (
    "image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,"
    "perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,"
    "depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,"
    "solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,"
    "distance2,codes"
)


class Setting:
    def __init__(self, words):
        self.name = words[1]
        self.connectivity = int(words[2])
        self.threshold = words[3]
        self.polarity = words[4]
        self.operations = words[5:]

    def method(self):
        if self.threshold in ("otsu", "isodata"):
            return self.threshold
        return "fixed"


class Parameters:
    def __init__(self):
        self.otsu_top = 0
        self.sweep_step = 0
        self.isotropy = Fraction(0)
        self.bay_min = 0
        self.elements = {}
        self.settings = {}


class Condition:
    def __init__(self, feature, comparison, text):
        self.feature = feature
        self.comparison = comparison
        self.text = text
        self.value = text if feature == "orientation" else parse_rational(text)

    def holds(self, features):
        return OPERATORS[self.comparison](features[self.feature], self.value)

    def words(self):
        return f"{self.feature} {self.comparison} {self.text}"


class Rule:
    def __init__(self, name, conditions):
        self.name = name
        self.conditions = conditions

    def matches(self, features):
        return all(condition.holds(features) for condition in self.conditions)


class Rules:
    def __init__(self):
        self.filters = []
        self.classes = []
        self.flags = []

    def class_names(self):
        names = []
        for rule in self.classes:
            if rule.name not in names:
                names.append(rule.name)
        names.append("other")
        return names


class Hole:
    def __init__(self, number, pixels, owner):
        self.number = number
        self.pixels = pixels
        self.owner = owner

    def box(self):
        xs = [x for x, _ in self.pixels]
        ys = [y for _, y in self.pixels]
        return min(xs), min(ys), max(xs), max(ys)


class Region:
    def __init__(self, number, pixels):
        self.number = number
        self.pixels = pixels
        self.features = {}
        self.codes = []
        self.skeleton = set()
        self.hull_doubled = 0
        self.parent = None
        self.depth = 0
        self.children = []
        self.kept = False
        self.dropped_by = None
        self.class_name = "other"
        self.flags = []
        self.neighbor = None
        self.distance = 0


def parse_rational(text):
    if "/" in text:
        numerator, denominator = text.split("/")
        return Fraction(int(numerator), int(denominator))
    return Fraction(int(text))


def element_offsets(words):
    origin_x = int(words[4])
    origin_y = int(words[5])
    offsets = []
    for row_index, row in enumerate(words[6:]):
        for column_index, symbol in enumerate(row):
            if symbol == "#":
                offsets.append((column_index - origin_x, row_index - origin_y))
    return offsets


def read_parameters(path):
    parameters = Parameters()
    with open(path) as file:
        for line in file:
            words = line.split()
            if not words:
                continue
            keyword = words[0]
            if keyword == "otsu_top":
                parameters.otsu_top = int(words[1])
            elif keyword == "sweep":
                parameters.sweep_step = int(words[1])
            elif keyword == "isotropy":
                parameters.isotropy = parse_rational(words[1])
            elif keyword == "bay_min":
                parameters.bay_min = int(words[1])
            elif keyword == "element":
                parameters.elements[words[1]] = element_offsets(words)
            elif keyword == "image":
                parameters.settings[words[1]] = Setting(words)
    return parameters


def parse_conditions(words):
    return [
        Condition(words[index], words[index + 1], words[index + 2])
        for index in range(0, len(words), 3)
    ]


def read_rules(path):
    rules = Rules()
    with open(path) as file:
        for line in file:
            words = line.split()
            if not words:
                continue
            if words[0] == "filter":
                rules.filters.append(Condition(words[1], words[2], words[3]))
            elif words[0] == "class":
                rules.classes.append(Rule(words[1], parse_conditions(words[2:])))
            elif words[0] == "flag":
                rules.flags.append(Rule(words[1], parse_conditions(words[2:])))
    return rules


def count_foreground(mask):
    return sum(row.count(True) for row in mask)


def group_pixels(labels, count):
    groups = [[] for _ in range(count + 1)]
    for y, row in enumerate(labels):
        for x, label in enumerate(row):
            groups[label].append((x, y))
    return groups


def enclosed_components(mask, connectivity):
    height = len(mask)
    width = len(mask[0])
    background = [[not value for value in row] for row in mask]
    components = labeling.label_components(background, connectivity)
    enclosed = []
    for pixels in group_pixels(components.labels, components.count)[1:]:
        on_edge = any(
            x == 0 or y == 0 or x == width - 1 or y == height - 1 for x, y in pixels
        )
        if not on_edge:
            enclosed.append(pixels)
    return enclosed


def fill_holes(mask, connectivity):
    filled = [row[:] for row in mask]
    for pixels in enclosed_components(mask, connectivity):
        for x, y in pixels:
            filled[y][x] = True
    return filled


def cross(a, b, p):
    return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])


def squared_distance(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2


def corner_points(pixels):
    extents = {}
    for x, y in pixels:
        if y in extents:
            left, right = extents[y]
            extents[y] = (min(left, x), max(right, x))
        else:
            extents[y] = (x, x)
    points = []
    for y, (left, right) in extents.items():
        points.extend(((left, y), (left, y + 1), (right + 1, y), (right + 1, y + 1)))
    return points


def half_hull(points):
    chain = []
    for point in points:
        while len(chain) >= 2 and cross(chain[-2], chain[-1], point) <= 0:
            chain.pop()
        chain.append(point)
    return chain


def convex_hull(points):
    ordered = sorted(set(points))
    return half_hull(ordered)[:-1] + half_hull(ordered[::-1])[:-1]


def hull_edges(hull):
    return zip(hull, hull[1:] + hull[:1])


def doubled_area(hull):
    return abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in hull_edges(hull)))


def squared_width(hull, a, b):
    reach = max(abs(cross(a, b, p)) for p in hull)
    return Fraction(reach * reach, squared_distance(a, b))


def contains_center(hull, x, y):
    center = (2 * x + 1, 2 * y + 1)
    for a, b in hull_edges(hull):
        if cross((2 * a[0], 2 * a[1]), (2 * b[0], 2 * b[1]), center) < 0:
            return False
    return True


def orientation_name(u, v, anisotropic):
    if not anisotropic:
        return "none"
    if abs(v) >= abs(u):
        return "falling" if v > 0 else "rising"
    return "horizontal" if u > 0 else "vertical"


def box_distance(first, second):
    a = first.features
    b = second.features
    dx = a["x0"] + a["x1"] - b["x0"] - b["x1"]
    dy = a["y0"] + a["y1"] - b["y0"] - b["y1"]
    return dx * dx + dy * dy


def mean_text(total, count):
    return decimal(Fraction(total, count), 2) if count else "-"


def orientation_line(regions):
    parts = ["orientations"]
    for name in ORIENTATIONS:
        count = sum(1 for region in regions if region.features["orientation"] == name)
        parts.extend((name, str(count)))
    return " ".join(parts)


class ImageAnalysis:
    def __init__(self, image, setting, parameters):
        self.image = image
        self.setting = setting
        self.parameters = parameters
        self.width = image.width
        self.height = image.height
        self.connectivity = setting.connectivity
        self.complement = 12 - setting.connectivity
        self.histogram = threshold.Histogram(image)
        self.otsu = threshold.otsu(self.histogram)
        self.isodata_cutoff, self.isodata_iterations = threshold.isodata(self.histogram)
        self.cutoff = self.chosen_cutoff()
        self.initial = self.binarize(self.cutoff)
        self.final = self.initial
        self.morph_counts = []
        for operation in setting.operations:
            self.final = self.apply_operation(self.final, operation)
            self.morph_counts.append(count_foreground(self.final))
        self.sweep = self.threshold_sweep()
        self.label_regions()
        self.find_holes()
        self.find_parents()
        for region in self.regions:
            self.measure(region)

    def chosen_cutoff(self):
        if self.setting.threshold == "otsu":
            return self.otsu.cutoff
        if self.setting.threshold == "isodata":
            return self.isodata_cutoff
        return int(self.setting.threshold)

    def binarize(self, cutoff):
        if self.setting.polarity == "bright":
            return [[value > cutoff for value in row] for row in self.image.pixels]
        return [[value <= cutoff for value in row] for row in self.image.pixels]

    def apply_operation(self, mask, operation):
        if operation == "fill":
            return fill_holes(mask, self.complement)
        kind, name = operation.split(":")
        return OPERATIONS[kind](mask, self.parameters.elements[name])

    def threshold_sweep(self):
        results = []
        step = self.parameters.sweep_step
        for cutoff in range(step, self.image.maxval, step):
            mask = self.binarize(cutoff)
            components = labeling.label_components(mask, self.connectivity)
            results.append((cutoff, count_foreground(mask), components.count))
        return results

    def label_regions(self):
        result = labeling.label_components(self.final, self.connectivity)
        self.labels = result.labels
        self.provisional = result.provisional
        groups = group_pixels(result.labels, result.count)
        self.regions = [Region(number, groups[number]) for number in range(1, result.count + 1)]
        self.four_components = labeling.label_components(self.final, 4).count
        self.eight_components = labeling.label_components(self.final, 8).count
        self.bit_quad = labeling.bit_quad_euler(self.final, self.connectivity)

    def find_holes(self):
        self.holes = []
        self.hole_of = [[0] * self.width for _ in range(self.height)]
        for pixels in enclosed_components(self.final, self.complement):
            x, y = pixels[0]
            hole = Hole(len(self.holes) + 1, pixels, self.labels[y - 1][x])
            for x, y in pixels:
                self.hole_of[y][x] = hole.number
            self.holes.append(hole)

    def find_parents(self):
        for region in self.regions:
            x, y = region.pixels[0]
            if y >= 1 and self.hole_of[y - 1][x] > 0:
                owner = self.holes[self.hole_of[y - 1][x] - 1].owner
                region.parent = self.regions[owner - 1]
                region.depth = region.parent.depth + 1
                region.parent.children.append(region)

    def label_at(self, x, y):
        if 0 <= x < self.width and 0 <= y < self.height:
            return self.labels[y][x]
        return -1

    def measure(self, region):
        features = region.features
        self.measure_basics(region)
        self.measure_boundary(region)
        owned = [hole for hole in self.holes if hole.owner == region.number]
        features["holes"] = len(owned)
        features["hole_area"] = sum(len(hole.pixels) for hole in owned)
        features["euler"] = 1 - len(owned)
        features["depth"] = region.depth
        self.measure_moments(region)
        self.measure_shape(region)
        self.measure_hull(region)
        self.measure_skeleton(region)

    def measure_basics(self, region):
        features = region.features
        pixels = region.pixels
        area = len(pixels)
        values = [self.image.pixels[y][x] for x, y in pixels]
        x0 = min(x for x, _ in pixels)
        x1 = max(x for x, _ in pixels)
        y0 = min(y for _, y in pixels)
        y1 = max(y for _, y in pixels)
        sum_values = sum(values)
        sum_squares = sum(value * value for value in values)
        features["area"] = area
        features["x0"] = x0
        features["y0"] = y0
        features["x1"] = x1
        features["y1"] = y1
        features["width"] = x1 - x0 + 1
        features["height"] = y1 - y0 + 1
        touches = x0 == 0 or y0 == 0 or x1 == self.width - 1 or y1 == self.height - 1
        features["border"] = 1 if touches else 0
        features["mean"] = Fraction(sum_values, area)
        features["variance"] = Fraction(area * sum_squares - sum_values * sum_values, area * area)
        features["min"] = min(values)
        features["max"] = max(values)
        features["contrast"] = self.contrast(region, sum_values)

    def contrast(self, region, sum_values):
        surrounding = set()
        for x, y in region.pixels:
            for dx, dy in DIRECTIONS[8]:
                if self.label_at(x + dx, y + dy) == 0:
                    surrounding.add((x + dx, y + dy))
        if not surrounding:
            return Fraction(0)
        area = len(region.pixels)
        count = len(surrounding)
        sum_surrounding = sum(self.image.pixels[y][x] for x, y in surrounding)
        return Fraction(sum_values * count - sum_surrounding * area, area * count)

    def measure_boundary(self, region):
        features = region.features
        number = region.number
        area = len(region.pixels)
        neighbors = DIRECTIONS[self.complement]
        features["perimeter"] = sum(
            1 for x, y in region.pixels
            if any(self.label_at(x + dx, y + dy) != number for dx, dy in neighbors)
        )
        codes = self.chain_code(region)
        region.codes = codes
        if self.connectivity == 8:
            straight = sum(1 for code in codes if code % 2 == 0)
            diagonal = len(codes) - straight
        else:
            straight = len(codes)
            diagonal = 0
        features["chain"] = len(codes)
        features["straight"] = straight
        features["diagonal"] = diagonal
        features["turns"] = sum(1 for index, code in enumerate(codes) if code != codes[index - 1])
        features["compactness"] = Fraction((5 * straight + 7 * diagonal) ** 2, 25 * area)
        features["runs"] = sum(1 for x, y in region.pixels if self.label_at(x - 1, y) != number)

    def search_start(self, heading):
        if self.connectivity == 4:
            return (heading + 3) % 4
        if heading % 2 == 0:
            return (heading + 7) % 8
        return (heading + 6) % 8

    def next_direction(self, number, x, y, start):
        directions = DIRECTIONS[self.connectivity]
        for offset in range(len(directions)):
            direction = (start + offset) % len(directions)
            dx, dy = directions[direction]
            if self.label_at(x + dx, y + dy) == number:
                return direction
        return None

    def chain_code(self, region):
        directions = DIRECTIONS[self.connectivity]
        visited = [region.pixels[0]]
        codes = []
        heading = len(directions) - 1
        while True:
            x, y = visited[-1]
            direction = self.next_direction(region.number, x, y, self.search_start(heading))
            if direction is None:
                return []
            dx, dy = directions[direction]
            visited.append((x + dx, y + dy))
            codes.append(direction)
            heading = direction
            moves = len(codes)
            if moves >= 2 and visited[moves] == visited[1] and visited[moves - 1] == visited[0]:
                return codes[:-1]

    def measure_moments(self, region):
        features = region.features
        pixels = region.pixels
        area = len(pixels)
        sum_x = sum(x for x, _ in pixels)
        sum_y = sum(y for _, y in pixels)
        m20 = area * sum(x * x for x, _ in pixels) - sum_x * sum_x
        m02 = area * sum(y * y for _, y in pixels) - sum_y * sum_y
        m11 = area * sum(x * y for x, y in pixels) - sum_x * sum_y
        features["cx"] = Fraction(sum_x, area)
        features["cy"] = Fraction(sum_y, area)
        features["var_x"] = Fraction(m20, area * area)
        features["var_y"] = Fraction(m02, area * area)
        features["cov_xy"] = Fraction(m11, area * area)
        features["hu1"] = Fraction(m20 + m02, area ** 3)
        if m20 + m02 > 0:
            anisotropy = Fraction(abs(m20 - m02) + 2 * abs(m11), m20 + m02)
        else:
            anisotropy = Fraction(0)
        features["anisotropy"] = anisotropy
        anisotropic = anisotropy > self.parameters.isotropy
        features["orientation"] = orientation_name(m20 - m02, 2 * m11, anisotropic)

    def measure_shape(self, region):
        features = region.features
        number = region.number
        area = len(region.pixels)
        x0, y0, x1, y1 = features["x0"], features["y0"], features["x1"], features["y1"]
        features["extent"] = Fraction(area, features["width"] * features["height"])
        mirrored_lr = sum(1 for x, y in region.pixels if self.label_at(x0 + x1 - x, y) == number)
        mirrored_tb = sum(1 for x, y in region.pixels if self.label_at(x, y0 + y1 - y) == number)
        features["mirror_lr"] = Fraction(mirrored_lr, area)
        features["mirror_tb"] = Fraction(mirrored_tb, area)

    def measure_hull(self, region):
        features = region.features
        hull = convex_hull(corner_points(region.pixels))
        region.hull_doubled = doubled_area(hull)
        feret2 = max(squared_distance(a, b) for a in hull for b in hull)
        width2 = min(squared_width(hull, a, b) for a, b in hull_edges(hull))
        features["solidity"] = Fraction(2 * len(region.pixels), region.hull_doubled)
        features["feret2"] = feret2
        features["width2"] = width2
        features["elongation"] = feret2 / width2
        self.measure_bays(region, hull)

    def measure_bays(self, region, hull):
        features = region.features
        x0, y0, x1, y1 = features["x0"], features["y0"], features["x1"], features["y1"]
        mask = [
            [
                self.labels[y][x] == 0 and self.hole_of[y][x] == 0
                and contains_center(hull, x, y)
                for x in range(x0, x1 + 1)
            ]
            for y in range(y0, y1 + 1)
        ]
        bays = labeling.label_components(mask, self.complement)
        sizes = [len(pixels) for pixels in group_pixels(bays.labels, bays.count)[1:]]
        features["bays"] = sum(1 for size in sizes if size >= self.parameters.bay_min)
        features["bay_area"] = sum(sizes)

    def measure_skeleton(self, region):
        features = region.features
        skeleton = morphology.thin(region.pixels)
        region.skeleton = skeleton
        crossings = [morphology.crossing_number(skeleton, x, y) for x, y in skeleton]
        features["skeleton"] = len(skeleton)
        features["endpoints"] = crossings.count(1)
        features["branches"] = sum(1 for crossing in crossings if crossing >= 3)

    def apply_rules(self, rules):
        for region in self.regions:
            features = region.features
            failed = [
                index for index, condition in enumerate(rules.filters)
                if not condition.holds(features)
            ]
            if failed:
                region.dropped_by = failed[0]
                continue
            region.kept = True
            for rule in rules.classes:
                if rule.matches(features):
                    region.class_name = rule.name
                    break
            region.flags = [rule.name for rule in rules.flags if rule.matches(features)]

    def kept_regions(self):
        return [region for region in self.regions if region.kept]

    def find_neighbors(self):
        kept = self.kept_regions()
        for region in kept:
            candidates = [
                (box_distance(region, other), other.number)
                for other in kept if other is not region
            ]
            if candidates:
                region.distance, region.neighbor = min(candidates)

    def tree_text(self, region):
        if not region.children:
            return str(region.number)
        inner = " ".join(self.tree_text(child) for child in region.children)
        return f"{region.number}({inner})"

    def threshold_lines(self):
        image = self.image
        histogram = self.histogram
        lines = [
            f"image {image.name} size {image.width} {image.height} maxval {image.maxval}",
            f"histogram pixels {histogram.pixels} min {histogram.minimum} max {histogram.maximum}"
            f" mean {mean_text(histogram.total, histogram.pixels)} median {histogram.median}"
            f" mode {histogram.mode} levels {histogram.levels}",
            "bins " + " ".join(str(value) for value in [histogram.bin_width] + histogram.bins),
            f"otsu threshold {self.otsu.cutoff} upper {self.otsu.upper}"
            f" candidates {len(self.otsu.candidates)}",
        ]
        top = self.otsu.candidates[:self.parameters.otsu_top]
        for rank, candidate in enumerate(top, 1):
            below = candidate.below
            above = candidate.above
            gap = Fraction(
                candidate.sum_above * below - candidate.sum_below * above, below * above
            )
            lines.append(
                f"rank {rank} t {candidate.cutoff} below {below} above {above}"
                f" mean_below {mean_text(candidate.sum_below, below)}"
                f" mean_above {mean_text(candidate.sum_above, above)}"
                f" gap {decimal(gap, 2)}"
            )
        lines.append(
            f"isodata threshold {self.isodata_cutoff} iterations {self.isodata_iterations}"
        )
        lines.append(
            f"threshold {self.cutoff} {self.setting.method()} {self.setting.polarity}"
            f" foreground {count_foreground(self.initial)}"
        )
        for operation, count in zip(self.setting.operations, self.morph_counts):
            lines.append(f"morph {operation} foreground {count}")
        for cutoff, foreground, regions in self.sweep:
            lines.append(f"sweep {cutoff} foreground {foreground} regions {regions}")
        return lines

    def region_symbol(self, x, y, skeleton_only):
        label = self.labels[y][x]
        if label == 0:
            return ":" if self.hole_of[y][x] > 0 else "."
        region = self.regions[label - 1]
        if skeleton_only and (x, y) not in region.skeleton:
            return "+"
        return SYMBOLS[label % len(SYMBOLS)] if region.kept else "#"

    def map_lines(self):
        size = f"{self.image.name} {self.width} {self.height}"
        lines = ["morphology " + size]
        for initial_row, final_row in zip(self.initial, self.final):
            lines.append("".join(
                MORPHOLOGY_SYMBOLS[(before, after)] for before, after in zip(initial_row, final_row)
            ))
        for heading, skeleton_only in (("labels", False), ("skeleton", True)):
            lines.append(f"{heading} {size}")
            for y in range(self.height):
                lines.append("".join(
                    self.region_symbol(x, y, skeleton_only) for x in range(self.width)
                ))
        return lines

    def csv_rows(self):
        return [self.csv_row(region) for region in self.kept_regions()]

    def csv_row(self, region):
        features = region.features
        if region.neighbor is None:
            neighbor = "-"
            distance = "-"
        else:
            neighbor = region.neighbor
            distance = decimal(Fraction(region.distance, 4), 2)
        columns = [
            self.image.name, region.number, region.class_name, "+".join(region.flags) or "-",
            features["area"], features["x0"], features["y0"], features["x1"], features["y1"],
            decimal(features["cx"], 3), decimal(features["cy"], 3),
            decimal(features["mean"], 2), decimal(features["variance"], 2),
            features["min"], features["max"], decimal(features["contrast"], 2),
            features["border"], features["perimeter"], features["chain"],
            features["straight"], features["diagonal"], features["turns"],
            decimal(features["compactness"], 3), features["runs"],
            features["holes"], features["hole_area"], features["euler"],
            "-" if region.parent is None else region.parent.number, features["depth"],
            decimal(features["var_x"], 3), decimal(features["var_y"], 3),
            decimal(features["cov_xy"], 3), decimal(features["hu1"], 4),
            features["orientation"], decimal(features["anisotropy"], 3),
            decimal(features["extent"], 3),
            decimal(features["mirror_lr"], 3), decimal(features["mirror_tb"], 3),
            hull_area_text(region.hull_doubled), decimal(features["solidity"], 3),
            features["feret2"], decimal(features["width2"], 3),
            decimal(features["elongation"], 3), features["bays"], features["bay_area"],
            features["skeleton"], features["endpoints"], features["branches"],
            neighbor, distance, "".join(str(code) for code in region.codes) or "-",
        ]
        return ",".join(str(column) for column in columns)

    def intensity_text(self, foreground):
        values = [
            value
            for pixel_row, mask_row in zip(self.image.pixels, self.final)
            for value, flag in zip(pixel_row, mask_row)
            if flag == foreground
        ]
        return mean_text(sum(values), len(values))

    def area_line(self):
        kept = self.kept_regions()
        if not kept:
            return "area total 0 mean - largest - smallest -"
        total = sum(region.features["area"] for region in kept)
        largest = max(kept, key=lambda region: region.features["area"])
        smallest = min(kept, key=lambda region: region.features["area"])
        return (
            f"area total {total} mean {mean_text(total, len(kept))}"
            f" largest {largest.number} {largest.features['area']}"
            f" smallest {smallest.number} {smallest.features['area']}"
        )

    def summary_lines(self, rules):
        kept = self.kept_regions()
        region_count = len(self.regions)
        hole_pixels = sum(len(hole.pixels) for hole in self.holes)
        lines = [
            f"image {self.image.name}",
            f"threshold {self.cutoff} {self.setting.method()} {self.setting.polarity}"
            f" conn {self.connectivity}",
            f"foreground {count_foreground(self.initial)} {count_foreground(self.final)}",
            f"regions {region_count} provisional {self.provisional} kept {len(kept)}"
            f" dropped {region_count - len(kept)}",
            f"connectivity four {self.four_components} eight {self.eight_components}",
            f"holes {len(self.holes)} hole_pixels {hole_pixels}"
            f" euler {region_count - len(self.holes)} bitquad {self.bit_quad}",
        ]
        for hole in self.holes:
            x0, y0, x1, y1 = hole.box()
            lines.append(
                f"hole {hole.number} owner {hole.owner} area {len(hole.pixels)}"
                f" box {x0} {y0} {x1} {y1}"
            )
        lines.append(f"depth_max {max((region.depth for region in self.regions), default=0)}")
        roots = [region for region in self.regions if region.parent is None]
        lines.append(" ".join(["tree"] + [self.tree_text(region) for region in roots]))
        lines.append(
            f"intensity foreground {self.intensity_text(True)}"
            f" background {self.intensity_text(False)}"
        )
        lines.append(self.area_line())
        parts = ["classes"]
        for name in rules.class_names():
            parts.extend((name, str(sum(1 for region in kept if region.class_name == name))))
        lines.append(" ".join(parts))
        lines.append(orientation_line(kept))
        parts = ["flags"]
        for rule in rules.flags:
            parts.extend((rule.name, str(sum(1 for region in kept if rule.name in region.flags))))
        lines.append(" ".join(parts))
        return lines


def overall_lines(analyses, rules):
    regions = [region for analysis in analyses for region in analysis.regions]
    kept = [region for region in regions if region.kept]
    hole_count = sum(len(analysis.holes) for analysis in analyses)
    lines = [
        "overall",
        f"images {len(analyses)}",
        f"regions {len(regions)} kept {len(kept)} dropped {len(regions) - len(kept)}",
        f"holes {hole_count} euler {len(regions) - hole_count}",
    ]
    for index, condition in enumerate(rules.filters):
        dropped = sum(1 for region in regions if region.dropped_by == index)
        lines.append(f"filter {index + 1} {condition.words()} dropped {dropped}")
    for name in rules.class_names():
        members = [region for region in kept if region.class_name == name]
        area = sum(region.features["area"] for region in members)
        lines.append(
            f"class {name} count {len(members)} area {area} mean {mean_text(area, len(members))}"
        )
    for rule in rules.flags:
        count = sum(1 for region in kept if rule.name in region.flags)
        lines.append(f"flag {rule.name} count {count}")
    lines.append(orientation_line(kept))
    entries = [
        (analysis.image.name, region)
        for analysis in analyses for region in analysis.kept_regions()
    ]
    if entries:
        name, region = max(entries, key=lambda entry: entry[1].features["area"])
        lines.append(f"largest {name} {region.number} {region.features['area']}")
    else:
        lines.append("largest -")
    return lines


def main():
    parameters = read_parameters(os.path.join(INPUT_DIR, "params.txt"))
    rules = read_rules(os.path.join(INPUT_DIR, "rules.txt"))
    analyses = []
    for image in read_images(os.path.join(INPUT_DIR, "images.txt")):
        analysis = ImageAnalysis(image, parameters.settings[image.name], parameters)
        analysis.apply_rules(rules)
        analysis.find_neighbors()
        analyses.append(analysis)
    thresholds = []
    maps = []
    rows = [CSV_HEADER]
    summary = []
    for analysis in analyses:
        thresholds.extend(analysis.threshold_lines())
        maps.extend(analysis.map_lines())
        rows.extend(analysis.csv_rows())
        summary.extend(analysis.summary_lines(rules))
    summary.extend(overall_lines(analyses, rules))
    write_files(OUTPUT_DIR, [
        ("thresholds.txt", thresholds),
        ("labels.txt", maps),
        ("regions.csv", rows),
        ("summary.txt", summary),
    ])


if __name__ == "__main__":
    main()
