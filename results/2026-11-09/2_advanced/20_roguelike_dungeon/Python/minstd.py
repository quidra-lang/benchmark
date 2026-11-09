MULTIPLIER = 48271
MODULUS = 2147483647


class Minstd:
    def __init__(self, seed):
        self.state = seed

    def draw(self):
        self.state = self.state * MULTIPLIER % MODULUS
        return self.state

    def rnd(self, n):
        return self.draw() % n

    def roll(self, count, sides):
        total = 0
        for _ in range(count):
            total += 1 + self.rnd(sides)
        return total

    def select(self, weights):
        q = self.draw() % sum(weights)
        total = 0
        for index, weight in enumerate(weights):
            total += weight
            if q < total:
                return index
        return len(weights) - 1
