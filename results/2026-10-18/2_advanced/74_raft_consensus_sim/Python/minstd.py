"""The sole random generator and its inclusive timeout conversion."""


class Minstd:
    def __init__(self, seed):
        self.state = seed
        self.draws = 0

    def draw(self):
        self.state = (48271 * self.state) % 2147483647
        self.draws += 1
        return self.state

    def between(self, minimum, maximum):
        return minimum + self.draw() % (maximum - minimum + 1)
