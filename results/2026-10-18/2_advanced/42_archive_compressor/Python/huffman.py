"""Deterministic Huffman trees, frequency halving and canonical codes."""

from heapq import heapify, heappop, heappush


def tree_lengths(frequencies):
    lengths = [0] * len(frequencies)
    nodes = [(weight, symbol, symbol)
             for symbol, weight in enumerate(frequencies) if weight]
    if not nodes:
        return lengths
    if len(nodes) == 1:
        lengths[nodes[0][1]] = 1
        return lengths
    heapify(nodes)
    while len(nodes) > 1:
        first_weight, first_minimum, first = heappop(nodes)
        second_weight, second_minimum, second = heappop(nodes)
        heappush(nodes, (first_weight + second_weight,
                         min(first_minimum, second_minimum), (first, second)))
    pending = [(nodes[0][2], 0)]
    while pending:
        node, depth = pending.pop()
        if isinstance(node, int):
            lengths[node] = depth
        else:
            left, right = node
            pending.append((left, depth + 1))
            pending.append((right, depth + 1))
    return lengths


def limited_lengths(frequencies, maximum):
    weights = list(frequencies)
    halvings = 0
    while True:
        lengths = tree_lengths(weights)
        if max(lengths, default=0) <= maximum:
            return lengths, halvings
        weights = [(weight + 1) // 2 for weight in weights]
        halvings += 1


def canonical_codes(lengths):
    ordered = sorted((length, symbol)
                     for symbol, length in enumerate(lengths) if length)
    codes = [0] * len(lengths)
    code = 0
    previous_length = 0
    for index, (length, symbol) in enumerate(ordered):
        if index:
            code = (code + 1) << (length - previous_length)
        codes[symbol] = code
        previous_length = length
    return codes
