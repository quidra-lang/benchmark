from fractions import Fraction
from math import isqrt
import re
import sys


BUILTINS = [
    ("black", (0, 0, 0)), ("maroon", (128, 0, 0)),
    ("green", (0, 128, 0)), ("olive", (128, 128, 0)),
    ("navy", (0, 0, 128)), ("purple", (128, 0, 128)),
    ("teal", (0, 128, 128)), ("silver", (192, 192, 192)),
    ("gray", (128, 128, 128)), ("red", (255, 0, 0)),
    ("lime", (0, 255, 0)), ("yellow", (255, 255, 0)),
    ("blue", (0, 0, 255)), ("magenta", (255, 0, 255)),
    ("cyan", (0, 255, 255)), ("white", (255, 255, 255)),
    ("orange", (255, 165, 0)), ("pink", (255, 192, 203)),
    ("brown", (165, 42, 42)), ("gold", (255, 215, 0)),
    ("coral", (255, 127, 80)), ("salmon", (250, 128, 114)),
    ("violet", (238, 130, 238)), ("indigo", (75, 0, 130)),
]
BUILTIN_NAMES = dict(BUILTINS)
SIMULATION = {
    "PROTANOPIA": ((567, 433, 0), (558, 442, 0), (0, 242, 758)),
    "DEUTERANOPIA": ((625, 375, 0), (700, 300, 0), (0, 300, 700)),
    "TRITANOPIA": ((950, 50, 0), (0, 433, 567), (0, 475, 525)),
    "ACHROMATOPSIA": ((299, 587, 114),) * 3,
}
HUE_NAMES = (
    "red", "orange", "yellow", "chartreuse", "green", "spring-green",
    "cyan", "azure", "blue", "violet", "magenta", "rose",
)


class InvalidCommand(Exception):
    pass


def require(condition):
    if not condition:
        raise InvalidCommand


def integer(text, minimum, maximum):
    require(re.fullmatch(r"-?[0-9]{1,9}", text) is not None)
    value = int(text)
    require(minimum <= value <= maximum)
    return value


def registered_name(text):
    require(re.fullmatch(r"[a-z]{1,12}", text) is not None)
    return text


def round_exact(value):
    value = Fraction(value)
    return (2 * value.numerator + value.denominator) // (2 * value.denominator)


def round_ratio(numerator, denominator):
    return round_exact(Fraction(numerator, denominator))


def away(value):
    return -round_exact(-value) if value < 0 else round_exact(value)


def clamp(value):
    return min(255, max(0, value))


def hex_color(color):
    return "#" + "".join(f"{component:02X}" for component in color)


def color_sequence(colors):
    return " ".join(map(hex_color, colors))


def distance(first, second):
    return sum((a - b) ** 2 for a, b in zip(first, second))


def hue(color):
    red, green, blue = color
    maximum = max(color)
    delta = maximum - min(color)
    if delta == 0:
        return 0
    if maximum == red:
        angle = Fraction(60 * (green - blue), delta)
        if angle < 0:
            angle += 360
    elif maximum == green:
        angle = Fraction(60 * (blue - red), delta) + 120
    else:
        angle = Fraction(60 * (red - green), delta) + 240
    return round_exact(angle) % 360


def hsl(color):
    maximum, minimum = max(color), min(color)
    delta = maximum - minimum
    total = maximum + minimum
    saturation = 0 if delta == 0 else round_ratio(100 * delta, 255 - abs(total - 255))
    return hue(color), saturation, round_ratio(100 * total, 510)


def hsv(color):
    maximum = max(color)
    saturation = 0 if maximum == 0 else round_ratio(100 * (maximum - min(color)), maximum)
    return hue(color), saturation, round_ratio(100 * maximum, 255)


def hwb(color):
    return hue(color), round_ratio(100 * min(color), 255), round_ratio(100 * (255 - max(color)), 255)


