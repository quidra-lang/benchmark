"""Fitch sets, ancestral reconstruction, branch insertion, and NNI."""

from alignment import BASES


def merge(first, second):
    common = first & second
    return (common, 0) if common else (first | second, 1)


def provisional(rooted, pattern):
    sets = {}
    changes = 0
    for node in reversed(rooted.order):
        if node < rooted.tree.size:
            sets[node] = pattern[node]
        else:
            children = [child for child in rooted.children[node] if child != rooted.outgroup]
            sets[node], added = merge(sets[children[0]], sets[children[1]])
            changes += added
            if node == rooted.root:
                combined, added = merge(sets[node], sets[rooted.outgroup])
                changes += added
    return sets, changes


def pattern_scores(tree, patterns, outgroup):
    rooted = tree.rooted(outgroup)
    return [provisional(rooted, pattern)[1] for pattern in patterns.encoded]


def score(tree, patterns, outgroup):
    changes = pattern_scores(tree, patterns, outgroup)
    return sum(change * weight for change, weight in zip(changes, patterns.weights))


def reconstruct(tree, patterns, outgroup):
    rooted = tree.rooted(outgroup)
    ancestors = {node: [] for node in tree.internal_nodes()}
    branch_changes = {(first, second): 0 for first, second, length in tree.edges()}
    scores = []
    for pattern, weight in zip(patterns.encoded, patterns.weights):
        sets, changes = provisional(rooted, pattern)
        scores.append(changes)
        combined, added = merge(sets[rooted.root], sets[outgroup])
        first_base = combined & -combined
        states = {}
        for node in (rooted.root, outgroup):
            states[node] = first_base if sets[node] & first_base else sets[node] & -sets[node]
        for node in rooted.order[1:]:
            if node == outgroup:
                continue
            parent_state = states[rooted.parents[node]]
            states[node] = parent_state if sets[node] & parent_state else sets[node] & -sets[node]
        for node in ancestors:
            ancestors[node].append(BASES[states[node].bit_length() - 1])
        for first, second in branch_changes:
            if states[first] != states[second]:
                branch_changes[first, second] += weight
    sequences = {node: "".join(states[index] for index in patterns.columns)
                 for node, states in ancestors.items()}
    site_changes = [scores[index] for index in patterns.columns]
    return sequences, branch_changes, site_changes


def branches(tree, outgroup):
    rooted = tree.rooted(outgroup)
    edges = []
    for child in rooted.order[1:]:
        mask = rooted.ingroup if child == outgroup else rooted.masks[child]
        edges.append((mask, rooted.parents[child], child))
    return sorted(edges)


def insert(tree, first, second, taxon):
    result = tree.copy()
    result.disconnect(first, second)
    node = result.internal()
    result.adjacent[taxon] = {}
    result.connect(first, node)
    result.connect(second, node)
    result.connect(taxon, node)
    return result


def nni_candidates(tree, outgroup):
    rooted = tree.rooted(outgroup)
    for mask, first, second in branches(tree, outgroup):
        if first < tree.size or second < tree.size:
            continue
        sibling = next(child for child in rooted.children[first]
                       if child != second and child != outgroup)
        children = sorted(rooted.children[second], key=rooted.masks.__getitem__)
        for swap, child in enumerate(children, 1):
            result = tree.copy()
            sibling_length = result.disconnect(first, sibling)
            child_length = result.disconnect(second, child)
            result.connect(first, child, child_length)
            result.connect(second, sibling, sibling_length)
            yield mask, swap, result
