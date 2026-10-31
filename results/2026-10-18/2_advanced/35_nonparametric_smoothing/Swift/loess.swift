import Foundation

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
}

func cholesky(_ matrix: [[Double]]) -> [[Double]] {
    let count = matrix.count
    var lower = [[Double]](repeating: [Double](repeating: 0, count: count), count: count)
    for row in 0..<count {
        for column in 0...row {
            var sigma = matrix[row][column]
            for k in 0..<column { sigma -= lower[row][k] * lower[column][k] }
            lower[row][column] = row == column ? sqrt(sigma) : sigma / lower[column][column]
        }
    }
    return lower
}

func solve(_ lower: [[Double]], _ right: [Double]) -> [Double] {
    let count = right.count
    var intermediate = [Double](repeating: 0, count: count)
    for row in 0..<count {
        var value = right[row]
        for k in 0..<row { value -= lower[row][k] * intermediate[k] }
        intermediate[row] = value / lower[row][row]
    }
    var solution = [Double](repeating: 0, count: count)
    for row in (0..<count).reversed() {
        var value = intermediate[row]
        for k in (row + 1)..<count { value -= lower[k][row] * solution[k] }
        solution[row] = value / lower[row][row]
    }
    return solution
}

struct LocalFit {
    let value: Double
    let zeta0: Double
    let weights: [Double]
}

struct RobustRecord {
    let iteration: Int
    let scale: Double
    let zeroWeights: Int
    let change: Double
}

final class LoessFit: Smoother {
    let positions: [Int]
    let x: [Double]
    let y: [Double]
    let span: Int
    let degree: Int
    var rho: [Double]
    var records: [RobustRecord] = []
    var cache: [Int: LocalFit] = [:]
    var fitted: [Double]?
    var leverage: [Double]?
    var edf: Double?

    init(_ positions: [Int], _ values: [Double], _ span: Int, _ degree: Int, _ iterations: Int, _ diagnostics: Bool) {
        self.positions = positions
        x = positions.map { Double($0) / 100 }
        y = values
        self.span = span
        self.degree = degree
        rho = [Double](repeating: 1, count: positions.count)
        if diagnostics {
            var fits = positions.map(localFit)
            for iteration in 0..<iterations {
                let residuals = values.indices.map { values[$0] - fits[$0].value }
                let scale = median(residuals.map { abs($0) })
                for i in residuals.indices {
                    let u = residuals[i] / (6 * scale)
                    let v = 1 - u * u
                    rho[i] = abs(u) < 1 ? v * v : 0
                }
                let updated = positions.map(localFit)
                let change = fits.indices.map { abs(updated[$0].value - fits[$0].value) }.max()!
                records.append(RobustRecord(
                    iteration: iteration + 1, scale: scale, zeroWeights: rho.filter { $0 == 0 }.count, change: change
                ))
                fits = updated
            }
            for i in positions.indices { cache[positions[i]] = fits[i] }
            fitted = fits.map { $0.value }
            let diagonal = fits.indices.map { rho[$0] * fits[$0].zeta0 }
            leverage = diagonal
            edf = orderedSum(diagonal)
        }
    }

    func localFit(_ position: Int) -> LocalFit {
        let count = positions.count
        let q = span * count / 100
        let neighborhood = positions.indices.sorted { a, b in
            let first = abs(positions[a] - position)
            let second = abs(positions[b] - position)
            return first == second ? a < b : first < second
        }.prefix(q).sorted()
        let distance = neighborhood.map { abs(positions[$0] - position) }.max()!
        let size = degree + 1
        var matrix = [[Double]](repeating: [Double](repeating: 0, count: size), count: size)
        var right = [Double](repeating: 0, count: size)
        var rows: [(Int, Double, [Double])] = []
        for i in neighborhood {
            let a = Double(abs(positions[i] - position)) / Double(distance)
            let s = 1 - a * a * a
            let weight = s * s * s * rho[i]
            let delta = x[i] - Double(position) / 100
            let basis = degree == 1 ? [1, delta] : [1, delta, delta * delta]
            rows.append((i, weight, basis))
            for row in 0..<size {
                right[row] += weight * basis[row] * y[i]
                for column in 0..<size { matrix[row][column] += weight * basis[row] * basis[column] }
            }
        }
        let lower = cholesky(matrix)
        let beta = solve(lower, right)
        let zeta = solve(lower, [1] + [Double](repeating: 0, count: degree))
        var weights = [Double](repeating: 0, count: count)
        for (i, weight, basis) in rows {
            weights[i] = weight * orderedSum((0..<size).map { zeta[$0] * basis[$0] })
        }
        return LocalFit(value: beta[0], zeta0: zeta[0], weights: weights)
    }

    func evaluate(_ position: Int) -> LocalFit {
        if let fit = cache[position] { return fit }
        let fit = localFit(position)
        cache[position] = fit
        return fit
    }

    func estimate(_ position: Int) -> Double? { evaluate(position).value }
    func weights(_ position: Int) -> [Double]? { evaluate(position).weights }
}
