import math

from logistic import gradient, hessian


MODULUS = 2147483647
MULTIPLIER = 48271
CHECKPOINT_INTERVAL = 100
NEWTON_ITERATIONS = 10


class Minstd:
    def __init__(self, seed):
        self.state = seed

    def draw(self):
        self.state = MULTIPLIER * self.state % MODULUS
        return self.state


def shuffle(sequence, generator):
    for i in range(len(sequence) - 1, 0, -1):
        k = generator.draw() % (i + 1)
        sequence[i], sequence[k] = sequence[k], sequence[i]


def move(weights, direction, rate):
    return [weight - rate * step for weight, step in zip(weights, direction)]


def gradient_descent(vectors, targets, lam, rate, iterations):
    weights = [0.0] * len(vectors[0])
    checkpoints = [(0, weights)]
    for t in range(1, iterations + 1):
        weights = move(weights, gradient(weights, vectors, targets, lam), rate)
        if t % CHECKPOINT_INTERVAL == 0:
            checkpoints.append((t, weights))
    return checkpoints


def stochastic_gradient_descent(vectors, targets, lam, rate, batch_size, epochs, seed):
    generator = Minstd(seed)
    order = list(range(len(vectors)))
    weights = [0.0] * len(vectors[0])
    checkpoints = [(0, weights)]
    for epoch in range(1, epochs + 1):
        shuffle(order, generator)
        for start in range(0, len(order), batch_size):
            batch = order[start:start + batch_size]
            direction = gradient(
                weights, [vectors[i] for i in batch], [targets[i] for i in batch], lam
            )
            weights = move(weights, direction, rate)
        checkpoints.append((epoch, weights))
    return checkpoints


def cholesky(matrix):
    size = len(matrix)
    lower = [[0.0] * size for _ in range(size)]
    for j in range(size):
        for i in range(j, size):
            total = 0.0
            for k in range(j):
                total += lower[i][k] * lower[j][k]
            remainder = matrix[i][j] - total
            if i == j:
                lower[j][j] = math.sqrt(remainder)
            else:
                lower[i][j] = remainder / lower[j][j]
    return lower


def solve(lower, values):
    size = len(lower)
    middle = [0.0] * size
    for i in range(size):
        total = 0.0
        for k in range(i):
            total += lower[i][k] * middle[k]
        middle[i] = (values[i] - total) / lower[i][i]
    solution = [0.0] * size
    for i in range(size - 1, -1, -1):
        total = 0.0
        for k in range(i + 1, size):
            total += lower[k][i] * solution[k]
        solution[i] = (middle[i] - total) / lower[i][i]
    return solution


def newton_direction(weights, vectors, targets, lam):
    direction = gradient(weights, vectors, targets, lam)
    step = solve(cholesky(hessian(weights, vectors, lam)), direction)
    return direction, step


def newton_method(vectors, targets, lam):
    weights = [0.0] * len(vectors[0])
    checkpoints = [(0, weights)]
    for t in range(1, NEWTON_ITERATIONS + 1):
        _, step = newton_direction(weights, vectors, targets, lam)
        weights = [weight - delta for weight, delta in zip(weights, step)]
        checkpoints.append((t, weights))
    return checkpoints
