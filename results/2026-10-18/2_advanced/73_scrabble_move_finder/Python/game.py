"""Continuous MINSTD shuffling and draw-before-return exchanges."""


TILE_ORDER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ?"


class Minstd:
    def __init__(self, seed):
        self.state = seed

    def next(self):
        self.state = self.state * 48271 % 2147483647
        return self.state


def shuffle(bag, random):
    for position in range(len(bag) - 1, 0, -1):
        other = random.next() % (position + 1)
        bag[position], bag[other] = bag[other], bag[position]


def make_bag(counts, random):
    bag = [letter for letter in TILE_ORDER for _ in range(counts[letter])]
    shuffle(bag, random)
    return bag


def draw(bag, count):
    return "".join(bag.pop() for _ in range(min(count, len(bag))))


def exchange(bag, returned, random):
    drawn = draw(bag, len(returned))
    bag.extend(sorted(returned))
    shuffle(bag, random)
    return drawn


def points(collection, values):
    return sum(values[letter] for letter in collection)
