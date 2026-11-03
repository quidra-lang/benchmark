"""Ordered face flows, Thomas sweeps, and the three transient updates."""

from mesh import LEFT, RIGHT, TOP, BOTTOM


def ordered_sum(values):
    values = iter(values)
    total = next(values, 0.0)
    for value in values:
        total += value
    return total


def heat_flow(system, field, point, directions):
    terms = []
    for direction in directions:
        face = system.faces[point][direction]
        if face.neighbor >= 0:
            terms.append(face.g * (field[face.neighbor] - field[point]))
        elif face.theta is not None:
            terms.append(face.g * (face.theta - field[point]))
    return ordered_sum(terms)


def horizontal_flow(system, field, point):
    return heat_flow(system, field, point, (LEFT, RIGHT))


def vertical_flow(system, field, point):
    return heat_flow(system, field, point, (TOP, BOTTOM))


def total_flow(system, field, point):
    return heat_flow(system, field, point, (LEFT, RIGHT, TOP, BOTTOM))


def thomas(lower, diagonal, upper, right_hand_side):
    length = len(diagonal)
    upper_prime = [upper[0] / diagonal[0]]
    rhs_prime = [right_hand_side[0] / diagonal[0]]
    for index in range(1, length):
        pivot = diagonal[index] - lower[index] * upper_prime[index - 1]
        upper_prime.append(upper[index] / pivot)
        rhs_prime.append(
            (right_hand_side[index] - lower[index] * rhs_prime[index - 1]) / pivot
        )
    result = [0.0] * length
    result[-1] = rhs_prime[-1]
    for index in range(length - 2, -1, -1):
        result[index] = rhs_prime[index] - upper_prime[index] * result[index + 1]
    return result


def sweep(system, tau, right_hand_side, horizontal):
    plate = system.mesh
    line_count = plate.height if horizontal else plate.width
    line_length = plate.width if horizontal else plate.height
    first_face, second_face = (LEFT, RIGHT) if horizontal else (TOP, BOTTOM)
    field = [0.0] * plate.count
    for line in range(line_count):
        cells = [
            plate.cell(line, index) if horizontal else plate.cell(index, line)
            for index in range(line_length)
        ]
        lower, diagonal, upper, rhs = [], [], [], []
        for point in cells:
            first = system.faces[point][first_face]
            second = system.faces[point][second_face]
            lower.append(-first.g if first.neighbor >= 0 else 0.0)
            diagonal.append(system.capacity[point] / tau + first.g + second.g)
            upper.append(-second.g if second.neighbor >= 0 else 0.0)
            value = right_hand_side[point]
            if first.theta is not None:
                value += first.g * first.theta
            if second.theta is not None:
                value += second.g * second.theta
            rhs.append(value)
        solved = thomas(lower, diagonal, upper, rhs)
        for point, value in zip(cells, solved):
            field[point] = value
    return field


def horizontal_sweep(system, tau, right_hand_side):
    return sweep(system, tau, right_hand_side, True)


def vertical_sweep(system, tau, right_hand_side):
    return sweep(system, tau, right_hand_side, False)


def ftcs(system, field, source, dt):
    updated = [
        field[point] + dt * (total_flow(system, field, point) + source[point])
        / system.capacity[point]
        for point in range(system.mesh.count)
    ]
    return updated, None


def backward_euler(system, field, source, dt):
    vertical = [vertical_flow(system, field, point) for point in range(system.mesh.count)]
    rhs = [
        system.capacity[point] / dt * field[point] + vertical[point] + source[point]
        for point in range(system.mesh.count)
    ]
    intermediate = horizontal_sweep(system, dt, rhs)
    rhs = [
        system.capacity[point] / dt * intermediate[point] - vertical[point]
        for point in range(system.mesh.count)
    ]
    return vertical_sweep(system, dt, rhs), intermediate


def crank_nicolson(system, field, source, dt):
    tau = dt / 2
    rhs = [
        system.capacity[point] / tau * field[point]
        + vertical_flow(system, field, point) + source[point]
        for point in range(system.mesh.count)
    ]
    intermediate = horizontal_sweep(system, tau, rhs)
    rhs = [
        system.capacity[point] / tau * intermediate[point]
        + horizontal_flow(system, intermediate, point) + source[point]
        for point in range(system.mesh.count)
    ]
    return vertical_sweep(system, tau, rhs), intermediate


def advance(method, system, field, source, dt):
    if method == "ftcs":
        return ftcs(system, field, source, dt)
    if method == "backward_euler":
        return backward_euler(system, field, source, dt)
    return crank_nicolson(system, field, source, dt)
