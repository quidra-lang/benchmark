"""Grid-search and 8-step Geiger relocation, Cholesky systems, covariance."""

import math


PI = 3.141592653589793


def distance(solution, station):
    x, y, z = solution[:3]
    return math.sqrt(
        (x - station["x"]) ** 2
        + (y - station["y"]) ** 2
        + (z + station["elevation"]) ** 2
    )


def residuals(solution, observations, velocity):
    x, y, z, origin = solution
    return [
        pick_time - origin - distance(solution, station) / velocity
        for station, pick_time in observations
    ]


def rms(solution, observations, velocity):
    errors = residuals(solution, observations, velocity)
    return math.sqrt(sum(value * value for value in errors) / len(errors))


def grid_search(observations, params):
    velocity = params["velocity"]
    ranges = [range(low, high + 1, step)
              for low, high, step in (
                  params["grid_x"], params["grid_y"], params["grid_z"]
              )]
    best = None
    best_error = float("inf")
    profile = {}
    for x in ranges[0]:
        for y in ranges[1]:
            for z in ranges[2]:
                travel = [
                    time - distance((x, y, z, 0), station) / velocity
                    for station, time in observations
                ]
                origin = sum(travel) / len(travel)
                error = sum((value - origin) ** 2 for value in travel)
                if error < best_error:
                    best = (float(x), float(y), float(z), origin)
                    best_error = error
                if z not in profile or error < profile[z]:
                    profile[z] = error
    depth_profile = [
        (z, math.sqrt(profile[z] / len(observations))) for z in sorted(profile)
    ]
    return {
        "solution": best, "rms": math.sqrt(best_error / len(observations)),
        "profile": depth_profile,
    }


def cholesky(matrix):
    size = len(matrix)
    lower = [[0.0] * size for _ in range(size)]
    for row in range(size):
        for col in range(row + 1):
            diagonal = matrix[row][col]
            for j in range(col):
                diagonal -= lower[row][j] * lower[col][j]
            if row == col:
                lower[row][col] = math.sqrt(diagonal)
            else:
                lower[row][col] = diagonal / lower[col][col]
    return lower


def cholesky_solve(lower, right):
    dimension = len(lower)
    forward = [0.0] * dimension
    for row in range(dimension):
        value = right[row]
        for col in range(row):
            value -= lower[row][col] * forward[col]
        forward[row] = value / lower[row][row]
    solution = [0.0] * dimension
    for row in range(dimension - 1, -1, -1):
        value = forward[row]
        for col in range(row + 1, dimension):
            value -= lower[col][row] * solution[col]
        solution[row] = value / lower[row][row]
    return solution


def normals(solution, observations, velocity):
    """The four Geiger derivatives and normal-equation matrix."""
    x, y, z, _ = solution
    normals_matrix = [[0.0] * 4 for _ in range(4)]
    right = [0.0] * 4
    values = residuals(solution, observations, velocity)
    for (station, _), error in zip(observations, values):
        d = distance(solution, station)
        derivatives = [
            (x - station["x"]) / (velocity * d),
            (y - station["y"]) / (velocity * d),
            (z + station["elevation"]) / (velocity * d),
            1.0,
        ]
        for i in range(4):
            right[i] += derivatives[i] * error
            for j in range(4):
                normals_matrix[i][j] += derivatives[i] * derivatives[j]
    return normals_matrix, right


def geiger(initial, observations, velocity):
    solution = list(initial)
    trace = []
    for iteration in range(1, 9):
        matrix, right = normals(solution, observations, velocity)
        delta = cholesky_solve(cholesky(matrix), right)
        for axis in range(4):
            solution[axis] += delta[axis]
        if solution[2] < 0:
            solution[2] = 0.0
        trace.append({
            "number": iteration, "solution": tuple(solution),
            "rms": rms(solution, observations, velocity),
        })
    solution = tuple(solution)
    return {
        "solution": solution, "trace": trace,
        "residuals": residuals(solution, observations, velocity),
        "rms": rms(solution, observations, velocity),
    }


def run_location(observations, params):
    grid = grid_search(observations, params)
    refined = geiger(grid["solution"], observations, params["velocity"])
    return {**refined, "grid": grid}


def error_ellipse(solution, observations, velocity):
    """Covariance from normal matrix and exact 2-D ellipse eigenvalues."""
    matrix, _ = normals(solution, observations, velocity)
    lower = cholesky(matrix)
    inverse_columns = [
        cholesky_solve(lower, [1.0 if row == col else 0.0 for row in range(4)])
        for col in range(4)
    ]
    variance = sum(
        value * value for value in residuals(solution, observations, velocity)
    ) / (len(observations) - 4)
    cov = [
        [variance * inverse_columns[j][i] for j in range(4)]
        for i in range(4)
    ]
    xx, yy, xy = cov[0][0], cov[1][1], cov[0][1]
    midpoint = (xx + yy) / 2
    radius = math.sqrt(((xx - yy) / 2) ** 2 + xy ** 2)
    theta = math.atan2(2 * xy, xx - yy) / 2 * 180 / PI
    return {
        "smaj": math.sqrt(midpoint + radius),
        "smin": math.sqrt(midpoint - radius),
        "az": 90 - theta,
        "erz": math.sqrt(cov[2][2]),
        "ert": math.sqrt(cov[3][3]),
    }
