from evaluation import PrunedTree


class Decision:
    def __init__(self, node, rows, leaf_error, subtree_error, pruned):
        self.node = node
        self.rows = rows
        self.leaf_error = leaf_error
        self.subtree_error = subtree_error
        self.pruned = pruned


class SequenceTree:
    def __init__(self, alpha, tree):
        self.alpha = alpha
        self.tree = tree


def reached_rows(tree, rows):
    reached = {}
    for row in rows:
        path, methods = tree.route(row)
        for node in path:
            reached.setdefault(node.number, []).append(row)
    return reached


def decide(node, reached, decisions, cut):
    rows = reached.get(node.number, [])
    leaf_error = sum(row.label != node.prediction for row in rows)
    if node.split is None:
        return leaf_error
    subtree_error = decide(node.left, reached, decisions, cut)
    subtree_error += decide(node.right, reached, decisions, cut)
    pruned = leaf_error <= subtree_error
    decisions.append(Decision(node, len(rows), leaf_error, subtree_error, pruned))
    if pruned:
        cut.add(node.number)
        return leaf_error
    return subtree_error


def reduced_error_pruning(root, rows):
    reached = reached_rows(PrunedTree(root), rows)
    decisions = []
    cut = set()
    decide(root, reached, decisions, cut)
    return PrunedTree(root, cut), decisions


def cost_complexity_sequence(root):
    tree = PrunedTree(root)
    sequence = [SequenceTree((0, 1), tree)]
    while not tree.is_leaf(root):
        alpha = None
        weakest = set()
        for node in tree.internal_nodes():
            leaves = tree.leaves(node)
            strength = (node.errors - sum(leaf.errors for leaf in leaves), len(leaves) - 1)
            if alpha is None or strength[0] * alpha[1] < alpha[0] * strength[1]:
                alpha = strength
                weakest = {node.number}
            elif strength[0] * alpha[1] == alpha[0] * strength[1]:
                weakest.add(node.number)
        tree = PrunedTree(root, tree.cut | weakest)
        sequence.append(SequenceTree(alpha, tree))
    return sequence