def cmyk(color):
    maximum = max(color)
    if maximum == 0:
        return 0, 0, 0, 100
    return tuple(round_ratio(100 * (maximum - x), maximum) for x in color) + (
        round_ratio(100 * (255 - maximum), 255),
    )


def ycbcr(color):
    red, green, blue = color
    return (
        clamp(round_ratio(299 * red + 587 * green + 114 * blue, 1000)),
        clamp(round_ratio(128000 - 169 * red - 331 * green + 500 * blue, 1000)),
        clamp(round_ratio(128000 + 500 * red - 419 * green - 81 * blue, 1000)),
    )


def yiq(color):
    red, green, blue = color
    return (
        round_ratio(299 * red + 587 * green + 114 * blue, 1000),
        round_ratio(596 * red - 274 * green - 322 * blue, 1000),
        round_ratio(211 * red - 523 * green + 312 * blue, 1000),
    )


def model_notation(model, values):
    if model in ("hsl", "hsv", "hwb"):
        return f"{model}({values[0]},{values[1]}%,{values[2]}%)"
    suffix = "%" if model == "cmyk" else ""
    return model + "(" + ",".join(f"{value}{suffix}" for value in values) + ")"


def hue_base(angle, chroma):
    sector, fraction = divmod(angle, 60)
    cross = chroma * Fraction(fraction if sector % 2 == 0 else 60 - fraction, 60)
    return (
        (chroma, cross, 0), (cross, chroma, 0), (0, chroma, cross),
        (0, cross, chroma), (cross, 0, chroma), (chroma, 0, cross),
    )[sector]


def from_hsl(angle, saturation, lightness):
    chroma = Fraction((100 - abs(2 * lightness - 100)) * saturation, 10000)
    offset = Fraction(lightness, 100) - chroma / 2
    return tuple(round_exact(255 * (component + offset)) for component in hue_base(angle, chroma))


def ansi_color(number):
    if number < 16:
        return BUILTINS[number][1]
    if number >= 232:
        return (8 + 10 * (number - 232),) * 3
    red, remainder = divmod(number - 16, 36)
    green, blue = divmod(remainder, 6)
    levels = (0, 95, 135, 175, 215, 255)
    return levels[red], levels[green], levels[blue]


def gradient(first, second, count):
    return [
        tuple(a + away(Fraction((b - a) * i, count - 1)) for a, b in zip(first, second))
        for i in range(count)
    ]


def contrast(first, second):
    def luminance(color):
        return sum(weight * value * value for weight, value in zip((2126, 7152, 722), color))

    first_y, second_y = luminance(first), luminance(second)
    upper = max(first_y, second_y) + 32512500
    lower = min(first_y, second_y) + 32512500
    verdict = "AAA" if upper >= 7 * lower else "AA" if 2 * upper >= 9 * lower else "FAIL"
    return round_ratio(100 * upper, lower), verdict


def contrast_notation(first, second):
    ratio, verdict = contrast(first, second)
    return f"{ratio // 100}.{ratio % 100:02d} {verdict}"


def color_mean(colors):
    return tuple(round_ratio(sum(color[channel] for color in colors), len(colors)) for channel in range(3))


def box_widths(colors):
    return [max(c[channel] for c in colors) - min(c[channel] for c in colors) for channel in range(3)]


def palette(colors, count):
    boxes = [colors[:]]
    while len(boxes) < count:
        candidates = [i for i, box in enumerate(boxes) if len(box) >= 2]
        chosen = max(candidates, key=lambda i: max(box_widths(boxes[i])))
        widths = box_widths(boxes[chosen])
        channel = widths.index(max(widths))
        ordered = sorted(boxes[chosen], key=lambda color: color[channel])
        middle = len(ordered) // 2
        boxes[chosen:chosen + 1] = [ordered[:middle], ordered[middle:]]
    return boxes


