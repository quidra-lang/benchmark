MULTIPLIER = 48271
MODULUS = 2147483647


class Minstd:
    def __init__(self, seed):
        self.state = seed

    def draw(self):
        self.state = MULTIPLIER * self.state % MODULUS
        return self.state

    def draw_below(self, limit):
        return self.draw() % limit

    def shuffle(self, items):
        for i in range(len(items) - 1, 0, -1):
            j = self.draw() % (i + 1)
            items[i], items[j] = items[j], items[i]
