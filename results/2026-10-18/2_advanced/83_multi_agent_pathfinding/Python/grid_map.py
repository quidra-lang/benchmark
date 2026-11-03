"""Warehouse grid, agents, deterministic action order and goal distances."""

import csv
from collections import deque
from pathlib import Path


ACTIONS = ((0, 0, "."), (0, -1, "N"), (1, 0, "E"),
           (0, 1, "S"), (-1, 0, "W"))


def read_grid(path="input/map.txt"):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    width, height = map(int, lines[0].split())
    rows = lines[1:]
    free = {
        (x, y) for y, row in enumerate(rows) for x, char in enumerate(row)
        if char == "."
    }
    return {"width": width, "height": height, "rows": rows, "free": free}


def read_agents(path="input/agents.csv"):
    with open(path, encoding="ascii", newline="") as file:
        rows = list(csv.reader(file))[1:]
    return [
        {"id": int(id_text), "start": (int(sx), int(sy)),
         "goal": (int(gx), int(gy)), "name": chr(65 + int(id_text))}
        for id_text, sx, sy, gx, gy in rows
    ]


def destinations(grid, cell):
    x, y = cell
    for dx, dy, action in ACTIONS:
        next_cell = (x + dx, y + dy)
        if next_cell in grid["free"]:
            yield next_cell, action


def neighbors(grid, cell):
    return [destination for destination, action in destinations(grid, cell)
            if action != "."]


def distance_table(grid, goal):
    """Breadth-first distance from the goal to every reachable free cell."""
    distances = {goal: 0}
    queue = deque([goal])
    while queue:
        cell = queue.popleft()
        for neighbor in neighbors(grid, cell):
            if neighbor not in distances:
                distances[neighbor] = distances[cell] + 1
                queue.append(neighbor)
    return distances


def grid_statistics(grid):
    degrees = {cell: len(neighbors(grid, cell)) for cell in grid["free"]}
    isolated = sum(degree == 0 for degree in degrees.values())
    dead_ends = sum(degree == 1 for degree in degrees.values())
    corridors = sum(degree == 2 for degree in degrees.values())
    junctions = sum(degree >= 3 for degree in degrees.values())
    remaining = set(grid["free"])
    components = 0
    while remaining:
        components += 1
        seed = min(remaining)
        remaining.remove(seed)
        queue = deque([seed])
        while queue:
            for adjacent in neighbors(grid, queue.popleft()):
                if adjacent in remaining:
                    remaining.remove(adjacent)
                    queue.append(adjacent)
    return {
        "isolated": isolated, "dead_ends": dead_ends,
        "corridors": corridors, "junctions": junctions,
        "components": components,
    }
