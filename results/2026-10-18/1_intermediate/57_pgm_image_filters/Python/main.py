from itertools import accumulate
import re
import sys


INTEGER_WORD = re.compile(r"0|-?[1-9][0-9]{0,6}")
NAME_WORD = re.compile(r"[a-z]{1,8}")
DIGIT_WORD = re.compile(r"[0-9]+")
MAX_SIDE = 64
MAX_MAXVAL = 255
COORDINATE_LIMIT = 1000
SHADES = "@#*+=~-:,."
HISTOGRAM_BINS = 16
BAR_LENGTH = 32
NEIGHBORHOOD = (
    (-1, -1), (0, -1), (1, -1),
    (-1, 0), (0, 0), (1, 0),
    (-1, 1), (0, 1), (1, 1),
)
FOUR_NEIGHBORS = ((0, -1), (-1, 0), (1, 0), (0, 1))
EIGHT_NEIGHBORS = (
    (-1, -1), (0, -1), (1, -1), (-1, 0),
    (1, 0), (-1, 1), (0, 1), (1, 1),
)
KERNELS = {
    "BLUR": ((1, 1, 1, 1, 1, 1, 1, 1, 1), 9),
    "GAUSS": ((1, 2, 1, 2, 4, 2, 1, 2, 1), 16),
    "SHARPEN": ((0, -1, 0, -1, 5, -1, 0, -1, 0), 1),
}
ERODE_RANK = 0
MEDIAN_RANK = 4
DILATE_RANK = 8
RANKS = {"ERODE": ERODE_RANK, "MEDIAN": MEDIAN_RANK, "DILATE": DILATE_RANK}
DIFFUSION = ((1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1))
FILL_COMMANDS = ("RECT", "CIRCLE")
IMAGELESS_COMMANDS = ("NEW", "RECALL", "DROP", "SLOTS", "INFO", "UNDO", "REDO")
SLOT_COMMANDS = ("RECALL", "DROP", "BLEND", "DIFF", "PASTE")


class CommandError(Exception):
    pass


def require(condition, reason="bad value"):
    if not condition:
        raise CommandError(reason)


def within_limit(*values):
    return all(-COORDINATE_LIMIT <= value <= COORDINATE_LIMIT for value in values)


class Image:
    def __init__(self, width, height, maxval, pixels):
        self.width = width
        self.height = height
        self.maxval = maxval
        self.pixels = pixels

    def get(self, x, y):
        return self.pixels[y * self.width + x]

    def row(self, y):
        return self.pixels[y * self.width:(y + 1) * self.width]

    def contains(self, x, y):
        return 0 <= x < self.width and 0 <= y < self.height

    def clamp(self, value):
        return min(max(value, 0), self.maxval)

    def with_pixels(self, pixels):
        return Image(self.width, self.height, self.maxval, pixels)

    def neighborhood(self, x, y):
        values = []
        for dx, dy in NEIGHBORHOOD:
            nx = min(max(x + dx, 0), self.width - 1)
            ny = min(max(y + dy, 0), self.height - 1)
            values.append(self.get(nx, ny))
        return values

    def checksum(self):
        return sum((index + 1) * value for index, value in enumerate(self.pixels))

    def summary(self):
        return f"{self.width}x{self.height} maxval {self.maxval} checksum {self.checksum()}"


class Command:
    def __init__(self, name, numbers, slot, fill):
        self.name = name
        self.numbers = numbers
        self.slot = slot
        self.fill = fill


def header_value(words, position, limit, reason):
    require(position < len(words), "truncated header")
    word = words[position]
    require(DIGIT_WORD.fullmatch(word) is not None, "bad number")
    value = int(word)
    require(1 <= value <= limit, reason)
    return value


def read_pgm(lines):
    words = []
    for line in lines:
        words.extend(line.partition("#")[0].split())
    require(words and words[0] == "P2", "bad magic")
    width = header_value(words, 1, MAX_SIDE, "bad size")
    height = header_value(words, 2, MAX_SIDE, "bad size")
    maxval = header_value(words, 3, MAX_MAXVAL, "bad maxval")
    values = words[4:]
    total = width * height
    pixels = []
    for index in range(total):
        x, y = index % width, index // width
        require(index < len(values), f"too few pixels ({len(values)} of {total})")
        word = values[index]
        require(DIGIT_WORD.fullmatch(word) is not None, f"bad pixel at {x},{y}")
        require(int(word) <= maxval, f"pixel out of range at {x},{y}")
        pixels.append(int(word))
    require(len(values) <= total, f"too many pixels ({len(values)} of {total})")
    return Image(width, height, maxval, pixels)


