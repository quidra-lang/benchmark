"""Reverse-index lower bounds and explicitly stacked mismatch searches."""


def lower_bounds(sequence, reverse_index):
    lower, upper = 0, reverse_index.size
    mismatches = 0
    bounds = []
    for base in sequence:
        lower, upper = reverse_index.extend(lower, upper, base)
        if lower >= upper:
            mismatches += 1
            lower, upper = 0, reverse_index.size
        bounds.append(mismatches)
    return bounds


def backtrack(sequence, maximum, forward_index, reverse_index):
    bounds = lower_bounds(sequence, reverse_index)
    stack = [(len(sequence) - 1, maximum, 0, forward_index.size)]
    nodes, leaves = 0, []
    while stack:
        position, remaining, lower, upper = stack.pop()
        nodes += 1
        if remaining < (bounds[position] if position >= 0 else 0):
            continue
        if position == -1:
            leaves.append((lower, upper, maximum - remaining))
            continue
        for base in "TGCA":
            first, last = forward_index.extend(lower, upper, base)
            if first >= last:
                continue
            mismatch = base != sequence[position]
            if not mismatch or remaining >= 1:
                stack.append((position - 1, remaining - int(mismatch), first, last))
    return nodes, leaves, sum(upper - lower for lower, upper, _ in leaves)
