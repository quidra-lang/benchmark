"""Integer stereo costs with clamped integral-image window sums."""


def clamped(image, width, height, x, y):
    x = min(max(x, 0), width - 1)
    y = min(max(y, 0), height - 1)
    return image[y * width + x]


def box_sum(image, width, height, window):
    radius = window // 2
    padded_width = width + 2 * radius
    padded_height = height + 2 * radius
    integral = [[0] * (padded_width + 1) for _ in range(padded_height + 1)]
    for y in range(padded_height):
        row_sum = 0
        for x in range(padded_width):
            row_sum += clamped(image, width, height, x - radius, y - radius)
            integral[y + 1][x + 1] = integral[y][x + 1] + row_sum
    result = []
    for y in range(height):
        for x in range(width):
            result.append(integral[y + window][x + window]
                          - integral[y][x + window]
                          - integral[y + window][x] + integral[y][x])
    return result


def census(image, width, height):
    result = []
    for y in range(height):
        for x in range(width):
            code = 0
            center = image[y * width + x]
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    if dx == 0 and dy == 0:
                        continue
                    lower = clamped(image, width, height, x + dx, y + dy) < center
                    code = (code << 1) | int(lower)
            result.append(code)
    return result


def texture(image, width, height, window):
    gradient = [
        abs(clamped(image, width, height, x + 1, y)
            - clamped(image, width, height, x - 1, y))
        for y in range(height) for x in range(width)
    ]
    return box_sum(gradient, width, height, window)


def cost_volume(left, right, census_left, census_right, width, height,
                kind, window, disparity_min, disparity_max):
    volume = [[] for _ in left]
    for disparity in range(disparity_min, disparity_max + 1):
        pixels = []
        for y in range(height):
            for x in range(width):
                p = y * width + x
                q = y * width + max(x - disparity, 0)
                if kind == "census":
                    value = (census_left[p] ^ census_right[q]).bit_count()
                else:
                    difference = left[p] - right[q]
                    value = abs(difference) if kind == "sad" else difference * difference
                pixels.append(value)
        totals = box_sum(pixels, width, height, window)
        for row, value in zip(volume, totals):
            row.append(value)
    return volume
