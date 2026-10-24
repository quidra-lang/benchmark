"""The specified elimination and incomplete-gamma algorithms."""

from math import exp, log


Z95 = 1.959963984540054


def total(values):
    """Add floating-point terms strictly in their supplied order."""
    result = 0.0
    for value in values:
        result += value
    return result


def solve(matrix, vector):
    a = [row[:] for row in matrix]
    b = list(vector)
    size = len(b)
    for k in range(size):
        for i in range(k + 1, size):
            factor = a[i][k] / a[k][k]
            for j in range(k, size):
                a[i][j] -= factor * a[k][j]
            b[i] -= factor * b[k]
    solution = [0.0] * size
    for i in range(size - 1, -1, -1):
        value = b[i]
        for j in range(i + 1, size):
            value -= a[i][j] * solution[j]
        solution[i] = value / a[i][i]
    return solution


def inverse(matrix):
    size = len(matrix)
    result = [[0.0] * size for _ in range(size)]
    for column in range(size):
        unit = [0.0] * size
        unit[column] = 1.0
        solution = solve(matrix, unit)
        for row in range(size):
            result[row][column] = solution[row]
    return result


def log_gamma(a):
    coefficients = (
        76.18009172947146,
        -86.50532032941677,
        24.01409824083091,
        -1.231739572450155,
        0.001208650973866179,
        -0.000005395239384953,
    )
    xi = a + 5.5
    xi -= (a + 0.5) * log(xi)
    sigma = 1.000000000190015
    y = a
    for coefficient in coefficients:
        y += 1.0
        sigma += coefficient / y
    return -xi + log(2.5066282746310005 * sigma / a)


def gamma_q(a, x):
    if x == 0.0:
        return 1.0
    prefactor = exp(-x + a * log(x) - log_gamma(a))
    if x < a + 1.0:
        alpha = a
        term = 1.0 / a
        sigma = term
        for _ in range(1000):
            alpha += 1.0
            term *= x / alpha
            sigma += term
            if abs(term) < abs(sigma) * 1e-15:
                break
        return 1.0 - sigma * prefactor
    epsilon = 1e-300
    b = x + 1.0 - a
    c = 1.0 / epsilon
    d = 1.0 / b
    h = d
    for i in range(1, 1001):
        an = -i * (i - a)
        b += 2.0
        d = an * d + b
        if abs(d) < epsilon:
            d = epsilon
        c = b + an / c
        if abs(c) < epsilon:
            c = epsilon
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < 1e-15:
            break
    return prefactor * h


def chi_square_p(statistic, degrees):
    return gamma_q(degrees / 2.0, statistic / 2.0)
