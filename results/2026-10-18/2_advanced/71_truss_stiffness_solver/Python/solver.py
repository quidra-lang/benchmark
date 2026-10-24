"""Ordered Cholesky factorization with a relative instability pivot check."""

from math import sqrt


def cholesky(matrix, free):
    size = len(matrix)
    lower = [[0.0] * size for _ in range(size)]
    for row in range(size):
        for column in range(row + 1):
            value = matrix[row][column]
            for index in range(column):
                value -= lower[row][index] * lower[column][index]
            if column < row:
                lower[row][column] = value / lower[column][column]
            else:
                if value <= 0.000000001 * matrix[row][row]:
                    return None, free[row]
                lower[row][row] = sqrt(value)
    return lower, None


def solve(lower, right):
    size = len(right)
    intermediate, result = [0.0] * size, [0.0] * size
    for row in range(size):
        value = right[row]
        for column in range(row):
            value -= lower[row][column] * intermediate[column]
        intermediate[row] = value / lower[row][row]
    for row in range(size - 1, -1, -1):
        value = intermediate[row]
        for column in range(row + 1, size):
            value -= lower[column][row] * result[column]
        result[row] = value / lower[row][row]
    return result
