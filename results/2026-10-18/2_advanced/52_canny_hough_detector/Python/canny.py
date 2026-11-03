"""Integer gradient directions, nonmax suppression, BFS hysteresis and blobs."""

from collections import Counter, deque


NEIGHBORS = (
    (-1, -1), (0, -1), (1, -1),
    (-1, 0),            (1, 0),
    (-1, 1), (0, 1), (1, 1),
)

OFFSETS = {
    0: ((-1, 0), (1, 0)),
    45: ((1, -1), (-1, 1)),
    90: ((0, -1), (0, 1)),
    135: ((-1, -1), (1, 1)),
}


def directions(gx, gy):
    image = []
    for rowx, rowy in zip(gx, gy):
        row = []
        for dx, dy in zip(rowx, rowy):
            ax, ay = abs(dx), abs(dy)
            if 29 * ay <= 12 * ax:
                row.append(0)
            elif 29 * ay >= 70 * ax:
                row.append(90)
            else:
                row.append(45 if dx * dy < 0 else 135)
        image.append(row)
    return image


def suppress(magnitude, direction):
    height = len(magnitude)
    width = len(magnitude[0])
    image = [[0] * width for _ in range(height)]
    for y in range(1, height - 1):
        for x in range(1, width - 1):
            before, after = OFFSETS[direction[y][x]]
            value = magnitude[y][x]
            if (value > magnitude[y + before[1]][x + before[0]]
                    and value >= magnitude[y + after[1]][x + after[0]]):
                image[y][x] = value
    return image


def hysteresis(nonmax, low, high):
    height = len(nonmax)
    width = len(nonmax[0])
    strong = {
        (x, y) for y in range(height) for x in range(width)
        if nonmax[y][x] >= high
    }
    weak = {
        (x, y) for y in range(height) for x in range(width)
        if low <= nonmax[y][x] < high
    }
    edges = set(strong)
    queue = deque(sorted(strong, key=lambda point: (point[1], point[0])))
    allowed = strong | weak
    while queue:
        x, y = queue.popleft()
        for dx, dy in NEIGHBORS:
            neighbor = x + dx, y + dy
            if neighbor in allowed and neighbor not in edges:
                edges.add(neighbor)
                queue.append(neighbor)
    return edges, strong, weak


def components(edges, magnitude, direction):
    """Trace 8-connected edge pixels in raster order; compute component attributes."""
    waiting = set(edges)
    found = []
    while waiting:
        first = min(waiting, key=lambda p: (p[1], p[0]))
        waiting.remove(first)
        queue = deque([first])
        pixels = []
        while queue:
            x, y = queue.popleft()
            pixels.append((x, y))
            for dx, dy in NEIGHBORS:
                next_pixel = x + dx, y + dy
                if next_pixel in waiting:
                    waiting.remove(next_pixel)
                    queue.append(next_pixel)
        xs = [p[0] for p in pixels]
        ys = [p[1] for p in pixels]
        ends = sum(
            sum((x + dx, y + dy) in edges for dx, dy in NEIGHBORS) == 1
            for x, y in pixels
        )
        strengths = sum(magnitude[y][x] for x, y in pixels)
        counts = Counter(direction[y][x] for x, y in pixels)
        major = min(counts, key=lambda angle: (-counts[angle], angle))
        found.append({
            "number": len(found) + 1, "pixels": pixels,
            "size": len(pixels),
            "box": (min(xs), min(ys), max(xs), max(ys)),
            "ends": ends, "strength": strengths // len(pixels),
            "direction": major,
        })
    return found
