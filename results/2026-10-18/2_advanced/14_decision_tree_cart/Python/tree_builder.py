from impurity import class_counts, error_count, evaluation_value, improves, is_greater, majority


LEFT = "left"
RIGHT = "right"


def half_text(doubled):
    return f"{doubled // 2}.{5 * (doubled % 2)}"


class Split:
    def __init__(self, attribute, point):
        self.attribute = attribute
        self.point = point

    def goes_left(self, value):
        if self.attribute.integer:
            return 2 * value <= self.point
        return value == self.point

    def left_condition(self):
        if self.attribute.integer:
            return f"{self.attribute.name} <= {half_text(self.point)}"
        return f"{self.attribute.name} = {self.attribute.values[self.point]}"

    def right_condition(self):
        if self.attribute.integer:
            return f"{self.attribute.name} > {half_text(self.point)}"
        return f"{self.attribute.name} != {self.attribute.values[self.point]}"

    def condition(self, left):
        return self.left_condition() if left else self.right_condition()


class Surrogate:
    def __init__(self, split, direction, score):
        self.split = split
        self.direction = direction
        self.score = score

    def goes_left(self, value):
        return self.split.goes_left(value) == (self.direction == LEFT)


class Candidate:
    def __init__(self, split, left_counts, right_counts):
        self.split = split
        self.left_counts = left_counts
        self.right_counts = right_counts
        self.left_size = sum(left_counts)
        self.right_size = sum(right_counts)

    def value(self):
        return evaluation_value(self.left_counts, self.right_counts)


class Node:
    def __init__(self, number, depth, counts):
        self.number = number
        self.depth = depth
        self.counts = counts
        self.size = sum(counts)
        self.prediction = majority(counts)
        self.errors = error_count(counts)
        self.split = None
        self.surrogates = []
        self.default = None
        self.left = None
        self.right = None


def candidates(attribute, rows, labels, label_count):
    groups = {}
    total = [0] * label_count
    for row, label in zip(rows, labels):
        value = row.value(attribute)
        if value not in groups:
            groups[value] = [0] * label_count
        groups[value][label] += 1
        total[label] += 1
    found = []
    if attribute.integer:
        ordered = sorted(groups)
        left = [0] * label_count
        for lower, upper in zip(ordered, ordered[1:]):
            left = [a + b for a, b in zip(left, groups[lower])]
            right = [a - b for a, b in zip(total, left)]
            found.append(Candidate(Split(attribute, lower + upper), left, right))
    elif len(groups) > 1:
        for value in range(len(attribute.values)):
            if value in groups:
                right = [a - b for a, b in zip(total, groups[value])]
                found.append(Candidate(Split(attribute, value), groups[value], right))
    return found


class TreeBuilder:
    def __init__(self, attributes, class_count, settings):
        self.attributes = attributes
        self.class_count = class_count
        self.max_depth = settings.max_depth
        self.min_samples_split = settings.min_samples_split
        self.min_samples_leaf = settings.min_samples_leaf
        self.max_surrogates = settings.max_surrogates

    def valid(self, candidate):
        return (
            candidate.left_size >= self.min_samples_leaf
            and candidate.right_size >= self.min_samples_leaf
        )

    def best_split(self, rows, attributes):
        labels = [row.label for row in rows]
        best = None
        for attribute in attributes:
            for candidate in candidates(attribute, rows, labels, self.class_count):
                if not self.valid(candidate):
                    continue
                if best is None or is_greater(candidate.value(), best.value()):
                    best = candidate
        return best

    def find_surrogates(self, rows, split):
        directions = [0 if split.goes_left(row.value(split.attribute)) else 1 for row in rows]
        size = len(rows)
        left_size = directions.count(0)
        limit = max(left_size, size - left_size)
        chosen = []
        for attribute in self.attributes:
            if attribute is split.attribute:
                continue
            best = None
            for candidate in candidates(attribute, rows, directions, 2):
                agreement = candidate.left_counts[0] + candidate.right_counts[1]
                if agreement >= size - agreement:
                    surrogate = Surrogate(candidate.split, LEFT, agreement)
                else:
                    surrogate = Surrogate(candidate.split, RIGHT, size - agreement)
                if best is None or surrogate.score > best.score:
                    best = surrogate
            if best is not None and best.score > limit:
                chosen.append(best)
        chosen.sort(key=lambda surrogate: -surrogate.score)
        return chosen[:self.max_surrogates]

    def grow(self, rows):
        return self.grow_node(rows, 1, 0)

    def grow_node(self, rows, number, depth):
        node = Node(number, depth, class_counts(rows, self.class_count))
        if max(node.counts) == node.size:
            return node
        if depth == self.max_depth or node.size < self.min_samples_split:
            return node
        best = self.best_split(rows, self.attributes)
        if best is None or not improves(best.value(), node.counts):
            return node
        split = best.split
        left_rows = [row for row in rows if split.goes_left(row.value(split.attribute))]
        right_rows = [row for row in rows if not split.goes_left(row.value(split.attribute))]
        node.split = split
        node.surrogates = self.find_surrogates(rows, split)
        node.default = LEFT if len(left_rows) >= len(right_rows) else RIGHT
        node.left = self.grow_node(left_rows, 2 * number, depth + 1)
        node.right = self.grow_node(right_rows, 2 * number + 1, depth + 1)
        return node
