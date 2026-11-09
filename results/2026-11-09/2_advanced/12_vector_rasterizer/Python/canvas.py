OPAQUE = 255


def round_ratio(numerator, denominator):
    if denominator < 0:
        numerator, denominator = -numerator, -denominator
    return (2 * numerator + denominator) // (2 * denominator)


def effective_alpha(alpha, opacity):
    return round_ratio(alpha * opacity, OPAQUE)


def blend_component(mode, source, value):
    if mode == "multiply":
        return round_ratio(source * value, OPAQUE)
    if mode == "screen":
        return OPAQUE - round_ratio((OPAQUE - source) * (OPAQUE - value), OPAQUE)
    return source


class Layer:
    def __init__(self, width, height, opacity, mode):
        self.width = width
        self.height = height
        self.opacity = opacity
        self.mode = mode
        self.colors = [[None] * width for _ in range(height)]
        self.lines = [[0] * width for _ in range(height)]

    def paint(self, x, y, color, line):
        self.colors[y][x] = color
        self.lines[y][x] = line

    def erase(self, x, y):
        painted = self.colors[y][x] is not None
        self.colors[y][x] = None
        return painted

    def color_at(self, x, y):
        return self.colors[y][x]

    def line_at(self, x, y):
        return self.lines[y][x]

    def alpha_at(self, x, y):
        color = self.colors[y][x]
        if color is None:
            return 0
        return effective_alpha(color[3], self.opacity)

    def blend(self, x, y, current):
        color = self.colors[y][x]
        if color is None:
            return current
        alpha = effective_alpha(color[3], self.opacity)
        return tuple(
            round_ratio(alpha * blend_component(self.mode, source, value) + (OPAQUE - alpha) * value, OPAQUE)
            for source, value in zip(color[:3], current)
        )


def composite(layers, background, width, height):
    image = []
    for y in range(height):
        row = []
        for x in range(width):
            color = background[:3]
            for layer in layers:
                color = layer.blend(x, y, color)
            row.append(color)
        image.append(row)
    return image
