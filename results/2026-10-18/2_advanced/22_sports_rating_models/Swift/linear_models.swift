import Foundation

private func choleskySolve(_ matrix: [[Double]], _ vector: [Double]) -> [Double] {
    let size = vector.count
    var lower = Array(repeating: Array(repeating: 0.0, count: size), count: size)
    for i in 0..<size { for j in 0...i {
        var total = 0.0
        for k in 0..<j { total += lower[i][k] * lower[j][k] }
        lower[i][j] = j < i ? (matrix[i][j] - total) / lower[j][j] : sqrt(matrix[i][i] - total)
    } }
    var forward = Array(repeating: 0.0, count: size)
    for i in 0..<size {
        var total = 0.0
        for k in 0..<i { total += lower[i][k] * forward[k] }
        forward[i] = (vector[i] - total) / lower[i][i]
    }
    var solution = Array(repeating: 0.0, count: size)
    for i in (0..<size).reversed() {
        var total = 0.0
        for k in (i + 1)..<size { total += lower[k][i] * solution[k] }
        solution[i] = (forward[i] - total) / lower[i][i]
    }
    return solution
}
private func gaussianSolve(_ originalMatrix: [[Double]], _ originalVector: [Double]) -> [Double] {
    var matrix = originalMatrix
    var vector = originalVector
    let size = vector.count
    for k in 0..<size {
        var pivot = k
        for row in (k + 1)..<size where abs(matrix[row][k]) > abs(matrix[pivot][k]) { pivot = row }
        matrix.swapAt(k, pivot); vector.swapAt(k, pivot)
        for i in (k + 1)..<size {
            let factor = matrix[i][k] / matrix[k][k]
            for j in k..<size { let pivotValue = matrix[k][j]; matrix[i][j] -= factor * pivotValue }
            let pivotValue = vector[k]; vector[i] -= factor * pivotValue
        }
    }
    var solution = Array(repeating: 0.0, count: size)
    for i in (0..<size).reversed() {
        var total = 0.0
        for j in (i + 1)..<size { total += matrix[i][j] * solution[j] }
        solution[i] = (vector[i] - total) / matrix[i][i]
    }
    return solution
}
func colleyRatings(_ count: Int, _ matches: [Match]) -> [Double] {
    var matrix = Array(repeating: Array(repeating: 0.0, count: count), count: count)
    var balance = Array(repeating: 0, count: count)
    for team in 0..<count { matrix[team][team] = 2 }
    for match in matches {
        matrix[match.home][match.home] += 1; matrix[match.away][match.away] += 1; matrix[match.home][match.away] -= 1; matrix[match.away][match.home] -= 1
        let difference = match.margin > 0 ? 1 : (match.margin < 0 ? -1 : 0)
        balance[match.home] += difference; balance[match.away] -= difference
    }
    return choleskySolve(matrix, balance.map { 1 + Double($0) / 2 })
}
func masseyRatings(_ count: Int, _ matches: [Match]) -> ([Double], Double) {
    let size = count + 1
    var matrix = Array(repeating: Array(repeating: 0.0, count: size), count: size)
    var vector = Array(repeating: 0.0, count: size)
    for match in matches {
        let home = match.home, away = match.away
        matrix[home][home] += 1; matrix[away][away] += 1; matrix[home][away] -= 1; matrix[away][home] -= 1
        matrix[home][count] += 1; matrix[count][home] += 1; matrix[away][count] -= 1; matrix[count][away] -= 1; matrix[count][count] += 1
        vector[home] += Double(match.margin); vector[away] -= Double(match.margin); vector[count] += Double(match.margin)
    }
    matrix[count - 1] = Array(repeating: 1, count: size); matrix[count - 1][count] = 0; vector[count - 1] = 0
    let solution = gaussianSolve(matrix, vector)
    return (Array(solution.prefix(count)), solution[count])
}
