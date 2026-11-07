import Foundation

let pi = 3.141592653589793
struct HarmonicConstant { let name: String; let speed: Double; let a: Double; let b: Double; let amplitude: Double; let phase: Double; let indexA: Int; let indexB: Int }
struct Model { let selected: [Constituent]; let coefficients: [Double]; let inverse: [[Double]]; let constants: [HarmonicConstant]
    var meanLevel: Double { coefficients[0] }
    var unknowns: Int { coefficients.count }
}
func angle(_ speed: Double, _ time: Double) -> Double { let degrees = speed * time, reduced = degrees - 360 * floor(degrees / 360); return reduced * pi / 180 }
func regressors(_ time: Double, _ selected: [Constituent]) -> [Double] { var vector = [1.0]; for constituent in selected { let theta = angle(constituent.speed, time); vector += [cos(theta), sin(theta)] }; return vector }
func solveWithInverse(_ matrix: [[Double]], _ right: [Double]) -> (coefficients: [Double], inverse: [[Double]]) {
    let count = matrix.count
    var augmented = matrix.indices.map { i in matrix[i] + [right[i]] + (0..<count).map { i == $0 ? 1.0 : 0 } }
    for column in 0..<count { var pivot = column; for row in (column + 1)..<count { if abs(augmented[row][column]) > abs(augmented[pivot][column]) { pivot = row } }; if pivot != column { augmented.swapAt(pivot, column) }; for row in (column + 1)..<count { let factor = augmented[row][column] / augmented[column][column]; for c in column...(2 * count) { augmented[row][c] -= factor * augmented[column][c] } } }
    var solutions: [[Double]] = []
    for column in count...(2 * count) { var solution = Array(repeating: 0.0, count: count); for i in stride(from: count - 1, through: 0, by: -1) { var current = augmented[i][column]; for j in (i + 1)..<count { current -= augmented[i][j] * solution[j] }; solution[i] = current / augmented[i][i] }; solutions.append(solution) }
    return (solutions[0], (0..<count).map { row in (0..<count).map { solutions[$0 + 1][row] } })
}
func fit(_ values: [Int: Double], _ times: [Int], _ selected: [Constituent]) -> Model {
    let count = 2 * selected.count + 1
    var matrix = Array(repeating: Array(repeating: 0.0, count: count), count: count), right = Array(repeating: 0.0, count: count)
    for time in times.sorted() { let vector = regressors(Double(time), selected), observed = values[time]!; for i in 0..<count { right[i] += vector[i] * observed; for j in 0..<count { matrix[i][j] += vector[i] * vector[j] } } }
    let solved = solveWithInverse(matrix, right)
    let constants = selected.enumerated().map { index, constituent -> HarmonicConstant in let ia = 2 * index + 1, ib = ia + 1, a = solved.coefficients[ia], b = solved.coefficients[ib], amplitude = sqrt(a * a + b * b); var phase = atan2(b, a) * 180 / pi; if phase < 0 { phase += 360 }; return HarmonicConstant(name: constituent.name, speed: constituent.speed, a: a, b: b, amplitude: amplitude, phase: phase, indexA: ia, indexB: ib) }
    return Model(selected: selected, coefficients: solved.coefficients, inverse: solved.inverse, constants: constants)
}
