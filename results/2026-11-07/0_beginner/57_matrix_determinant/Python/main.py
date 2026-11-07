def determinant(matrix):
    if len(matrix) == 1:
        return matrix[0][0]
    total = 0
    for j, value in enumerate(matrix[0]):
        minor = [row[:j] + row[j + 1 :] for row in matrix[1:]]
        term = value * determinant(minor)
        total += term if j % 2 == 0 else -term
    return total


matrices = [
    [[2, -3, 1], [5, 4, -2], [-1, 6, 3]],
    [[3, 0, -2, 5], [1, 4, 7, -3], [-6, 2, 1, 8], [9, -5, 3, 2]],
    [
        [4, -1, 7, 0, -3],
        [2, 8, -5, 6, 1],
        [-9, 3, 2, -4, 5],
        [6, 0, -7, 3, -2],
        [1, -6, 4, 9, 8],
    ],
]
for matrix in matrices:
    n = len(matrix)
    print(f"det({n}x{n}) = {determinant(matrix)}")
