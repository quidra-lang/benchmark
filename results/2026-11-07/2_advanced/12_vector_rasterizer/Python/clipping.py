from canvas import round_ratio


LEFT = 1
RIGHT = 2
TOP = 4
BOTTOM = 8


def region_code(point, clip):
    x, y = point
    x0, y0, x1, y1 = clip
    code = 0
    if x < x0:
        code |= LEFT
    if x > x1:
        code |= RIGHT
    if y < y0:
        code |= TOP
    if y > y1:
        code |= BOTTOM
    return code


def clip_segment(start, end, clip):
    x0, y0, x1, y1 = clip
    while True:
        start_code = region_code(start, clip)
        end_code = region_code(end, clip)
        if start_code == 0 and end_code == 0:
            return start, end
        if start_code & end_code:
            return None
        if start_code:
            code, outside, other = start_code, start, end
        else:
            code, outside, other = end_code, end, start
        ax, ay = outside
        bx, by = other
        if code & TOP:
            point = (ax + round_ratio((bx - ax) * (y0 - ay), by - ay), y0)
        elif code & BOTTOM:
            point = (ax + round_ratio((bx - ax) * (y1 - ay), by - ay), y1)
        elif code & RIGHT:
            point = (x1, ay + round_ratio((by - ay) * (x1 - ax), bx - ax))
        else:
            point = (x0, ay + round_ratio((by - ay) * (x0 - ax), bx - ax))
        if start_code:
            start = point
        else:
            end = point


def inside(point, axis, limit, is_minimum):
    if is_minimum:
        return point[axis] >= limit
    return point[axis] <= limit


def intersection(start, end, axis, limit):
    sx, sy = start
    ex, ey = end
    if axis == 0:
        return limit, sy + round_ratio((limit - sx) * (ey - sy), ex - sx)
    return sx + round_ratio((limit - sy) * (ex - sx), ey - sy), limit


def clip_polygon(vertices, clip):
    x0, y0, x1, y1 = clip
    boundaries = ((0, x0, True), (0, x1 + 1, False), (1, y0, True), (1, y1 + 1, False))
    for axis, limit, is_minimum in boundaries:
        output = []
        for index, end in enumerate(vertices):
            start = vertices[index - 1]
            if inside(end, axis, limit, is_minimum):
                if not inside(start, axis, limit, is_minimum):
                    output.append(intersection(start, end, axis, limit))
                output.append(end)
            elif inside(start, axis, limit, is_minimum):
                output.append(intersection(start, end, axis, limit))
        vertices = output
    return vertices