def blend_component(mode, base, top):
    if mode == "MULTIPLY":
        return base * top // 255
    if mode == "SCREEN":
        return 255 - (255 - base) * (255 - top) // 255
    if mode in ("OVERLAY", "HARDLIGHT"):
        condition = base if mode == "OVERLAY" else top
        if condition < 128:
            return 2 * base * top // 255
        return 255 - 2 * (255 - base) * (255 - top) // 255
    if mode == "SOFTLIGHT":
        multiply = base * top // 255
        screen = 255 - (255 - base) * (255 - top) // 255
        return ((255 - base) * multiply + base * screen) // 255
    if mode == "DARKEN":
        return min(base, top)
    if mode == "LIGHTEN":
        return max(base, top)
    if mode == "DIFFERENCE":
        return abs(base - top)
    if mode == "EXCLUSION":
        return base + top - 2 * base * top // 255
    if mode == "ADD":
        return min(255, base + top)
    if mode == "SUBTRACT":
        return max(0, base - top)
    if mode == "COLORDODGE":
        return 255 if top == 255 else min(255, 255 * base // (255 - top))
    return 0 if top == 0 else max(0, 255 - 255 * (255 - base) // top)


class ColorCommands:
    def __init__(self):
        self.registered = {}
        self.handlers = {
            "PARSE": (1, self.parse_notations), "DEFINE": (2, self.define),
            "UNDEFINE": (1, self.undefine), "LIST": (0, self.list_registered),
            "HSL": (1, self.to_hsl), "FROMHSL": (3, self.from_hsl),
            "HSV": (1, self.to_hsv), "FROMHSV": (3, self.from_hsv),
            "HWB": (1, self.to_hwb), "FROMHWB": (3, self.from_hwb),
            "CMYK": (1, self.to_cmyk), "FROMCMYK": (4, self.from_cmyk),
            "YCBCR": (1, self.to_ycbcr), "FROMYCBCR": (3, self.from_ycbcr),
            "YIQ": (1, self.to_yiq), "FROMYIQ": (3, self.from_yiq),
            "RGB565": (1, self.to_565), "FROM565": (1, self.from_565),
            "ANSI": (1, self.to_ansi), "FROMANSI": (1, self.from_ansi),
            "WEBSAFE": (1, self.websafe), "GRAY": (2, self.gray),
            "INVERT": (1, self.invert), "MIX": (3, self.mix),
            "MIXHSL": (3, self.mix_hsl), "GRADIENT": (3, self.gradient),
            "TINTS": (2, self.tints), "SHADES": (2, self.shades),
            "TONES": (2, self.tones), "BLEND": (3, self.blend),
            "ALPHA": (4, self.alpha), "SIMULATE": (2, self.simulate),
            "ROTATE": (2, self.rotate), "COMPLEMENT": (1, self.complement),
            "TRIADIC": (1, self.triadic), "TETRADIC": (1, self.tetradic),
            "SPLITCOMP": (1, self.split_complement), "ANALOGOUS": (3, self.analogous),
            "LIGHTEN": (2, self.lighten), "DARKEN": (2, self.darken),
            "SATURATE": (2, self.saturate), "DESATURATE": (2, self.desaturate),
            "NEAREST": (1, self.nearest), "DISTANCE": (2, self.distance),
            "CONTRAST": (2, self.contrast), "ACCESSIBLE": (2, self.accessible),
            "BEST": ((2, 33), self.best), "DESCRIBE": (1, self.describe),
            "PALETTE": ((2, 33), self.palette), "KMEANS": ((2, 33), self.kmeans),
            "SORT": ((1, 32), self.sort), "DITHER": ((1, 32), self.dither),
            "RANDOM": (2, self.random),
        }

    def color(self, text):
        if re.fullmatch(r"#[0-9A-Fa-f]{6}", text):
            return tuple(int(text[i:i + 2], 16) for i in (1, 3, 5))
        if re.fullmatch(r"#[0-9A-Fa-f]{3}", text):
            return tuple(17 * int(digit, 16) for digit in text[1:])
        match = re.fullmatch(r"rgb\(([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3})\)", text)
        if match:
            color = tuple(map(int, match.groups()))
            require(all(component <= 255 for component in color))
            return color
        if text in BUILTIN_NAMES:
            return BUILTIN_NAMES[text]
        require(text in self.registered)
        return self.registered[text]

    def table(self):
        return BUILTINS + list(self.registered.items())

    def execute(self, line):
        words = line.split(" ")
        try:
            require(words[0] in self.handlers)
            arity, handler = self.handlers[words[0]]
            count = len(words) - 1
            if isinstance(arity, tuple):
                require(arity[0] <= count <= arity[1])
            else:
                require(count == arity)
            return handler(words[1:])
        except InvalidCommand:
            return "INVALID"

    def parse_notations(self, args):
        color = self.color(args[0])
        name = next((name for name, value in self.table() if value == color), "-")
        rgb = "rgb(" + ",".join(map(str, color)) + ")"
        models = (("hsl", hsl), ("hsv", hsv), ("hwb", hwb), ("cmyk", cmyk),
                  ("ycbcr", ycbcr), ("yiq", yiq))
        return " ".join([hex_color(color), rgb] + [
            model_notation(model, convert(color)) for model, convert in models
        ] + [name])

    def define(self, args):
        name = registered_name(args[0])
        require(name not in BUILTIN_NAMES)
        color = self.color(args[1])
        self.registered[name] = color
        return f"{name} {hex_color(color)}"

    def undefine(self, args):
        name = registered_name(args[0])
        require(name in self.registered)
        del self.registered[name]
        return f"{name} removed"

    def list_registered(self, args):
        if not self.registered:
            return "NONE"
        return " ".join(f"{name}={hex_color(self.registered[name])}" for name in sorted(self.registered))

    def to_hsl(self, args):
        return model_notation("hsl", hsl(self.color(args[0])))

    def from_hsl(self, args):
        angle = integer(args[0], 0, 359)
        saturation = integer(args[1], 0, 100)
        lightness = integer(args[2], 0, 100)
        return hex_color(from_hsl(angle, saturation, lightness))

    def to_hsv(self, args):
        return model_notation("hsv", hsv(self.color(args[0])))

    def from_hsv(self, args):
        angle = integer(args[0], 0, 359)
        saturation = integer(args[1], 0, 100)
        value = integer(args[2], 0, 100)
        chroma = Fraction(value * saturation, 10000)
        offset = Fraction(value, 100) - chroma
        color = tuple(round_exact(255 * (x + offset)) for x in hue_base(angle, chroma))
        return hex_color(color)

    def to_hwb(self, args):
        return model_notation("hwb", hwb(self.color(args[0])))

    def from_hwb(self, args):
        angle = integer(args[0], 0, 359)
        white = integer(args[1], 0, 100)
        black = integer(args[2], 0, 100)
        if white + black >= 100:
            color = (round_ratio(255 * white, white + black),) * 3
        else:
            color = tuple(round_exact(255 * (
                x * Fraction(100 - white - black, 100) + Fraction(white, 100)
            )) for x in hue_base(angle, Fraction(1)))
        return hex_color(color)

    def to_cmyk(self, args):
        return model_notation("cmyk", cmyk(self.color(args[0])))

    def from_cmyk(self, args):
        cyan, magenta, yellow, black = [integer(text, 0, 100) for text in args]
        color = tuple(round_ratio(255 * (100 - x) * (100 - black), 10000)
                      for x in (cyan, magenta, yellow))
        return hex_color(color)

    def to_ycbcr(self, args):
        return model_notation("ycbcr", ycbcr(self.color(args[0])))

    def from_ycbcr(self, args):
        y, cb, cr = [integer(text, 0, 255) for text in args]
        color = (
            clamp(round_ratio(1000 * y + 1402 * (cr - 128), 1000)),
            clamp(round_ratio(1000 * y - 344 * (cb - 128) - 714 * (cr - 128), 1000)),
            clamp(round_ratio(1000 * y + 1772 * (cb - 128), 1000)),
        )
        return hex_color(color)

    def to_yiq(self, args):
        return model_notation("yiq", yiq(self.color(args[0])))

    def from_yiq(self, args):
        y = integer(args[0], 0, 255)
        i, q = [integer(text, -255, 255) for text in args[1:]]
        color = (
            clamp(round_ratio(1000 * y + 956 * i + 619 * q, 1000)),
            clamp(round_ratio(1000 * y - 272 * i - 647 * q, 1000)),
            clamp(round_ratio(1000 * y - 1106 * i + 1703 * q, 1000)),
        )
        return hex_color(color)

    def to_565(self, args):
        red, green, blue = self.color(args[0])
        value = (2048 * round_ratio(31 * red, 255) + 32 * round_ratio(63 * green, 255)
                 + round_ratio(31 * blue, 255))
        return f"0x{value:04X}"

    def from_565(self, args):
        require(re.fullmatch(r"0x[0-9A-Fa-f]{4}", args[0]) is not None)
        value = int(args[0][2:], 16)
        color = (round_ratio(255 * (value // 2048), 31),
                 round_ratio(255 * (value // 32 % 64), 63), round_ratio(255 * (value % 32), 31))
        return hex_color(color)

    def to_ansi(self, args):
        color = self.color(args[0])
        number = min(range(16, 256), key=lambda number: distance(color, ansi_color(number)))
        return f"{number} {hex_color(ansi_color(number))} {distance(color, ansi_color(number))}"

    def from_ansi(self, args):
        return hex_color(ansi_color(integer(args[0], 0, 255)))

    def websafe(self, args):
        return hex_color(tuple(51 * round_ratio(x, 51) for x in self.color(args[0])))

    def gray(self, args):
        color = self.color(args[0])
        method = args[1]
        require(method in ("LUMA", "AVERAGE", "LIGHTNESS", "HSP"))
        if method == "LUMA":
            value = round_ratio(sum(w * x for w, x in zip((299, 587, 114), color)), 1000)
        elif method == "AVERAGE":
            value = round_ratio(sum(color), 3)
        elif method == "LIGHTNESS":
            value = round_ratio(max(color) + min(color), 2)
        else:
            square = sum(w * x * x for w, x in zip((299, 587, 114), color))
            value = isqrt(square // 1000)
        return hex_color((value,) * 3)

    def invert(self, args):
        return hex_color(tuple(255 - x for x in self.color(args[0])))

    def mix(self, args):
        first, second = self.color(args[0]), self.color(args[1])
        percent = integer(args[2], 0, 100)
        color = tuple(round_ratio(a * (100 - percent) + b * percent, 100)
                      for a, b in zip(first, second))
        return hex_color(color)

    def mix_hsl(self, args):
        first, second = hsl(self.color(args[0])), hsl(self.color(args[1]))
        percent = integer(args[2], 0, 100)
        difference = (second[0] - first[0]) % 360
        if difference > 180:
            difference -= 360
        angle = (first[0] + away(Fraction(difference * percent, 100))) % 360
        saturation = first[1] + away(Fraction((second[1] - first[1]) * percent, 100))
        lightness = first[2] + away(Fraction((second[2] - first[2]) * percent, 100))
        return hex_color(from_hsl(angle, saturation, lightness))

    def gradient(self, args):
        first, second = self.color(args[0]), self.color(args[1])
        count = integer(args[2], 2, 16)
        return color_sequence(gradient(first, second, count))

    def toward(self, args, target):
        color = self.color(args[0])
        count = integer(args[1], 1, 10)
        return color_sequence(gradient(color, target, count + 2)[1:-1])

    def tints(self, args):
        return self.toward(args, (255, 255, 255))

    def shades(self, args):
        return self.toward(args, (0, 0, 0))

    def tones(self, args):
        return self.toward(args, (128, 128, 128))

    def blend(self, args):
        mode = args[0]
        channel_modes = ("MULTIPLY", "SCREEN", "OVERLAY", "HARDLIGHT", "SOFTLIGHT", "DARKEN",
                         "LIGHTEN", "DIFFERENCE", "EXCLUSION", "ADD", "SUBTRACT", "COLORDODGE", "COLORBURN")
        hsl_modes = ("HUE", "SATURATION", "COLOR", "LUMINOSITY")
        require(mode in channel_modes + hsl_modes)
        base, top = self.color(args[1]), self.color(args[2])
        if mode in channel_modes:
            color = tuple(blend_component(mode, x, y) for x, y in zip(base, top))
        else:
            h1, s1, l1 = hsl(base)
            h2, s2, l2 = hsl(top)
            values = {"HUE": (h2, s1, l1), "SATURATION": (h1, s2, l1),
                      "COLOR": (h2, s2, l1), "LUMINOSITY": (h1, s1, l2)}
            color = from_hsl(*values[mode])
        return hex_color(color)

    def alpha(self, args):
        foreground = self.color(args[0])
        p = integer(args[1], 0, 100)
        background = self.color(args[2])
        q = integer(args[3], 0, 100)
        opacity = 100 * p + q * (100 - p)
        if opacity == 0:
            color = (0, 0, 0)
        else:
            color = tuple(round_ratio(100 * p * x + q * (100 - p) * y, opacity)
                          for x, y in zip(foreground, background))
        return f"{hex_color(color)} {round_ratio(opacity, 100)}%"

    def simulate(self, args):
        color = self.color(args[0])
        require(args[1] in SIMULATION)
        result = tuple(round_ratio(sum(w * x for w, x in zip(weights, color)), 1000)
                       for weights in SIMULATION[args[1]])
        return hex_color(result)

    def rotation_colors(self, color, angles):
        angle, saturation, lightness = hsl(color)
        return [from_hsl((angle + change) % 360, saturation, lightness) for change in angles]

    def rotate(self, args):
        color = self.color(args[0])
        change = integer(args[1], -720, 720)
        return color_sequence(self.rotation_colors(color, [change]))

    def complement(self, args):
        return color_sequence(self.rotation_colors(self.color(args[0]), [180]))

    def triadic(self, args):
        return color_sequence(self.rotation_colors(self.color(args[0]), [120, 240]))

    def tetradic(self, args):
        return color_sequence(self.rotation_colors(self.color(args[0]), [90, 180, 270]))

    def split_complement(self, args):
        return color_sequence(self.rotation_colors(self.color(args[0]), [150, 210]))

    def analogous(self, args):
        color = self.color(args[0])
        count = integer(args[1], 1, 6)
        step = integer(args[2], 1, 60)
        changes = [i * step for i in range(-count, count + 1) if i != 0]
        return color_sequence(self.rotation_colors(color, changes))

    def adjust(self, args, component, direction):
        values = list(hsl(self.color(args[0])))
        amount = integer(args[1], 0, 100)
        values[component] = min(100, max(0, values[component] + direction * amount))
        return hex_color(from_hsl(*values))

    def lighten(self, args):
        return self.adjust(args, 2, 1)

    def darken(self, args):
        return self.adjust(args, 2, -1)

    def saturate(self, args):
        return self.adjust(args, 1, 1)

    def desaturate(self, args):
        return self.adjust(args, 1, -1)

    def nearest(self, args):
        color = self.color(args[0])
        name, chosen = min(self.table(), key=lambda entry: distance(color, entry[1]))
        return f"{name} {hex_color(chosen)} {distance(color, chosen)}"

    def distance(self, args):
        first, second = self.color(args[0]), self.color(args[1])
        red_difference, green_difference, blue_difference = [a - b for a, b in zip(first, second)]
        red_sum = first[0] + second[0]
        weighted = ((1024 + red_sum) * red_difference ** 2 + 2048 * green_difference ** 2
                    + (1534 - red_sum) * blue_difference ** 2)
        return f"{distance(first, second)} {isqrt(weighted // 512)}"

    def contrast(self, args):
        return contrast_notation(self.color(args[0]), self.color(args[1]))

    def accessible(self, args):
        foreground, background = self.color(args[0]), self.color(args[1])
        if contrast(foreground, background)[1] != "FAIL":
            result = foreground
        else:
            angle, saturation, lightness = hsl(foreground)
            result = None
            for step in range(1, 101):
                for candidate_l in (lightness - step, lightness + step):
                    if 0 <= candidate_l <= 100:
                        candidate = from_hsl(angle, saturation, candidate_l)
                        if contrast(candidate, background)[1] != "FAIL":
                            result = candidate
                            break
                if result is not None:
                    break
        return f"{hex_color(result)} {contrast_notation(result, background)}"

    def best(self, args):
        background = self.color(args[0])
        candidates = [self.color(text) for text in args[1:]]
        chosen = max(candidates, key=lambda color: contrast(color, background)[0])
        return f"{hex_color(chosen)} {contrast_notation(chosen, background)}"

    def describe(self, args):
        angle, saturation, lightness = hsl(self.color(args[0]))
        if lightness <= 5:
            return "black"
        if lightness >= 95:
            return "white"
        if lightness <= 20:
            light_word = "very dark"
        elif lightness <= 40:
            light_word = "dark"
        elif lightness <= 60:
            light_word = "medium"
        elif lightness <= 80:
            light_word = "light"
        else:
            light_word = "very light"
        if saturation < 10:
            return f"{light_word} gray"
        saturation_word = "muted" if saturation < 40 else "moderate" if saturation < 80 else "vivid"
        return f"{light_word} {saturation_word} {HUE_NAMES[((angle + 15) % 360) // 30]}"

    def cluster_arguments(self, args):
        colors = [self.color(text) for text in args[1:]]
        count = integer(args[0], 1, len(colors))
        return count, colors

    def palette(self, args):
        count, colors = self.cluster_arguments(args)
        boxes = palette(colors, count)
        return " ".join(f"{hex_color(color_mean(box))}:{len(box)}" for box in boxes)

    def kmeans(self, args):
        count, colors = self.cluster_arguments(args)
        representatives = [color_mean(box) for box in palette(colors, count)]
        for iteration in range(1, 21):
            groups = [[] for _ in range(count)]
            for color in colors:
                chosen = min(range(count), key=lambda i: distance(color, representatives[i]))
                groups[chosen].append(color)
            updated = [color_mean(group) if group else representatives[i]
                       for i, group in enumerate(groups)]
            unchanged = updated == representatives
            representatives = updated
            if unchanged:
                break
        entries = [f"{hex_color(color)}:{len(group)}" for color, group in zip(representatives, groups)]
        return " ".join([str(iteration)] + entries)

    def sort(self, args):
        colors = [self.color(text) for text in args]
        return color_sequence(sorted(colors, key=hsl))

    def dither(self, args):
        colors = [self.color(text) for text in args]
        error = (0, 0, 0)
        names = []
        for color in colors:
            target = tuple(clamp(x + e) for x, e in zip(color, error))
            number = min(range(16), key=lambda i: distance(target, BUILTINS[i][1]))
            name, quantized = BUILTINS[number]
            names.append(name)
            error = tuple(x - y for x, y in zip(target, quantized))
        return " ".join(names)

    def random(self, args):
        seed = integer(args[0], 1, 999999999)
        count = integer(args[1], 1, 16)
        colors = []
        for _ in range(count):
            values = []
            for _ in range(3):
                seed = 48271 * seed % 2147483647
                values.append(seed)
            angle, saturation, lightness = values
            colors.append(from_hsl(angle % 360, 40 + saturation % 61, 25 + lightness % 51))
        return color_sequence(colors)


def main():
    commands = ColorCommands()
    count = int(sys.stdin.readline())
    for _ in range(count):
        line = sys.stdin.readline().rstrip("\n")
        print(commands.execute(line))


if __name__ == "__main__":
    main()
