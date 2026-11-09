def discounted_return(rewards, gamma):
    value = 0
    for reward in reversed(rewards):
        value = 10000 * reward + gamma * value // 100
    return value


class ReturnAverages:
    def __init__(self, state_count):
        self.sums = [[0] * 4 for _ in range(state_count)]
        self.counts = [[0] * 4 for _ in range(state_count)]

    def update(self, q_values, history, gamma):
        seen = set()
        first_visits = []
        for state, action, _ in history:
            first_visits.append((state, action) not in seen)
            seen.add((state, action))
        value = 0
        for index in range(len(history) - 1, -1, -1):
            state, action, reward = history[index]
            value = 10000 * reward + gamma * value // 100
            if first_visits[index]:
                self.sums[state][action] += value
                self.counts[state][action] += 1
                q_values[state][action] = self.sums[state][action] // self.counts[state][action]
