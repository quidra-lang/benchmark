import re
import sys
from fractions import Fraction


GEOHASH_DIGITS = "0123456789bcdefghjkmnpqrstuvwxyz"
PLUS_DIGITS = "23456789CFGHJMPQRVWX"
L24 = "ABCDEFGHJKLMNPQRSTUVWXYZ"
OSGB_LETTERS = "ABCDEFGHJKLMNOPQRSTUVWXYZ"
MGRS_ROWS = "ABCDEFGHJKLMNPQRSTUV"
MGRS_COLUMNS = ("STUVWXYZ", "ABCDEFGH", "JKLMNPQR")
BANDS = "CDEFGHJKLMNPQRSTUVWX"
MAIDENHEAD_SETS = (
    "ABCDEFGHIJKLMNOPQR", "0123456789", "abcdefghijklmnopqrstuvwx", "0123456789"
)
PRECISIONS = {
    "GEOHASH": tuple(range(1, 10)),
    "MAIDENHEAD": (2, 4, 6, 8),
    "PLUSCODE": (2, 4, 6, 8, 10, 11),
    "GARS": (5, 6, 7),
    "GEOREF": (2, 4, 8, 10, 12),
    "MESH": (4, 6, 8, 9, 10, 11),
}
MESH_SCALES = {4: 1, 6: 8, 8: 80, 9: 160, 10: 320, 11: 640}
GRIDS = {
    "MAIDENHEAD": {2: (18, 18), 4: (180, 180), 6: (4320, 4320), 8: (43200, 43200)},
    "PLUSCODE": {
        2: (18, 9), 4: (360, 180), 6: (7200, 3600),
        8: (144000, 72000), 10: (2880000, 1440000), 11: (11520000, 7200000),
    },
    "GARS": {5: (720, 360), 6: (1440, 720), 7: (4320, 2160)},
    "GEOREF": {
        2: (24, 12), 4: (360, 180), 8: (21600, 10800),
        10: (216000, 108000), 12: (2160000, 1080000),
    },
}
INTEGER_PATTERN = re.compile(r"-?[0-9]{1,9}\Z")
COORDINATE_PATTERN = re.compile(r"-?[0-9]{1,3}(?:\.[0-9]{1,6})?\Z")


class Invalid(Exception):
    pass


def require(condition):
    if not condition:
        raise Invalid


def integer(text, minimum, maximum):
    require(INTEGER_PATTERN.fullmatch(text) is not None)
    value = int(text)
    require(minimum <= value <= maximum)
    return value


def coordinate(text, latitude):
    require(COORDINATE_PATTERN.fullmatch(text) is not None)
    negative = text.startswith("-")
    unsigned = text[1:] if negative else text
    whole, dot, fraction = unsigned.partition(".")
    value = int(whole) * 1000000 + int(fraction.ljust(6, "0") if dot else "0")
    if negative:
        value = -value
    if latitude:
        require(-90000000 <= value <= 90000000)
    else:
        require(-180000000 <= value < 180000000)
    return value


def coordinate_text(value):
    sign = "-" if value < 0 else ""
    whole, fraction = divmod(abs(value), 1000000)
    return f"{sign}{whole}.{fraction:06d}"


def system_name(text):
    require(text in PRECISIONS)
    return text


def precision(system, text):
    value = integer(text, 1, 12)
    require(value in PRECISIONS[system])
    return value


