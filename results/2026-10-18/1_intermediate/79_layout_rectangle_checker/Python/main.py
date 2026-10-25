import sys
from collections import deque
from dataclasses import dataclass, replace
from enum import Enum, auto
from itertools import combinations, groupby

LIMIT = 10000
MAX_TILES = 20
MAX_RENDER_WIDTH = 60
MAX_RENDER_HEIGHT = 40
MODIFYING = {"ADD", "COPY", "MOVE", "RESIZE", "SPLIT", "LAYER", "DELETE"}
POSITIONS = ("inside", "edge", "corner")


class CommandError(Exception):
    pass


class Kind(Enum):
    OVERLAP = auto()
    EDGE = auto()
    CORNER = auto()
    SEPARATE = auto()


def box(x1, y1, x2, y2):
    return f"({x1},{y1})-({x2},{y2})"


def point(x, y):
    return f"({x},{y})"


def two_decimals(numerator, denominator):
    hundredths = 100 * numerator // denominator
    return f"{hundredths // 100}.{hundredths % 100:02d}"


def name_list(rects):
    return " ".join(rect.name for rect in rects) or "none"


def symbol(count):
    if count == 0:
        return "."
    return str(count) if count < 10 else "*"


def emit(heading, lines):
    print(heading)
    for line in lines:
        print(line)


def parse_argument(text):
    return int(text) if text.lstrip("-").isdigit() else text


@dataclass(frozen=True)
class Rect:
    name: str
    layer: str
    x1: int
    y1: int
    x2: int
    y2: int

    @property
    def width(self):
        return self.x2 - self.x1

    @property
    def height(self):
        return self.y2 - self.y1

    @property
    def area(self):
        return self.width * self.height

    def __str__(self):
        return box(self.x1, self.y1, self.x2, self.y2)

    def moved(self, dx, dy):
        return replace(self, x1=self.x1 + dx, y1=self.y1 + dy,
                       x2=self.x2 + dx, y2=self.y2 + dy)

    def margins(self, inner):
        return (inner.x1 - self.x1, inner.y1 - self.y1,
                self.x2 - inner.x2, self.y2 - inner.y2)

    def contains(self, inner):
        return min(self.margins(inner)) >= 0


class Relation:
    def __init__(self, a, b):
        self.x1 = max(a.x1, b.x1)
        self.y1 = max(a.y1, b.y1)
        self.x2 = min(a.x2, b.x2)
        self.y2 = min(a.y2, b.y2)
        self.ox = self.x2 - self.x1
        self.oy = self.y2 - self.y1
        if self.ox > 0 and self.oy > 0:
            self.kind = Kind.OVERLAP
        elif self.ox < 0 or self.oy < 0:
            self.kind = Kind.SEPARATE
        elif self.ox == 0 and self.oy == 0:
            self.kind = Kind.CORNER
        else:
            self.kind = Kind.EDGE
        self.gap = max(0, -self.ox, -self.oy)

    def common(self):
        return box(self.x1, self.y1, self.x2, self.y2)

    def corner(self):
        return point(self.x1, self.y1)

    def direction(self):
        if self.ox < 0 and self.oy < 0:
            return "diagonal"
        return "x" if self.ox < 0 else "y"


def connected(a, b):
    return Relation(a, b).kind in (Kind.OVERLAP, Kind.EDGE)


def bounding_box(rects):
    return (min(rect.x1 for rect in rects), min(rect.y1 for rect in rects),
            max(rect.x2 for rect in rects), max(rect.y2 for rect in rects))


def overlap_lines(rects):
    lines = []
    for a, b in combinations(rects, 2):
        relation = Relation(a, b)
        if relation.kind == Kind.OVERLAP:
            lines.append(f"{a.name} {b.name} {relation.common()} "
                         f"area {relation.ox * relation.oy}")
    return lines


