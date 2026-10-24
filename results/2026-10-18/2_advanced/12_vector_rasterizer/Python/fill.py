def polygon_edges(sequences):
    edges = []
    for vertices in sequences:
        for index, start in enumerate(vertices):
            end = vertices[(index + 1) % len(vertices)]
            if start[1] != end[1]:
                edges.append((start, end))
    return edges


def crossing_start(start, end, y):
    xa, ya = start
    xb, yb = end
    denominator = yb - ya
    numerator = 2 * xa * denominator + (2 * y + 1 - 2 * ya) * (xb - xa)
    if denominator < 0:
        numerator, denominator = -numerator, -denominator
    return (numerator - denominator) // (2 * denominator) + 1


def row_crossings(edges, y):
    crossings = []
    for start, end in edges:
        if min(start[1], end[1]) <= y < max(start[1], end[1]):
            direction = 1 if end[1] > start[1] else -1
            crossings.append((crossing_start(start, end, y), direction))
    crossings.sort()
    return crossings


def is_filled(rule, count, winding):
    if rule == "evenodd":
        return count % 2 == 1
    return winding != 0


def fill_polygons(sequences, rule, clip):
    x0, y0, x1, y1 = clip
    edges = polygon_edges(sequences)
    pixels = set()
    for y in range(y0, y1 + 1):
        crossings = row_crossings(edges, y)
        if not crossings:
            continue
        count = 0
        winding = 0
        index = 0
        for x in range(x0, x1 + 1):
            while index < len(crossings) and crossings[index][0] <= x:
                count += 1
                winding += crossings[index][1]
                index += 1
            if is_filled(rule, count, winding):
                pixels.add((x, y))
    return pixels


def fill_shape(center, points, clip):
    center_x, center_y = center
    x0, y0, x1, y1 = clip
    extents = {}
    for dx, dy in points:
        extents[dy] = max(extents.get(dy, 0), abs(dx))
    pixels = set()
    for dy, extent in extents.items():
        y = center_y + dy
        if not y0 <= y <= y1:
            continue
        for x in range(max(x0, center_x - extent), min(x1, center_x + extent) + 1):
            pixels.add((x, y))
    return pixels


def flood_fill(layer, seed, clip):
    x0, y0, x1, y1 = clip
    target = layer.color_at(seed[0], seed[1])
    pixels = {seed}
    pending = [seed]
    while pending:
        x, y = pending.pop()
        for neighbor in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            nx, ny = neighbor
            if neighbor in pixels or not (x0 <= nx <= x1 and y0 <= ny <= y1):
                continue
            if layer.color_at(nx, ny) == target:
                pixels.add(neighbor)
                pending.append(neighbor)
    return pixels
