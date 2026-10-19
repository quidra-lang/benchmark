"""Ordered stationary iterations and simultaneous band Gaussian elimination."""

from transient import ordered_sum


def g_value(system, field, point):
    terms = []
    for face in system.faces[point]:
        if face.neighbor >= 0:
            terms.append(face.g * field[face.neighbor])
        elif face.theta is not None:
            terms.append(face.g * face.theta)
    return ordered_sum(terms) + system.source_all[point]


def iterate(system, initial, tolerance, maximum, method, omega=1.0):
    field = [initial] * system.mesh.count
    changes = []
    for iteration in range(1, maximum + 1):
        previous = field.copy()
        if method == "jacobi":
            field = [
                g_value(system, previous, point) / system.diagonal[point]
                for point in range(system.mesh.count)
            ]
        else:
            for point in range(system.mesh.count):
                value = g_value(system, field, point) / system.diagonal[point]
                if method == "gauss_seidel":
                    field[point] = value
                else:
                    field[point] = field[point] + omega * (value - field[point])
        change = max(abs(after - before) for after, before in zip(field, previous))
        changes.append(change)
        if change < tolerance:
            break
    return {
        "method": method,
        "field": field,
        "changes": changes,
        "iterations": iteration,
        "converged": changes[-1] < tolerance,
        "omega": omega,
    }


def band_solve(system, right_hand_sides):
    count = system.mesh.count
    width = system.mesh.width
    matrix = [[0.0] * count for _ in range(count)]
    for point, faces in enumerate(system.faces):
        matrix[point][point] = system.diagonal[point]
        for face in faces:
            if face.neighbor >= 0:
                matrix[point][face.neighbor] = -face.g
    vectors = [values.copy() for values in right_hand_sides]
    for column in range(count):
        stop = min(count, column + width + 1)
        for row in range(column + 1, stop):
            factor = matrix[row][column] / matrix[column][column]
            matrix[row][column] = 0.0
            for following in range(column + 1, stop):
                matrix[row][following] -= factor * matrix[column][following]
            for values in vectors:
                values[row] -= factor * values[column]
    solutions = []
    for values in vectors:
        field = [0.0] * count
        for row in range(count - 1, -1, -1):
            value = values[row]
            for column in range(row + 1, min(count, row + width + 1)):
                value -= matrix[row][column] * field[column]
            field[row] = value / matrix[row][row]
        solutions.append(field)
    return solutions


def maximum_residual(system, field, right_hand_side):
    maximum = 0.0
    for point, faces in enumerate(system.faces):
        residual = right_hand_side[point]
        for face in faces:
            if face.neighbor >= 0:
                residual += face.g * field[face.neighbor]
        residual -= system.diagonal[point] * field[point]
        maximum = max(maximum, abs(residual))
    return maximum
