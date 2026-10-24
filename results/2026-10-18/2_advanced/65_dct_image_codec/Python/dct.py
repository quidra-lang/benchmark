"""Two-stage integer transforms and quantization in the supplied zigzag order."""

from color import clamp


ZIGZAG = tuple(sorted(
    ((u, v) for u in range(8) for v in range(8)),
    key=lambda position: (
        position[0] + position[1],
        position[0] if (position[0] + position[1]) % 2 else -position[0],
    ),
))


def rounded_shift(value, shift):
    return (value + (1 << (shift - 1))) >> shift


def forward(block, transform):
    intermediate = [[0] * 8 for _ in range(8)]
    for u in range(8):
        for x in range(8):
            total = 0
            for y in range(8):
                total += transform[u][y] * (block[y][x] - 128)
            intermediate[u][x] = rounded_shift(total, 11)
    result = [[0] * 8 for _ in range(8)]
    for u in range(8):
        for v in range(8):
            total = 0
            for x in range(8):
                total += intermediate[u][x] * transform[v][x]
            result[u][v] = rounded_shift(total, 15)
    return result


def inverse(coefficients, transform):
    intermediate = [[0] * 8 for _ in range(8)]
    for y in range(8):
        for v in range(8):
            total = 0
            for u in range(8):
                total += transform[u][y] * coefficients[u][v]
            intermediate[y][v] = rounded_shift(total, 11)
    result = [[0] * 8 for _ in range(8)]
    for y in range(8):
        for x in range(8):
            total = 0
            for v in range(8):
                total += intermediate[y][v] * transform[v][x]
            result[y][x] = clamp(rounded_shift(total, 15) + 128)
    return result


def quantization_tables(basic_tables, quality):
    scale = 5000 // quality if quality < 50 else 200 - 2 * quality
    return {
        identifier: [[min(max((value * scale + 50) // 100, 1), 255) for value in row]
                     for row in table]
        for identifier, table in enumerate(basic_tables)
    }


def quantize(values, table):
    result = []
    for value_row, quant_row in zip(values, table):
        row = []
        for value, divisor in zip(value_row, quant_row):
            magnitude = (abs(value) + divisor // 2) // divisor
            row.append(magnitude if value >= 0 else -magnitude)
        result.append(row)
    return result


def zigzag(values):
    return [values[u][v] for u, v in ZIGZAG]


def unzigzag(sequence):
    result = [[0] * 8 for _ in range(8)]
    for (u, v), value in zip(ZIGZAG, sequence):
        result[u][v] = value
    return result


def dequantize(sequence, table, keep=64):
    result = [[0] * 8 for _ in range(8)]
    for index, (u, v) in enumerate(ZIGZAG):
        if index < keep:
            result[u][v] = sequence[index] * table[u][v]
    return result
