import Foundation

struct CholeskyResult { let lower: [[Double]]?; let unstable: Int? }
func cholesky(_ matrix: [[Double]], _ free: [Int]) -> CholeskyResult {
    let size = matrix.count
    var lower = Array(repeating: Array(repeating: 0.0, count: size), count: size)
    for row in 0..<size {
        for column in 0...row {
            var value = matrix[row][column]
            for index in 0..<column { value -= lower[row][index] * lower[column][index] }
            if column < row { lower[row][column] = value / lower[column][column] }
            else {
                if value <= 0.000000001 * matrix[row][row] { return CholeskyResult(lower: nil, unstable: free[row]) }
                lower[row][row] = sqrt(value)
            }
        }
    }
    return CholeskyResult(lower: lower, unstable: nil)
}
func solve(_ lower: [[Double]], _ right: [Double]) -> [Double] {
    let size = right.count
    var intermediate = Array(repeating: 0.0, count: size), result = intermediate
    for row in 0..<size {
        var value = right[row]
        for column in 0..<row { value -= lower[row][column] * intermediate[column] }
        intermediate[row] = value / lower[row][row]
    }
    for row in stride(from: size - 1, through: 0, by: -1) {
        var value = intermediate[row]
        for column in (row + 1)..<size { value -= lower[column][row] * result[column] }
        result[row] = value / lower[row][row]
    }
    return result
}
