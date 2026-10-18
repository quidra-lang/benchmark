class FPNode:
    def __init__(self, item, parent):
        self.item = item
        self.parent = parent
        self.count = 0
        self.children = {}


class FPTree:
    def __init__(self, pattern_base, minimum):
        supports = {}
        for items, weight in pattern_base:
            for item in items:
                supports[item] = supports.get(item, 0) + weight
        frequent = [item for item in supports if supports[item] >= minimum]
        self.header = sorted(frequent, key=lambda item: (-supports[item], item))
        order = {item: index for index, item in enumerate(self.header)}
        self.root = FPNode(None, None)
        self.links = {item: [] for item in self.header}
        self.node_count = 0
        for items, weight in pattern_base:
            path = sorted((item for item in items if item in order), key=order.get)
            self.insert(path, weight)

    def insert(self, path, weight):
        node = self.root
        for item in path:
            child = node.children.get(item)
            if child is None:
                child = FPNode(item, node)
                node.children[item] = child
                self.links[item].append(child)
                self.node_count += 1
            child.count += weight
            node = child

    def support(self, item):
        return sum(node.count for node in self.links[item])

    def conditional_base(self, item):
        base = []
        for node in self.links[item]:
            path = []
            ancestor = node.parent
            while ancestor is not self.root:
                path.append(ancestor.item)
                ancestor = ancestor.parent
            path.reverse()
            base.append((path, node.count))
        return base


class GrowthResult:
    def __init__(self, tree):
        self.header_count = len(tree.header)
        self.node_count = tree.node_count
        self.conditional_trees = 0
        self.conditional_nodes = 0
        self.itemsets = []


def fp_growth(pattern_base, minimum, max_size):
    tree = FPTree(pattern_base, minimum)
    result = GrowthResult(tree)
    stack = [(tree, ())]
    while stack:
        current, suffix = stack.pop()
        for item in reversed(current.header):
            itemset = tuple(sorted(suffix + (item,)))
            result.itemsets.append((itemset, current.support(item)))
            if len(itemset) < max_size:
                conditional = FPTree(current.conditional_base(item), minimum)
                if conditional.node_count >= 1:
                    stack.append((conditional, itemset))
                    result.conditional_trees += 1
                    result.conditional_nodes += conditional.node_count
    return result
