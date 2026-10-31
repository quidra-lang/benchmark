func determinant(_ matrix: [[Int]]) -> Int {
    if matrix.count == 1 { return matrix[0][0] }
    var result = 0
    for column in matrix.indices {
        let minor = matrix.dropFirst().map { row in row.enumerated().filter { $0.offset != column }.map { $0.element } }
        let term = matrix[0][column] * determinant(minor)
        result += column % 2 == 0 ? term : -term
    }
    return result
}

let matrices = [
    [[2, -3, 1], [5, 4, -2], [-1, 6, 3]],
    [[3, 0, -2, 5], [1, 4, 7, -3], [-6, 2, 1, 8], [9, -5, 3, 2]],
    [[4, -1, 7, 0, -3], [2, 8, -5, 6, 1], [-9, 3, 2, -4, 5], [6, 0, -7, 3, -2], [1, -6, 4, 9, 8]],
]
for matrix in matrices { print("det(\(matrix.count)x\(matrix.count)) = \(determinant(matrix))") }
