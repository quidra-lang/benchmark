"""Rectangular Hungarian matching and maximum-cardinality usable assignment."""

from math import inf


def minimum_matching(costs):
    if not costs or not costs[0]:
        return []
    transposed = len(costs) > len(costs[0])
    matrix = [list(row) for row in zip(*costs)] if transposed else costs
    rows, columns = len(matrix), len(matrix[0])
    u, v = [0.0] * (rows + 1), [0.0] * (columns + 1)
    matched, previous = [0] * (columns + 1), [0] * (columns + 1)
    for row in range(1, rows + 1):
        matched[0] = row
        column = 0
        distances = [inf] * (columns + 1)
        used = [False] * (columns + 1)
        while True:
            used[column] = True
            current_row = matched[column]
            delta, following = inf, 0
            for candidate in range(1, columns + 1):
                if used[candidate]:
                    continue
                reduced = matrix[current_row - 1][candidate - 1] - u[current_row] - v[candidate]
                if reduced < distances[candidate]:
                    distances[candidate] = reduced
                    previous[candidate] = column
                if distances[candidate] < delta:
                    delta, following = distances[candidate], candidate
            for candidate in range(columns + 1):
                if used[candidate]:
                    u[matched[candidate]] += delta
                    v[candidate] -= delta
                else:
                    distances[candidate] -= delta
            column = following
            if matched[column] == 0:
                break
        while column:
            following = previous[column]
            matched[column] = matched[following]
            column = following
    pairs = [(matched[column] - 1, column - 1)
             for column in range(1, columns + 1) if matched[column]]
    return sorted((column, row) for row, column in pairs) if transposed else sorted(pairs)


def optimal_assignment(rows, columns, usable):
    if rows == 0 or columns == 0 or not usable:
        return []
    largest = max(usable.values())
    penalty = (min(rows, columns) + 1) * (max(1.0, largest) + 1.0)
    costs = [[usable.get((row, column), penalty) for column in range(columns)]
             for row in range(rows)]
    return [(row, column) for row, column in minimum_matching(costs) if (row, column) in usable]
