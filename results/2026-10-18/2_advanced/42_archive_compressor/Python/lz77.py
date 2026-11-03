"""Greedy, nearest-distance LZ77 tokens and overlapping match copies."""

from collections import defaultdict, deque

from bitio import DecodeError


def tokenize(data, offset_bits, length_bits):
    window = 1 << offset_bits
    lookahead = (1 << length_bits) + 2
    prefixes = defaultdict(deque)
    tokens = []
    position = 0
    while position < len(data):
        distance = 0
        longest = 0
        limit = min(lookahead, len(data) - position)
        if limit >= 3:
            candidates = prefixes[data[position:position + 3]]
            while candidates and candidates[0] < position - window:
                candidates.popleft()
            # Shorter matches cannot become tokens. Reversed positions give
            # increasing distances, so keeping the first tie is exact.
            for start in reversed(candidates):
                candidate_distance = position - start
                length = 3
                while (length < limit and
                       data[position + length] ==
                       data[position + length - candidate_distance]):
                    length += 1
                if length > longest:
                    distance = candidate_distance
                    longest = length
                if longest == limit:
                    break
        if longest >= 3:
            tokens.append((distance, longest))
            consumed = longest
        else:
            tokens.append(data[position])
            consumed = 1
        # Index every consumed position, including positions within a match.
        for start in range(position, min(position + consumed, len(data) - 2)):
            prefixes[data[start:start + 3]].append(start)
        position += consumed
    return tokens


def copy_match(output, distance, length, original_size):
    if distance > len(output):
        raise DecodeError("bad_offset", len(output))
    if len(output) + length > original_size:
        raise DecodeError("overrun", len(output))
    for _ in range(length):
        output.append(output[-distance])
