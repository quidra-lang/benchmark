import os
import re

from canvas import OPAQUE, Layer, composite, round_ratio
from clipping import clip_polygon, clip_segment
from fill import fill_polygons, fill_shape, flood_fill
from ppm_writer import write_ppm, write_preview
from primitives import bezier_points, bresenham, circle_points, ellipse_points, expand_square


INPUT_DIR = "input"
OUTPUT_DIR = "output"
IDENTITY = (1, 0, 0, 1, 0, 0)
PEN_COMMANDS = ("LINE", "RECT", "CIRCLE", "ELLIPSE", "POLYLINE", "POLYGON", "PATH")
BRUSH_COMMANDS = (
    "FILLRECT", "FILLCIRCLE", "FILLELLIPSE", "FILLPOLYGON", "FILLPATH", "FLOOD", "TEXT",
)
STATE_COMMANDS = ("TRANSLATE", "SCALE", "ROTATE", "SAVE", "RESTORE", "CLIP", "NOCLIP", "USE")
COMMANDS = PEN_COMMANDS + BRUSH_COMMANDS + ("ERASE",) + STATE_COMMANDS
FIXED_FORMS = {
    "LINE": (5, 1), "RECT": (5, 1), "FILLRECT": (5, 1),
    "CIRCLE": (4, 1), "FILLCIRCLE": (4, 1),
    "ELLIPSE": (5, 1), "FILLELLIPSE": (5, 1),
    "FLOOD": (3, 1), "ERASE": (4, 0),
    "TRANSLATE": (2, 0), "SCALE": (2, 0), "ROTATE": (1, 0),
    "SAVE": (0, 0), "RESTORE": (0, 0), "NOCLIP": (0, 0),
    "CLIP": (4, 0), "USE": (3, 1),
}
POLYGON_COMMANDS = ("POLYLINE", "POLYGON", "FILLPOLYGON")
ERROR_NAMES = (
    "unknown_command", "bad_arguments", "unknown_style", "unknown_symbol",
    "unknown_glyph", "bad_value", "stack_empty",
)
PATH_ARITY = {
    "M": 2, "m": 2, "L": 2, "l": 2, "H": 1, "h": 1, "V": 1, "v": 1,
    "Q": 4, "q": 4, "C": 6, "c": 6, "Z": 0, "z": 0,
}
ALIGNMENTS = ("left", "center", "right")
MAX_SEGMENTS = 32
LAYER_COLOR_LINES = 5
TOP_COLOR_LINES = 8
INTEGER_WORD = re.compile(r"-?[0-9]+")


class CommandError(Exception):
    pass


class Pen:
    def __init__(self, width, color, on, off):
        self.width = width
        self.color = color
        self.on = on
        self.off = off


class Brush:
    def __init__(self, colors, axis, rule):
        self.colors = colors
        self.axis = axis
        self.rule = rule


class Styles:
    def __init__(self):
        self.colors = {}
        self.pens = {}
        self.brushes = {}


class Font:
    def __init__(self, width, height):
        self.width = width
        self.height = height
        self.glyphs = {}


class Command:
    def __init__(self, line, keyword, arguments):
        self.line = line
        self.keyword = keyword
        self.arguments = arguments


class Repeat:
    def __init__(self, count, dx, dy):
        self.count = count
        self.dx = dx
        self.dy = dy
        self.body = []


class Block:
    def __init__(self, name):
        self.name = name
        self.body = []
        self.end_line = 0


class LayerBlock(Block):
    def __init__(self, name, opacity, mode):
        super().__init__(name)
        self.opacity = opacity
        self.mode = mode


class Scene:
    def __init__(self):
        self.width = 0
        self.height = 0
        self.background = ""
        self.layers = []
        self.symbols = {}


class Probe:
    def __init__(self, kind, values):
        self.kind = kind
        self.values = values


class PathCommand:
    def __init__(self, letter, values):
        self.letter = letter
        self.values = values


class Subpath:
    def __init__(self, start):
        self.points = [start]
        self.closed = False


class Execution:
    def __init__(self, sequence, layer, command):
        self.sequence = sequence
        self.layer = layer
        self.command = command
        self.kind = None
        self.error = None
        self.pixels = 0
        self.box = None


class KeywordTally:
    def __init__(self):
        self.executed = 0
        self.errors = 0
        self.pixels = 0


def is_integer(word):
    return INTEGER_WORD.fullmatch(word) is not None