def dimensions(system, level):
    if system == "GEOHASH":
        return 1 << ((5 * level + 1) // 2), 1 << (5 * level // 2)
    if system == "MESH":
        scale = MESH_SCALES[level]
        return 360 * scale, 270 * scale
    return GRIDS[system][level]


def radix_digits(value, radices):
    digits = []
    for radix in reversed(radices):
        value, digit = divmod(value, radix)
        digits.append(digit)
    return digits[::-1]


def radix_value(digits, radices):
    value = 0
    for digit, radix in zip(digits, radices):
        value = value * radix + digit
    return value


def encode_geohash(level, x, y):
    longitude_bits = (5 * level + 1) // 2
    latitude_bits = 5 * level // 2
    characters = []
    group = 0
    for bit in range(5 * level):
        if bit % 2 == 0:
            longitude_bits -= 1
            value = (x >> longitude_bits) & 1
        else:
            latitude_bits -= 1
            value = (y >> latitude_bits) & 1
        group = 2 * group + value
        if bit % 5 == 4:
            characters.append(GEOHASH_DIGITS[group])
            group = 0
    return "".join(characters)


def encode_maidenhead(level, x, y):
    sets = MAIDENHEAD_SETS[:level // 2]
    radices = [len(alphabet) for alphabet in sets]
    xs = radix_digits(x, radices)
    ys = radix_digits(y, radices)
    return "".join(alphabet[a] + alphabet[b] for alphabet, a, b in zip(sets, xs, ys))


def encode_pluscode(level, x, y):
    suffix = ""
    if level == 11:
        x, column = divmod(x, 4)
        y, row = divmod(y, 5)
        suffix = PLUS_DIGITS[4 * row + column]
    pairs = min(level, 10) // 2
    xs = radix_digits(x, [18] + [20] * (pairs - 1))
    ys = radix_digits(y, [9] + [20] * (pairs - 1))
    digits = "".join(PLUS_DIGITS[b] + PLUS_DIGITS[a] for a, b in zip(xs, ys)) + suffix
    if level < 8:
        return digits + "0" * (8 - level) + "+"
    return digits[:8] + "+" + digits[8:]


def encode_gars(level, x, y):
    area = ""
    quadrant = ""
    if level == 7:
        x, column = divmod(x, 3)
        y, row = divmod(y, 3)
        area = str(1 + column + 3 * (2 - row))
    if level >= 6:
        x, column = divmod(x, 2)
        y, row = divmod(y, 2)
        quadrant = str(1 + column + 2 * (1 - row))
    return f"{x + 1:03d}" + L24[y // 24] + L24[y % 24] + quadrant + area


def encode_georef(level, x, y):
    minutes = ""
    if level >= 8:
        places = (level - 4) // 2
        radix = 6 * 10 ** (places - 1)
        x, easting = divmod(x, radix)
        y, northing = divmod(y, radix)
        minutes = f"{easting:0{places}d}{northing:0{places}d}"
    degrees = ""
    if level >= 4:
        x, east_degree = divmod(x, 15)
        y, north_degree = divmod(y, 15)
        degrees = L24[east_degree] + L24[north_degree]
    return L24[x] + L24[y] + degrees + minutes


def encode_mesh(level, x, y):
    scale = MESH_SCALES[level]
    u = x - 280 * scale
    v = y - 135 * scale
    if not (0 <= u < 80 * scale and 0 <= v < 100 * scale):
        return None
    count = PRECISIONS["MESH"].index(level) + 1
    us = radix_digits(u, (80, 8, 10, 2, 2, 2)[:count])
    vs = radix_digits(v, (100, 8, 10, 2, 2, 2)[:count])
    code = f"{vs[0]:02d}{us[0]:02d}"
    if count >= 2:
        code += str(vs[1]) + str(us[1])
    if count >= 3:
        code += str(vs[2]) + str(us[2])
    for index in range(3, count):
        code += str(1 + us[index] + 2 * vs[index])
    return code


ENCODERS = {
    "GEOHASH": encode_geohash,
    "MAIDENHEAD": encode_maidenhead,
    "PLUSCODE": encode_pluscode,
    "GARS": encode_gars,
    "GEOREF": encode_georef,
    "MESH": encode_mesh,
}


class Cell:
    def __init__(self, system, level, x, y):
        self.system = system
        self.level = level
        self.x = x
        self.y = y
        self.width, self.height = dimensions(system, level)

    def code(self, missing="-"):
        result = ENCODERS[self.system](self.level, self.x, self.y)
        return missing if result is None else result

    def ancestor(self, level):
        width, height = dimensions(self.system, level)
        return Cell(self.system, level, self.x * width // self.width, self.y * height // self.height)

    def identity(self):
        return self.level, self.x, self.y

    def center(self):
        latitude = Fraction((2 * self.y + 1) * 180000000, 2 * self.height) - 90000000
        longitude = Fraction((2 * self.x + 1) * 360000000, 2 * self.width) - 180000000
        return latitude, longitude

    def normalized_bounds(self):
        return (
            Fraction(self.x, self.width), Fraction(self.x + 1, self.width),
            Fraction(self.y, self.height), Fraction(self.y + 1, self.height),
        )


def point_cell(system, level, latitude, longitude):
    width, height = dimensions(system, level)
    x = (longitude + 180000000) * width // 360000000
    y = min((latitude + 90000000) * height // 180000000, height - 1)
    return Cell(system, level, x, y)


def decode_geohash(code):
    require(1 <= len(code) <= 9 and all(c in GEOHASH_DIGITS for c in code))
    x = 0
    y = 0
    index = 0
    for character in code:
        value = GEOHASH_DIGITS.index(character)
        for bit in range(4, -1, -1):
            digit = (value >> bit) & 1
            if index % 2 == 0:
                x = 2 * x + digit
            else:
                y = 2 * y + digit
            index += 1
    return len(code), x, y


def decode_maidenhead(code):
    require(len(code) in PRECISIONS["MAIDENHEAD"])
    x = 0
    y = 0
    for index in range(len(code) // 2):
        alphabet = MAIDENHEAD_SETS[index]
        east, north = code[2 * index:2 * index + 2]
        require(east in alphabet and north in alphabet)
        x = x * len(alphabet) + alphabet.index(east)
        y = y * len(alphabet) + alphabet.index(north)
    return len(code), x, y


def decode_pluscode(code):
    require(code.count("+") == 1 and code.find("+") == 8)
    before, after = code.split("+")
    if "0" in before:
        count = before.index("0")
        require(count in (2, 4, 6) and before[count:] == "0" * (8 - count))
        require(after == "")
        digits = before[:count]
    else:
        require(len(after) in (0, 2, 3))
        digits = before + after
    require(all(character in PLUS_DIGITS for character in digits))
    require(PLUS_DIGITS.index(digits[0]) <= 8 and PLUS_DIGITS.index(digits[1]) <= 17)
    level = len(digits)
    x = 0
    y = 0
    for index in range(min(level, 10) // 2):
        y = 20 * y + PLUS_DIGITS.index(digits[2 * index])
        x = 20 * x + PLUS_DIGITS.index(digits[2 * index + 1])
    if level == 11:
        refinement = PLUS_DIGITS.index(digits[-1])
        x = 4 * x + refinement % 4
        y = 5 * y + refinement // 4
    return level, x, y


def decode_gars(code):
    require(len(code) in PRECISIONS["GARS"])
    require(re.fullmatch(r"[0-9]{3}", code[:3]) is not None)
    band = int(code[:3])
    require(1 <= band <= 720 and code[3] in L24[:15] and code[4] in L24)
    x = band - 1
    y = 24 * L24.index(code[3]) + L24.index(code[4])
    if len(code) >= 6:
        require(code[5] in "1234")
        quadrant = int(code[5]) - 1
        x = 2 * x + quadrant % 2
        y = 2 * y + 1 - quadrant // 2
    if len(code) == 7:
        require(code[6] in "123456789")
        area = int(code[6]) - 1
        x = 3 * x + area % 3
        y = 3 * y + 2 - area // 3
    return len(code), x, y


def decode_georef(code):
    require(len(code) in PRECISIONS["GEOREF"])
    require(code[0] in L24 and code[1] in L24[:12])
    x = L24.index(code[0])
    y = L24.index(code[1])
    if len(code) >= 4:
        require(code[2] in L24[:15] and code[3] in L24[:15])
        x = 15 * x + L24.index(code[2])
        y = 15 * y + L24.index(code[3])
    if len(code) >= 8:
        places = (len(code) - 4) // 2
        require(re.fullmatch(r"[0-9]+", code[4:]) is not None)
        east = int(code[4:4 + places])
        north = int(code[4 + places:])
        radix = 6 * 10 ** (places - 1)
        require(east < radix and north < radix)
        x = radix * x + east
        y = radix * y + north
    return len(code), x, y


def decode_mesh(code):
    require(len(code) in PRECISIONS["MESH"])
    require(re.fullmatch(r"[0-9]+", code) is not None)
    us = [int(code[2:4])]
    vs = [int(code[:2])]
    require(us[0] <= 79)
    if len(code) >= 6:
        require(code[4] in "01234567" and code[5] in "01234567")
        vs.append(int(code[4]))
        us.append(int(code[5]))
    if len(code) >= 8:
        vs.append(int(code[6]))
        us.append(int(code[7]))
    for character in code[8:]:
        require(character in "1234")
        value = int(character) - 1
        us.append(value % 2)
        vs.append(value // 2)
    count = len(us)
    scale = MESH_SCALES[len(code)]
    x = 280 * scale + radix_value(us, (80, 8, 10, 2, 2, 2)[:count])
    y = 135 * scale + radix_value(vs, (100, 8, 10, 2, 2, 2)[:count])
    return len(code), x, y


DECODERS = {
    "GEOHASH": decode_geohash,
    "MAIDENHEAD": decode_maidenhead,
    "PLUSCODE": decode_pluscode,
    "GARS": decode_gars,
    "GEOREF": decode_georef,
    "MESH": decode_mesh,
}


def decode_cell(system, code):
    level, x, y = DECODERS[system](code)
    return Cell(system, level, x, y)


def offsets(first, second):
    dx = (second.x - first.x) % first.width
    if 2 * dx > first.width:
        dx -= first.width
    return dx, second.y - first.y


def encode(arguments):
    system = system_name(arguments[0])
    latitude = coordinate(arguments[1], True)
    longitude = coordinate(arguments[2], False)
    level = precision(system, arguments[3])
    return point_cell(system, level, latitude, longitude).code("OUT OF AREA")


def decode(arguments):
    cell = decode_cell(system_name(arguments[0]), arguments[1])
    south = -90000000 + cell.y * 180000000 // cell.height
    north = -90000000 + (cell.y + 1) * 180000000 // cell.height
    west = -180000000 + cell.x * 360000000 // cell.width
    east = -180000000 + (cell.x + 1) * 360000000 // cell.width
    latitude, longitude = cell.center()
    latitude = latitude.numerator // latitude.denominator
    longitude = longitude.numerator // longitude.denominator
    return (
        f"sw={coordinate_text(south)},{coordinate_text(west)} "
        f"ne={coordinate_text(north)},{coordinate_text(east)} "
        f"c={coordinate_text(latitude)},{coordinate_text(longitude)}"
    )


def neighbors(arguments):
    cell = decode_cell(system_name(arguments[0]), arguments[1])
    directions = ((0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1))
    codes = []
    for dx, dy in directions:
        y = cell.y + dy
        if y < 0 or y >= cell.height:
            codes.append("-")
        else:
            neighbor = Cell(cell.system, cell.level, (cell.x + dx) % cell.width, y)
            codes.append(neighbor.code())
    return " ".join(codes)


def parent(arguments):
    cell = decode_cell(system_name(arguments[0]), arguments[1])
    levels = PRECISIONS[cell.system]
    index = levels.index(cell.level)
    return "NONE" if index == 0 else cell.ancestor(levels[index - 1]).code("NONE")


def children(arguments):
    cell = decode_cell(system_name(arguments[0]), arguments[1])
    levels = PRECISIONS[cell.system]
    index = levels.index(cell.level)
    if index == len(levels) - 1:
        return "NONE"
    level = levels[index + 1]
    width, height = dimensions(cell.system, level)
    rx, ry = width // cell.width, height // cell.height
    if rx * ry > 100:
        return "TOO MANY"
    return " ".join(
        Cell(cell.system, level, rx * cell.x + i, ry * cell.y + j).code()
        for j in range(ry - 1, -1, -1) for i in range(rx)
    )


def common(arguments):
    system = system_name(arguments[0])
    first, second = (decode_cell(system, code) for code in arguments[1:])
    levels = PRECISIONS[system]
    index = min(levels.index(first.level), levels.index(second.level))
    for level in reversed(levels[:index + 1]):
        a, b = first.ancestor(level), second.ancestor(level)
        if a.identity() == b.identity():
            return a.code("NONE")
    return "NONE"


def compact(arguments):
    system = system_name(arguments[0])
    cells = {}
    levels = PRECISIONS[system]
    for code in arguments[1:]:
        cell = decode_cell(system, code)
        cells[cell.identity()] = cell
    for key, cell in list(cells.items()):
        index = levels.index(cell.level)
        if any(cell.ancestor(level).identity() in cells for level in levels[:index]):
            del cells[key]
    while True:
        merged = False
        for index in range(len(levels) - 1, 0, -1):
            level, previous = levels[index], levels[index - 1]
            width, height = dimensions(system, level)
            old_width, old_height = dimensions(system, previous)
            required = (width // old_width) * (height // old_height)
            families = {}
            for cell in cells.values():
                if cell.level == level:
                    ancestor = cell.ancestor(previous)
                    families.setdefault(ancestor.identity(), []).append(cell)
            for parent_key, siblings in families.items():
                if len(siblings) == required:
                    for sibling in siblings:
                        del cells[sibling.identity()]
                    ancestor = siblings[0].ancestor(previous)
                    cells[parent_key] = ancestor
                    merged = True
            if merged:
                break
        if not merged:
            break
    ordered = sorted(cells.values(), key=lambda cell: (cell.level, -cell.y, cell.x))
    return " ".join(cell.code() for cell in ordered)


def contains(arguments):
    system = system_name(arguments[0])
    cell = decode_cell(system, arguments[1])
    latitude = coordinate(arguments[2], True)
    longitude = coordinate(arguments[3], False)
    point = point_cell(system, cell.level, latitude, longitude)
    return "YES" if cell.identity() == point.identity() else "NO"


def cover(arguments):
    system = system_name(arguments[0])
    level = precision(system, arguments[1])
    south = coordinate(arguments[2], True)
    west = coordinate(arguments[3], False)
    north = coordinate(arguments[4], True)
    east = coordinate(arguments[5], False)
    require(south <= north)
    first = point_cell(system, level, south, west)
    last = point_cell(system, level, north, east)
    columns = last.x - first.x + 1
    if west > east:
        columns = min(first.width, columns + first.width)
    if columns * (last.y - first.y + 1) > 100:
        return "TOO MANY"
    return " ".join(
        Cell(system, level, (first.x + i) % first.width, y).code()
        for y in range(last.y, first.y - 1, -1) for i in range(columns)
    )


def convert(arguments):
    source = system_name(arguments[0])
    cell = decode_cell(source, arguments[1])
    require(arguments[2] == "TO")
    target = system_name(arguments[3])
    level = precision(target, arguments[4])
    width, height = dimensions(target, level)
    x = (2 * cell.x + 1) * width // (2 * cell.width)
    y = (2 * cell.y + 1) * height // (2 * cell.height)
    return Cell(target, level, x, y).code("OUT OF AREA")


def steps(arguments):
    system = system_name(arguments[0])
    first, second = (decode_cell(system, code) for code in arguments[1:])
    if first.level != second.level:
        return "MISMATCH"
    dx, dy = offsets(first, second)
    return f"dx={dx} dy={dy}"


def path(arguments):
    system = system_name(arguments[0])
    first, second = (decode_cell(system, code) for code in arguments[1:])
    if first.level != second.level:
        return "MISMATCH"
    dx, dy = offsets(first, second)
    count = max(abs(dx), abs(dy))
    if count + 1 > 100:
        return "TOO MANY"
    if count == 0:
        return first.code()
    codes = []
    for index in range(count + 1):
        x = (first.x + (2 * index * dx + count) // (2 * count)) % first.width
        y = first.y + (2 * index * dy + count) // (2 * count)
        codes.append(Cell(system, first.level, x, y).code())
    return " ".join(codes)


def relate(arguments):
    first = decode_cell(system_name(arguments[0]), arguments[1])
    second = decode_cell(system_name(arguments[2]), arguments[3])
    left1, right1, bottom1, top1 = first.normalized_bounds()
    left2, right2, bottom2, top2 = second.normalized_bounds()
    if (left1, right1, bottom1, top1) == (left2, right2, bottom2, top2):
        return "EQUAL"
    if left2 <= left1 and right1 <= right2 and bottom2 <= bottom1 and top1 <= top2:
        return "INSIDE"
    if left1 <= left2 and right2 <= right1 and bottom1 <= bottom2 and top2 <= top1:
        return "CONTAINS"
    shared_left, shared_right = max(left1, left2), min(right1, right2)
    shared_bottom, shared_top = max(bottom1, bottom2), min(top1, top2)
    if shared_left < shared_right and shared_bottom < shared_top:
        return "OVERLAP"
    if shared_left <= shared_right and shared_bottom <= shared_top:
        return "TOUCH"
    dateline = (right1 == 1 and left2 == 0) or (right2 == 1 and left1 == 0)
    if dateline and shared_bottom <= shared_top:
        return "TOUCH"
    return "DISJOINT"


def size(arguments):
    system = system_name(arguments[0])
    level = precision(system, arguments[1])
    width, height = dimensions(system, level)
    total = width * height
    if system == "MESH":
        total = 8000 * MESH_SCALES[level] ** 2
    return (
        f"w={coordinate_text(360000000 // width)} "
        f"h={coordinate_text(180000000 // height)} cells={total}"
    )


def shorten(arguments):
    code = arguments[0]
    cell = decode_cell("PLUSCODE", code)
    require(cell.level in (8, 10, 11))
    latitude = coordinate(arguments[1], True)
    longitude = coordinate(arguments[2], False)
    cy, cx = cell.center()
    distance = max(abs(cy - latitude), abs(cx - longitude))
    if distance < 15000:
        return code[6:]
    if distance < 300000:
        return code[4:]
    return code


def recover(arguments):
    short = arguments[0]
    require(short.count("+") == 1)
    before, after = short.split("+")
    require(len(before) in (2, 4) and len(after) in (0, 2, 3))
    require(all(c in PLUS_DIGITS for c in before + after))
    latitude = coordinate(arguments[1], True)
    longitude = coordinate(arguments[2], False)
    removed = 8 - len(before)
    prefix = point_cell("PLUSCODE", 10, latitude, longitude).code()[:removed]
    cell = decode_cell("PLUSCODE", prefix + short)
    cy, cx = cell.center()
    distance = 1000000 if removed == 4 else 50000
    rows = distance * cell.height // 180000000
    columns = distance * cell.width // 360000000
    if latitude + distance // 2 < cy and cy - distance >= -90000000:
        cell.y -= rows
    elif latitude - distance // 2 > cy and cy + distance <= 90000000:
        cell.y += rows
    if longitude + distance // 2 < cx:
        cell.x = (cell.x - columns) % cell.width
    elif longitude - distance // 2 > cx:
        cell.x = (cell.x + columns) % cell.width
    return cell.code()


def utmzone(arguments):
    latitude = coordinate(arguments[0], True)
    longitude = coordinate(arguments[1], False)
    if latitude < -80000000 or latitude >= 84000000:
        return "NONE"
    band = BANDS[min((latitude + 80000000) // 8000000, 19)]
    zone = (longitude + 180000000) // 6000000 + 1
    if band == "V" and 3000000 <= longitude < 12000000:
        zone = 32
    elif band == "X":
        if 0 <= longitude < 9000000:
            zone = 31
        elif 9000000 <= longitude < 21000000:
            zone = 33
        elif 21000000 <= longitude < 33000000:
            zone = 35
        elif 33000000 <= longitude < 42000000:
            zone = 37
    return str(zone) + band


def metre_digits(easting, northing, places):
    return f"{easting % 100000:05d}"[:places], f"{northing % 100000:05d}"[:places]


def square_offsets(arguments):
    if not arguments:
        return 0, 0, 100000
    east, north = arguments
    require(re.fullmatch(r"[0-9]{1,5}", east) is not None)
    require(re.fullmatch(r"[0-9]{1,5}", north) is not None)
    require(len(east) == len(north))
    square_size = 10 ** (5 - len(east))
    return int(east) * square_size, int(north) * square_size, square_size


def osgb(arguments):
    easting = integer(arguments[0], 0, 699999)
    northing = integer(arguments[1], 0, 1299999)
    places = integer(arguments[2], 0, 5)
    first = 5 * (3 - northing // 500000) + 2 + easting // 500000
    second = 5 * (4 - northing // 100000 % 5) + easting // 100000 % 5
    letters = OSGB_LETTERS[first] + OSGB_LETTERS[second]
    if places == 0:
        return letters
    east, north = metre_digits(easting, northing, places)
    return f"{letters} {east} {north}"


def unosgb(arguments):
    letters = arguments[0]
    require(len(letters) == 2 and all(c in OSGB_LETTERS for c in letters))
    row1, column1 = divmod(OSGB_LETTERS.index(letters[0]), 5)
    row2, column2 = divmod(OSGB_LETTERS.index(letters[1]), 5)
    easting = 500000 * (column1 - 2) + 100000 * column2
    northing = 500000 * (3 - row1) + 100000 * (4 - row2)
    require(0 <= easting < 700000 and 0 <= northing < 1300000)
    east_offset, north_offset, square_size = square_offsets(arguments[1:])
    return f"sw={easting + east_offset},{northing + north_offset} size={square_size}"


def mgrs(arguments):
    zone = integer(arguments[0], 1, 60)
    band = arguments[1]
    require(len(band) == 1 and band in BANDS)
    easting = integer(arguments[2], 100000, 899999)
    northing = integer(arguments[3], 0, 9999999)
    places = integer(arguments[4], 0, 5)
    column = MGRS_COLUMNS[zone % 3][easting // 100000 - 1]
    shift = 5 if zone % 2 == 0 else 0
    row = MGRS_ROWS[(northing // 100000 + shift) % 20]
    prefix = f"{zone}{band} {column}{row}"
    if places == 0:
        return prefix
    east, north = metre_digits(easting, northing, places)
    return f"{prefix} {east} {north}"


def unmgrs(arguments):
    designator, square = arguments[:2]
    require(re.fullmatch(r"[1-9][0-9]?[CDEFGHJKLMNPQRSTUVWX]", designator) is not None)
    zone = int(designator[:-1])
    require(zone <= 60)
    require(len(square) == 2)
    columns = MGRS_COLUMNS[zone % 3]
    require(square[0] in columns and square[1] in MGRS_ROWS)
    easting = 100000 * (columns.index(square[0]) + 1)
    shift = 5 if zone % 2 == 0 else 0
    northing = 100000 * ((MGRS_ROWS.index(square[1]) - shift) % 20)
    east_offset, north_offset, square_size = square_offsets(arguments[2:])
    return f"{designator} sw={easting + east_offset},{northing + north_offset} size={square_size}"


def quadkey(arguments):
    zoom = integer(arguments[2], 1, 23)
    x = integer(arguments[0], 0, (1 << zoom) - 1)
    y = integer(arguments[1], 0, (1 << zoom) - 1)
    return "".join(str(((x >> bit) & 1) + 2 * ((y >> bit) & 1)) for bit in range(zoom - 1, -1, -1))


def unquadkey(arguments):
    key = arguments[0]
    require(1 <= len(key) <= 23 and all(character in "0123" for character in key))
    x = 0
    y = 0
    for character in key:
        digit = int(character)
        x = 2 * x + digit % 2
        y = 2 * y + digit // 2
    return f"x={x} y={y} z={len(key)}"


COMMANDS = {
    "ENCODE": (encode, (4,)),
    "DECODE": (decode, (2,)),
    "NEIGHBORS": (neighbors, (2,)),
    "PARENT": (parent, (2,)),
    "CHILDREN": (children, (2,)),
    "COMMON": (common, (3,)),
    "COMPACT": (compact, range(2, 102)),
    "CONTAINS": (contains, (4,)),
    "COVER": (cover, (6,)),
    "CONVERT": (convert, (5,)),
    "STEPS": (steps, (3,)),
    "PATH": (path, (3,)),
    "RELATE": (relate, (4,)),
    "SIZE": (size, (2,)),
    "SHORTEN": (shorten, (3,)),
    "RECOVER": (recover, (3,)),
    "UTMZONE": (utmzone, (2,)),
    "OSGB": (osgb, (3,)),
    "UNOSGB": (unosgb, (1, 3)),
    "MGRS": (mgrs, (5,)),
    "UNMGRS": (unmgrs, (2, 4)),
    "QUADKEY": (quadkey, (3,)),
    "UNQUADKEY": (unquadkey, (1,)),
}


def process(line):
    command, *arguments = line.split(" ")
    try:
        require(command in COMMANDS)
        handler, counts = COMMANDS[command]
        require(len(arguments) in counts)
        return handler(arguments)
    except Invalid:
        return "INVALID"


def main():
    count = int(sys.stdin.readline())
    results = []
    for _ in range(count):
        results.append(process(sys.stdin.readline().rstrip("\n")))
    sys.stdout.write("\n".join(results) + "\n")


if __name__ == "__main__":
    main()
