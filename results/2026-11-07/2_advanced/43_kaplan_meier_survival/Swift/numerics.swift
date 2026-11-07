import Foundation

let z95 = 1.959963984540054
typealias Matrix = [[Double]]

func total<S: Sequence>(_ values: S) -> Double where S.Element == Double {
    var result = 0.0
    for value in values { result += value }
    return result
}

func solve(_ matrix: Matrix, _ vector: [Double]) -> [Double] {
    var a = matrix
    var b = vector
    let size = b.count
    for k in 0..<size {
        for i in (k + 1)..<size {
            let factor = a[i][k] / a[k][k]
            for j in k..<size { a[i][j] = a[i][j] - factor * a[k][j] }
            b[i] = b[i] - factor * b[k]
        }
    }
    var solution = Array(repeating: 0.0, count: size)
    for i in (0..<size).reversed() {
        var value = b[i]
        for j in (i + 1)..<size { value = value - a[i][j] * solution[j] }
        solution[i] = value / a[i][i]
    }
    return solution
}

func inverse(_ matrix: Matrix) -> Matrix {
    let size = matrix.count
    var result = Array(repeating: Array(repeating: 0.0, count: size), count: size)
    for column in 0..<size {
        var unit = Array(repeating: 0.0, count: size)
        unit[column] = 1
        let solution = solve(matrix, unit)
        for row in 0..<size { result[row][column] = solution[row] }
    }
    return result
}

func logGamma(_ a: Double) -> Double {
    let coefficients = [76.18009172947146, -86.50532032941677, 24.01409824083091,
                        -1.231739572450155, 0.001208650973866179, -0.000005395239384953]
    let initial = a + 5.5
    let xi = initial - (a + 0.5) * log(initial)
    var sigma = 1.000000000190015
    var y = a
    for coefficient in coefficients {
        y += 1
        sigma += coefficient / y
    }
    return -xi + log(2.5066282746310005 * sigma / a)
}

func gammaQ(_ a: Double, _ x: Double) -> Double {
    if x == 0 { return 1 }
    let prefactor = exp(-x + a * log(x) - logGamma(a))
    if x < a + 1 {
        var alpha = a
        var term = 1 / a
        var sigma = term
        for _ in 0..<1000 {
            alpha += 1
            term *= x / alpha
            sigma += term
            if abs(term) < abs(sigma) * 1e-15 { break }
        }
        return 1 - sigma * prefactor
    }
    let epsilon = 1e-300
    var b = x + 1 - a
    var c = 1 / epsilon
    var d = 1 / b
    var h = d
    for index in 1...1000 {
        let i = Double(index)
        let an = -i * (i - a)
        b += 2
        d = an * d + b
        if abs(d) < epsilon { d = epsilon }
        c = b + an / c
        if abs(c) < epsilon { c = epsilon }
        d = 1 / d
        let delta = d * c
        h *= delta
        if abs(delta - 1) < 1e-15 { break }
    }
    return prefactor * h
}

func chiSquareP(_ statistic: Double, _ degrees: Int) -> Double { gammaQ(Double(degrees) / 2, statistic / 2) }
