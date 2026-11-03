"""MINSTD drawing, synthetic sequences, and backward posterior sampling."""


class MINSTD:
    def __init__(self, seed):
        self.state = seed

    def random(self):
        self.state = (48271 * self.state) % 2147483647
        return self.state / 2147483647


def draw(weights, generator):
    total = 0.0
    for weight in weights:
        total += weight
    threshold = generator.random() * total
    cumulative = 0.0
    for index, weight in enumerate(weights):
        cumulative += weight
        if threshold < cumulative:
            return index
    return len(weights) - 1


def synthetic_sequence(model, length, generator):
    states = []
    observations = []
    for position in range(length):
        weights = model.initial if position == 0 else model.transition[states[-1]]
        state = draw(weights, generator)
        symbol = draw(model.emission[state], generator)
        states.append(state)
        observations.append(symbol)
    return states, observations


def posterior_path(model, forward, generator):
    path = [0] * len(forward)
    path[-1] = draw(forward[-1], generator)
    for position in range(len(forward) - 2, -1, -1):
        following = path[position + 1]
        weights = [
            forward[position][state] * model.transition[state][following]
            for state in range(len(model.states))
        ]
        path[position] = draw(weights, generator)
    return path
