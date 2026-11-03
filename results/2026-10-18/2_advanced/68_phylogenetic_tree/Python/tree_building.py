"""Unrooted trees, outgroup orientation, neighbor joining, and paths."""


class Tree:
    def __init__(self, size, taxa):
        self.size = size
        self.adjacent = {taxon: {} for taxon in taxa}
        self.next_node = size
        self.negative = 0

    def internal(self):
        node = self.next_node
        self.next_node += 1
        self.adjacent[node] = {}
        return node

    def connect(self, first, second, length=0.0):
        self.adjacent[first][second] = length
        self.adjacent[second][first] = length

    def disconnect(self, first, second):
        length = self.adjacent[first].pop(second)
        del self.adjacent[second][first]
        return length

    def copy(self):
        result = Tree(self.size, ())
        result.adjacent = {node: neighbors.copy() for node, neighbors in self.adjacent.items()}
        result.next_node = self.next_node
        result.negative = self.negative
        return result

    def taxa(self):
        return sorted(node for node in self.adjacent if node < self.size)

    def internal_nodes(self):
        return sorted(node for node in self.adjacent if node >= self.size)

    def edges(self):
        for first in sorted(self.adjacent):
            for second in sorted(self.adjacent[first]):
                if first < second:
                    yield first, second, self.adjacent[first][second]

    def rooted(self, outgroup):
        return Rooted(self, outgroup)


class Rooted:
    def __init__(self, tree, outgroup):
        self.tree = tree
        self.outgroup = outgroup
        self.root = next(iter(tree.adjacent[outgroup]))
        self.parents = {}
        self.children = {}
        self.masks = {}
        self.order = []

        def visit(node, parent):
            self.parents[node] = parent
            self.order.append(node)
            children = [neighbor for neighbor in tree.adjacent[node] if neighbor != parent]
            self.children[node] = children
            mask = 1 << node if node < tree.size else 0
            for child in children:
                visit(child, node)
                mask |= self.masks[child]
            self.masks[node] = mask

        visit(self.root, None)
        self.ingroup = self.masks[self.root] ^ (1 << outgroup)

    def splits(self):
        return {self.masks[node] for node in self.tree.internal_nodes() if node != self.root}

    def branch_lengths(self):
        lengths = {}
        for node in self.order[1:]:
            mask = self.ingroup if node == self.outgroup else self.masks[node]
            lengths[mask] = self.tree.adjacent[node][self.parents[node]]
        return lengths


def star(size, taxa):
    tree = Tree(size, taxa)
    root = tree.internal()
    for taxon in taxa:
        tree.connect(root, taxon)
    return tree


def neighbor_joining(matrix, taxa):
    active = list(taxa)
    tree = Tree(len(matrix), active)
    distances = {first: {second: matrix[first][second] for second in active} for first in active}
    while len(active) >= 4:
        count = len(active)
        totals = {}
        for first in active:
            total = 0.0
            for second in active:
                if first != second:
                    total += distances[first][second]
            totals[first] = total
        minimum = None
        selected = None
        for index, first in enumerate(active):
            for second in active[index + 1:]:
                value = (count - 2) * distances[first][second] - totals[first] - totals[second]
                if minimum is None or value < minimum:
                    minimum = value
                    selected = first, second
        first, second = selected
        node = tree.internal()
        distance = distances[first][second]
        first_length = distance / 2 + (totals[first] - totals[second]) / (2 * (count - 2))
        tree.connect(first, node, first_length)
        tree.connect(second, node, distance - first_length)
        remaining = [other for other in active if other != first and other != second]
        distances[node] = {}
        for other in remaining:
            value = (distances[first][other] + distances[second][other] - distance) / 2
            distances[node][other] = distances[other][node] = value
        active = [*remaining, node]
    first, second, third = active
    node = tree.internal()
    a, b, c = distances[first][second], distances[first][third], distances[second][third]
    tree.connect(first, node, (a + b - c) / 2)
    tree.connect(second, node, (a + c - b) / 2)
    tree.connect(third, node, (b + c - a) / 2)
    for first, second, length in tree.edges():
        if length < 0:
            tree.connect(first, second, 0.0)
            tree.negative += 1
    return tree


def path_distances(tree, start, unit=False):
    distances = {start: 0 if unit else 0.0}
    stack = [(start, None)]
    while stack:
        node, parent = stack.pop()
        for neighbor, length in tree.adjacent[node].items():
            if neighbor != parent:
                distances[neighbor] = distances[node] + (1 if unit else length)
                stack.append((neighbor, node))
    return distances


def patristic_matrix(tree):
    matrix = [[0.0] * tree.size for _ in range(tree.size)]
    taxa = tree.taxa()
    for index, first in enumerate(taxa):
        distances = path_distances(tree, first)
        for second in taxa[index + 1:]:
            matrix[first][second] = matrix[second][first] = distances[second]
    return matrix
