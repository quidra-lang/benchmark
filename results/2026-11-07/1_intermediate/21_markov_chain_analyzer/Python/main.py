from collections import deque
from fractions import Fraction
from math import gcd, lcm
import sys


MAX_STATES = 10
MAX_GAMBLER_SIZE = 9
MODULUS = 2147483647
MULTIPLIER = 48271
ZERO = Fraction(0)
ONE = Fraction(1)


class CommandError(Exception):
    pass


def delta(i, j):
    return ONE if i == j else ZERO


def answer(flag):
    return "yes" if flag else "no"


def fraction_text(value):
    return f"{value.numerator}/{value.denominator}"


def value_text(value):
    whole, remainder = divmod(value.numerator, value.denominator)
    digits = remainder * 1000000 // value.denominator
    return f"{fraction_text(value)}({whole}.{digits:06d})"


def time_text(value):
    return "inf" if value is None else value_text(value)


def parse_probability(text):
    parts = text.split("/")
    numerator = int(parts[0])
    denominator = int(parts[1]) if len(parts) == 2 else 1
    if denominator == 0 or numerator > denominator:
        raise CommandError("BAD PROBABILITY")
    return Fraction(numerator, denominator)


def membership(size, states):
    inside = [False] * size
    for state in states:
        inside[state] = True
    return inside


def identity(size):
    return [[delta(i, j) for j in range(size)] for i in range(size)]


def eliminate(matrix, size):
    for column in range(size):
        pivot_row = column
        while matrix[pivot_row][column] == 0:
            pivot_row += 1
        matrix[column], matrix[pivot_row] = matrix[pivot_row], matrix[column]
        pivot = matrix[column][column]
        matrix[column] = [value / pivot for value in matrix[column]]
        for row in range(size):
            factor = matrix[row][column]
            if row != column and factor != 0:
                matrix[row] = [
                    value - factor * base
                    for value, base in zip(matrix[row], matrix[column])
                ]
    return [row[size:] for row in matrix]


class Chain:
    def __init__(self, names):
        self.names = names
        self.positions = {name: i for i, name in enumerate(names)}
        self.matrix = [[ZERO] * len(names) for _ in names]

    def size(self):
        return len(self.names)

    def state(self, text):
        if text not in self.positions:
            raise CommandError(f"UNKNOWN STATE {text}")
        return self.positions[text]

    def distinct_states(self, texts):
        states = []
        for text in texts:
            state = self.state(text)
            if state in states:
                raise CommandError(f"DUPLICATE STATE {text}")
            states.append(state)
        return states

    def labels(self, states):
        return [self.names[i] for i in states]

    def row_sum(self, i):
        return sum(self.matrix[i])

    def block_sum(self, i, block):
        return sum(self.matrix[i][j] for j in block)

    def edge(self, i, j):
        return self.matrix[i][j] > 0

    def absorbing(self, i):
        return self.matrix[i][i] == 1

    def advance(self, distribution):
        size = self.size()
        return [
            sum(distribution[i] * self.matrix[i][j] for i in range(size))
            for j in range(size)
        ]

    def reachable(self, start):
        seen = [False] * self.size()
        seen[start] = True
        stack = [start]
        while stack:
            i = stack.pop()
            for j in range(self.size()):
                if self.edge(i, j) and not seen[j]:
                    seen[j] = True
                    stack.append(j)
        return seen


class CommunicatingClass:
    def __init__(self, chain, number, members):
        size = chain.size()
        self.number = number
        self.members = members
        inside = membership(size, members)
        self.closed = not any(
            chain.edge(i, j) and not inside[j] for i in members for j in range(size)
        )
        self.levels = [-1] * size
        self.levels[members[0]] = 0
        queue = deque([members[0]])
        while queue:
            u = queue.popleft()
            for v in members:
                if chain.edge(u, v) and self.levels[v] < 0:
                    self.levels[v] = self.levels[u] + 1
                    queue.append(v)
        self.period = 0
        for u in members:
            for v in members:
                if chain.edge(u, v):
                    self.period = gcd(self.period, self.levels[u] + 1 - self.levels[v])


