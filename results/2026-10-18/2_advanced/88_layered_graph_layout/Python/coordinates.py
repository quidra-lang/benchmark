"""Integer Brandes–Kopf conflicts, alignments, compaction, and balancing."""

from collections import namedtuple

import crossing


VARIANTS = ("ul", "ur", "dl", "dr")
Result = namedtuple("Result", "x left right aligned blocks widths smallest conflicts")


def mark_conflicts(orders, upper, node_count, position):
    marked = set()
    for layer in range(len(orders) - 1):
        above, below = orders[layer:layer + 2]
        first_bound = 0
        start = 0
        for last, vertex in enumerate(below):
            inner = vertex >= node_count and upper[vertex][0] >= node_count
            if not inner and last != len(below) - 1:
                continue
            last_bound = position[upper[vertex][0]] if inner else len(above) - 1
            for following in below[start:last + 1]:
                for previous in upper[following]:
                    if position[previous] < first_bound or position[previous] > last_bound:
                        marked.add((previous, following))
            start = last + 1
            first_bound = last_bound
    return marked


def alignment(variant, orders, upper, lower, marked, count):
    scan = [list(layer) if variant[1] == "l" else list(reversed(layer)) for layer in orders]
    rank = crossing.positions(scan)
    root = list(range(count))
    align = list(range(count))
    layers = range(len(orders)) if variant[0] == "u" else range(len(orders) - 1, -1, -1)
    reference = upper if variant[0] == "u" else lower
    for layer in list(layers)[1:]:
        boundary = -1
        for vertex in scan[layer]:
            neighbors = sorted(reference[vertex], key=rank.get)
            if not neighbors:
                continue
            for middle in ((len(neighbors) - 1) // 2, len(neighbors) // 2):
                neighbor = neighbors[middle]
                segment = (neighbor, vertex) if variant[0] == "u" else (vertex, neighbor)
                if align[vertex] == vertex and segment not in marked and boundary < rank[neighbor]:
                    align[neighbor] = vertex
                    root[vertex] = root[neighbor]
                    align[vertex] = root[vertex]
                    boundary = rank[neighbor]
    return root, scan


def compact(root, scan, variant, left, right, node_count, settings):
    blocks = sorted(set(root))
    outgoing = {block: {} for block in blocks}
    incoming = {block: {} for block in blocks}
    for layer in scan:
        for first, second in zip(layer, layer[1:]):
            a, b = (first, second) if variant[1] == "l" else (second, first)
            gap = settings["node_sep"] if a < node_count and b < node_count else settings["dummy_sep"]
            distance = right[a] + left[b] + 1 + gap
            origin, target = root[first], root[second]
            distance = max(distance, outgoing[origin].get(target, distance))
            outgoing[origin][target] = distance
            incoming[target][origin] = distance
    pending = {block: len(incoming[block]) for block in blocks}
    ready = [block for block in blocks if pending[block] == 0]
    ordered = []
    first_coordinate = {}
    while ready:
        block = ready.pop()
        ordered.append(block)
        first_coordinate[block] = max((first_coordinate[previous] + distance
                                       for previous, distance in incoming[block].items()), default=0)
        for following in outgoing[block]:
            pending[following] -= 1
            if pending[following] == 0:
                ready.append(following)
    second_coordinate = {}
    for block in reversed(ordered):
        coordinate = first_coordinate[block]
        if outgoing[block]:
            coordinate = max(coordinate, min(second_coordinate[following] - distance
                                              for following, distance in outgoing[block].items()))
        second_coordinate[block] = coordinate
    sign = 1 if variant[1] == "l" else -1
    return [sign * second_coordinate[block] for block in root], len(blocks)


def assign(orders, upper, lower, widths, node_count, settings):
    count = len(widths)
    if settings["direction"] in ("TB", "BT"):
        left = [(width - 1) // 2 for width in widths]
        right = [width - 1 - extent for width, extent in zip(widths, left)]
    else:
        left = [0] * count
        right = [0] * count
    position = crossing.positions(orders)
    conflicts = mark_conflicts(orders, upper, node_count, position)
    layouts, blocks, bounds, spans = {}, {}, {}, {}
    for variant in VARIANTS:
        root, scan = alignment(variant, orders, upper, lower, conflicts, count)
        layout, block_count = compact(root, scan, variant, left, right, node_count, settings)
        low = min(value - extent for value, extent in zip(layout, left))
        high = max(value + extent for value, extent in zip(layout, right))
        layouts[variant] = layout
        blocks[variant] = block_count
        bounds[variant] = low, high
        spans[variant] = high - low + 1
    smallest = min(VARIANTS, key=spans.get)
    aligned = {}
    for variant in VARIANTS:
        side = 0 if variant[1] == "l" else 1
        shift = bounds[smallest][side] - bounds[variant][side]
        aligned[variant] = [value + shift for value in layouts[variant]]
    x = []
    for vertex in range(count):
        values = sorted(aligned[variant][vertex] for variant in VARIANTS)
        x.append((values[1] + values[2]) // 2)
    low = min(value - extent for value, extent in zip(x, left))
    x = [value - low for value in x]
    return Result(x, left, right, aligned, blocks, spans, smallest, conflicts)
