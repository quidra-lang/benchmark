"""The single continuous MINSTD stream and one likelihood-weighted sample."""

from learning import parent_row


class Minstd:
    def __init__(self, seed):
        self.state = seed

    def uniform(self):
        self.state = 48271 * self.state % 2147483647
        return self.state / 2147483647


def choose(probabilities, random):
    uniform, cumulative = random.uniform(), 0.0
    for state, probability in enumerate(probabilities):
        cumulative += probability
        if uniform < cumulative:
            return state
    return len(probabilities) - 1


def weighted_sample(topological_order, parents, cpts, sizes, evidence, random):
    sample, weight = [0] * len(sizes), 1.0
    for variable in topological_order:
        row = cpts[variable][parent_row(parents[variable], sample, sizes)]
        if variable in evidence:
            sample[variable] = evidence[variable]
            weight *= row[evidence[variable]]
        else:
            sample[variable] = choose(row, random)
    return sample, weight
