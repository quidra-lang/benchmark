from collections import deque

from dungeon_gen import DOOR, PASSABLE


DIRECTION_NAMES = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")
DIRECTIONS = ((0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1))


def passable(level, x, y):
    return level.terrain[y][x] in PASSABLE


def can_move(level, x, y, dx, dy):
    if not passable(level, x + dx, y + dy):
        return False
    if dx != 0 and dy != 0:
        return level.terrain[y][x] != DOOR and level.terrain[y + dy][x + dx] != DOOR
    return True


def line(x0, y0, x1, y1):
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = 1 if x1 > x0 else -1
    sy = 1 if y1 > y0 else -1
    err = dx - dy
    x, y = x0, y0
    cells = []
    while (x, y) != (x1, y1):
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x += sx
        if e2 < dx:
            err += dx
            y += sy
        cells.append((x, y))
    return cells


def field_of_view(level, px, py, radius):
    visible = [[False] * level.width for _ in range(level.height)]
    for y in range(max(0, py - radius), min(level.height, py + radius + 1)):
        for x in range(max(0, px - radius), min(level.width, px + radius + 1)):
            if (x - px) ** 2 + (y - py) ** 2 > radius * radius:
                continue
            cells = line(px, py, x, y)
            if all(passable(level, cx, cy) for cx, cy in cells[:-1]):
                visible[y][x] = True
    return visible


def distances(level, px, py):
    dist = [[None] * level.width for _ in range(level.height)]
    dist[py][px] = 0
    queue = deque([(px, py)])
    while queue:
        x, y = queue.popleft()
        for dx, dy in DIRECTIONS:
            if can_move(level, x, y, dx, dy) and dist[y + dy][x + dx] is None:
                dist[y + dy][x + dx] = dist[y][x] + 1
                queue.append((x + dx, y + dy))
    return dist