def all_integers(words):
    return all(is_integer(word) for word in words)


def integers(words):
    return [int(word) for word in words]


def intersect(first, second):
    return (
        max(first[0], second[0]), max(first[1], second[1]),
        min(first[2], second[2]), min(first[3], second[3]),
    )


def is_empty(rect):
    return rect[0] > rect[2] or rect[1] > rect[3]


def contains(rect, point):
    return rect[0] <= point[0] <= rect[2] and rect[1] <= point[1] <= rect[3]


def rect_pixels(rect):
    x0, y0, x1, y1 = rect
    return {(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)}


def bounding_box(pixels):
    if not pixels:
        return None
    xs = [x for x, _ in pixels]
    ys = [y for _, y in pixels]
    return min(xs), min(ys), max(xs), max(ys)


def box_text(box):
    if box is None:
        return "none"
    return " ".join(str(value) for value in box)


def ranked(counts):
    return sorted(counts.items(), key=lambda item: (-item[1], item[0]))


def open_segments(points):
    return [(points[index], points[index + 1]) for index in range(len(points) - 1)]


def closed_segments(points):
    return open_segments(points) + [(points[-1], points[0])]


def parse_path(words):
    commands = []
    index = 0
    while index < len(words):
        letter = words[index]
        if letter not in PATH_ARITY:
            return None
        values = words[index + 1:index + 1 + PATH_ARITY[letter]]
        if len(values) < PATH_ARITY[letter] or not all_integers(values):
            return None
        starts_subpath = not commands or commands[-1].letter in ("Z", "z")
        if starts_subpath and letter not in ("M", "m"):
            return None
        commands.append(PathCommand(letter, integers(values)))
        index += 1 + PATH_ARITY[letter]
    if not commands:
        return None
    return commands


def path_points(command, current):
    current_x, current_y = current
    offset_x, offset_y = (current_x, current_y) if command.letter.islower() else (0, 0)
    values = command.values
    kind = command.letter.upper()
    if kind == "H":
        return [(values[0] + offset_x, current_y)]
    if kind == "V":
        return [(current_x, values[0] + offset_y)]
    return [
        (values[index] + offset_x, values[index + 1] + offset_y)
        for index in range(0, len(values), 2)
    ]


def path_segments(subpaths):
    segments = []
    for subpath in subpaths:
        if subpath.closed:
            segments.extend(closed_segments(subpath.points))
        else:
            segments.extend(open_segments(subpath.points))
    return segments


def gradient_color(first, second, axis, box, x, y):
    if axis == "x":
        offset, length = x - box[0], box[2] - box[0]
    else:
        offset, length = y - box[1], box[3] - box[1]
    if length == 0:
        return first
    return tuple(
        start + round_ratio((end - start) * offset, length)
        for start, end in zip(first, second)
    )


def valid_form(keyword, arguments):
    if keyword in FIXED_FORMS:
        count, first_integer = FIXED_FORMS[keyword]
        return len(arguments) == count and all_integers(arguments[first_integer:])
    if keyword == "TEXT":
        return len(arguments) == 5 and all_integers(arguments[1:3])
    if keyword in POLYGON_COMMANDS:
        return (
            len(arguments) >= 2
            and all_integers(arguments[1:])
            and len(arguments) == 2 + 2 * int(arguments[1])
        )
    return (
        len(arguments) >= 2
        and is_integer(arguments[1])
        and parse_path(arguments[2:]) is not None
    )


class DrawingState:
    def __init__(self, screen):
        self.screen = screen
        self.matrix = IDENTITY
        self.clip = screen
        self.stack = []

    def snapshot(self):
        return self.matrix, self.clip, list(self.stack)

    def rollback(self, snapshot):
        self.matrix, self.clip, stack = snapshot
        self.stack = list(stack)

    def transform(self, x, y):
        a, b, c, d, e, f = self.matrix
        return a * x + b * y + e, c * x + d * y + f

    def device_rect(self, x0, y0, x1, y1):
        first_x, first_y = self.transform(x0, y0)
        second_x, second_y = self.transform(x1, y1)
        return (
            min(first_x, second_x), min(first_y, second_y),
            max(first_x, second_x), max(first_y, second_y),
        )

    def device_radii(self, rx, ry):
        a, b, c, d, _, _ = self.matrix
        return abs(a) * rx + abs(b) * ry, abs(c) * rx + abs(d) * ry

    def translate(self, dx, dy):
        a, b, c, d, e, f = self.matrix
        self.matrix = (a, b, c, d, e + a * dx + b * dy, f + c * dx + d * dy)

    def scale(self, sx, sy):
        a, b, c, d, e, f = self.matrix
        self.matrix = (a * sx, b * sy, c * sx, d * sy, e, f)

    def rotate(self, quarter_turns):
        for _ in range(quarter_turns % 4):
            a, b, c, d, e, f = self.matrix
            self.matrix = (b, -a, d, -c, e, f)

    def save(self):
        self.stack.append((self.matrix, self.clip))

    def restore(self):
        self.matrix, self.clip = self.stack.pop()


