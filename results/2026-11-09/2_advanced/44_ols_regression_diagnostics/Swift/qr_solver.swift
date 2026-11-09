import Foundation

typealias Matrix = [[Double]]

func orderedSum<S: Sequence>(_ values: S) -> Double where S.Element == Double {
    var result = 0.0
    for value in values { result = result + value }
    return result
}

struct Fit {
    let matrix: Matrix
    let response: [Double]
    let weights: [Double]
    let accepted: [Int]
    let aliases: [Int]
    let triangular: Matrix
    let effects: [Double]
    let beta: [Double?]
    let inverse: Matrix
    let variance: [Double]
    let u: Matrix
    let g: Matrix
    let leverage: [Double]
    let fitted: [Double]
    let residual: [Double]
    let weightedResidual: [Double]
    let rss: Double
    var n: Int { matrix.count }
    var p: Int { matrix[0].count }
    var rank: Int { accepted.count }

    init(_ matrix: Matrix, _ response: [Double], _ weights: [Double], _ tolerance: Double) {
        let n = matrix.count
        let p = matrix[0].count
        let roots = weights.map(sqrt)
        let weighted = matrix.indices.map { i in matrix[i].map { roots[i] * $0 } }
        let lengths = (0..<p).map { j in sqrt(orderedSum((0..<n).map { weighted[$0][j] * weighted[$0][j] })) }
        var work = weighted
        var transformed = response.indices.map { roots[$0] * response[$0] }
        var triangular = Array(repeating: Array(repeating: 0.0, count: p), count: p)
        var accepted: [Int] = []
        var aliases: [Int] = []
        for j in 0..<p {
            let k = accepted.count
            let eta = sqrt(orderedSum((k..<n).map { work[$0][j] * work[$0][j] }))
            if eta <= tolerance * lengths[j] { aliases.append(j); continue }
            accepted.append(j)
            let alpha = work[k][j] >= 0 ? -eta : eta
            let vector = [work[k][j] - alpha] + ((k + 1)..<n).map { work[$0][j] }
            let squaredLength = orderedSum(vector.map { $0 * $0 })
            for l in 0..<k { triangular[l][k] = work[l][j] }
            triangular[k][k] = alpha
            for l in (j + 1)..<p {
                let product = orderedSum((k..<n).map { vector[$0 - k] * work[$0][l] })
                let delta = 2 * product / squaredLength
                for i in k..<n { work[i][l] = work[i][l] - delta * vector[i - k] }
            }
            let product = orderedSum((k..<n).map { vector[$0 - k] * transformed[$0] })
            let delta = 2 * product / squaredLength
            for i in k..<n { transformed[i] = transformed[i] - delta * vector[i - k] }
        }
        let r = accepted.count
        let rMatrix = triangular.prefix(r).map { Array($0.prefix(r)) }
        let effects = Array(transformed.prefix(r))
        var beta = Array<Double?>(repeating: nil, count: p)
        for k in (0..<r).reversed() {
            let tail = orderedSum(((k + 1)..<r).map { rMatrix[k][$0] * beta[accepted[$0]]! })
            beta[accepted[k]] = (effects[k] - tail) / rMatrix[k][k]
        }
        var inverse = Array(repeating: Array(repeating: 0.0, count: r), count: r)
        for m in 0..<r {
            for l in (0..<r).reversed() {
                let diagonal = l == m ? 1.0 : 0.0
                let tail = orderedSum(((l + 1)..<r).map { rMatrix[l][$0] * inverse[$0][m] })
                inverse[l][m] = (diagonal - tail) / rMatrix[l][l]
            }
        }
        let variance = inverse.map { orderedSum($0.map { $0 * $0 }) }
        var u: Matrix = []
        var g: Matrix = []
        var leverage: [Double] = []
        var fitted: [Double] = []
        var residual: [Double] = []
        var weightedResidual: [Double] = []
        for i in 0..<n {
            let values = (0..<r).map { k in orderedSum((0..<r).map { weighted[i][accepted[$0]] * inverse[$0][k] }) }
            u.append(values)
            leverage.append(orderedSum(values.map { $0 * $0 }))
            g.append((0..<r).map { k in orderedSum((0..<r).map { inverse[k][$0] * values[$0] }) })
            let prediction = orderedSum((0..<r).map { matrix[i][accepted[$0]] * beta[accepted[$0]]! })
            let error = response[i] - prediction
            fitted.append(prediction)
            residual.append(error)
            weightedResidual.append(roots[i] * error)
        }
        self.matrix = matrix
        self.response = response
        self.weights = weights
        self.accepted = accepted
        self.aliases = aliases
        self.triangular = rMatrix
        self.effects = effects
        self.beta = beta
        self.inverse = inverse
        self.variance = variance
        self.u = u
        self.g = g
        self.leverage = leverage
        self.fitted = fitted
        self.residual = residual
        self.weightedResidual = weightedResidual
        rss = orderedSum(weightedResidual.map { $0 * $0 })
    }
}
