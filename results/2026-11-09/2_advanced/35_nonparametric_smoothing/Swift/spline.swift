struct SplineValues {
    let fitted: [Double]
    let gamma: [Double]
}

struct SplineSystem {
    let positions: [Int]
    let x: [Double]
    let penalty: Double
    let h: [Double]
    let d: [Double]
    let l1: [Double]
    let l2: [Double]

    init(_ positions: [Int], _ penalty: Double) {
        let x = positions.map { Double($0) / 100 }
        let h = (0..<(x.count - 1)).map { x[$0 + 1] - x[$0] }
        let size = positions.count - 2
        let a = (0..<size).map { 1 / h[$0] }
        let c = (0..<size).map { 1 / h[$0 + 1] }
        let b = (0..<size).map { -(a[$0] + c[$0]) }
        let diagonal = (0..<size).map { i in
            (h[i] + h[i + 1]) / 3 + penalty * (a[i] * a[i] + b[i] * b[i] + c[i] * c[i])
        }
        let first = (0..<max(0, size - 1)).map { i in h[i + 1] / 6 + penalty * c[i] * (b[i] + b[i + 1]) }
        let second = (0..<max(0, size - 2)).map { i in penalty * c[i] * c[i + 1] }
        var d = [Double](repeating: 0, count: size)
        var l1 = d
        var l2 = d
        for i in 0..<size {
            if i >= 2 { l2[i] = second[i - 2] / d[i - 2] }
            if i >= 1 {
                let correction = i >= 2 ? l2[i] * d[i - 2] * l1[i - 1] : 0
                l1[i] = (first[i - 1] - correction) / d[i - 1]
            }
            var value = diagonal[i]
            if i >= 1 { value -= l1[i] * l1[i] * d[i - 1] }
            if i >= 2 { value -= l2[i] * l2[i] * d[i - 2] }
            d[i] = value
        }
        self.positions = positions
        self.x = x
        self.penalty = penalty
        self.h = h
        self.d = d
        self.l1 = l1
        self.l2 = l2
    }

    func fitValues(_ values: [Double]) -> SplineValues {
        let n = values.count
        let size = n - 2
        var z = [Double](repeating: 0, count: size)
        for i in 0..<size {
            var value = (values[i + 2] - values[i + 1]) / h[i + 1] - (values[i + 1] - values[i]) / h[i]
            if i >= 1 { value -= l1[i] * z[i - 1] }
            if i >= 2 { value -= l2[i] * z[i - 2] }
            z[i] = value
        }
        var gamma = [Double](repeating: 0, count: n)
        for i in (0..<size).reversed() {
            var value = z[i] / d[i]
            if i + 1 < size { value -= l1[i + 1] * gamma[i + 2] }
            if i + 2 < size { value -= l2[i + 2] * gamma[i + 3] }
            gamma[i + 1] = value
        }
        var omega = [(gamma[1] - gamma[0]) / h[0]]
        for i in 1..<(n - 1) {
            omega.append((gamma[i + 1] - gamma[i]) / h[i] - (gamma[i] - gamma[i - 1]) / h[i - 1])
        }
        omega.append(0 - (gamma[n - 1] - gamma[n - 2]) / h[n - 2])
        let fitted = values.indices.map { values[$0] - penalty * omega[$0] }
        return SplineValues(fitted: fitted, gamma: gamma)
    }

    func evaluate(_ fit: SplineValues, _ position: Int) -> Double {
        let values = fit.fitted
        let gamma = fit.gamma
        let x0 = Double(position) / 100
        let index = positions.firstIndex { $0 >= position } ?? positions.count
        if index < positions.count && positions[index] == position { return values[index] }
        if index == 0 {
            let slope = (values[1] - values[0]) / h[0] - h[0] * gamma[1] / 6
            return values[0] - (x[0] - x0) * slope
        }
        if index == positions.count {
            let n = positions.count
            let slope = (values[n - 1] - values[n - 2]) / h[n - 2] + h[n - 2] * gamma[n - 2] / 6
            return values[n - 1] + (x0 - x[n - 1]) * slope
        }
        let i = index - 1
        let left = x0 - x[i]
        let right = x[i + 1] - x0
        return (left * values[i + 1] + right * values[i]) / h[i]
            - left * right * ((1 + left / h[i]) * gamma[i + 1] + (1 + right / h[i]) * gamma[i]) / 6
    }
}

final class SplineFit: Smoother {
    let system: SplineSystem
    let fit: SplineValues
    var fitted: [Double]? { fit.fitted }
    var basis: [SplineValues]?
    var leverage: [Double]?
    var edf: Double?

    init(_ positions: [Int], _ values: [Double], _ penalty: Double, _ diagnostics: Bool) {
        let system = SplineSystem(positions, penalty)
        self.system = system
        fit = system.fitValues(values)
        if diagnostics { prepareBasis() }
    }

    func prepareBasis() {
        if basis != nil { return }
        let n = system.positions.count
        let fits = (0..<n).map { i -> SplineValues in
            var unit = [Double](repeating: 0, count: n)
            unit[i] = 1
            return system.fitValues(unit)
        }
        basis = fits
        let diagonal = fits.enumerated().map { $0.element.fitted[$0.offset] }
        leverage = diagonal
        edf = orderedSum(diagonal)
    }

    func estimate(_ position: Int) -> Double? { system.evaluate(fit, position) }

    func weights(_ position: Int) -> [Double]? {
        prepareBasis()
        return basis!.map { system.evaluate($0, position) }
    }
}
