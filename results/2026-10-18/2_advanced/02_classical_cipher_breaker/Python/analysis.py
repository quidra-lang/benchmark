from collections import Counter
from math import gcd

from scoring import letter_value


class RepeatedTrigram:
    def __init__(self, trigram, positions):
        self.trigram = trigram
        self.positions = positions
        self.gaps = [later - earlier for earlier, later in zip(positions, positions[1:])]
        self.gcd = gcd(*self.gaps)


def letter_counts(text):
    counts = [0] * 26
    for letter in text:
        counts[letter_value(letter)] += 1
    return counts


def index_of_coincidence(text):
    total = sum(count * (count - 1) for count in letter_counts(text))
    return 100000 * total // (len(text) * (len(text) - 1))


def columns(text, period):
    return [text[column::period] for column in range(period)]


def column_indices(text, period):
    return [index_of_coincidence(column) for column in columns(text, period)]


def repeated_trigrams(text):
    positions = {}
    for start in range(len(text) - 2):
        positions.setdefault(text[start:start + 3], []).append(start + 1)
    return [
        RepeatedTrigram(trigram, found)
        for trigram, found in sorted(positions.items())
        if len(found) >= 2
    ]


def percentage(count, total):
    tenths = (2000 * count + total) // (2 * total)
    return f"{tenths // 10}.{tenths % 10}"


def top_counts(items, limit):
    counts = Counter(items)
    return sorted(counts.items(), key=lambda entry: (-entry[1], entry[0]))[:limit]