def spacing_violations(rects, spacing):
    found = []
    for a, b in combinations(rects, 2):
        relation = Relation(a, b)
        if relation.kind == Kind.CORNER:
            found.append((0, a.name, b.name, "corner"))
        elif relation.kind == Kind.SEPARATE and relation.gap < spacing:
            found.append((relation.gap, a.name, b.name, relation.direction()))
    found.sort()
    return [f"{a} {b} gap {gap} {where}" for gap, a, b, where in found]


def find_nets(rects):
    seen = set()
    groups = []
    for start in rects:
        if start.name in seen:
            continue
        seen.add(start.name)
        group = [start]
        stack = [start]
        while stack:
            current = stack.pop()
            for other in rects:
                if other.name not in seen and connected(current, other):
                    seen.add(other.name)
                    group.append(other)
                    stack.append(other)
        groups.append(sorted(group, key=lambda rect: rect.name))
    return groups


def runs(flags, coordinates):
    found = []
    start = 0
    for flag, group in groupby(flags):
        end = start + len(list(group))
        if flag:
            found.append((coordinates[start], coordinates[end]))
        start = end
    return found


class Coverage:

    def __init__(self, rects, extra_xs=(), extra_ys=()):
        self.xs = sorted({x for rect in rects for x in (rect.x1, rect.x2)}.union(extra_xs))
        self.ys = sorted({y for rect in rects for y in (rect.y1, rect.y2)}.union(extra_ys))
        self.columns = len(self.xs) - 1
        self.rows = len(self.ys) - 1
        x_index = {x: i for i, x in enumerate(self.xs)}
        y_index = {y: j for j, y in enumerate(self.ys)}
        self.counts = [[0] * self.rows for _ in range(self.columns)]
        for rect in rects:
            for i in range(x_index[rect.x1], x_index[rect.x2]):
                column = self.counts[i]
                for j in range(y_index[rect.y1], y_index[rect.y2]):
                    column[j] += 1

    def cells(self):
        for i in range(self.columns):
            for j in range(self.rows):
                yield i, j

    def covered(self, i, j):
        return 0 <= i < self.columns and 0 <= j < self.rows and self.counts[i][j] > 0

    def cell_area(self, i, j):
        return (self.xs[i + 1] - self.xs[i]) * (self.ys[j + 1] - self.ys[j])

    def area(self, minimum=1):
        return sum(self.cell_area(i, j) for i, j in self.cells()
                   if self.counts[i][j] >= minimum)

    def perimeter(self):
        total = 0
        for i in range(self.columns + 1):
            for j in range(self.rows):
                if self.covered(i - 1, j) != self.covered(i, j):
                    total += self.ys[j + 1] - self.ys[j]
        for j in range(self.rows + 1):
            for i in range(self.columns):
                if self.covered(i, j - 1) != self.covered(i, j):
                    total += self.xs[i + 1] - self.xs[i]
        return total

    def flood(self, start):
        component = {start}
        stack = [start]
        while stack:
            i, j = stack.pop()
            for neighbor in ((i - 1, j), (i + 1, j), (i, j - 1), (i, j + 1)):
                ni, nj = neighbor
                if (0 <= ni < self.columns and 0 <= nj < self.rows
                        and self.counts[ni][nj] == 0 and neighbor not in component):
                    component.add(neighbor)
                    stack.append(neighbor)
        return component

    def holes(self):
        seen = set()
        found = []
        for j in range(self.rows):
            for i in range(self.columns):
                if (i, j) in seen or self.counts[i][j] > 0:
                    continue
                component = self.flood((i, j))
                seen.update(component)
                if any(ci in (0, self.columns - 1) or cj in (0, self.rows - 1)
                       for ci, cj in component):
                    continue
                area = sum(self.cell_area(ci, cj) for ci, cj in component)
                bounds = (min(self.xs[ci] for ci, _ in component),
                          min(self.ys[cj] for _, cj in component),
                          max(self.xs[ci + 1] for ci, _ in component),
                          max(self.ys[cj + 1] for _, cj in component))
                found.append((area, bounds))
        return found

    def pieces(self):
        row_runs = [runs([self.counts[i][j] > 0 for i in range(self.columns)], self.xs)
                    for j in range(self.rows)]
        found = []
        for j, current in enumerate(row_runs):
            for left, right in current:
                if j > 0 and (left, right) in row_runs[j - 1]:
                    continue
                top = j + 1
                while top < self.rows and (left, right) in row_runs[top]:
                    top += 1
                found.append((left, self.ys[j], right, self.ys[top]))
        return found

    def largest_empty(self):
        candidates = []
        for a in range(self.columns):
            free = [True] * self.rows
            for b in range(a + 1, self.columns + 1):
                free = [is_free and self.counts[b - 1][j] == 0
                        for j, is_free in enumerate(free)]
                width = self.xs[b] - self.xs[a]
                for bottom, top in runs(free, self.ys):
                    candidates.append((-width * (top - bottom), self.xs[a], bottom, width, top))
        if not candidates:
            return None
        _, left, bottom, width, top = min(candidates)
        return left, bottom, left + width, top