class Renderer:
    def __init__(self, scene, styles, font):
        self.scene = scene
        self.styles = styles
        self.font = font
        self.screen = (0, 0, scene.width - 1, scene.height - 1)
        self.layers = []
        self.executions = []
        self.layer = None
        self.state = None

    def run(self):
        for block in self.scene.layers:
            self.layer = Layer(self.scene.width, self.scene.height, block.opacity, block.mode)
            self.layers.append(self.layer)
            self.state = DrawingState(self.screen)
            self.execute_body(block.body)

    def execute_body(self, body):
        for item in body:
            if isinstance(item, Repeat):
                self.execute_repeat(item)
            else:
                self.execute_command(item)

    def execute_repeat(self, repeat):
        saved = self.state.snapshot()
        for k in range(repeat.count):
            self.state.rollback(saved)
            self.state.translate(k * repeat.dx, k * repeat.dy)
            self.execute_body(repeat.body)
        self.state.rollback(saved)

    def execute_command(self, command):
        execution = Execution(len(self.executions) + 1, len(self.layers), command)
        self.executions.append(execution)
        try:
            self.check(command)
        except CommandError as error:
            execution.kind = "error"
            execution.error = str(error)
            return
        if command.keyword in STATE_COMMANDS:
            execution.kind = "state"
            self.apply_state(command)
            return
        pixels = self.draw(command)
        execution.kind = "drawing"
        execution.pixels = len(pixels)
        execution.box = bounding_box(pixels)

    def check(self, command):
        keyword = command.keyword
        arguments = command.arguments
        if keyword not in COMMANDS:
            raise CommandError("unknown_command")
        if not valid_form(keyword, arguments):
            raise CommandError("bad_arguments")
        if keyword in PEN_COMMANDS and arguments[0] not in self.styles.pens:
            raise CommandError("unknown_style")
        if keyword in BRUSH_COMMANDS and arguments[0] not in self.styles.brushes:
            raise CommandError("unknown_style")
        if keyword == "USE" and not self.symbol_ready(arguments[0], command.line):
            raise CommandError("unknown_symbol")
        if keyword == "TEXT" and not self.known_glyphs(arguments[4]):
            raise CommandError("unknown_glyph")
        if keyword == "RESTORE" and not self.state.stack:
            raise CommandError("stack_empty")
        if not self.valid_value(keyword, arguments):
            raise CommandError("bad_value")

    def symbol_ready(self, name, line):
        symbol = self.scene.symbols.get(name)
        return symbol is not None and symbol.end_line < line

    def known_glyphs(self, text):
        return all(character == "_" or character in self.font.glyphs for character in text)

    def valid_value(self, keyword, arguments):
        if keyword in ("CIRCLE", "FILLCIRCLE"):
            return int(arguments[3]) >= 1
        if keyword in ("ELLIPSE", "FILLELLIPSE"):
            return int(arguments[3]) >= 1 and int(arguments[4]) >= 1
        if keyword == "POLYLINE":
            return int(arguments[1]) >= 2
        if keyword in ("POLYGON", "FILLPOLYGON"):
            return int(arguments[1]) >= 3
        if keyword in ("PATH", "FILLPATH"):
            return 1 <= int(arguments[1]) <= MAX_SEGMENTS
        if keyword == "FLOOD":
            seed = self.state.transform(int(arguments[1]), int(arguments[2]))
            return contains(self.state.clip, seed)
        if keyword == "TEXT":
            return arguments[3] in ALIGNMENTS
        if keyword == "SCALE":
            return int(arguments[0]) != 0 and int(arguments[1]) != 0
        if keyword == "CLIP":
            rect = self.state.device_rect(*integers(arguments))
            return not is_empty(intersect(rect, self.state.clip))
        return True

    def apply_state(self, command):
        keyword = command.keyword
        arguments = command.arguments
        state = self.state
        if keyword == "TRANSLATE":
            state.translate(int(arguments[0]), int(arguments[1]))
        elif keyword == "SCALE":
            state.scale(int(arguments[0]), int(arguments[1]))
        elif keyword == "ROTATE":
            state.rotate(int(arguments[0]))
        elif keyword == "SAVE":
            state.save()
        elif keyword == "RESTORE":
            state.restore()
        elif keyword == "CLIP":
            state.clip = intersect(state.device_rect(*integers(arguments)), state.clip)
        elif keyword == "NOCLIP":
            state.clip = self.screen
        else:
            symbol = self.scene.symbols[arguments[0]]
            self.use_symbol(symbol, int(arguments[1]), int(arguments[2]))

    def use_symbol(self, symbol, dx, dy):
        saved = self.state.snapshot()
        self.state.translate(dx, dy)
        self.execute_body(symbol.body)
        self.state.rollback(saved)

    def draw(self, command):
        keyword = command.keyword
        arguments = command.arguments
        if keyword == "ERASE":
            return self.erase(integers(arguments))
        if keyword in PEN_COMMANDS:
            pen = self.styles.pens[arguments[0]]
            pixels = self.pen_coverage(keyword, pen, arguments[1:])
            color = self.styles.colors[pen.color]
            for x, y in pixels:
                self.layer.paint(x, y, color, command.line)
            return pixels
        brush = self.styles.brushes[arguments[0]]
        pixels = self.brush_coverage(keyword, brush, arguments[1:])
        self.paint_with_brush(brush, pixels, command.line)
        return pixels

    def paint_with_brush(self, brush, pixels, line):
        first = self.styles.colors[brush.colors[0]]
        if brush.axis is None:
            for x, y in pixels:
                self.layer.paint(x, y, first, line)
            return
        second = self.styles.colors[brush.colors[1]]
        box = bounding_box(pixels)
        for x, y in pixels:
            self.layer.paint(x, y, gradient_color(first, second, brush.axis, box, x, y), line)

    def vertices(self, arguments):
        values = integers(arguments[1:])
        return [
            self.state.transform(values[index], values[index + 1])
            for index in range(0, len(values), 2)
        ]

    def pen_coverage(self, keyword, pen, arguments):
        if keyword in ("CIRCLE", "ELLIPSE"):
            (center_x, center_y), points = self.shape(keyword, integers(arguments))
            return self.expand([(center_x + dx, center_y + dy) for dx, dy in points], pen.width)
        if keyword == "LINE":
            values = integers(arguments)
            start = self.state.transform(values[0], values[1])
            end = self.state.transform(values[2], values[3])
            segments = [(start, end)]
        elif keyword == "RECT":
            x0, y0, x1, y1 = self.state.device_rect(*integers(arguments))
            segments = closed_segments([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
        elif keyword == "POLYLINE":
            segments = open_segments(self.vertices(arguments))
        elif keyword == "POLYGON":
            segments = closed_segments(self.vertices(arguments))
        else:
            subpaths = self.build_subpaths(parse_path(arguments[1:]), int(arguments[0]))
            segments = path_segments(subpaths)
        return self.stroke(pen, segments)

    def stroke(self, pen, segments):
        points = []
        for start, end in segments:
            clipped = clip_segment(start, end, self.state.clip)
            if clipped is not None:
                points.extend(bresenham(clipped[0], clipped[1]))
        if pen.off > 0:
            period = pen.on + pen.off
            points = [point for index, point in enumerate(points) if index % period < pen.on]
        return self.expand(points, pen.width)

    def expand(self, points, width):
        pixels = set()
        for x, y in points:
            for pixel in expand_square(x, y, width):
                if contains(self.state.clip, pixel):
                    pixels.add(pixel)
        return pixels

    def shape(self, keyword, values):
        center = self.state.transform(values[0], values[1])
        if keyword in ("CIRCLE", "FILLCIRCLE"):
            rx, ry = self.state.device_radii(values[2], values[2])
            if rx == ry:
                return center, circle_points(rx)
        else:
            rx, ry = self.state.device_radii(values[2], values[3])
        return center, ellipse_points(rx, ry)

    def brush_coverage(self, keyword, brush, arguments):
        clip = self.state.clip
        if keyword == "FILLRECT":
            return rect_pixels(intersect(self.state.device_rect(*integers(arguments)), clip))
        if keyword in ("FILLCIRCLE", "FILLELLIPSE"):
            center, points = self.shape(keyword, integers(arguments))
            return fill_shape(center, points, clip)
        if keyword == "FILLPOLYGON":
            clipped = clip_polygon(self.vertices(arguments), clip)
            return fill_polygons([clipped], brush.rule, clip)
        if keyword == "FILLPATH":
            subpaths = self.build_subpaths(parse_path(arguments[1:]), int(arguments[0]))
            sequences = [clip_polygon(subpath.points, clip) for subpath in subpaths]
            return fill_polygons(sequences, brush.rule, clip)
        if keyword == "FLOOD":
            seed = self.state.transform(int(arguments[0]), int(arguments[1]))
            return flood_fill(self.layer, seed, clip)
        return self.text_coverage(int(arguments[0]), int(arguments[1]), arguments[2], arguments[3])

    def text_coverage(self, x, y, alignment, text):
        advance = self.font.width + 1
        extent = len(text) * advance - 1
        if alignment == "left":
            left = x
        elif alignment == "center":
            left = x - extent // 2
        else:
            left = x - extent + 1
        pixels = set()
        for index, character in enumerate(text):
            if character == "_":
                continue
            origin = left + index * advance
            for column, row in self.font.glyphs[character]:
                first_x, first_y = self.state.transform(origin + column, y + row)
                second_x, second_y = self.state.transform(origin + column + 1, y + row + 1)
                for pixel_y in range(min(first_y, second_y), max(first_y, second_y)):
                    for pixel_x in range(min(first_x, second_x), max(first_x, second_x)):
                        if contains(self.state.clip, (pixel_x, pixel_y)):
                            pixels.add((pixel_x, pixel_y))
        return pixels

    def build_subpaths(self, commands, segments):
        subpaths = []
        current = (0, 0)
        start = (0, 0)
        for command in commands:
            kind = command.letter.upper()
            if kind == "Z":
                subpaths[-1].closed = True
                current = start
                continue
            points = path_points(command, current)
            device = [self.state.transform(x, y) for x, y in points]
            if kind == "M":
                subpaths.append(Subpath(device[0]))
                start = points[0]
            elif kind in ("L", "H", "V"):
                subpaths[-1].points.append(device[0])
            else:
                controls = [subpaths[-1].points[-1]] + device
                subpaths[-1].points.extend(bezier_points(controls, segments)[1:])
            current = points[-1]
        return subpaths

    def erase(self, values):
        x0, y0, x1, y1 = intersect(self.state.device_rect(*values), self.state.clip)
        erased = set()
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if self.layer.erase(x, y):
                    erased.add((x, y))
        return erased


def read_lines(name):
    with open(os.path.join(INPUT_DIR, name)) as handle:
        return handle.read().splitlines()


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w") as handle:
        handle.write("\n".join(lines) + "\n")


def read_styles(lines):
    styles = Styles()
    for line in lines:
        if not line or line.startswith("#"):
            continue
        kind, name, *values = line.split(" ")
        if kind == "color":
            styles.colors[name] = tuple(integers(values))
        elif kind == "pen":
            styles.pens[name] = Pen(int(values[0]), values[1], int(values[2]), int(values[3]))
        elif kind == "brush":
            styles.brushes[name] = Brush([values[0]], None, values[1])
        else:
            styles.brushes[name] = Brush([values[0], values[1]], values[2], values[3])
    return styles


def read_font(lines):
    _, width, height = lines[0].split(" ")
    font = Font(int(width), int(height))
    index = 1
    while index < len(lines):
        character = lines[index].split(" ")[1]
        dots = []
        for row in range(font.height):
            for column, mark in enumerate(lines[index + 1 + row]):
                if mark == "#":
                    dots.append((column, row))
        font.glyphs[character] = dots
        index += 1 + font.height
    return font


def read_scene(lines):
    scene = Scene()
    block = None
    bodies = []
    for number, line in enumerate(lines, 1):
        words = line.split()
        if not words or words[0].startswith("#"):
            continue
        keyword, arguments = words[0], words[1:]
        if keyword == "CANVAS":
            scene.width = int(arguments[0])
            scene.height = int(arguments[1])
            scene.background = arguments[2]
        elif keyword == "LAYER":
            block = LayerBlock(arguments[0], int(arguments[1]), arguments[2])
            scene.layers.append(block)
            bodies = [block.body]
        elif keyword == "SYMBOL":
            block = Block(arguments[0])
            scene.symbols[block.name] = block
            bodies = [block.body]
        elif keyword == "END":
            block.end_line = number
            bodies = []
        elif keyword == "REPEAT":
            repeat = Repeat(int(arguments[0]), int(arguments[1]), int(arguments[2]))
            bodies[-1].append(repeat)
            bodies.append(repeat.body)
        elif keyword == "ENDREPEAT":
            bodies.pop()
        else:
            bodies[-1].append(Command(number, keyword, arguments))
    return scene


def read_probes(lines):
    probes = []
    for line in lines[1:int(lines[0]) + 1]:
        kind, *values = line.split(" ")
        probes.append(Probe(kind, integers(values)))
    return probes


def command_lines(executions):
    lines = []
    for execution in executions:
        command = execution.command
        head = f"cmd {execution.sequence} line {command.line} {command.keyword}"
        if execution.kind == "error":
            lines.append(f"{head} error {execution.error}")
        elif execution.kind == "drawing":
            lines.append(f"{head} pixels {execution.pixels} box {box_text(execution.box)}")
        else:
            lines.append(f"{head} ok")
    return lines


def visible_counts(layers, width, height):
    counts = [0] * len(layers)
    for y in range(height):
        for x in range(width):
            covered = False
            for index in range(len(layers) - 1, -1, -1):
                alpha = layers[index].alpha_at(x, y)
                if alpha > 0 and not covered:
                    counts[index] += 1
                if alpha >= OPAQUE:
                    covered = True
    return counts


def layer_lines(scene, layers, executions):
    visible = visible_counts(layers, scene.width, scene.height)
    lines = [f"layers {len(layers)}"]
    for number, (block, layer) in enumerate(zip(scene.layers, layers), 1):
        own = [execution for execution in executions if execution.layer == number]
        errors = sum(execution.kind == "error" for execution in own)
        painted = []
        counts = {}
        for y in range(layer.height):
            for x in range(layer.width):
                color = layer.color_at(x, y)
                if color is not None:
                    painted.append((x, y))
                    counts[color] = counts.get(color, 0) + 1
        lines.append(
            f"layer {number} {block.name} opacity {block.opacity} mode {block.mode}"
            f" commands {len(own)} errors {errors} pixels {len(painted)}"
            f" box {box_text(bounding_box(painted))} visible {visible[number - 1]}"
            f" colors {len(counts)}"
        )
        for (red, green, blue, alpha), count in ranked(counts)[:LAYER_COLOR_LINES]:
            lines.append(f"color {red} {green} {blue} {alpha} pixels {count}")
    return lines


def symbol_uses(scene, executions):
    uses = dict.fromkeys(scene.symbols, 0)
    for execution in executions:
        if execution.kind == "state" and execution.command.keyword == "USE":
            uses[execution.command.arguments[0]] += 1
    return uses


def keyword_tallies(executions):
    tallies = {}
    for execution in executions:
        tally = tallies.setdefault(execution.command.keyword, KeywordTally())
        tally.executed += 1
        if execution.kind == "error":
            tally.errors += 1
        elif execution.kind == "drawing":
            tally.pixels += execution.pixels
    return tallies


def unused_items(scene, styles, executions):
    used_pens = set()
    used_brushes = set()
    for execution in executions:
        if execution.kind != "drawing":
            continue
        keyword = execution.command.keyword
        if keyword in PEN_COMMANDS:
            used_pens.add(execution.command.arguments[0])
        elif keyword in BRUSH_COMMANDS:
            used_brushes.add(execution.command.arguments[0])
    used_colors = {scene.background}
    for name in used_pens:
        used_colors.add(styles.pens[name].color)
    for name in used_brushes:
        used_colors.update(styles.brushes[name].colors)
    uses = symbol_uses(scene, executions)
    unused = [("color", name) for name in sorted(styles.colors) if name not in used_colors]
    unused.extend(("pen", name) for name in sorted(styles.pens) if name not in used_pens)
    unused.extend(("brush", name) for name in sorted(styles.brushes) if name not in used_brushes)
    unused.extend(("symbol", name) for name in sorted(scene.symbols) if uses[name] == 0)
    return unused


def image_color_counts(image):
    counts = {}
    for row in image:
        for color in row:
            counts[color] = counts.get(color, 0) + 1
    return counts


def summary_lines(scene, styles, executions, image):
    red, green, blue, _ = styles.colors[scene.background]
    kinds = [execution.kind for execution in executions]
    lines = [
        f"canvas {scene.width} {scene.height}",
        f"background {red} {green} {blue}",
        f"layers {len(scene.layers)}",
        f"symbols {len(scene.symbols)}",
        f"commands {len(executions)}",
        f"drawing {kinds.count('drawing')}",
        f"state {kinds.count('state')}",
        f"errors {kinds.count('error')}",
    ]
    for name in ERROR_NAMES:
        count = sum(execution.error == name for execution in executions)
        lines.append(f"error {name} {count}")
    painted = 0
    erased = 0
    for execution in executions:
        if execution.kind == "drawing" and execution.command.keyword == "ERASE":
            erased += execution.pixels
        elif execution.kind == "drawing":
            painted += execution.pixels
    lines.append(f"painted {painted}")
    lines.append(f"erased {erased}")
    counts = image_color_counts(image)
    lines.append(f"colors {len(counts)}")
    for rank, ((red, green, blue), count) in enumerate(ranked(counts)[:TOP_COLOR_LINES], 1):
        lines.append(f"top {rank} {red} {green} {blue} pixels {count}")
    uses = symbol_uses(scene, executions)
    for name in sorted(scene.symbols):
        lines.append(f"symbol {name} uses {uses[name]}")
    tallies = keyword_tallies(executions)
    for keyword in sorted(tallies):
        tally = tallies[keyword]
        lines.append(
            f"keyword {keyword} executed {tally.executed} errors {tally.errors} pixels {tally.pixels}"
        )
    unused = unused_items(scene, styles, executions)
    lines.append(f"unused {len(unused)}")
    for kind, name in unused:
        lines.append(f"unused {kind} {name}")
    return lines


def point_line(number, probe, image, layers):
    x, y = probe.values
    red, green, blue = image[y][x]
    stack = [
        f"{index}:{layer.line_at(x, y)}"
        for index, layer in enumerate(layers, 1)
        if layer.alpha_at(x, y) > 0
    ]
    overlap = " ".join(stack) if stack else "none"
    return f"point {number} {x} {y} rgb {red} {green} {blue} layers {len(stack)} stack {overlap}"


def area_line(number, probe, image, layers):
    x0, y0, x1, y1 = probe.values
    totals = [0, 0, 0]
    colors = set()
    cover = [0] * len(layers)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            color = image[y][x]
            colors.add(color)
            for channel in range(3):
                totals[channel] += color[channel]
            for index, layer in enumerate(layers):
                if layer.alpha_at(x, y) > 0:
                    cover[index] += 1
    count = (x1 - x0 + 1) * (y1 - y0 + 1)
    means = " ".join(str(total // count) for total in totals)
    covers = " ".join(str(value) for value in cover)
    return (
        f"area {number} {x0} {y0} {x1} {y1} pixels {count} mean {means}"
        f" colors {len(colors)} cover {covers}"
    )


def probe_lines(probes, image, layers):
    lines = []
    for number, probe in enumerate(probes, 1):
        if probe.kind == "point":
            lines.append(point_line(number, probe, image, layers))
        else:
            lines.append(area_line(number, probe, image, layers))
    return lines


def main():
    styles = read_styles(read_lines("styles.txt"))
    font = read_font(read_lines("font.txt"))
    scene = read_scene(read_lines("scene.txt"))
    probes = read_probes(read_lines("probes.txt"))
    renderer = Renderer(scene, styles, font)
    renderer.run()
    background = styles.colors[scene.background]
    image = composite(renderer.layers, background, scene.width, scene.height)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_ppm(os.path.join(OUTPUT_DIR, "image.ppm"), image)
    write_preview(os.path.join(OUTPUT_DIR, "preview.txt"), image)
    write_lines("commands.txt", command_lines(renderer.executions))
    write_lines("layers.txt", layer_lines(scene, renderer.layers, renderer.executions))
    write_lines("summary.txt", summary_lines(scene, styles, renderer.executions, image))
    write_lines("probes.txt", probe_lines(probes, image, renderer.layers))


if __name__ == "__main__":
    main()
