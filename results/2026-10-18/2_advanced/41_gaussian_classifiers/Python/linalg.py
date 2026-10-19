"""Small dense matrix procedures with the specified arithmetic order."""

from math import log, sqrt


def ordered_sum(values):
    # Built-in sum may compensate floating-point additions in modern Python.
    total = 0.0
    for value in values:
        total += value
    return total


def dot(left, right):
    return ordered_sum(a * b for a, b in zip(left, right))


def zeros(size):
    return [[0.0] * size for _ in range(size)]


def cholesky(matrix):
    size = len(matrix)
    lower = zeros(size)
    for i in range(size):
        for j in range(i + 1):
            subtotal = ordered_sum(lower[i][k] * lower[j][k] for k in range(j))
            remainder = matrix[i][j] - subtotal
            if i == j:
                lower[i][i] = sqrt(remainder)
            else:
                lower[i][j] = remainder / lower[j][j]
    return lower


def forward(lower, right):
    result = [0.0] * len(lower)
    for i in range(len(lower)):
        subtotal = ordered_sum(lower[i][k] * result[k] for k in range(i))
        result[i] = (right[i] - subtotal) / lower[i][i]
    return result


def backward(lower, right):
    size = len(lower)
    result = [0.0] * size
    for i in range(size - 1, -1, -1):
        subtotal = ordered_sum(lower[k][i] * result[k] for k in range(i + 1, size))
        result[i] = (right[i] - subtotal) / lower[i][i]
    return result


def log_determinant(lower):
    return 2 * ordered_sum(log(lower[i][i]) for i in range(len(lower)))


def quadratic_form(lower, difference):
    transformed = forward(lower, difference)
    return dot(transformed, transformed)


def jacobi(matrix):
    """Return eigenvalues in original index order, eigenvectors, and sweeps."""
    size = len(matrix)
    current = [row[:] for row in matrix]
    vectors = zeros(size)
    for i in range(size):
        vectors[i][i] = 1.0
    sweeps = 0
    while True:
        off = sqrt(ordered_sum(
            current[a][b] * current[a][b]
            for a in range(size - 1)
            for b in range(a + 1, size)
        ))
        if off < 0.000000000001 or sweeps == 50:
            break
        for a in range(size - 1):
            for b in range(a + 1, size):
                if current[a][b] == 0:
                    continue
                theta = (current[b][b] - current[a][a]) / (2 * current[a][b])
                sign = 1 if theta >= 0 else -1
                tangent = sign / (abs(theta) + sqrt(theta * theta + 1))
                cosine = 1 / sqrt(tangent * tangent + 1)
                sine = tangent * cosine
                for k in range(size):
                    if k == a or k == b:
                        continue
                    x, y = current[k][a], current[k][b]
                    current[k][a] = current[a][k] = cosine * x - sine * y
                    current[k][b] = current[b][k] = sine * x + cosine * y
                off_diagonal = current[a][b]
                current[a][a] = current[a][a] - tangent * off_diagonal
                current[b][b] = current[b][b] + tangent * off_diagonal
                current[a][b] = current[b][a] = 0.0
                for k in range(size):
                    x, y = vectors[k][a], vectors[k][b]
                    vectors[k][a] = cosine * x - sine * y
                    vectors[k][b] = sine * x + cosine * y
        sweeps += 1
    return [current[i][i] for i in range(size)], vectors, sweeps