class Decomposition:
    def __init__(self, chain):
        size = chain.size()
        self.reach = [chain.reachable(i) for i in range(size)]
        self.classes = []
        self.class_of = [-1] * size
        for i in range(size):
            if self.class_of[i] < 0:
                members = [j for j in range(size) if self.reach[i][j] and self.reach[j][i]]
                for j in members:
                    self.class_of[j] = len(self.classes)
                self.classes.append(CommunicatingClass(chain, len(self.classes) + 1, members))

    def closed_classes(self):
        return [item for item in self.classes if item.closed]

    def class_containing(self, state):
        return self.classes[self.class_of[state]]

    def reaches(self, state, targets):
        return any(reached and target for reached, target in zip(self.reach[state], targets))


class Absorption:
    def __init__(self, chain):
        size = chain.size()
        self.transient = [i for i in range(size) if not chain.absorbing(i)]
        self.absorbing = [i for i in range(size) if chain.absorbing(i)]
        count = len(self.transient)
        matrix = []
        for row, i in enumerate(self.transient):
            left = [delta(i, j) - chain.matrix[i][j] for j in self.transient]
            right = [delta(row, column) for column in range(count)]
            matrix.append(left + right)
        self.fundamental = eliminate(matrix, count)
        self.steps = [sum(row) for row in self.fundamental]
        self.probabilities = [
            [
                sum(row[k] * chain.matrix[self.transient[k]][a] for k in range(count))
                for a in self.absorbing
            ]
            for row in self.fundamental
        ]

    def variance(self, i):
        total = sum(
            (2 * self.fundamental[i][j] - delta(i, j)) * self.steps[j]
            for j in range(len(self.transient))
        )
        return total - self.steps[i] * self.steps[i]


def stationary_distribution(chain, members):
    size = len(members)
    matrix = []
    for r in range(size - 1):
        row = [chain.matrix[members[k]][members[r]] - delta(k, r) for k in range(size)]
        matrix.append(row + [ZERO])
    matrix.append([ONE] * (size + 1))
    return [row[0] for row in eliminate(matrix, size)]


def irreducible_distribution(chain, decomposition):
    if len(decomposition.classes) > 1:
        raise CommandError("NOT IRREDUCIBLE")
    return stationary_distribution(chain, decomposition.classes[0].members)


def solve_restricted(chain, states, constants):
    matrix = []
    for row, i in enumerate(states):
        coefficients = [delta(i, j) - chain.matrix[i][j] for j in states]
        matrix.append(coefficients + [constants[row]])
    return [values[0] for values in eliminate(matrix, len(states))]


def hitting_probabilities(chain, decomposition, targets):
    size = chain.size()
    probabilities = [ONE if targets[i] else ZERO for i in range(size)]
    remaining = [
        i for i in range(size) if not targets[i] and decomposition.reaches(i, targets)
    ]
    if remaining:
        constants = [
            sum(chain.matrix[i][j] for j in range(size) if targets[j]) for i in remaining
        ]
        for i, value in zip(remaining, solve_restricted(chain, remaining, constants)):
            probabilities[i] = value
    return probabilities


def hitting_times(chain, targets, probabilities):
    size = chain.size()
    times = [ZERO if targets[i] else None for i in range(size)]
    certain = [i for i in range(size) if not targets[i] and probabilities[i] == 1]
    if certain:
        constants = [ONE] * len(certain)
        for i, value in zip(certain, solve_restricted(chain, certain, constants)):
            times[i] = value
    return times


def regular_exponent(chain):
    size = chain.size()
    edges = [[chain.edge(i, j) for j in range(size)] for i in range(size)]
    power = edges
    for exponent in range(1, (size - 1) * (size - 1) + 2):
        if all(all(row) for row in power):
            return exponent
        power = [
            [any(power[i][k] and edges[k][j] for k in range(size)) for j in range(size)]
            for i in range(size)
        ]
    return None


