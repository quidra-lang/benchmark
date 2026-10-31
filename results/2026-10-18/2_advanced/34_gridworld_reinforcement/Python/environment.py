WALL = "#"
FLOOR = "."
ICE = "~"
GOAL = "G"
PIT = "P"
START = "S"
ACTION_LETTERS = "NESW"
ROW_STEPS = (-1, 0, 1, 0)
COLUMN_STEPS = (0, 1, 0, -1)
MULTIPLIER = 48271
MODULUS = 2147483647


class World:
    def __init__(self, rows, cols, kinds, wind, rewards):
        self.rows = rows
        self.cols = cols
        self.kinds = kinds
        self.wind = wind
        self.terminal_rewards = rewards
        self.states = []
        self.terminals = []
        self.state_index = [None] * len(kinds)
        self.terminal_index = [None] * len(kinds)
        for cell, kind in enumerate(kinds):
            if kind in (GOAL, PIT):
                self.terminal_index[cell] = len(self.terminals)
                self.terminals.append(cell)
            elif kind != WALL:
                self.state_index[cell] = len(self.states)
                self.states.append(cell)
        self.start = kinds.index(START)
        self.start_state = self.state_index[self.start]

    def is_terminal(self, cell):
        return self.terminal_index[cell] is not None

    def terminal_name(self, cell):
        return "goal" if self.kinds[cell] == GOAL else "pit"

    def move(self, cell, direction):
        target = cell + ROW_STEPS[direction] * self.cols + COLUMN_STEPS[direction]
        if self.kinds[target] == WALL:
            target = cell
        if self.is_terminal(target):
            return target
        for _ in range(self.wind[cell % self.cols]):
            above = target - self.cols
            if self.kinds[above] == WALL:
                break
            target = above
            if self.is_terminal(target):
                break
        return target


def read_world(path):
    with open(path) as file:
        lines = file.read().splitlines()
    rows = int(lines[0].split()[1])
    cols = int(lines[1].split()[1])
    kinds = "".join(lines[2:2 + rows])
    wind = [int(digit) for digit in lines[2 + rows].split()[1]]
    rewards = [int(value) for value in lines[3 + rows].split()[1:]]
    return World(rows, cols, kinds, wind, rewards)


class RandomGenerator:
    def __init__(self, seed):
        self.value = seed

    def draw(self):
        self.value = MULTIPLIER * self.value % MODULUS
        return self.value


class Environment:
    def __init__(self, world, step_reward, slip_total, floor_slip, ice_slip):
        self.world = world
        self.step_reward = step_reward
        self.slip_total = slip_total
        self.floor_slip = floor_slip
        self.ice_slip = ice_slip
        self.moves = [
            [world.move(cell, direction) for direction in range(4)] for cell in world.states
        ]
        self.transitions = [
            [self.build_transitions(state, action) for action in range(4)]
            for state in range(len(world.states))
        ]

    def slip(self, state):
        if self.world.kinds[self.world.states[state]] == ICE:
            return self.ice_slip
        return self.floor_slip

    def slip_outcomes(self, state, action):
        slip = self.slip(state)
        return (
            (action, self.slip_total - 2 * slip),
            ((action + 1) % 4, slip),
            ((action + 3) % 4, slip),
        )

    def build_transitions(self, state, action):
        return [
            (self.moves[state][direction], numerator)
            for direction, numerator in self.slip_outcomes(state, action)
            if numerator > 0
        ]

    def reward(self, cell):
        index = self.world.terminal_index[cell]
        if index is None:
            return self.step_reward
        return self.world.terminal_rewards[index]

    def step(self, generator, state, action):
        draw = generator.draw() % self.slip_total
        slip = self.slip(state)
        if draw < self.slip_total - 2 * slip:
            direction = action
        elif draw < self.slip_total - slip:
            direction = (action + 1) % 4
        else:
            direction = (action + 3) % 4
        cell = self.moves[state][direction]
        return cell, self.reward(cell)