def rotated(image, angle):
    width, height = image.width, image.height
    if angle == 180:
        pixels = [
            image.get(width - 1 - x, height - 1 - y)
            for y in range(height) for x in range(width)
        ]
        return image.with_pixels(pixels)
    if angle == 90:
        pixels = [image.get(y, height - 1 - x) for y in range(width) for x in range(height)]
    else:
        pixels = [image.get(width - 1 - y, x) for y in range(width) for x in range(height)]
    return Image(height, width, image.maxval, pixels)


def cropped(image, left, top, width, height):
    pixels = [image.get(left + i, top + j) for j in range(height) for i in range(width)]
    return Image(width, height, image.maxval, pixels)


def translated(image, width, height, dx, dy, fill):
    pixels = []
    for y in range(height):
        for x in range(width):
            if image.contains(x - dx, y - dy):
                pixels.append(image.get(x - dx, y - dy))
            else:
                pixels.append(fill)
    return Image(width, height, image.maxval, pixels)


def scaled(image, width, height, numerator, denominator):
    pixels = []
    for y in range(height):
        source_y = (2 * y + 1) * denominator // (2 * numerator)
        for x in range(width):
            source_x = (2 * x + 1) * denominator // (2 * numerator)
            pixels.append(image.get(source_x, source_y))
    return Image(width, height, image.maxval, pixels)