class MarkovAnalyzer:
    def __init__(self):
        self.chains = {}
        self.output = []
        self.handlers = {
            "CHAIN": self.create_chain,
            "P": self.set_probability,
            "ROW": self.set_row,
            "SHOW": self.show,
            "CHECK": self.check,
            "BUILD": self.build,
            "GAMBLER": self.gambler,
            "CLASSES": self.classes,
            "CLASSIFY": self.classify,
            "STEP": self.step,
            "POWER": self.power,
            "STATIONARY": self.stationary,
            "RECURRENCE": self.recurrence,
            "ABSORB": self.absorb,
            "HITTING": self.hitting,
            "PASSAGE": self.passage,
            "FIRSTPASSAGE": self.first_passage,
            "PATHPROB": self.path_probability,
            "MOSTLIKELY": self.most_likely,
            "REVERSIBLE": self.reversible,
            "REVERSE": self.reverse,
            "MIXING": self.mixing,
            "LUMP": self.lump,
            "REWARD": self.reward,
            "RESTRICT": self.restrict,
            "SIMULATE": self.simulate,
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def display(self, names, matrix, label="ROW"):
        self.emit("STATES", *names)
        for name, row in zip(names, matrix):
            self.emit(label, name, *(fraction_text(value) for value in row))

    def require_chain(self, name):
        if name not in self.chains:
            raise CommandError(f"UNKNOWN CHAIN {name}")
        return self.chains[name]

    def require_stochastic(self, name):
        chain = self.require_chain(name)
        for i in range(chain.size()):
            if chain.row_sum(i) != 1:
                raise CommandError(f"NOT STOCHASTIC {chain.names[i]}")
        return chain

    def create_chain(self, arguments):
        name, names = arguments[0], arguments[1:]
        if len(names) > MAX_STATES:
            raise CommandError("TOO MANY STATES")
        for position, state in enumerate(names):
            if state in names[:position]:
                raise CommandError(f"DUPLICATE STATE {state}")
        self.chains[name] = Chain(names)
        self.emit("CHAIN", name, f"states={len(names)}")

    def set_probability(self, arguments):
        name, source, target, text = arguments
        chain = self.require_chain(name)
        i = chain.state(source)
        j = chain.state(target)
        value = parse_probability(text)
        chain.matrix[i][j] = value
        self.emit(
            "P", name, source, target, fraction_text(value),
            f"rowsum={fraction_text(chain.row_sum(i))}",
        )

    def set_row(self, arguments):
        name, source, texts = arguments[0], arguments[1], arguments[2:]
        chain = self.require_chain(name)
        i = chain.state(source)
        if len(texts) != chain.size():
            raise CommandError("BAD LENGTH")
        chain.matrix[i] = [parse_probability(text) for text in texts]
        self.emit("ROW", name, source, f"rowsum={fraction_text(chain.row_sum(i))}")

    def show(self, arguments):
        chain = self.require_chain(arguments[0])
        self.emit("MATRIX", arguments[0], f"states={chain.size()}")
        self.display(chain.names, chain.matrix)

    def check(self, arguments):
        chain = self.require_chain(arguments[0])
        bad = [i for i in range(chain.size()) if chain.row_sum(i) != 1]
        if not bad:
            self.emit("CHECK", arguments[0], "ok")
            return
        self.emit("CHECK", arguments[0], f"bad={len(bad)}")
        for i in bad:
            self.emit("BADROW", chain.names[i], f"sum={fraction_text(chain.row_sum(i))}")

    def build(self, arguments):
        name, order, tokens = arguments[0], int(arguments[1]), arguments[2:]
        if order not in (1, 2):
            raise CommandError("BAD ORDER")
        if len(tokens) <= order:
            raise CommandError("TOO FEW TOKENS")
        if order == 1:
            observations = tokens
        else:
            observations = [f"{first}.{second}" for first, second in zip(tokens, tokens[1:])]
        names = []
        for observation in observations:
            if observation not in names:
                names.append(observation)
        if len(names) > MAX_STATES:
            raise CommandError("TOO MANY STATES")
        chain = Chain(names)
        size = chain.size()
        counts = [[0] * size for _ in range(size)]
        for source, target in zip(observations, observations[1:]):
            counts[chain.positions[source]][chain.positions[target]] += 1
        self.emit(
            "BUILD", name, f"order={order}", f"states={size}",
            f"transitions={len(observations) - 1}",
        )
        for a in range(size):
            total = sum(counts[a])
            if total == 0:
                chain.matrix[a][a] = ONE
                self.emit("FROM", names[a], "total=0", "absorbing")
                continue
            parts = []
            for b in range(size):
                if counts[a][b] > 0:
                    chain.matrix[a][b] = Fraction(counts[a][b], total)
                    parts.append(f"{names[b]}:{counts[a][b]}")
            self.emit("FROM", names[a], f"total={total}", *parts)
        self.chains[name] = chain

    def gambler(self, arguments):
        name, goal, start = arguments[0], int(arguments[1]), int(arguments[2])
        if goal == 0 or goal > MAX_GAMBLER_SIZE:
            raise CommandError("BAD SIZE")
        if start > goal:
            raise CommandError("BAD START")
        p = parse_probability(arguments[3])
        if p == 0 or p == 1:
            raise CommandError("BAD PROBABILITY")
        chain = Chain([f"s{i}" for i in range(goal + 1)])
        chain.matrix[0][0] = ONE
        chain.matrix[goal][goal] = ONE
        for i in range(1, goal):
            chain.matrix[i][i + 1] = p
            chain.matrix[i][i - 1] = 1 - p
        self.chains[name] = chain
        absorption = Absorption(chain)
        ruin = [ONE] + [row[0] for row in absorption.probabilities] + [ZERO]
        duration = [ZERO] + absorption.steps + [ZERO]
        self.emit(
            "GAMBLER", name, f"g={goal}", f"p={fraction_text(p)}", f"start=s{start}",
            f"ruin={value_text(ruin[start])}", f"duration={value_text(duration[start])}",
        )
        for i in range(goal + 1):
            self.emit(
                "CAPITAL", f"s{i}", f"ruin={value_text(ruin[i])}",
                f"win={value_text(1 - ruin[i])}", f"duration={value_text(duration[i])}",
            )

    def classes(self, arguments):
        chain = self.require_stochastic(arguments[0])
        decomposition = Decomposition(chain)
        self.emit("CLASSES", arguments[0], f"count={len(decomposition.classes)}")
        for item in decomposition.classes:
            kind = "RECURRENT" if item.closed else "TRANSIENT"
            self.emit(
                "CLASS", item.number, kind, f"period={item.period}",
                f"size={len(item.members)}", *chain.labels(item.members),
            )
            if item.period < 2:
                continue
            for remainder in range(item.period):
                states = [i for i in item.members if item.levels[i] % item.period == remainder]
                self.emit("CYCLIC", remainder, *chain.labels(states))

    def classify(self, arguments):
        chain = self.require_stochastic(arguments[0])
        size = chain.size()
        decomposition = Decomposition(chain)
        absorbing = [chain.absorbing(i) for i in range(size)]
        count = sum(absorbing)
        absorbing_chain = count > 0 and all(
            decomposition.reaches(i, absorbing) for i in range(size)
        )
        exponent = regular_exponent(chain)
        self.emit(
            "CLASSIFY", arguments[0], f"absorbing_states={count}",
            f"absorbing={answer(absorbing_chain)}",
            f"ergodic={answer(len(decomposition.classes) == 1)}",
            f"regular={answer(exponent is not None)}",
            f"exponent={'-' if exponent is None else exponent}",
        )

    def step(self, arguments):
        chain = self.require_stochastic(arguments[0])
        initial, steps = arguments[1], int(arguments[2])
        size = chain.size()
        if initial[0].isdigit():
            texts = initial.split(",")
            if len(texts) != size:
                raise CommandError("BAD LENGTH")
            distribution = [parse_probability(text) for text in texts]
            if sum(distribution) != 1:
                raise CommandError("BAD DISTRIBUTION")
        else:
            state = chain.state(initial)
            distribution = [delta(state, j) for j in range(size)]
        for _ in range(steps):
            distribution = chain.advance(distribution)
        self.emit("STEP", arguments[0], f"k={steps}")
        for name, value in zip(chain.names, distribution):
            self.emit("PROB", name, value_text(value))

    def power(self, arguments):
        chain = self.require_stochastic(arguments[0])
        steps = int(arguments[1])
        matrix = identity(chain.size())
        for _ in range(steps):
            matrix = [chain.advance(row) for row in matrix]
        self.emit("POWER", arguments[0], f"k={steps}")
        self.display(chain.names, matrix)

    def stationary(self, arguments):
        chain = self.require_stochastic(arguments[0])
        closed = Decomposition(chain).closed_classes()
        self.emit("STATIONARY", arguments[0], f"count={len(closed)}")
        for number, item in enumerate(closed, 1):
            self.emit("DIST", number, f"class={item.number}", f"size={len(item.members)}")
            distribution = stationary_distribution(chain, item.members)
            for i, value in zip(item.members, distribution):
                self.emit("PI", chain.names[i], value_text(value))

    def recurrence(self, arguments):
        chain = self.require_stochastic(arguments[0])
        state = chain.state(arguments[1])
        item = Decomposition(chain).class_containing(state)
        if not item.closed:
            raise CommandError(f"TRANSIENT STATE {arguments[1]}")
        distribution = stationary_distribution(chain, item.members)
        rho = distribution[item.members.index(state)]
        self.emit(
            "RECURRENCE", arguments[0], arguments[1], f"pi={value_text(rho)}",
            f"mean={value_text(1 / rho)}", f"period={item.period}",
        )

    def absorb(self, arguments):
        chain = self.require_stochastic(arguments[0])
        size = chain.size()
        absorbing = [chain.absorbing(i) for i in range(size)]
        if not any(absorbing):
            raise CommandError("NO ABSORBING STATE")
        decomposition = Decomposition(chain)
        for i in range(size):
            if not absorbing[i] and not decomposition.reaches(i, absorbing):
                raise CommandError(f"NOT ABSORBING {chain.names[i]}")
        absorption = Absorption(chain)
        transient_names = chain.labels(absorption.transient)
        self.emit(
            "ABSORB", arguments[0], f"transient={len(absorption.transient)}",
            f"absorbing={len(absorption.absorbing)}",
        )
        if not absorption.transient:
            return
        self.emit("TRANSIENT", *transient_names)
        self.emit("ABSORBING", *chain.labels(absorption.absorbing))
        for name, row in zip(transient_names, absorption.fundamental):
            self.emit("N", name, *(fraction_text(value) for value in row))
        for i, name in enumerate(transient_names):
            self.emit(
                "STEPS", name, f"mean={value_text(absorption.steps[i])}",
                f"var={value_text(absorption.variance(i))}",
            )
        for name, row in zip(transient_names, absorption.probabilities):
            self.emit("B", name, *(fraction_text(value) for value in row))

    def hitting(self, arguments):
        chain = self.require_stochastic(arguments[0])
        size = chain.size()
        targets = membership(size, chain.distinct_states(arguments[1:]))
        probabilities = hitting_probabilities(chain, Decomposition(chain), targets)
        times = hitting_times(chain, targets, probabilities)
        names = [chain.names[i] for i in range(size) if targets[i]]
        self.emit("HITTING", arguments[0], "targets=" + ",".join(names))
        for i in range(size):
            self.emit(
                "HIT", chain.names[i], f"prob={value_text(probabilities[i])}",
                f"time={time_text(times[i])}",
            )

    def passage(self, arguments):
        chain = self.require_stochastic(arguments[0])
        size = chain.size()
        decomposition = Decomposition(chain)
        pi = irreducible_distribution(chain, decomposition)
        times = [[ZERO] * size for _ in range(size)]
        for j in range(size):
            targets = membership(size, [j])
            probabilities = hitting_probabilities(chain, decomposition, targets)
            column = hitting_times(chain, targets, probabilities)
            for i in range(size):
                times[i][j] = 1 / pi[j] if i == j else column[i]
        kemeny = sum(pi[j] * times[0][j] for j in range(1, size))
        self.emit("PASSAGE", arguments[0], f"kemeny={value_text(kemeny)}")
        self.display(chain.names, times, "M")

    def first_passage(self, arguments):
        name, source, target, text = arguments
        chain = self.require_stochastic(name)
        x = chain.state(source)
        y = chain.state(target)
        steps = int(text)
        if steps == 0:
            raise CommandError("BAD STEPS")
        size = chain.size()
        current = [chain.matrix[i][y] for i in range(size)]
        first = [current[x]]
        for _ in range(1, steps):
            current = [
                sum(chain.matrix[i][j] * current[j] for j in range(size) if j != y)
                for i in range(size)
            ]
            first.append(current[x])
        self.emit(
            "FIRSTPASSAGE", name, source, target, f"k={steps}",
            f"total={value_text(sum(first))}",
        )
        cumulative = ZERO
        for t, value in enumerate(first, 1):
            cumulative += value
            self.emit("FP", t, value_text(value), f"cum={value_text(cumulative)}")

    def path_probability(self, arguments):
        chain = self.require_stochastic(arguments[0])
        path = [chain.state(text) for text in arguments[1:]]
        probability = ONE
        zero_at = None
        for t in range(1, len(path)):
            probability *= chain.matrix[path[t - 1]][path[t]]
            if probability == 0 and zero_at is None:
                zero_at = t
        parts = [
            "PATHPROB", arguments[0], f"steps={len(path) - 1}",
            f"prob={value_text(probability)}",
        ]
        if zero_at is not None:
            parts.append(f"zero_at={zero_at}")
        self.emit(*parts)

    def most_likely(self, arguments):
        chain = self.require_stochastic(arguments[0])
        start = chain.state(arguments[1])
        steps = int(arguments[2])
        if steps == 0:
            raise CommandError("BAD STEPS")
        size = chain.size()
        best = [[ONE] * size for _ in range(steps + 1)]
        for t in range(steps - 1, -1, -1):
            best[t] = [
                max(chain.matrix[i][j] * best[t + 1][j] for j in range(size))
                for i in range(size)
            ]
        path = [start]
        for t in range(steps):
            current = path[-1]
            path.append(next(
                j for j in range(size)
                if chain.matrix[current][j] * best[t + 1][j] == best[t][current]
            ))
        self.emit(
            "MOSTLIKELY", arguments[0], arguments[1], f"k={steps}",
            f"prob={value_text(best[0][start])}",
        )
        self.emit("PATH", *chain.labels(path))

    def reversible(self, arguments):
        chain = self.require_stochastic(arguments[0])
        pi = irreducible_distribution(chain, Decomposition(chain))
        size = chain.size()
        violations = []
        for i in range(size):
            for j in range(i + 1, size):
                forward = pi[i] * chain.matrix[i][j]
                backward = pi[j] * chain.matrix[j][i]
                if forward != backward:
                    violations.append((i, j, forward, backward))
        if not violations:
            self.emit("REVERSIBLE", arguments[0], "yes")
            return
        self.emit("REVERSIBLE", arguments[0], "no", f"violations={len(violations)}")
        for i, j, forward, backward in violations:
            self.emit(
                "VIOLATION", chain.names[i], chain.names[j],
                value_text(forward), value_text(backward),
            )

    def reverse(self, arguments):
        name, reversed_name = arguments
        chain = self.require_stochastic(name)
        pi = irreducible_distribution(chain, Decomposition(chain))
        size = chain.size()
        reversed_chain = Chain(list(chain.names))
        for i in range(size):
            for j in range(size):
                reversed_chain.matrix[i][j] = pi[j] * chain.matrix[j][i] / pi[i]
        self.chains[reversed_name] = reversed_chain
        same = reversed_chain.matrix == chain.matrix
        self.emit("REVERSE", name, reversed_name, f"reversible={answer(same)}")
        self.display(reversed_chain.names, reversed_chain.matrix)

    def mixing(self, arguments):
        chain = self.require_stochastic(arguments[0])
        steps = int(arguments[1])
        if steps == 0:
            raise CommandError("BAD STEPS")
        epsilon = parse_probability(arguments[2])
        pi = irreducible_distribution(chain, Decomposition(chain))
        size = chain.size()
        matrix = identity(size)
        mixing_time = None
        lines = []
        for t in range(1, steps + 1):
            matrix = [chain.advance(row) for row in matrix]
            distances = [
                sum(abs(row[j] - pi[j]) for j in range(size)) / 2 for row in matrix
            ]
            largest = max(distances)
            worst = distances.index(largest)
            if mixing_time is None and largest <= epsilon:
                mixing_time = t
            lines.append((t, largest, chain.names[worst]))
        self.emit(
            "MIXING", arguments[0], f"k={steps}", f"eps={fraction_text(epsilon)}",
            f"time={'none' if mixing_time is None else mixing_time}",
        )
        for t, largest, worst in lines:
            self.emit("TV", t, value_text(largest), f"from={worst}")

    def lump(self, arguments):
        name, lumped_name, partition = arguments
        chain = self.require_stochastic(name)
        size = chain.size()
        seen = [False] * size
        blocks = []
        for group in partition.split("|"):
            block = []
            for text in group.split(","):
                state = chain.state(text)
                if seen[state]:
                    raise CommandError("BAD PARTITION")
                seen[state] = True
                block.append(state)
            blocks.append(sorted(block))
        if not all(seen):
            raise CommandError("BAD PARTITION")
        blocks.sort(key=lambda block: block[0])
        for block in blocks:
            representative = block[0]
            for target in blocks:
                expected = chain.block_sum(representative, target)
                for i in block:
                    actual = chain.block_sum(i, target)
                    if actual != expected:
                        self.emit(
                            "LUMP", name, "not", "lumpable",
                            f"block={chain.names[representative]}",
                            f"target={chain.names[target[0]]}",
                            f"{chain.names[representative]}={value_text(expected)}",
                            f"{chain.names[i]}={value_text(actual)}",
                        )
                        return
        lumped = Chain([chain.names[block[0]] for block in blocks])
        lumped.matrix = [
            [chain.block_sum(block[0], target) for target in blocks] for block in blocks
        ]
        self.chains[lumped_name] = lumped
        self.emit("LUMP", name, lumped_name, f"blocks={len(blocks)}")
        self.display(lumped.names, lumped.matrix)

    def reward(self, arguments):
        chain = self.require_stochastic(arguments[0])
        size = chain.size()
        texts = arguments[2:]
        if len(texts) != size:
            raise CommandError("BAD LENGTH")
        gamma = parse_probability(arguments[1])
        if gamma == 1:
            raise CommandError("BAD DISCOUNT")
        rewards = [Fraction(int(text)) for text in texts]
        matrix = []
        for i in range(size):
            coefficients = [delta(i, j) - gamma * chain.matrix[i][j] for j in range(size)]
            matrix.append(coefficients + [rewards[i]])
        values = [row[0] for row in eliminate(matrix, size)]
        decomposition = Decomposition(chain)
        gains = [ZERO] * size
        for item in decomposition.closed_classes():
            distribution = stationary_distribution(chain, item.members)
            gain = sum(rho * rewards[i] for i, rho in zip(item.members, distribution))
            targets = membership(size, item.members)
            probabilities = hitting_probabilities(chain, decomposition, targets)
            for i in range(size):
                gains[i] += probabilities[i] * gain
        self.emit("REWARD", arguments[0], f"gamma={fraction_text(gamma)}")
        for i in range(size):
            self.emit(
                "VALUE", chain.names[i], f"discounted={value_text(values[i])}",
                f"gain={value_text(gains[i])}",
            )

    def restrict(self, arguments):
        name, restricted_name = arguments[0], arguments[1]
        chain = self.require_stochastic(name)
        size = chain.size()
        inside = membership(size, chain.distinct_states(arguments[2:]))
        for i in range(size):
            if inside[i] and any(chain.edge(i, j) and not inside[j] for j in range(size)):
                raise CommandError(f"NOT CLOSED {chain.names[i]}")
        members = [i for i in range(size) if inside[i]]
        restricted = Chain(chain.labels(members))
        restricted.matrix = [[chain.matrix[i][j] for j in members] for i in members]
        self.chains[restricted_name] = restricted
        self.emit("RESTRICT", name, restricted_name, f"states={len(members)}")
        self.display(restricted.names, restricted.matrix)

    def simulate(self, arguments):
        name, source = arguments[0], arguments[1]
        chain = self.require_stochastic(name)
        start = chain.state(source)
        steps, seed = int(arguments[2]), int(arguments[3])
        if steps == 0:
            raise CommandError("BAD STEPS")
        if seed == 0 or seed >= MODULUS:
            raise CommandError("BAD SEED")
        random_value = seed
        path = [start]
        for _ in range(steps):
            row = chain.matrix[path[-1]]
            common = lcm(*(value.denominator for value in row))
            random_value = MULTIPLIER * random_value % MODULUS
            threshold = random_value % common
            cumulative = ZERO
            for j, value in enumerate(row):
                cumulative += value
                if cumulative * common > threshold:
                    path.append(j)
                    break
        self.emit(
            "SIMULATE", name, source, f"steps={steps}", f"seed={seed}",
            f"end={chain.names[path[-1]]}",
        )
        self.emit("PATH", *chain.labels(path))
        for i in range(chain.size()):
            self.emit("VISIT", chain.names[i], path.count(i))

    def execute(self, line):
        command, *arguments = line.split(" ")
        try:
            self.handlers[command](arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    analyzer = MarkovAnalyzer()
    count = int(sys.stdin.readline())
    for _ in range(count):
        analyzer.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(analyzer.output) + "\n")


if __name__ == "__main__":
    main()
