"""BWT, checkpoint occurrences, sampled locating and backward search."""

from collections import Counter

from suffix_array import SYMBOLS, SYMBOL_NUMBER


class FMIndex:
    def __init__(self, text, suffixes, occurrence_interval, sample_interval=None):
        self.size = len(text)
        self.bwt = "".join(text[position - 1] for position in suffixes)
        self.interval = occurrence_interval
        frequencies = Counter(text)
        self.C = {}
        offset = 0
        for symbol in SYMBOLS:
            self.C[symbol] = offset
            offset += frequencies[symbol]
        counts = [0] * len(SYMBOLS)
        self.checkpoints = [counts[:]]
        for position, symbol in enumerate(self.bwt, 1):
            counts[SYMBOL_NUMBER[symbol]] += 1
            if position % occurrence_interval == 0:
                self.checkpoints.append(counts[:])
        self.samples = None if sample_interval is None else {
            row: position for row, position in enumerate(suffixes) if position % sample_interval == 0
        }

    def occurrence(self, symbol, position):
        checkpoint = position // self.interval
        start = checkpoint * self.interval
        return self.checkpoints[checkpoint][SYMBOL_NUMBER[symbol]] + self.bwt.count(symbol, start, position)

    def lf(self, row):
        symbol = self.bwt[row]
        return self.C[symbol] + self.occurrence(symbol, row)

    def extend(self, lower, upper, base):
        if base == "N":
            return 0, 0
        return self.C[base] + self.occurrence(base, lower), self.C[base] + self.occurrence(base, upper)

    def locate(self, row):
        steps = 0
        while row not in self.samples:
            row = self.lf(row)
            steps += 1
        return self.samples[row] + steps, steps

    def inverse(self):
        result = [""] * self.size
        result[-1] = "$"
        row = 0
        for position in range(self.size - 2, -1, -1):
            result[position] = self.bwt[row]
            row = self.lf(row)
        return "".join(result)

    def backward_search(self, sequence):
        lower, upper = 0, self.size
        for base in reversed(sequence):
            lower, upper = self.extend(lower, upper, base)
            if lower >= upper:
                break
        return lower, upper
