MULTIPLIER = 48271
MODULUS = 2147483647


class Minstd:
    def __init__(self, seed):
        self.state = seed

    def draw(self):
        self.state = MULTIPLIER * self.state % MODULUS
        return self.state

    def below(self, limit):
        return self.draw() % limit

    def chance(self, numerator, denominator):
        return self.draw() % denominator < numerator

    def shuffle(self, items):
        for size in range(len(items), 1, -1):
            index = self.below(size)
            items[size - 1], items[index] = items[index], items[size - 1]
