"""Integer colour conversion, edge extension, subsampling, and upsampling."""


def clamp(value):
    return min(max(value, 0), 255)


def to_ycbcr(pixel):
    red, green, blue = pixel
    y = (19595 * red + 38470 * green + 7471 * blue + 32768) // 65536
    cb = (-11059 * red - 21709 * green + 32768 * blue + 8421375) // 65536
    cr = (32768 * red - 27439 * green - 5329 * blue + 8421375) // 65536
    return y, cb, cr


def to_rgb(y, cb, cr):
    red = clamp(y + (91881 * (cr - 128) + 32768) // 65536)
    green = clamp(y + (-22554 * (cb - 128) - 46802 * (cr - 128) + 32768) // 65536)
    blue = clamp(y + (116130 * (cb - 128) + 32768) // 65536)
    return red, green, blue


def split_planes(image):
    height, width = len(image), len(image[0])
    planes = [[[0] * width for _ in range(height)] for _ in range(3)]
    for y, row in enumerate(image):
        for x, pixel in enumerate(row):
            for component, value in enumerate(to_ycbcr(pixel)):
                planes[component][y][x] = value
    return planes


def component_planes(planes, factors, mcu_columns, mcu_rows):
    width, height = len(planes[0][0]), len(planes[0])
    hmax = max(horizontal for horizontal, _ in factors)
    vmax = max(vertical for _, vertical in factors)
    padded_width = 8 * hmax * mcu_columns
    padded_height = 8 * vmax * mcu_rows
    result = []
    for plane, (horizontal, vertical) in zip(planes, factors):
        extended = [
            [plane[min(y, height - 1)][min(x, width - 1)] for x in range(padded_width)]
            for y in range(padded_height)
        ]
        fx, fy = hmax // horizontal, vmax // vertical
        component = []
        for y in range(8 * vertical * mcu_rows):
            row = []
            for x in range(8 * horizontal * mcu_columns):
                total = 0
                for j in range(fy):
                    for i in range(fx):
                        total += extended[fy * y + j][fx * x + i]
                row.append(total // (fx * fy))
            component.append(row)
        result.append(component)
    return result


def upsample(planes, factors, width, height):
    hmax = max(horizontal for horizontal, _ in factors)
    vmax = max(vertical for _, vertical in factors)
    return [
        [[plane[y * vertical // vmax][x * horizontal // hmax] for x in range(width)]
         for y in range(height)]
        for plane, (horizontal, vertical) in zip(planes, factors)
    ]


def combine_rgb(planes):
    height, width = len(planes[0]), len(planes[0][0])
    return [
        [to_rgb(planes[0][y][x], planes[1][y][x], planes[2][y][x]) for x in range(width)]
        for y in range(height)
    ]
