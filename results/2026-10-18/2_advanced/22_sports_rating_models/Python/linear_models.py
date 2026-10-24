from math import sqrt


def cholesky_solve(matrix, vector):
    size = len(vector)
    lower = [[0.0] * size for _ in range(size)]
    for i in range(size):
        for j in range(i + 1):
            total = 0.0
            for k in range(j):
                total += lower[i][k] * lower[j][k]
            if j < i:
                lower[i][j] = (matrix[i][j] - total) / lower[j][j]
            else:
                lower[i][i] = sqrt(matrix[i][i] - total)
    forward = [0.0] * size
    for i in range(size):
        total = 0.0
        for k in range(i):
            total += lower[i][k] * forward[k]
        forward[i] = (vector[i] - total) / lower[i][i]
    solution = [0.0] * size
    for i in range(size - 1, -1, -1):
        total = 0.0
        for k in range(i + 1, size):
            total += lower[k][i] * solution[k]
        solution[i] = (forward[i] - total) / lower[i][i]
    return solution


def gaussian_solve(matrix, vector):
    size = len(vector)
    for k in range(size):
        pivot = k
        for row in range(k + 1, size):
            if abs(matrix[row][k]) > abs(matrix[pivot][k]):
                pivot = row
        matrix[k], matrix[pivot] = matrix[pivot], matrix[k]
        vector[k], vector[pivot] = vector[pivot], vector[k]
        for i in range(k + 1, size):
            factor = matrix[i][k] / matrix[k][k]
            for j in range(k, size):
                matrix[i][j] -= factor * matrix[k][j]
            vector[i] -= factor * vector[k]
    solution = [0.0] * size
    for i in range(size - 1, -1, -1):
        total = 0.0
        for j in range(i + 1, size):
            total += matrix[i][j] * solution[j]
        solution[i] = (vector[i] - total) / matrix[i][i]
    return solution


def colley_ratings(team_count, matches):
    matrix = [[0.0] * team_count for _ in range(team_count)]
    balance = [0] * team_count
    for team in range(team_count):
        matrix[team][team] = 2.0
    for match in matches:
        matrix[match.home][match.home] += 1
        matrix[match.away][match.away] += 1
        matrix[match.home][match.away] -= 1
        matrix[match.away][match.home] -= 1
        if match.margin > 0:
            balance[match.home] += 1
            balance[match.away] -= 1
        elif match.margin < 0:
            balance[match.home] -= 1
            balance[match.away] += 1
    vector = [1 + balance[team] / 2 for team in range(team_count)]
    return cholesky_solve(matrix, vector)


def massey_ratings(team_count, matches):
    size = team_count + 1
    last = team_count
    matrix = [[0.0] * size for _ in range(size)]
    vector = [0.0] * size
    for match in matches:
        home, away = match.home, match.away
        matrix[home][home] += 1
        matrix[away][away] += 1
        matrix[home][away] -= 1
        matrix[away][home] -= 1
        matrix[home][last] += 1
        matrix[last][home] += 1
        matrix[away][last] -= 1
        matrix[last][away] -= 1
        matrix[last][last] += 1
        vector[home] += match.margin
        vector[away] -= match.margin
        vector[last] += match.margin
    matrix[team_count - 1] = [1.0] * team_count + [0.0]
    vector[team_count - 1] = 0.0
    solution = gaussian_solve(matrix, vector)
    return solution[:team_count], solution[last]
