"""Function modules, BCH information fields, and QR data traversal."""

DATA = 0
FUNCTION = 1
FORMAT = 2
VERSION = 3


def polynomial_remainder(value, divisor):
    while value.bit_length() >= divisor.bit_length():
        value ^= divisor << (value.bit_length() - divisor.bit_length())
    return value


def format_information(level, mask):
    indicator = {"L": 1, "M": 0, "Q": 3, "H": 2}[level]
    shifted = (8 * indicator + mask) << 10
    return (shifted + polynomial_remainder(shifted, 0x537)) ^ 0x5412


def version_information(version):
    shifted = version << 12
    return shifted + polynomial_remainder(shifted, 0x1F25)


def format_positions(size):
    first = [(8, index) for index in range(6)]
    first += [(8, 7), (8, 8), (7, 8)]
    first += [(14 - index, 8) for index in range(9, 15)]
    second = [(size - 1 - index, 8) for index in range(8)]
    second += [(8, size - 15 + index) for index in range(8, 15)]
    return first, second


def version_positions(size):
    first = [(size - 11 + index % 3, index // 3) for index in range(18)]
    second = [(index // 3, size - 11 + index % 3) for index in range(18)]
    return first, second


def write_value(symbol, positions, value):
    for index, (x, y) in enumerate(positions):
        symbol[y][x] = (value >> index) & 1


def read_value(symbol, positions):
    value = 0
    for index, (x, y) in enumerate(positions):
        value |= symbol[y][x] << index
    return value


def function_matrix(version, alignments):
    size = 17 + 4 * version
    symbol = [[0] * size for _ in range(size)]
    areas = [[DATA] * size for _ in range(size)]
    for center_x, center_y in ((3, 3), (size - 4, 3), (3, size - 4)):
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                x, y = center_x + dx, center_y + dy
                if 0 <= x < size and 0 <= y < size:
                    distance = max(abs(dx), abs(dy))
                    symbol[y][x] = int(distance in (0, 1, 3))
                    areas[y][x] = FUNCTION
    for index in range(8, size - 8):
        symbol[index][6] = symbol[6][index] = int(index % 2 == 0)
        areas[index][6] = areas[6][index] = FUNCTION
    if alignments:
        first, last = alignments[0], alignments[-1]
        excluded = {(first, first), (first, last), (last, first)}
        for center_y in alignments:
            for center_x in alignments:
                if (center_x, center_y) in excluded:
                    continue
                for dy in range(-2, 3):
                    for dx in range(-2, 3):
                        x, y = center_x + dx, center_y + dy
                        symbol[y][x] = int(max(abs(dx), abs(dy)) != 1)
                        areas[y][x] = FUNCTION
    symbol[size - 8][8] = 1
    areas[size - 8][8] = FUNCTION
    for positions in format_positions(size):
        for x, y in positions:
            areas[y][x] = FORMAT
            symbol[y][x] = 0
    if version >= 7:
        for positions in version_positions(size):
            for x, y in positions:
                areas[y][x] = VERSION
            write_value(symbol, positions, version_information(version))
    return symbol, areas


def reading_order(areas):
    size = len(areas)
    right_columns = list(range(size - 1, 7, -2)) + [5, 3, 1]
    positions = []
    for pair, right in enumerate(right_columns):
        rows = range(size - 1, -1, -1) if pair % 2 == 0 else range(size)
        for y in rows:
            for x in (right, right - 1):
                if areas[y][x] == DATA:
                    positions.append((x, y))
    return positions
