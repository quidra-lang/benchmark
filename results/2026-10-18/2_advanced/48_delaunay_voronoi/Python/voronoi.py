from predicates import d2, orient, reduce_direction


def squared_radius(a, b, c):
    l1, l2, l3 = float(d2(a, b)), float(d2(b, c)), float(d2(c, a))
    area2 = float(orient(a, b, c))
    return ((l1 * l2) * l3) / ((4.0 * area2) * area2)


def position(center, points, hull):
    x, y, denominator = center
    on = False
    for index, u in enumerate(hull):
        v = hull[(index + 1) % len(hull)]
        ux, uy = points[u]
        vx, vy = points[v]
        sigma = (vx - ux) * (y - uy * denominator) - (vy - uy) * (x - ux * denominator)
        if sigma < 0:
            return "outside"
        if sigma == 0:
            on = True
    return "on" if on else "inside"


def neighbor_order(s, neighbors, directed, hull_next):
    first = hull_next[s] if s in hull_next else min(neighbors)
    order = [first]
    while len(order) < len(neighbors):
        order.append(directed[s, order[-1]])
    return order


def outward(points, u, v):
    dx = points[v][0] - points[u][0]
    dy = points[v][1] - points[u][1]
    return reduce_direction(dy, -dx)


def bounded_area(site, vertex_centers):
    x, y = site
    relative = [(vx / denominator - x, vy / denominator - y)
                for vx, vy, denominator in vertex_centers]
    total = 0.0
    for index, (u, w) in enumerate(relative):
        next_u, next_w = relative[(index + 1) % len(relative)]
        total += u * next_w - next_u * w
    return total / 2.0


def clipped_area(points, s, neighbors_order):
    polygon = [(0.0, 0.0), (1000.0, 0.0), (1000.0, 1000.0), (0.0, 1000.0)]
    xs, ys = points[s]
    for t in neighbors_order:
        xt, yt = points[t]
        c1 = 2 * (xt - xs)
        c2 = 2 * (yt - ys)
        c3 = xt * xt + yt * yt - xs * xs - ys * ys
        clipped = []
        for index, p in enumerate(polygon):
            q = polygon[(index + 1) % len(polygon)]
            fp = c1 * p[0] + c2 * p[1] - c3
            fq = c1 * q[0] + c2 * q[1] - c3
            if fp <= 0.0:
                clipped.append(p)
            if fp < 0.0 < fq or fq < 0.0 < fp:
                fraction = fp / (fp - fq)
                clipped.append((p[0] + (q[0] - p[0]) * fraction,
                                p[1] + (q[1] - p[1]) * fraction))
        polygon = clipped

    total = 0.0
    for index, p in enumerate(polygon):
        q = polygon[(index + 1) % len(polygon)]
        total += p[0] * q[1] - q[0] * p[1]
    return total / 2.0
