from canvas import round_ratio


def bresenham(start, end):
    x, y = start
    end_x, end_y = end
    dx = abs(end_x - x)
    dy = -abs(end_y - y)
    step_x = 1 if x < end_x else -1
    step_y = 1 if y < end_y else -1
    error = dx + dy
    points = []
    while True:
        points.append((x, y))
        if x == end_x and y == end_y:
            return points
        doubled = 2 * error
        if doubled >= dy:
            error += dy
            x += step_x
        if doubled <= dx:
            error += dx
            y += step_y


def expand_square(x, y, width):
    low = -((width - 1) // 2)
    return [
        (x + i, y + j)
        for j in range(low, low + width)
        for i in range(low, low + width)
    ]


def circle_points(radius):
    points = set()
    a = radius
    b = 0
    error = 1 - radius
    while a >= b:
        points.update(((a, b), (b, a), (-b, a), (-a, b), (-a, -b), (-b, -a), (b, -a), (a, -b)))
        b += 1
        if error < 0:
            error += 2 * b + 1
        else:
            a -= 1
            error += 2 * (b - a) + 1
    return points


def add_quadrants(points, x, y):
    points.update(((x, y), (-x, y), (x, -y), (-x, -y)))


def ellipse_points(rx, ry):
    rx2 = rx * rx
    ry2 = ry * ry
    x = 0
    y = ry
    points = {(0, ry), (0, -ry)}
    while ry2 * x < rx2 * y:
        decision = 4 * ry2 * (x + 1) ** 2 + rx2 * (2 * y - 1) ** 2 - 4 * rx2 * ry2
        x += 1
        if decision >= 0:
            y -= 1
        add_quadrants(points, x, y)
    while y > 0:
        decision = ry2 * (2 * x + 1) ** 2 + 4 * rx2 * (y - 1) ** 2 - 4 * rx2 * ry2
        y -= 1
        if decision <= 0:
            x += 1
        add_quadrants(points, x, y)
    return points


def bezier_weights(degree, segments, i):
    rest = segments - i
    if degree == 2:
        return rest * rest, 2 * i * rest, i * i
    return rest ** 3, 3 * i * rest * rest, 3 * i * i * rest, i ** 3


def bezier_points(controls, segments):
    degree = len(controls) - 1
    scale = segments ** degree
    points = []
    for i in range(segments + 1):
        weights = bezier_weights(degree, segments, i)
        x = sum(weight * control[0] for weight, control in zip(weights, controls))
        y = sum(weight * control[1] for weight, control in zip(weights, controls))
        points.append((round_ratio(x, scale), round_ratio(y, scale)))
    return points
