"""Drawing box trees and emitting their absolute preorder positions."""


def walk(box, x, y, level=0, role=""):
    yield box, x, y, level, role
    for child, dx, dy, child_role in box.children:
        yield from walk(child, x + dx, y + dy, level + 1, child_role)


def draw(roots, width, height):
    grid = [[" "] * width for row in range(height)]
    for root, root_x, root_y in roots:
        for box, x, y, level, role in walk(root, root_x, root_y):
            for text, dx, dy in box.strings:
                for index, character in enumerate(text):
                    if character != " ":
                        grid[y + dy][x + dx + index] = character
    return ["".join(row).rstrip(" ") for row in grid]


def box_lines(roots):
    for root, root_x, root_y in roots:
        for box, x, y, level, role in walk(root, root_x, root_y):
            line = ("  " * level + role + box.description
                    + f" x={x} y={y} w={box.width} h={box.height} b={box.baseline}")
            yield line, level, box.description.split(" ", 1)[0]
