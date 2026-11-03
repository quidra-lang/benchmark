"""PR quadtree buckets, deterministic splitting, and bottom-up merging."""

from bisect import insort


CHILD_NAMES = ("NW", "NE", "SW", "SE")


class Node:
    __slots__ = ("x", "y", "size", "points", "children")

    def __init__(self, x, y, size):
        self.x = x
        self.y = y
        self.size = size
        self.points = []
        self.children = []


def destination(node, point):
    half = node.size // 2
    east = point[1] >= node.x + half
    south = point[2] >= node.y + half
    return int(east) + 2 * int(south)


def split(node, capacity):
    half = node.size // 2
    node.children = [
        Node(node.x, node.y, half),
        Node(node.x + half, node.y, half),
        Node(node.x, node.y + half, half),
        Node(node.x + half, node.y + half, half),
    ]
    previous = node.points
    node.points = []
    for point in previous:
        insert(node, point, capacity)


def insert(root, point, capacity):
    node = root
    while node.children:
        node = node.children[destination(node, point)]
    insort(node.points, point)
    if len(node.points) > capacity:
        split(node, capacity)


def delete(root, point, capacity):
    ancestors = []
    node = root
    while node.children:
        ancestors.append(node)
        node = node.children[destination(node, point)]
    node.points.remove(point)
    for node in reversed(ancestors):
        if any(child.children for child in node.children):
            break
        points = [point for child in node.children for point in child.points]
        if len(points) > capacity:
            break
        node.points = sorted(points)
        node.children = []


def build(points, world, capacity):
    root = Node(0, 0, world)
    for point in points:
        insert(root, point, capacity)
    return root
