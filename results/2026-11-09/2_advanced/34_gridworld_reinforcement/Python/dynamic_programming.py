def first_max(values):
    return values.index(max(values))


def bellman(environment, values, gamma, state, action):
    world = environment.world
    total = 0
    for cell, numerator in environment.transitions[state][action]:
        target = world.state_index[cell]
        future = 0 if target is None else gamma * values[target] // 100
        total += numerator * (10000 * environment.reward(cell) + future)
    return total // environment.slip_total


def action_values(environment, values, gamma, state):
    return [bellman(environment, values, gamma, state, action) for action in range(4)]


def greedy_policy(environment, values, gamma):
    return [
        first_max(action_values(environment, values, gamma, state))
        for state in range(len(values))
    ]


def value_iteration(environment, gamma, theta):
    values = [0] * len(environment.world.states)
    changes = []
    while True:
        updated = [
            max(action_values(environment, values, gamma, state))
            for state in range(len(values))
        ]
        change = max(abs(new - old) for new, old in zip(updated, values))
        changes.append(change)
        values = updated
        if change <= theta:
            return values, changes


def in_place_value_iteration(environment, gamma, theta):
    values = [0] * len(environment.world.states)
    sweeps = 0
    while True:
        sweeps += 1
        delta = 0
        for state in range(len(values)):
            value = max(action_values(environment, values, gamma, state))
            delta = max(delta, abs(value - values[state]))
            values[state] = value
        if delta <= theta:
            return values, sweeps


def evaluate_policy(environment, policy, initial, gamma, theta):
    values = list(initial)
    sweeps = 0
    while True:
        sweeps += 1
        delta = 0
        for state, action in enumerate(policy):
            value = bellman(environment, values, gamma, state, action)
            delta = max(delta, abs(value - values[state]))
            values[state] = value
        if delta <= theta:
            return values, sweeps


def policy_iteration(environment, gamma, theta):
    start = environment.world.start_state
    policy = [0] * len(environment.world.states)
    values = [0] * len(policy)
    rounds = []
    while True:
        values, sweeps = evaluate_policy(environment, policy, values, gamma, theta)
        improved = greedy_policy(environment, values, gamma)
        changes = sum(new != old for new, old in zip(improved, policy))
        rounds.append((sweeps, changes, values[start]))
        policy = improved
        if changes == 0:
            return policy, values, rounds