class Layout:
    def __init__(self):
        self.rects = {}
        self.rules = {}
        self.history = []
        self.handlers = {
            "ADD": self.add,
            "COPY": self.copy,
            "MOVE": self.move,
            "RESIZE": self.resize,
            "SPLIT": self.split,
            "LAYER": self.change_layer,
            "DELETE": self.delete,
            "UNDO": self.undo,
            "LIST": self.list_rects,
            "INFO": self.info,
            "LAYERS": self.layers,
            "OVERLAPS": self.overlaps,
            "AREA": self.area,
            "COVER": self.cover,
            "PERIMETER": self.perimeter,
            "INTERSECT": self.intersect,
            "ADJACENT": self.adjacent,
            "ENCLOSE": self.enclose,
            "AT": self.at,
            "NETS": self.nets,
            "PATH": self.path,
            "NEAREST": self.nearest,
            "DRC": self.drc,
            "BBOX": self.bbox,
            "DENSITY": self.density,
            "RENDER": self.render,
            "EMPTY": self.empty,
            "HOLES": self.holes,
            "MERGE": self.merge,
            "RULE": self.rule,
            "CHECK": self.check,
        }

    def execute(self, line):
        command, *arguments = line.split(" ")
        before = dict(self.rects)
        try:
            self.handlers[command](*map(parse_argument, arguments))
        except CommandError as error:
            print(f"error: {error}")
            return
        if command in MODIFYING:
            self.history.append((before, line))

    def get(self, name):
        if name not in self.rects:
            raise CommandError(f"unknown rectangle {name}")
        return self.rects[name]

    def require_unused(self, name):
        if name in self.rects:
            raise CommandError(f"duplicate rectangle {name}")

    def pair(self, a, b):
        first = self.get(a)
        second = self.get(b)
        if a == b:
            raise CommandError(f"same rectangle {a}")
        return first, second

    def place(self, rect):
        if any(abs(c) > LIMIT for c in (rect.x1, rect.y1, rect.x2, rect.y2)):
            raise CommandError("out of bounds")
        self.rects[rect.name] = rect

    def sorted_rects(self):
        return [self.rects[name] for name in sorted(self.rects)]

    def layer_names(self):
        return sorted({rect.layer for rect in self.rects.values()})

    def on_layer(self, layer):
        return [rect for rect in self.sorted_rects() if rect.layer == layer]

    def require_layer(self, layer):
        rects = self.on_layer(layer)
        if not rects:
            raise CommandError(f"no rectangles on {layer}")
        return rects

    def add(self, name, layer, x1, y1, x2, y2):
        self.require_unused(name)
        if x1 >= x2 or y1 >= y2:
            raise CommandError("invalid rectangle")
        rect = Rect(name, layer, x1, y1, x2, y2)
        self.place(rect)
        print(f"added {name} {layer} {rect}")

    def copy(self, name, new, dx, dy):
        rect = self.get(name)
        self.require_unused(new)
        copied = replace(rect.moved(dx, dy), name=new)
        self.place(copied)
        print(f"copied {name} to {new} {copied}")

    def move(self, name, dx, dy):
        moved = self.get(name).moved(dx, dy)
        self.place(moved)
        print(f"moved {name} to {moved}")

    def resize(self, name, width, height):
        rect = self.get(name)
        if width <= 0 or height <= 0:
            raise CommandError("invalid size")
        resized = replace(rect, x2=rect.x1 + width, y2=rect.y1 + height)
        self.place(resized)
        print(f"resized {name} to {resized}")

    def split(self, name, axis, position, new):
        rect = self.get(name)
        self.require_unused(new)
        low, high = (rect.x1, rect.x2) if axis == "x" else (rect.y1, rect.y2)
        if not low < position < high:
            raise CommandError(f"cut outside {name}")
        if axis == "x":
            kept = replace(rect, x2=position)
            part = replace(rect, name=new, x1=position)
        else:
            kept = replace(rect, y2=position)
            part = replace(rect, name=new, y1=position)
        self.rects[name] = kept
        self.rects[new] = part
        print(f"split {name} at {axis}={position}: {name} {kept}, {new} {part}")

    def change_layer(self, name, layer):
        rect = self.get(name)
        if rect.layer == layer:
            raise CommandError(f"already on {layer}")
        self.rects[name] = replace(rect, layer=layer)
        print(f"layer {name} {rect.layer} -> {layer}")

    def delete(self, name):
        self.get(name)
        del self.rects[name]
        print(f"deleted {name}")

    def undo(self):
        if not self.history:
            raise CommandError("nothing to undo")
        self.rects, line = self.history.pop()
        print(f"undo: {line}")

    def list_rects(self):
        rects = self.sorted_rects()
        emit(f"rectangles: {len(rects)}",
             [f"{rect.name} {rect.layer} {rect} {rect.width}x{rect.height}" for rect in rects])

    def info(self, name):
        rect = self.get(name)
        others = [other for other in self.sorted_rects() if other.name != name]
        kinds = {other.name: Relation(rect, other).kind
                 for other in others if other.layer == rect.layer}
        print(f"{name} {rect.layer} {rect} {rect.width}x{rect.height} area {rect.area}")
        for label, kind in (("overlaps", Kind.OVERLAP), ("touches", Kind.EDGE),
                            ("corners", Kind.CORNER)):
            print(f"{label}: {name_list(o for o in others if kinds.get(o.name) == kind)}")
        print(f"encloses: {name_list(o for o in others if rect.contains(o))}")
        print(f"enclosed by: {name_list(o for o in others if o.contains(rect))}")

    def layers(self):
        lines = []
        for layer in self.layer_names():
            rects = self.on_layer(layer)
            lines.append(f"{layer}: {len(rects)} rectangles, area {Coverage(rects).area()}, "
                         f"nets {len(find_nets(rects))}")
        emit(f"layers: {len(lines)}", lines)

    def overlaps(self, layer=None):
        if layer is None:
            lines = [f"{name} {line}" for name in self.layer_names()
                     for line in overlap_lines(self.on_layer(name))]
            emit(f"overlaps all layers: {len(lines)}", lines)
        else:
            lines = overlap_lines(self.require_layer(layer))
            emit(f"overlaps {layer}: {len(lines)}", lines)

    def area(self, layer):
        coverage = Coverage(self.require_layer(layer))
        print(f"area {layer}: {coverage.area()}")

    def cover(self, minimum, layer):
        coverage = Coverage(self.require_layer(layer))
        print(f"cover {layer} >= {minimum}: {coverage.area(minimum)}")

    def perimeter(self, layer):
        coverage = Coverage(self.require_layer(layer))
        print(f"perimeter {layer}: {coverage.perimeter()}")

    def intersect(self, a, b):
        relation = Relation(*self.pair(a, b))
        match relation.kind:
            case Kind.OVERLAP:
                detail = f"{relation.common()} area {relation.ox * relation.oy}"
            case Kind.EDGE:
                detail = f"segment {relation.common()} length {relation.ox + relation.oy}"
            case Kind.CORNER:
                detail = f"point {relation.corner()}"
            case Kind.SEPARATE:
                detail = f"none, gap {relation.gap}"
        print(f"intersect {a} {b}: {detail}")

    def adjacent(self, a, b):
        first, second = self.pair(a, b)
        relation = Relation(first, second)
        match relation.kind:
            case Kind.OVERLAP:
                detail = "overlapping"
            case Kind.EDGE:
                if relation.ox == 0:
                    side = "west" if first.x2 == relation.x1 else "east"
                else:
                    side = "south" if first.y2 == relation.y1 else "north"
                detail = (f"{a} is {side} of {b}, edge {relation.common()}, "
                          f"length {relation.ox + relation.oy}")
            case Kind.CORNER:
                detail = f"corner only at {relation.corner()}"
            case Kind.SEPARATE:
                detail = "not adjacent"
        print(f"adjacent {a} {b}: {detail}")

    def enclose(self, a, b):
        first, second = self.pair(a, b)
        margins = first.margins(second)
        left, bottom, right, top = margins
        text = f"margins left {left} bottom {bottom} right {right} top {top}"
        if min(margins) >= 0:
            print(f"enclose {a} {b}: yes, {text}, min {min(margins)}")
        else:
            print(f"enclose {a} {b}: no, {text}")

    def at(self, x, y):
        found = []
        for rect in self.sorted_rects():
            if rect.x1 <= x <= rect.x2 and rect.y1 <= y <= rect.y2:
                on_sides = (x in (rect.x1, rect.x2)) + (y in (rect.y1, rect.y2))
                found.append(f"{rect.name} {rect.layer} {POSITIONS[on_sides]}")
        print(f"at {point(x, y)}: {', '.join(found) or 'none'}")

    def nets(self, layer):
        groups = find_nets(self.require_layer(layer))
        emit(f"nets {layer}: {len(groups)}",
             [f"net {number}: {name_list(group)} area {Coverage(group).area()}"
              for number, group in enumerate(groups, 1)])

    def path(self, a, b):
        first, second = self.pair(a, b)
        if first.layer != second.layer:
            raise CommandError("different layers")
        rects = self.on_layer(first.layer)
        links = {rect.name: [other.name for other in rects
                             if other.name != rect.name and connected(rect, other)]
                 for rect in rects}
        distance = {b: 0}
        queue = deque([b])
        while queue:
            current = queue.popleft()
            for neighbor in links[current]:
                if neighbor not in distance:
                    distance[neighbor] = distance[current] + 1
                    queue.append(neighbor)
        if a not in distance:
            print(f"path {a} {b}: none")
            return
        route = [a]
        while route[-1] != b:
            remaining = distance[route[-1]] - 1
            route.append(min(name for name in links[route[-1]]
                             if distance.get(name) == remaining))
        print(f"path {a} {b}: {' -> '.join(route)} ({len(route) - 1} steps)")

    def nearest(self, name):
        rect = self.get(name)
        others = [other for other in self.on_layer(rect.layer) if other.name != name]
        if not others:
            print(f"nearest {name}: none")
            return
        gap, closest = min((Relation(rect, other).gap, other.name) for other in others)
        print(f"nearest {name}: {closest} gap {gap}")

    def drc(self, layer, spacing):
        lines = spacing_violations(self.require_layer(layer), spacing)
        emit(f"drc {layer} spacing {spacing}: {len(lines)} violations", lines)

    def bbox(self, layer):
        rects = self.require_layer(layer)
        x1, y1, x2, y2 = bounding_box(rects)
        width = x2 - x1
        height = y2 - y1
        density = two_decimals(100 * Coverage(rects).area(), width * height)
        print(f"bbox {layer}: {box(x1, y1, x2, y2)} {width}x{height}, "
              f"{len(rects)} rectangles, density {density}%")

    def density(self, layer, window):
        rects = self.require_layer(layer)
        x1, y1, x2, y2 = bounding_box(rects)
        columns = -(-(x2 - x1) // window)
        rows = -(-(y2 - y1) // window)
        if columns > MAX_TILES or rows > MAX_TILES:
            raise CommandError("too many windows")
        coverage = Coverage(rects, [x1 + i * window for i in range(columns + 1)],
                            [y1 + j * window for j in range(rows + 1)])
        covered = {(i, j): 0 for j in range(rows) for i in range(columns)}
        for i, j in coverage.cells():
            if coverage.counts[i][j] > 0:
                tile = ((coverage.xs[i] - x1) // window, (coverage.ys[j] - y1) // window)
                covered[tile] += coverage.cell_area(i, j)
        tile_area = window * window
        print(f"density {layer} window {window}: {columns}x{rows}")
        for j in reversed(range(rows)):
            print(" ".join(str(100 * covered[i, j] // tile_area) for i in range(columns)))
        for label, choose in (("min", min), ("max", max)):
            i, j = choose(covered, key=covered.get)
            percent = two_decimals(100 * covered[i, j], tile_area)
            print(f"{label} {percent}% at {point(x1 + i * window, y1 + j * window)}")

    def render(self, layer, x1, y1, x2, y2):
        rects = self.require_layer(layer)
        if x1 >= x2 or y1 >= y2:
            raise CommandError("invalid window")
        if x2 - x1 > MAX_RENDER_WIDTH or y2 - y1 > MAX_RENDER_HEIGHT:
            raise CommandError("window too large")
        lines = []
        for j in range(y2 - 1, y1 - 1, -1):
            counts = (sum(r.x1 <= i < r.x2 and r.y1 <= j < r.y2 for r in rects)
                      for i in range(x1, x2))
            lines.append("".join(symbol(count) for count in counts))
        emit(f"render {layer} {box(x1, y1, x2, y2)}", lines)

    def empty(self, layer):
        found = Coverage(self.require_layer(layer)).largest_empty()
        if found is None:
            print(f"empty {layer}: none")
            return
        x1, y1, x2, y2 = found
        print(f"empty {layer}: {box(x1, y1, x2, y2)} area {(x2 - x1) * (y2 - y1)}")

    def holes(self, layer):
        found = Coverage(self.require_layer(layer)).holes()
        emit(f"holes {layer}: {len(found)}",
             [f"hole {number}: area {area}, bbox {box(*bounds)}"
              for number, (area, bounds) in enumerate(found, 1)])

    def merge(self, layer):
        pieces = Coverage(self.require_layer(layer)).pieces()
        emit(f"merge {layer}: {len(pieces)} pieces", [box(*piece) for piece in pieces])

    def rule(self, kind, *values):
        kind = kind.lower()
        *layers, value = values
        if kind == "enclose" and layers[0] == layers[1]:
            raise CommandError(f"same layer {layers[0]}")
        self.rules[kind, tuple(layers)] = value
        print(f"rule {kind} {' '.join(layers)} {value}")

    def enclosure_violations(self, inner, outer, margin):
        outers = self.on_layer(outer)
        lines = []
        for rect in self.on_layer(inner):
            if not outers:
                lines.append(f"{rect.name} best margin none")
                continue
            best = max(min(other.margins(rect)) for other in outers)
            if best < margin:
                lines.append(f"{rect.name} best margin {best}")
        return lines

    def width_violations(self, layer, minimum):
        lines = []
        for rect in self.on_layer(layer):
            size = min(rect.width, rect.height)
            if size < minimum:
                lines.append(f"{rect.name} width {size}")
        return lines

    def check(self):
        if not self.rules:
            raise CommandError("no rules")
        total = 0
        for (kind, layers), value in sorted(self.rules.items()):
            if kind == "enclose":
                lines = self.enclosure_violations(*layers, value)
            elif kind == "spacing":
                lines = spacing_violations(self.on_layer(layers[0]), value)
            else:
                lines = self.width_violations(layers[0], value)
            emit(f"{kind} {' '.join(layers)} {value}: {len(lines)} violations", lines)
            total += len(lines)
        print(f"check: {total} violations in {len(self.rules)} rules")


def main():
    layout = Layout()
    count = int(sys.stdin.readline())
    for _ in range(count):
        layout.execute(sys.stdin.readline().rstrip("\n"))


if __name__ == "__main__":
    main()
