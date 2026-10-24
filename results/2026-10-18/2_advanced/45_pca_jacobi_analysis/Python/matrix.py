import math


def sequential_sum(values):
    total = 0.0
    for value in values:
        total += value
    return total


def identity(size):
    return [[1.0 if row == col else 0.0 for col in range(size)] for row in range(size)]


def copy_matrix(matrix):
    return [row[:] for row in matrix]


def column(matrix, index):
    return [row[index] for row in matrix]


def dot(first, second):
    return sequential_sum(a * b for a, b in zip(first, second))


def multiply(matrix, vector):
    return [dot(row, vector) for row in matrix]


def vector_length(vector):
    return math.sqrt(dot(vector, vector))


def normalize(vector):
    length = vector_length(vector)
    return [value / length for value in vector]


def orient(vector):
    largest = max(range(len(vector)), key=lambda j: abs(vector[j]))
    if vector[largest] < 0:
        return [-value for value in vector]
    return vector


def max_difference(first, second):
    return max(abs(a - b) for a, b in zip(first, second))


def deflate(matrix, value, vector):
    for i, row in enumerate(matrix):
        for j in range(len(row)):
            row[j] -= value * vector[i] * vector[j]


def gauss_jordan(matrix):
    size = len(matrix)
    augmented = [row[:] + unit for row, unit in zip(matrix, identity(size))]
    determinant = 1.0
    for k in range(size):
        pivot = augmented[k][k]
        determinant *= pivot
        augmented[k] = [value / pivot for value in augmented[k]]
        for i in range(size):
            if i != k:
                gamma = augmented[i][k]
                augmented[i] = [a - gamma * b for a, b in zip(augmented[i], augmented[k])]
    inverse = [row[size:] for row in augmented]
    return inverse, determinant