def convolution(image, kernel, divisor):
    pixels = []
    for y in range(image.height):
        for x in range(image.width):
            total = sum(k * q for k, q in zip(kernel, image.neighborhood(x, y)))
            pixels.append(image.clamp(total // divisor))
    return image.with_pixels(pixels)


def rank_filtered(image, rank):
    pixels = [
        sorted(image.neighborhood(x, y))[rank]
        for y in range(image.height) for x in range(image.width)
    ]
    return image.with_pixels(pixels)


def sobel_edges(image):
    pixels = []
    for y in range(image.height):
        for x in range(image.width):
            q = image.neighborhood(x, y)
            gx = (q[2] + 2 * q[5] + q[8]) - (q[0] + 2 * q[3] + q[6])
            gy = (q[6] + 2 * q[7] + q[8]) - (q[0] + 2 * q[1] + q[2])
            pixels.append(image.clamp(abs(gx) + abs(gy)))
    return image.with_pixels(pixels)


def line_points(x0, y0, x1, y1):
    dx = abs(x1 - x0)
    dy = -abs(y1 - y0)
    step_x = 1 if x0 < x1 else -1
    step_y = 1 if y0 < y1 else -1
    error = dx + dy
    x, y = x0, y0
    points = []
    while True:
        points.append((x, y))
        if x == x1 and y == y1:
            return points
        doubled = 2 * error
        if doubled >= dy:
            error += dy
            x += step_x
        if doubled <= dx:
            error += dx
            y += step_y


def rectangle_points(image, left, top, width, height, filled):
    right = left + width - 1
    bottom = top + height - 1
    points = []
    for y in range(max(top, 0), min(bottom, image.height - 1) + 1):
        for x in range(max(left, 0), min(right, image.width - 1) + 1):
            if filled or x == left or x == right or y == top or y == bottom:
                points.append((x, y))
    return points


def circle_points(cx, cy, radius):
    a, b = radius, 0
    error = 1 - radius
    points = []
    while a >= b:
        points.extend((
            (cx + a, cy + b), (cx + b, cy + a), (cx - b, cy + a), (cx - a, cy + b),
            (cx - a, cy - b), (cx - b, cy - a), (cx + b, cy - a), (cx + a, cy - b),
        ))
        b += 1
        if error < 0:
            error += 2 * b + 1
        else:
            a -= 1
            error += 2 * (b - a) + 1
    return points


def disc_points(image, outline):
    spans = {}
    for x, y in outline:
        if y in spans:
            low, high = spans[y]
            spans[y] = (min(low, x), max(high, x))
        else:
            spans[y] = (x, x)
    points = []
    for y, (low, high) in spans.items():
        if 0 <= y < image.height:
            for x in range(max(low, 0), min(high, image.width - 1) + 1):
                points.append((x, y))
    return points


def flood_points(image, x, y):
    target = image.get(x, y)
    visited = [False] * len(image.pixels)
    visited[y * image.width + x] = True
    stack = [(x, y)]
    points = []
    while stack:
        cx, cy = stack.pop()
        points.append((cx, cy))
        for dx, dy in FOUR_NEIGHBORS:
            nx, ny = cx + dx, cy + dy
            if not image.contains(nx, ny) or image.get(nx, ny) != target:
                continue
            index = ny * image.width + nx
            if not visited[index]:
                visited[index] = True
                stack.append((nx, ny))
    return points


def equalized(image):
    total = len(image.pixels)
    counts = [0] * (image.maxval + 1)
    for pixel in image.pixels:
        counts[pixel] += 1
    cdf = list(accumulate(counts))
    lowest = cdf[min(image.pixels)]
    if lowest == total:
        return image
    span = total - lowest
    pixels = [
        (2 * (cdf[pixel] - lowest) * image.maxval + span) // (2 * span)
        for pixel in image.pixels
    ]
    return image.with_pixels(pixels)


def components(image, threshold):
    width = image.width
    foreground = [pixel >= threshold for pixel in image.pixels]
    visited = [False] * len(image.pixels)
    result = []
    for start in range(len(image.pixels)):
        if not foreground[start] or visited[start]:
            continue
        visited[start] = True
        stack = [(start % width, start // width)]
        members = []
        while stack:
            x, y = stack.pop()
            members.append((x, y))
            for dx, dy in EIGHT_NEIGHBORS:
                nx, ny = x + dx, y + dy
                if not image.contains(nx, ny):
                    continue
                index = ny * width + nx
                if foreground[index] and not visited[index]:
                    visited[index] = True
                    stack.append((nx, ny))
        result.append(members)
    return result


def on_boundary(image, x, y, threshold):
    for dx, dy in FOUR_NEIGHBORS:
        nx, ny = x + dx, y + dy
        if not image.contains(nx, ny) or image.get(nx, ny) < threshold:
            return True
    return False


def component_text(image, threshold, members):
    xs = [x for x, _ in members]
    ys = [y for _, y in members]
    area = len(members)
    perimeter = sum(1 for x, y in members if on_boundary(image, x, y, threshold))
    return (
        f"area {area} perimeter {perimeter} box {min(xs)} {min(ys)} {max(xs)} {max(ys)}"
        f" center {sum(xs) // area} {sum(ys) // area}"
    )


def distance_map(image, threshold):
    width, height = image.width, image.height
    if all(pixel >= threshold for pixel in image.pixels):
        return image.with_pixels([image.maxval] * len(image.pixels))
    far = width + height
    distances = [0 if pixel < threshold else far for pixel in image.pixels]
    for y in range(height):
        for x in range(width):
            index = y * width + x
            if x > 0:
                distances[index] = min(distances[index], distances[index - 1] + 1)
            if y > 0:
                distances[index] = min(distances[index], distances[index - width] + 1)
    for y in range(height - 1, -1, -1):
        for x in range(width - 1, -1, -1):
            index = y * width + x
            if x < width - 1:
                distances[index] = min(distances[index], distances[index + 1] + 1)
            if y < height - 1:
                distances[index] = min(distances[index], distances[index + width] + 1)
    return image.with_pixels([min(distance, image.maxval) for distance in distances])


def statistics_text(values, maxval):
    ordered = sorted(values)
    count = len(ordered)
    occurrences = [0] * (maxval + 1)
    for value in ordered:
        occurrences[value] += 1
    mode = occurrences.index(max(occurrences))
    return (
        f"min {ordered[0]} max {ordered[-1]} mean {sum(ordered) // count}"
        f" median {ordered[(count - 1) // 2]} mode {mode}"
    )


def dithered(image):
    width, maxval = image.width, image.maxval
    errors = list(image.pixels)
    pixels = [0] * len(errors)
    for y in range(image.height):
        for x in range(width):
            old = errors[y * width + x]
            new = maxval if 2 * old >= maxval else 0
            pixels[y * width + x] = new
            error = old - new
            for dx, dy, weight in DIFFUSION:
                if image.contains(x + dx, y + dy):
                    errors[(y + dy) * width + x + dx] += error * weight // 16
    return image.with_pixels(pixels)


class ImageEditor:
    def __init__(self):
        self.current = None
        self.undo_history = []
        self.redo_history = []
        self.slots = {}
        self.output = []
        self.handlers = {
            "NEW": ("iiii", self.new_image),
            "OUTPUT": ("", self.write_image),
            "INVERT": ("", self.invert),
            "BRIGHTNESS": ("i", self.brightness),
            "CONTRAST": ("ii", self.contrast),
            "THRESHOLD": ("i", self.threshold),
            "LEVELS": ("ii", self.levels),
            "POSTERIZE": ("i", self.posterize),
            "MAXVAL": ("i", self.change_maxval),
            "FLIPH": ("", self.flip),
            "FLIPV": ("", self.flip),
            "ROTATE": ("i", self.rotate),
            "CROP": ("iiii", self.crop),
            "PAD": ("ii", self.pad),
            "SCALE": ("ii", self.scale),
            "SHIFT": ("iii", self.shift),
            "TILE": ("ii", self.tile),
            "BLUR": ("", self.kernel_filter),
            "GAUSS": ("", self.kernel_filter),
            "SHARPEN": ("", self.kernel_filter),
            "CONVOLVE": ("iiiiiiiiii", self.convolve),
            "SOBEL": ("", self.sobel),
            "MEDIAN": ("", self.rank_filter),
            "ERODE": ("", self.rank_filter),
            "DILATE": ("", self.rank_filter),
            "OPEN": ("", self.morphology),
            "CLOSE": ("", self.morphology),
            "GRADIENT": ("", self.morphology),
            "LINE": ("iiiii", self.line),
            "RECT": ("iiiii", self.rect),
            "CIRCLE": ("iiii", self.circle),
            "FLOOD": ("iii", self.flood),
            "HISTOGRAM": ("", self.histogram),
            "EQUALIZE": ("", self.equalize),
            "LABEL": ("i", self.label),
            "DISTANCE": ("i", self.distance),
            "STATS": ("", self.stats),
            "REGION": ("iiii", self.region),
            "DITHER": ("", self.dither),
            "ASCIIART": ("", self.ascii_art),
            "STORE": ("n", self.store),
            "RECALL": ("n", self.recall),
            "DROP": ("n", self.drop),
            "BLEND": ("nii", self.blend),
            "DIFF": ("n", self.diff),
            "PASTE": ("nii", self.paste),
            "SLOTS": ("", self.list_slots),
            "INFO": ("", self.info),
            "UNDO": ("", self.undo),
            "REDO": ("", self.redo),
        }

    def emit(self, line):
        self.output.append(line)

    def parse(self, words):
        name, arguments = words[0], words[1:]
        if name not in self.handlers:
            raise CommandError("unknown command " + name)
        pattern = self.handlers[name][0]
        fill = (
            name in FILL_COMMANDS
            and len(arguments) == len(pattern) + 1
            and arguments[-1] == "FILL"
        )
        if fill:
            arguments = arguments[:-1]
        require(len(arguments) == len(pattern), "bad arguments")
        numbers = []
        slot = None
        for kind, word in zip(pattern, arguments):
            if kind == "i":
                require(INTEGER_WORD.fullmatch(word) is not None, "bad arguments")
                numbers.append(int(word))
            else:
                require(NAME_WORD.fullmatch(word) is not None, "bad arguments")
                slot = word
        return Command(name, numbers, slot, fill)

    def execute(self, words):
        try:
            command = self.parse(words)
            if command.name not in IMAGELESS_COMMANDS:
                require(self.current is not None, "no image")
            if command.name in SLOT_COMMANDS:
                require(command.slot in self.slots, "no slot " + command.slot)
            self.handlers[command.name][1](command)
        except CommandError as error:
            self.emit(f"error: {error}")

    def load(self, lines):
        try:
            image = read_pgm(lines)
        except CommandError as error:
            self.emit(f"error: load: {error}")
            return
        self.replace(image, "loaded")

    def replace(self, image, label):
        self.current = image
        self.undo_history.clear()
        self.redo_history.clear()
        self.emit(f"{label} {image.summary()}")

    def commit(self, image, painted=None):
        self.undo_history.append(self.current)
        self.redo_history.clear()
        self.current = image
        line = "ok " + image.summary()
        if painted is not None:
            line += f" painted {painted}"
        self.emit(line)

    def paint(self, points, value):
        image = self.current
        marked = [False] * len(image.pixels)
        for x, y in points:
            if image.contains(x, y):
                marked[y * image.width + x] = True
        pixels = [value if mark else pixel for mark, pixel in zip(marked, image.pixels)]
        self.commit(image.with_pixels(pixels), sum(marked))

    def crop_area(self, command):
        left, top, width, height = command.numbers
        image = self.current
        require(left >= 0 and top >= 0 and width >= 1 and height >= 1)
        require(left + width <= image.width and top + height <= image.height)
        return left, top, width, height

    def matching_slot(self, command):
        other = self.slots[command.slot]
        image = self.current
        require(other.width == image.width and other.height == image.height, "size mismatch")
        require(other.maxval == image.maxval, "maxval mismatch")
        return other

    def new_image(self, command):
        width, height, maxval, value = command.numbers
        require(1 <= width <= MAX_SIDE and 1 <= height <= MAX_SIDE)
        require(1 <= maxval <= MAX_MAXVAL and 0 <= value <= maxval)
        self.replace(Image(width, height, maxval, [value] * (width * height)), "created")

    def write_image(self, command):
        image = self.current
        self.emit("P2")
        self.emit(f"{image.width} {image.height}")
        self.emit(str(image.maxval))
        for y in range(image.height):
            self.emit(" ".join(str(value) for value in image.row(y)))

    def invert(self, command):
        image = self.current
        self.commit(image.with_pixels([image.maxval - pixel for pixel in image.pixels]))

    def brightness(self, command):
        delta = command.numbers[0]
        require(-MAX_MAXVAL <= delta <= MAX_MAXVAL)
        image = self.current
        self.commit(image.with_pixels([image.clamp(pixel + delta) for pixel in image.pixels]))

    def contrast(self, command):
        numerator, denominator = command.numbers
        require(0 <= numerator <= 100 and 1 <= denominator <= 100)
        image = self.current
        center = (image.maxval + 1) // 2
        pixels = [
            image.clamp(center + (pixel - center) * numerator // denominator)
            for pixel in image.pixels
        ]
        self.commit(image.with_pixels(pixels))

    def threshold(self, command):
        level = command.numbers[0]
        image = self.current
        require(0 <= level <= image.maxval)
        pixels = [image.maxval if pixel >= level else 0 for pixel in image.pixels]
        self.commit(image.with_pixels(pixels))

    def levels(self, command):
        low, high = command.numbers
        image = self.current
        require(0 <= low < high <= image.maxval)
        pixels = [
            image.clamp((pixel - low) * image.maxval // (high - low))
            for pixel in image.pixels
        ]
        self.commit(image.with_pixels(pixels))

    def posterize(self, command):
        count = command.numbers[0]
        image = self.current
        maxval = image.maxval
        require(2 <= count <= maxval + 1)
        pixels = [
            (pixel * count // (maxval + 1)) * maxval // (count - 1)
            for pixel in image.pixels
        ]
        self.commit(image.with_pixels(pixels))

    def change_maxval(self, command):
        target = command.numbers[0]
        require(1 <= target <= MAX_MAXVAL)
        image = self.current
        old = image.maxval
        pixels = [(2 * pixel * target + old) // (2 * old) for pixel in image.pixels]
        self.commit(Image(image.width, image.height, target, pixels))

    def flip(self, command):
        image = self.current
        width, height = image.width, image.height
        if command.name == "FLIPH":
            pixels = [image.get(width - 1 - x, y) for y in range(height) for x in range(width)]
        else:
            pixels = [image.get(x, height - 1 - y) for y in range(height) for x in range(width)]
        self.commit(image.with_pixels(pixels))

    def rotate(self, command):
        angle = command.numbers[0]
        require(angle in (90, 180, 270))
        self.commit(rotated(self.current, angle))

    def crop(self, command):
        self.commit(cropped(self.current, *self.crop_area(command)))

    def pad(self, command):
        border, value = command.numbers
        image = self.current
        require(border >= 1 and 0 <= value <= image.maxval)
        width = image.width + 2 * border
        height = image.height + 2 * border
        require(width <= MAX_SIDE and height <= MAX_SIDE, "too large")
        self.commit(translated(image, width, height, border, border, value))

    def scale(self, command):
        numerator, denominator = command.numbers
        require(1 <= numerator <= 16 and 1 <= denominator <= 16)
        image = self.current
        width = image.width * numerator // denominator
        height = image.height * numerator // denominator
        require(width > 0 and height > 0, "too small")
        require(width <= MAX_SIDE and height <= MAX_SIDE, "too large")
        self.commit(scaled(image, width, height, numerator, denominator))

    def shift(self, command):
        dx, dy, value = command.numbers
        image = self.current
        require(within_limit(dx, dy) and 0 <= value <= image.maxval)
        self.commit(translated(image, image.width, image.height, dx, dy, value))

    def tile(self, command):
        across, down = command.numbers
        require(across >= 1 and down >= 1)
        image = self.current
        width = image.width * across
        height = image.height * down
        require(width <= MAX_SIDE and height <= MAX_SIDE, "too large")
        pixels = [
            image.get(x % image.width, y % image.height)
            for y in range(height) for x in range(width)
        ]
        self.commit(Image(width, height, image.maxval, pixels))

    def kernel_filter(self, command):
        kernel, divisor = KERNELS[command.name]
        self.commit(convolution(self.current, kernel, divisor))

    def convolve(self, command):
        kernel, divisor = command.numbers[:9], command.numbers[9]
        require(all(-16 <= weight <= 16 for weight in kernel) and 1 <= divisor <= 256)
        self.commit(convolution(self.current, kernel, divisor))

    def sobel(self, command):
        self.commit(sobel_edges(self.current))

    def rank_filter(self, command):
        self.commit(rank_filtered(self.current, RANKS[command.name]))

    def morphology(self, command):
        image = self.current
        if command.name == "OPEN":
            result = rank_filtered(rank_filtered(image, ERODE_RANK), DILATE_RANK)
        elif command.name == "CLOSE":
            result = rank_filtered(rank_filtered(image, DILATE_RANK), ERODE_RANK)
        else:
            dilated = rank_filtered(image, DILATE_RANK)
            eroded = rank_filtered(image, ERODE_RANK)
            result = image.with_pixels([
                high - low for high, low in zip(dilated.pixels, eroded.pixels)
            ])
        self.commit(result)

    def line(self, command):
        x0, y0, x1, y1, value = command.numbers
        require(within_limit(x0, y0, x1, y1) and 0 <= value <= self.current.maxval)
        self.paint(line_points(x0, y0, x1, y1), value)

    def rect(self, command):
        left, top, width, height, value = command.numbers
        require(within_limit(left, top))
        require(1 <= width <= COORDINATE_LIMIT and 1 <= height <= COORDINATE_LIMIT)
        require(0 <= value <= self.current.maxval)
        points = rectangle_points(self.current, left, top, width, height, command.fill)
        self.paint(points, value)

    def circle(self, command):
        cx, cy, radius, value = command.numbers
        require(within_limit(cx, cy) and 0 <= radius <= COORDINATE_LIMIT)
        require(0 <= value <= self.current.maxval)
        points = circle_points(cx, cy, radius)
        if command.fill:
            points = disc_points(self.current, points)
        self.paint(points, value)

    def flood(self, command):
        x, y, value = command.numbers
        image = self.current
        require(image.contains(x, y) and 0 <= value <= image.maxval)
        self.paint(flood_points(image, x, y), value)

    def histogram(self, command):
        image = self.current
        levels = image.maxval + 1
        lows = [None] * HISTOGRAM_BINS
        highs = [0] * HISTOGRAM_BINS
        counts = [0] * HISTOGRAM_BINS
        for value in range(levels):
            number = value * HISTOGRAM_BINS // levels
            if lows[number] is None:
                lows[number] = value
            highs[number] = value
        for pixel in image.pixels:
            counts[pixel * HISTOGRAM_BINS // levels] += 1
        used = [number for number in range(HISTOGRAM_BINS) if lows[number] is not None]
        top = max(counts[number] for number in used)
        for number in used:
            bar = "#" * (counts[number] * BAR_LENGTH // top)
            self.emit(f"{lows[number]:3d}-{highs[number]:3d} {counts[number]:4d} |{bar}")

    def equalize(self, command):
        self.commit(equalized(self.current))

    def label(self, command):
        threshold = command.numbers[0]
        image = self.current
        require(0 <= threshold <= image.maxval)
        found = components(image, threshold)
        self.emit(f"labels {len(found)}")
        for number, members in enumerate(found, 1):
            self.emit(f"label {number} {component_text(image, threshold, members)}")

    def distance(self, command):
        threshold = command.numbers[0]
        image = self.current
        require(0 <= threshold <= image.maxval)
        self.commit(distance_map(image, threshold))

    def stats(self, command):
        self.emit(statistics_text(self.current.pixels, self.current.maxval))

    def region(self, command):
        part = cropped(self.current, *self.crop_area(command))
        self.emit(statistics_text(part.pixels, part.maxval))

    def dither(self, command):
        self.commit(dithered(self.current))

    def ascii_art(self, command):
        image = self.current
        for y in range(image.height):
            self.emit("".join(
                SHADES[pixel * len(SHADES) // (image.maxval + 1)] for pixel in image.row(y)
            ))

    def store(self, command):
        self.slots[command.slot] = self.current
        self.emit(f"stored {command.slot} {self.current.summary()}")

    def recall(self, command):
        self.replace(self.slots[command.slot], "recalled " + command.slot)

    def drop(self, command):
        del self.slots[command.slot]
        self.emit("dropped " + command.slot)

    def blend(self, command):
        weight, total = command.numbers
        require(0 <= weight <= total and 1 <= total <= 100)
        other = self.matching_slot(command)
        image = self.current
        pixels = [
            (pixel * (total - weight) + source * weight) // total
            for pixel, source in zip(image.pixels, other.pixels)
        ]
        self.commit(image.with_pixels(pixels))

    def diff(self, command):
        other = self.matching_slot(command)
        image = self.current
        pixels = [abs(pixel - source) for pixel, source in zip(image.pixels, other.pixels)]
        self.commit(image.with_pixels(pixels))

    def paste(self, command):
        left, top = command.numbers
        require(within_limit(left, top))
        other = self.slots[command.slot]
        image = self.current
        require(other.maxval == image.maxval, "maxval mismatch")
        pixels = list(image.pixels)
        painted = 0
        for j in range(other.height):
            for i in range(other.width):
                if image.contains(left + i, top + j):
                    pixels[(top + j) * image.width + left + i] = other.get(i, j)
                    painted += 1
        self.commit(image.with_pixels(pixels), painted)

    def list_slots(self, command):
        if not self.slots:
            self.emit("no slots")
        for name in sorted(self.slots):
            self.emit(f"{name} {self.slots[name].summary()}")

    def info(self, command):
        summary = "none" if self.current is None else self.current.summary()
        self.emit(
            f"image {summary} undo {len(self.undo_history)}"
            f" redo {len(self.redo_history)} slots {len(self.slots)}"
        )

    def undo(self, command):
        require(self.undo_history, "nothing to undo")
        self.redo_history.append(self.current)
        self.current = self.undo_history.pop()
        self.emit("undo " + self.current.summary())

    def redo(self, command):
        require(self.redo_history, "nothing to redo")
        self.undo_history.append(self.current)
        self.current = self.redo_history.pop()
        self.emit("redo " + self.current.summary())


def main():
    editor = ImageEditor()
    count = int(sys.stdin.readline())
    for _ in range(count):
        words = sys.stdin.readline().rstrip("\n").split(" ")
        if words[0] == "LOAD":
            lines = [sys.stdin.readline().rstrip("\n") for _ in range(int(words[1]))]
            editor.load(lines)
        else:
            editor.execute(words)
    sys.stdout.write("\n".join(editor.output) + "\n")


if __name__ == "__main__":
    main()
