from math import gcd

from tree_builder import LEFT


PRIMARY = "primary"
SURROGATE = "surrogate"
DEFAULT = "default"


def real_text(value, places=4):
    text = f"{value:.{places}f}"
    if text == "-0." + "0" * places:
        return text[1:]
    return text


def ratio_text(numerator, denominator):
    if denominator == 0:
        return "0/0 -"
    return f"{numerator}/{denominator} {real_text(numerator / denominator)}"


def fraction_text(numerator, denominator, places=4):
    if denominator == 0:
        return "- -"
    divisor = gcd(numerator, denominator)
    numerator //= divisor
    denominator //= divisor
    return f"{numerator}/{denominator} {real_text(numerator / denominator, places)}"


def average(values):
    total = 0.0
    for value in values:
        total += value
    return total / len(values)


def direction(node, row):
    value = row.value(node.split.attribute)
    if value is not None:
        return node.split.goes_left(value), PRIMARY
    for surrogate in node.surrogates:
        value = row.value(surrogate.split.attribute)
        if value is not None:
            return surrogate.goes_left(value), SURROGATE
    return node.default == LEFT, DEFAULT


class PrunedTree:
    def __init__(self, root, cut=None):
        self.root = root
        self.cut = set() if cut is None else cut

    def is_leaf(self, node):
        return node.split is None or node.number in self.cut

    def preorder(self, start=None):
        nodes = []
        pending = [self.root if start is None else start]
        while pending:
            node = pending.pop()
            nodes.append(node)
            if not self.is_leaf(node):
                pending.append(node.right)
                pending.append(node.left)
        return nodes

    def leaves(self, start=None):
        return [node for node in self.preorder(start) if self.is_leaf(node)]

    def internal_nodes(self, start=None):
        return [node for node in self.preorder(start) if not self.is_leaf(node)]

    def depth(self):
        return max(node.depth for node in self.leaves())

    def training_errors(self):
        return sum(node.errors for node in self.leaves())

    def route(self, row):
        node = self.root
        path = [node]
        methods = []
        while not self.is_leaf(node):
            left, method = direction(node, row)
            node = node.left if left else node.right
            path.append(node)
            methods.append(method)
        return path, methods

    def leaf_of(self, row):
        path, methods = self.route(row)
        return path[-1]

    def predict(self, row):
        return self.leaf_of(row).prediction

    def correct_count(self, rows):
        return sum(self.predict(row) == row.label for row in rows)


def confusion_matrix(actual, predicted, class_count):
    matrix = [[0] * class_count for _ in range(class_count)]
    for label, prediction in zip(actual, predicted):
        matrix[label][prediction] += 1
    return matrix


def classification_lines(title, class_names, actual, predicted):
    matrix = confusion_matrix(actual, predicted, len(class_names))
    correct = sum(matrix[index][index] for index in range(len(class_names)))
    total = len(actual)
    lines = [
        f"confusion {title} correct {correct}/{total} accuracy {fraction_text(correct, total)}",
        "actual\\predicted " + " ".join(class_names),
    ]
    for name, counts in zip(class_names, matrix):
        lines.append(name + " " + " ".join(str(count) for count in counts))
    f1_values = []
    for index, name in enumerate(class_names):
        hits = matrix[index][index]
        predicted_total = sum(counts[index] for counts in matrix)
        support = sum(matrix[index])
        if predicted_total + support > 0:
            f1_values.append(2 * hits / (predicted_total + support))
        lines.append(
            f"class {name} precision {fraction_text(hits, predicted_total)}"
            f" recall {fraction_text(hits, support)}"
            f" f1 {fraction_text(2 * hits, predicted_total + support)} support {support}"
        )
    lines.append(f"macro_f1 {real_text(average(f1_values))}")
    return lines
