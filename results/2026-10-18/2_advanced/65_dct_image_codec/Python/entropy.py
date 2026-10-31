"""Signed amplitudes, canonical codes, and the specified Huffman optimization."""


TABLE_KEYS = ((0, 0), (1, 0), (0, 1), (1, 1))
TABLE_NAMES = ("dc_luma", "ac_luma", "dc_chroma", "ac_chroma")


def category(value):
    return abs(value).bit_length()


def extra_bits(value):
    size = category(value)
    return (value if value >= 0 else value + (1 << size) - 1), size


def amplitude(bits, size):
    if size == 0:
        return 0
    return bits if bits >= 1 << (size - 1) else bits - (1 << size) + 1


class HuffmanTable:
    def __init__(self, counts, symbols):
        self.counts = list(counts)
        self.symbols = list(symbols)
        self.codes = {}
        self.decode = {}
        code = offset = 0
        for length, count in enumerate(self.counts, 1):
            for symbol in self.symbols[offset:offset + count]:
                self.codes[symbol] = (length, code)
                self.decode[length, code] = symbol
                code += 1
            offset += count
            code *= 2


def optimized_table(frequencies):
    frequencies = list(frequencies) + [1]
    sizes = [0] * 257
    others = [-1] * 257
    while True:
        available = [symbol for symbol in range(257) if frequencies[symbol] > 0]
        if len(available) < 2:
            break
        available.sort(key=lambda symbol: (frequencies[symbol], -symbol))
        first, second = available[:2]
        frequencies[first] += frequencies[second]
        frequencies[second] = 0
        sizes[first] += 1
        while others[first] != -1:
            first = others[first]
            sizes[first] += 1
        others[first] = second
        sizes[second] += 1
        while others[second] != -1:
            second = others[second]
            sizes[second] += 1
    counts = [0] * 257
    for size in sizes:
        if size > 0:
            counts[size] += 1
    for length in range(max(sizes), 16, -1):
        while counts[length] > 0:
            shorter = length - 2
            while counts[shorter] == 0:
                shorter -= 1
            counts[length] -= 2
            counts[length - 1] += 1
            counts[shorter + 1] += 2
            counts[shorter] -= 1
    longest = max(length for length in range(1, 17) if counts[length] > 0)
    counts[longest] -= 1
    symbols = sorted((symbol for symbol in range(256) if sizes[symbol] > 0),
                     key=lambda symbol: (sizes[symbol], symbol))
    return HuffmanTable(counts[1:17], symbols)
