"""Rayleigh selection, normal equations, Gaussian elimination and phase."""

import math


PI = 3.141592653589793


def select_constituents(constituents, record_length, rayleigh):
    selected = []
    status = {}
    minimum = 360 * rayleigh
    for constituent in constituents:
        name = constituent["name"]
        speed = constituent["speed"]
        if speed * record_length < minimum:
            status[name] = "short"
            continue
        conflict = next((chosen for chosen in selected
                         if abs(speed - chosen["speed"]) * record_length < minimum),
                        None)
        if conflict is not None:
            status[name] = "conflict:" + conflict["name"]
            continue
        status[name] = "fitted"
        selected.append(constituent)
    return selected, status


def angle(speed, time):
    degrees = speed * time
    reduced = degrees - 360 * math.floor(degrees / 360)
    return reduced * PI / 180


def regressors(time, selected):
    features = [1.0]
    for constituent in selected:
        theta = angle(constituent["speed"], time)
        features.append(math.cos(theta))
        features.append(math.sin(theta))
    return features


def solve_with_inverse(matrix, right):
    """Gaussian elimination on [A | right | identity], with partial pivoting."""
    dimension = len(matrix)
    aug = [
        list(matrix[i]) + [right[i]] +
        [1.0 if i == j else 0.0 for j in range(dimension)]
        for i in range(dimension)
    ]
    for column in range(dimension):
        pivot = max(range(column, dimension),
                    key=lambda i: (abs(aug[i][column]), -i))
        if pivot != column:
            aug[column], aug[pivot] = aug[pivot], aug[column]
        for row in range(column + 1, dimension):
            factor = aug[row][column] / aug[column][column]
            for c in range(column, 2 * dimension + 1):
                aug[row][c] = aug[row][c] - factor * aug[column][c]
    solutions = []
    for column in range(dimension, 2 * dimension + 1):
        solution = [0.0] * dimension
        for i in range(dimension - 1, -1, -1):
            current = aug[i][column]
            for j in range(i + 1, dimension):
                current = current - aug[i][j] * solution[j]
            solution[i] = current / aug[i][i]
        solutions.append(solution)
    inverse = [
        [solutions[column + 1][row] for column in range(dimension)]
        for row in range(dimension)
    ]
    return solutions[0], inverse


def fit(values, times, selected):
    """Fit Z0 plus cosine/sine terms using all samples in increasing time order."""
    dimension = len(selected) * 2 + 1
    matrix = [[0.0] * dimension for _ in range(dimension)]
    right = [0.0] * dimension
    for time in sorted(times):
        vector = regressors(time, selected)
        observed = values[time]
        for i in range(dimension):
            right[i] += vector[i] * observed
            for j in range(dimension):
                matrix[i][j] += vector[i] * vector[j]
    coefficients, inverse = solve_with_inverse(matrix, right)
    constants = {}
    for i, constituent in enumerate(selected):
        a = coefficients[2 * i + 1]
        b = coefficients[2 * i + 2]
        amplitude = math.sqrt(a * a + b * b)
        phase = math.atan2(b, a) * 180 / PI
        if phase < 0:
            phase += 360
        constants[constituent["name"]] = {
            "speed": constituent["speed"],
            "a": a, "b": b, "amplitude": amplitude, "phase": phase,
            "index_a": 2 * i + 1, "index_b": 2 * i + 2,
        }
    return {
        "selected": selected, "coefficients": coefficients,
        "inverse": inverse, "mean_level": coefficients[0],
        "constants": constants, "unknowns": dimension,
    }
