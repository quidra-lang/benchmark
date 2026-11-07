struct KernelEstimate {
    let value: Double?
    let weights: [Double]?
}

final class KernelFit: Smoother {
    let positions: [Int]
    let x: [Double]
    let y: [Double]
    let bandwidth: Int
    let kernel: String
    let localLinear: Bool
    var cache: [Int: KernelEstimate] = [:]
    var fitted: [Double]?
    var leverage: [Double]?
    var edf: Double?

    init(_ positions: [Int], _ values: [Double], _ bandwidth: Int, _ kernel: String, _ localLinear: Bool, _ diagnostics: Bool) {
        self.positions = positions
        x = positions.map { Double($0) / 100 }
        y = values
        self.bandwidth = bandwidth
        self.kernel = kernel
        self.localLinear = localLinear
        if diagnostics {
            let pairs = positions.map(evaluate)
            if pairs.allSatisfy({ $0.value != nil }) {
                fitted = pairs.map { $0.value! }
                let diagonal = pairs.enumerated().map { $0.element.weights![$0.offset] }
                leverage = diagonal
                edf = orderedSum(diagonal)
            }
        }
    }

    func evaluate(_ position: Int) -> KernelEstimate {
        if let saved = cache[position] { return saved }
        let used = positions.indices.filter { abs(positions[$0] - position) < bandwidth }
        if used.count < (localLinear ? 2 : 1) {
            let result = KernelEstimate(value: nil, weights: nil)
            cache[position] = result
            return result
        }
        let x0 = Double(position) / 100
        let h = Double(bandwidth) / 100
        let kappa = ["epanechnikov": 0.75, "biweight": 0.9375, "triweight": 1.09375][kernel]!
        var kernelValues: [Double] = []
        var differences: [Double] = []
        for i in used {
            let delta = x[i] - x0
            let u = delta / h
            let t = 1 - u * u
            var weight = kappa * t
            if kernel != "epanechnikov" { weight *= t }
            if kernel == "triweight" { weight *= t }
            kernelValues.append(weight)
            differences.append(delta)
        }
        let s0 = orderedSum(kernelValues)
        let t0 = orderedSum(used.indices.map { kernelValues[$0] * y[used[$0]] })
        var weights = [Double](repeating: 0, count: positions.count)
        let value: Double
        if localLinear {
            let s1 = orderedSum(used.indices.map { kernelValues[$0] * differences[$0] })
            let s2 = orderedSum(used.indices.map { kernelValues[$0] * differences[$0] * differences[$0] })
            let t1 = orderedSum(used.indices.map { kernelValues[$0] * differences[$0] * y[used[$0]] })
            let determinant = s0 * s2 - s1 * s1
            value = (s2 * t0 - s1 * t1) / determinant
            for j in used.indices {
                weights[used[j]] = kernelValues[j] * (s2 - s1 * differences[j]) / determinant
            }
        } else {
            value = t0 / s0
            for j in used.indices { weights[used[j]] = kernelValues[j] / s0 }
        }
        let result = KernelEstimate(value: value, weights: weights)
        cache[position] = result
        return result
    }

    func estimate(_ position: Int) -> Double? { evaluate(position).value }
    func weights(_ position: Int) -> [Double]? { evaluate(position).weights }
}
