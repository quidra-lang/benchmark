"""Median construction and the prescribed mutable k-d tree operations."""


class Node:
    __slots__ = ("point", "axis", "left", "right")

    def __init__(self, point, axis, left=None, right=None):
        self.point = point
        self.axis = axis
        self.left = left
        self.right = right


def key(point, axis):
    identifier, x, y = point
    return (x, y, identifier) if axis == 0 else (y, x, identifier)


def build(points, depth=0):
    if not points:
        return None
    axis = depth % 2
    ordered = sorted(points, key=lambda point: key(point, axis))
    middle = len(ordered) // 2
    return Node(
        ordered[middle],
        axis,
        build(ordered[:middle], depth + 1),
        build(ordered[middle + 1:], depth + 1),
    )


def insert(root, point):
    if root is None:
        return Node(point, 0)
    node = root
    while True:
        side = "left" if key(point, node.axis) < key(node.point, node.axis) else "right"
        child = getattr(node, side)
        if child is None:
            setattr(node, side, Node(point, 1 - node.axis))
            return root
        node = child


def minimum(root, axis):
    best = None
    pending = [root]
    while pending:
        node = pending.pop()
        if node.axis == axis and node.left is not None:
            pending.append(node.left)
            continue
        if best is None or key(node.point, axis) < key(best, axis):
            best = node.point
        if node.axis != axis:
            if node.right is not None:
                pending.append(node.right)
            if node.left is not None:
                pending.append(node.left)
    return best


def delete(root, point):
    # Each replacement leaves one deletion to do in a descendant subtree.
    # Following that deletion iteratively also supports long insertion chains.
    parent = None
    side = None
    node = root
    while node is not None:
        if node.point[0] != point[0]:
            parent = node
            side = "left" if key(point, node.axis) < key(node.point, node.axis) else "right"
            node = getattr(node, side)
            continue
        if node.right is not None:
            point = minimum(node.right, node.axis)
            node.point = point
            parent, side, node = node, "right", node.right
        elif node.left is not None:
            point = minimum(node.left, node.axis)
            node.point = point
            node.right = node.left
            node.left = None
            parent, side, node = node, "right", node.right
        else:
            if parent is None:
                return None
            setattr(parent, side, None)
            return root
    return root
