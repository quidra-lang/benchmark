"""FASTA records, DNA base sets, site patterns, and column classes."""

from collections import Counter
from pathlib import Path


BASES = "ACGT"
AMBIGUOUS = "RYSWKMBDHV"
BASE_SETS = {
    "A": 1, "C": 2, "G": 4, "T": 8,
    "R": 5, "Y": 10, "S": 6, "W": 9, "K": 12, "M": 3,
    "B": 14, "D": 13, "H": 11, "V": 7, "N": 15, "-": 15,
}


def read_fasta(path="input/alignment.fasta"):
    records = []
    name = None
    pieces = []
    header_line = 0
    with Path(path).open(encoding="ascii") as source:
        for line_number, line in enumerate(source, 1):
            line = line.rstrip("\n")
            if line.startswith(">"):
                if name is not None:
                    records.append((header_line, name, "".join(pieces).upper()))
                name = line[1:].split(" ", 1)[0]
                header_line = line_number
                pieces = []
            else:
                pieces.append(line)
    records.append((header_line, name, "".join(pieces).upper()))
    return records


class Patterns:
    def __init__(self, sequences):
        self.patterns = []
        self.columns = []
        self.weights = []
        numbers = {}
        for characters in zip(*sequences):
            pattern = "".join(characters)
            if pattern not in numbers:
                numbers[pattern] = len(self.patterns)
                self.patterns.append(pattern)
                self.weights.append(0)
            index = numbers[pattern]
            self.columns.append(index)
            self.weights[index] += 1
        self.encoded = [tuple(BASE_SETS[character] for character in pattern)
                        for pattern in self.patterns]


def classify_columns(sequences):
    totals = dict.fromkeys(("constant", "variable", "informative", "gapped", "empty"), 0)
    for characters in zip(*sequences):
        counts = Counter(character for character in characters if character in BASES)
        kind = "empty" if not counts else "constant" if len(counts) == 1 else "variable"
        totals[kind] += 1
        totals["informative"] += sum(count >= 2 for count in counts.values()) >= 2
        totals["gapped"] += "-" in characters
    return totals
