import Foundation

typealias Matrix = [[Double]]

func sequentialSum<S: Sequence>(_ values: S) -> Double where S.Element == Double {
    var total = 0.0
    for value in values { total = total + value }
    return total
}

func identity(_ size: Int) -> Matrix { (0..<size).map { i in (0..<size).map { i == $0 ? 1 : 0 } } }
func column(_ matrix: Matrix, _ index: Int) -> [Double] { matrix.map { $0[index] } }
func dot(_ first: [Double], _ second: [Double]) -> Double { sequentialSum(zip(first, second).map { $0 * $1 }) }
func multiply(_ matrix: Matrix, _ vector: [Double]) -> [Double] { matrix.map { dot($0, vector) } }
func vectorLength(_ vector: [Double]) -> Double { sqrt(dot(vector, vector)) }
func normalize(_ vector: [Double]) -> [Double] { let length = vectorLength(vector); return vector.map { $0 / length } }

func orient(_ vector: [Double]) -> [Double] {
    var largest = 0
    for j in vector.indices.dropFirst() where abs(vector[j]) > abs(vector[largest]) { largest = j }
    return vector[largest] < 0 ? vector.map { -$0 } : vector
}

func maxDifference(_ first: [Double], _ second: [Double]) -> Double { zip(first, second).map { abs($0 - $1) }.max()! }

func deflate(_ matrix: inout Matrix, _ value: Double, _ vector: [Double]) {
    for i in matrix.indices {
        for j in matrix[i].indices { matrix[i][j] = matrix[i][j] - value * vector[i] * vector[j] }
    }
}

func gaussJordan(_ matrix: Matrix) -> (inverse: Matrix, determinant: Double) {
    let size = matrix.count, unit = identity(matrix.count)
    var augmented = matrix.indices.map { matrix[$0] + unit[$0] }
    var determinant = 1.0
    for k in 0..<size {
        let pivot = augmented[k][k]
        determinant = determinant * pivot
        augmented[k] = augmented[k].map { $0 / pivot }
        for i in 0..<size where i != k {
            let gamma = augmented[i][k]
            for h in 0..<(2 * size) { augmented[i][h] = augmented[i][h] - gamma * augmented[k][h] }
        }
    }
    return (augmented.map { Array($0.dropFirst(size)) }, determinant)
}
