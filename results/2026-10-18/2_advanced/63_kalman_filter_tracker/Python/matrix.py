"""Small dense matrices with explicitly ordered double-precision operations."""


def total(values):
    result = 0.0
    for value in values:
        result += value
    return result


def zeros(rows, columns=None):
    return [[0.0] * (rows if columns is None else columns) for _ in range(rows)]


def diagonal(values):
    result = zeros(len(values))
    for index, value in enumerate(values):
        result[index][index] = value
    return result


def identity(size):
    return diagonal([1.0] * size)


def transpose(a):
    return [list(column) for column in zip(*a)]


def add(a, b):
    return [[x + y for x, y in zip(row_a, row_b)] for row_a, row_b in zip(a, b)]


def subtract(a, b):
    return [[x - y for x, y in zip(row_a, row_b)] for row_a, row_b in zip(a, b)]


def vector_add(a, b):
    return [x + y for x, y in zip(a, b)]


def vector_subtract(a, b):
    return [x - y for x, y in zip(a, b)]


def product(a, b):
    columns = transpose(b)
    return [[total(x * y for x, y in zip(row, column)) for column in columns] for row in a]


def matrix_vector(a, vector):
    return [total(x * y for x, y in zip(row, vector)) for row in a]


def inverse(a):
    size = len(a)
    unit = identity(size)
    augmented = [list(row) + unit[index] for index, row in enumerate(a)]
    for column in range(size):
        pivot = augmented[column][column]
        for j in range(2 * size):
            augmented[column][j] /= pivot
        for row in range(size):
            if row == column:
                continue
            factor = augmented[row][column]
            for j in range(2 * size):
                augmented[row][j] -= factor * augmented[column][j]
    return [row[size:] for row in augmented]


def determinant2(a):
    return a[0][0] * a[1][1] - a[0][1] * a[1][0]


def quadratic2(vector, a):
    x, y = vector
    return x * (a[0][0] * x + a[0][1] * y) + y * (a[1][0] * x + a[1][1] * y)
