from dynamic_programming import first_max


def choose(generator, q_row, epsilon):
    if generator.draw() % 1000 < epsilon:
        return generator.draw() % 4
    return first_max(q_row)


def td_target(reward, terminal, next_value, gamma):
    if terminal:
        return 10000 * reward
    return 10000 * reward + gamma * next_value // 100


def expected_value(q_row, epsilon):
    return (epsilon * sum(q_row) + 4 * (1000 - epsilon) * max(q_row)) // 4000


def td_update(q_row, action, target, alpha):
    q_row[action] += alpha * (target - q_row[action]) // 100


class DynaModel:
    def __init__(self, state_count):
        self.outcomes = [[None] * 4 for _ in range(state_count)]
        self.pairs = []

    def record(self, state, action, reward, next_state):
        if self.outcomes[state][action] is None:
            self.pairs.append((state, action))
        self.outcomes[state][action] = (reward, next_state)

    def plan(self, generator, q_values, gamma, alpha, count):
        for _ in range(count):
            state, action = self.pairs[generator.draw() % len(self.pairs)]
            reward, next_state = self.outcomes[state][action]
            terminal = next_state is None
            next_value = 0 if terminal else max(q_values[next_state])
            target = td_target(reward, terminal, next_value, gamma)
            td_update(q_values[state], action, target, alpha)
