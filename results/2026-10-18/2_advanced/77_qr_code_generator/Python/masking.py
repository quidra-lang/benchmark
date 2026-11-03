"""Eight QR masks and the four integer penalty terms."""


def condition(mask, x, y):
    if mask == 0:
        return (y + x) % 2 == 0
    if mask == 1:
        return y % 2 == 0
    if mask == 2:
        return x % 3 == 0
    if mask == 3:
        return (y + x) % 3 == 0
    if mask == 4:
        return (y // 2 + x // 3) % 2 == 0
    if mask == 5:
        return (y * x) % 2 + (y * x) % 3 == 0
    if mask == 6:
        return ((y * x) % 2 + (y * x) % 3) % 2 == 0
    return ((y + x) % 2 + (y * x) % 3) % 2 == 0


def apply(symbol, data_positions, mask):
    result = [row[:] for row in symbol]
    for x, y in data_positions:
        if condition(mask, x, y):
            result[y][x] ^= 1
    return result


def penalties(symbol):
    size = len(symbol)
    n1 = 0
    n3 = 0
    patterns = ([1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0],
                [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1])
    lines = list(symbol) + [[symbol[y][x] for y in range(size)] for x in range(size)]
    for line in lines:
        run = 1
        for index in range(1, size):
            if line[index] == line[index - 1]:
                run += 1
            else:
                if run >= 5:
                    n1 += run - 2
                run = 1
        if run >= 5:
            n1 += run - 2
        for index in range(size - 10):
            if line[index:index + 11] in patterns:
                n3 += 40
    n2 = 0
    for y in range(size - 1):
        for x in range(size - 1):
            value = symbol[y][x]
            if value == symbol[y][x + 1] == symbol[y + 1][x] == symbol[y + 1][x + 1]:
                n2 += 3
    dark = sum(sum(row) for row in symbol)
    n4 = 10 * (abs(20 * dark - 10 * size * size) // (size * size))
    return n1, n2, n3, n4
