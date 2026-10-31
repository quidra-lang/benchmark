import Foundation

typealias Matrix = [[Double]]
func total<S: Sequence>(_ values: S) -> Double where S.Element == Double { var result = 0.0; for value in values { result += value }; return result }
func zeros(_ rows: Int, _ columns: Int? = nil) -> Matrix { Array(repeating: Array(repeating: 0, count: columns ?? rows), count: rows) }
func diagonal(_ values: [Double]) -> Matrix { var result = zeros(values.count); for i in values.indices { result[i][i] = values[i] }; return result }
func identity(_ count: Int) -> Matrix { diagonal(Array(repeating: 1, count: count)) }
func transpose(_ matrix: Matrix) -> Matrix { matrix[0].indices.map { column in matrix.map { $0[column] } } }
func add(_ first: Matrix, _ second: Matrix) -> Matrix { first.indices.map { i in first[i].indices.map { first[i][$0] + second[i][$0] } } }
func subtract(_ first: Matrix, _ second: Matrix) -> Matrix { first.indices.map { i in first[i].indices.map { first[i][$0] - second[i][$0] } } }
func vectorAdd(_ first: [Double], _ second: [Double]) -> [Double] { first.indices.map { first[$0] + second[$0] } }
func vectorSubtract(_ first: [Double], _ second: [Double]) -> [Double] { first.indices.map { first[$0] - second[$0] } }
func product(_ first: Matrix, _ second: Matrix) -> Matrix { first.indices.map { i in second[0].indices.map { j in var value = 0.0; for k in first[i].indices { value += first[i][k] * second[k][j] }; return value } } }
func matrixVector(_ matrix: Matrix, _ vector: [Double]) -> [Double] { matrix.map { row in total(row.indices.map { row[$0] * vector[$0] }) } }
func inverse(_ matrix: Matrix) -> Matrix {
    let count = matrix.count, unit = identity(count)
    var augmented = matrix.indices.map { matrix[$0] + unit[$0] }
    for column in 0..<count { let pivot = augmented[column][column]; for j in 0..<(2 * count) { augmented[column][j] /= pivot }; for row in 0..<count where row != column { let factor = augmented[row][column]; for j in 0..<(2 * count) { augmented[row][j] -= factor * augmented[column][j] } } }
    return augmented.map { Array($0.dropFirst(count)) }
}
func determinant2(_ matrix: Matrix) -> Double { matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0] }
func quadratic2(_ vector: [Double], _ matrix: Matrix) -> Double { vector[0] * (matrix[0][0] * vector[0] + matrix[0][1] * vector[1]) + vector[1] * (matrix[1][0] * vector[0] + matrix[1][1] * vector[1]) }
