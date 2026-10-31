import Foundation

typealias Matrix = [[Double]]

func orderedSum<S: Sequence>(_ values: S) -> Double where S.Element == Double {
    var total = 0.0
    for value in values { total += value }
    return total
}

func dot(_ first: [Double], _ second: [Double]) -> Double { orderedSum(zip(first, second).map { $0.0 * $0.1 }) }
func zeros(_ size: Int) -> Matrix { Array(repeating: Array(repeating: 0.0, count: size), count: size) }

func cholesky(_ matrix: Matrix) -> Matrix {
    let size = matrix.count
    var lower = zeros(size)
    for i in 0..<size {
        for j in 0...i {
            let subtotal = orderedSum((0..<j).map { lower[i][$0] * lower[j][$0] })
            let remainder = matrix[i][j] - subtotal
            lower[i][j] = i == j ? sqrt(remainder) : remainder / lower[j][j]
        }
    }
    return lower
}

func forward(_ lower: Matrix, _ right: [Double]) -> [Double] {
    var result = Array(repeating: 0.0, count: lower.count)
    for i in lower.indices {
        let subtotal = orderedSum((0..<i).map { lower[i][$0] * result[$0] })
        result[i] = (right[i] - subtotal) / lower[i][i]
    }
    return result
}

func backward(_ lower: Matrix, _ right: [Double]) -> [Double] {
    var result = Array(repeating: 0.0, count: lower.count)
    for i in lower.indices.reversed() {
        let subtotal = orderedSum(((i + 1)..<lower.count).map { lower[$0][i] * result[$0] })
        result[i] = (right[i] - subtotal) / lower[i][i]
    }
    return result
}

func logDeterminant(_ lower: Matrix) -> Double { 2 * orderedSum(lower.indices.map { log(lower[$0][$0]) }) }
func quadraticForm(_ lower: Matrix, _ difference: [Double]) -> Double {
    let transformed = forward(lower, difference)
    return dot(transformed, transformed)
}

struct EigenDecomposition {
    let values: [Double]
    let vectors: Matrix
    let sweeps: Int
}

func jacobi(_ matrix: Matrix) -> EigenDecomposition {
    let size = matrix.count
    var current = matrix
    var vectors = zeros(size)
    for i in 0..<size { vectors[i][i] = 1 }
    var sweeps = 0
    while true {
        var squares = 0.0
        for a in 0..<(size - 1) {
            for b in (a + 1)..<size { squares += current[a][b] * current[a][b] }
        }
        if sqrt(squares) < 0.000000000001 || sweeps == 50 { break }
        for a in 0..<(size - 1) {
            for b in (a + 1)..<size where current[a][b] != 0 {
                let theta = (current[b][b] - current[a][a]) / (2 * current[a][b])
                let sign = theta >= 0 ? 1.0 : -1.0
                let tangent = sign / (abs(theta) + sqrt(theta * theta + 1))
                let cosine = 1 / sqrt(tangent * tangent + 1)
                let sine = tangent * cosine
                for k in 0..<size where k != a && k != b {
                    let x = current[k][a]
                    let y = current[k][b]
                    current[k][a] = cosine * x - sine * y
                    current[a][k] = current[k][a]
                    current[k][b] = sine * x + cosine * y
                    current[b][k] = current[k][b]
                }
                let off = current[a][b]
                current[a][a] = current[a][a] - tangent * off
                current[b][b] = current[b][b] + tangent * off
                current[a][b] = 0
                current[b][a] = 0
                for k in 0..<size {
                    let x = vectors[k][a]
                    let y = vectors[k][b]
                    vectors[k][a] = cosine * x - sine * y
                    vectors[k][b] = sine * x + cosine * y
                }
            }
        }
        sweeps += 1
    }
    return EigenDecomposition(values: (0..<size).map { current[$0][$0] }, vectors: vectors, sweeps: sweeps)
}
