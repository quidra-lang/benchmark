MODULUS = 2147483647
MULTIPLIER = 48271


class Minstd:
    def __init__(self, seed):
        self.state = seed

    def draw(self):
        self.state = MULTIPLIER * self.state % MODULUS
        return self.state


def select(weights, value):
    remainder = value % sum(weights)
    total = 0
    for index, weight in enumerate(weights):
        total += weight
        if remainder < total:
            return index
