"""Integer boxes and ordered R-trees with quadratic splits and STR loading."""

from math import isqrt


def point_box(point):
    return point[1], point[2], point[1], point[2]


def area(box):
    return (box[2] - box[0]) * (box[3] - box[1])


def mbr(first, second):
    return (
        min(first[0], second[0]),
        min(first[1], second[1]),
        max(first[2], second[2]),
        max(first[3], second[3]),
    )


def bounding_box(boxes):
    boxes = iter(boxes)
    result = next(boxes)
    for box in boxes:
        result = mbr(result, box)
    return result


def enlargement(first, second):
    return area(mbr(first, second)) - area(first)


def contains(outer, inner):
    return (
        outer[0] <= inner[0]
        and inner[2] <= outer[2]
        and outer[1] <= inner[1]
        and inner[3] <= outer[3]
    )


def intersects(first, second):
    return (
        first[0] <= second[2]
        and second[0] <= first[2]
        and first[1] <= second[3]
        and second[1] <= first[3]
    )


def overlap(first, second):
    width = min(first[2], second[2]) - max(first[0], second[0])
    height = min(first[3], second[3]) - max(first[1], second[1])
    return width * height if width > 0 and height > 0 else 0


class Entry:
    __slots__ = ("box", "object_id", "child")

    def __init__(self, box, object_id=None, child=None):
        self.box = box
        self.object_id = object_id
        self.child = child


class Node:
    __slots__ = ("level", "entries", "parent")

    def __init__(self, level, entries=(), parent=None):
        self.level = level
        self.entries = list(entries)
        self.parent = parent
        self.adopt_children()

    @property
    def box(self):
        return bounding_box(entry.box for entry in self.entries)

    def adopt_children(self):
        if self.level > 0:
            for entry in self.entries:
                entry.child.parent = self


class RTree:
    def __init__(self, maximum, minimum):
        self.maximum = maximum
        self.minimum = minimum
        self.root = Node(0)

    def choose_subtree(self, box, level):
        node = self.root
        while node.level > level:
            entry = min(
                node.entries,
                key=lambda entry: (enlargement(entry.box, box), area(entry.box)),
            )
            node = entry.child
        return node

    def split(self, node):
        entries = node.entries
        best_waste = None
        seeds = None
        for first in range(len(entries) - 1):
            for second in range(first + 1, len(entries)):
                a, b = entries[first].box, entries[second].box
                waste = area(mbr(a, b)) - area(a) - area(b)
                if best_waste is None or waste > best_waste:
                    best_waste = waste
                    seeds = first, second
        first, second = seeds
        group1, group2 = [entries[first]], [entries[second]]
        box1, box2 = entries[first].box, entries[second].box
        rest = [entry for index, entry in enumerate(entries) if index not in seeds]
        while rest:
            if len(group1) + len(rest) == self.minimum:
                group1.extend(rest)
                break
            if len(group2) + len(rest) == self.minimum:
                group2.extend(rest)
                break
            selected = 0
            greatest_difference = -1
            selected_d1 = selected_d2 = 0
            for index, entry in enumerate(rest):
                d1 = enlargement(box1, entry.box)
                d2 = enlargement(box2, entry.box)
                difference = abs(d1 - d2)
                if difference > greatest_difference:
                    selected = index
                    greatest_difference = difference
                    selected_d1, selected_d2 = d1, d2
            entry = rest.pop(selected)
            choice1 = selected_d1, area(box1), len(group1), 0
            choice2 = selected_d2, area(box2), len(group2), 1
            if choice1 < choice2:
                group1.append(entry)
                box1 = mbr(box1, entry.box)
            else:
                group2.append(entry)
                box2 = mbr(box2, entry.box)
        node.entries = group1
        node.adopt_children()
        return Node(node.level, group2, node.parent)

    def insert(self, entry, level=0):
        node = self.choose_subtree(entry.box, level)
        node.entries.append(entry)
        if level > 0:
            entry.child.parent = node
        while True:
            sibling = self.split(node) if len(node.entries) > self.maximum else None
            parent = node.parent
            if parent is None:
                if sibling is not None:
                    self.root = Node(
                        node.level + 1,
                        [Entry(node.box, child=node), Entry(sibling.box, child=sibling)],
                    )
                return
            for parent_entry in parent.entries:
                if parent_entry.child is node:
                    parent_entry.box = node.box
                    break
            if sibling is not None:
                parent.entries.append(Entry(sibling.box, child=sibling))
                sibling.parent = parent
            node = parent

    def find_leaf(self, identifier, box):
        pending = [self.root]
        while pending:
            node = pending.pop()
            if node.level == 0:
                for index, entry in enumerate(node.entries):
                    if entry.object_id == identifier:
                        return node, index
            else:
                for entry in reversed(node.entries):
                    if contains(entry.box, box):
                        pending.append(entry.child)
        return None

    def delete(self, point):
        node, index = self.find_leaf(point[0], point_box(point))
        node.entries.pop(index)
        removed = []
        while node is not self.root:
            parent = node.parent
            for index, entry in enumerate(parent.entries):
                if entry.child is node:
                    if len(node.entries) < self.minimum:
                        parent.entries.pop(index)
                        removed.append(node)
                        node.parent = None
                    else:
                        entry.box = node.box
                    break
            node = parent
        # Q is bottom-up. Its internal entries retain their entire subtrees.
        for node in removed:
            for entry in node.entries:
                self.insert(entry, node.level)
        while self.root.level > 0 and len(self.root.entries) == 1:
            self.root = self.root.entries[0].child
            self.root.parent = None


def str_root(entries, maximum):
    numbered = [(entry.object_id, entry) for entry in entries]
    level = 0
    while True:
        pages = (len(numbered) + maximum - 1) // maximum
        slabs = isqrt(pages)
        if slabs * slabs < pages:
            slabs += 1
        numbered.sort(
            key=lambda item: (
                item[1].box[0] + item[1].box[2],
                item[1].box[1] + item[1].box[3],
                item[0],
            )
        )
        nodes = []
        slab_size = slabs * maximum
        for start in range(0, len(numbered), slab_size):
            slab = numbered[start:start + slab_size]
            slab.sort(
                key=lambda item: (
                    item[1].box[1] + item[1].box[3],
                    item[1].box[0] + item[1].box[2],
                    item[0],
                )
            )
            for offset in range(0, len(slab), maximum):
                group = [entry for number, entry in slab[offset:offset + maximum]]
                nodes.append(Node(level, group))
        if len(nodes) == 1:
            return nodes[0]
        numbered = [
            (number, Entry(node.box, child=node))
            for number, node in enumerate(nodes)
        ]
        level += 1


def build(entries, maximum, minimum, bulk=False):
    tree = RTree(maximum, minimum)
    if bulk:
        tree.root = str_root(entries, maximum)
    else:
        for entry in entries:
            tree.insert(entry)
    return tree
