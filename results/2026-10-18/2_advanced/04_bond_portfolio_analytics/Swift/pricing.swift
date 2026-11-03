func bisection(low: Double, high: Double, target: Double, function: (Double) -> Double) -> Double {
    var lo = low
    var hi = high
    for _ in 0..<80 {
        let middle = (lo + hi) / 2
        if function(middle) > target { lo = middle } else { hi = middle }
    }
    return (lo + hi) / 2
}

struct RiskMeasures { let macaulay: Double; let modified: Double; let convexity: Double; let dv01: Double }

struct YieldPricer {
    let flows: [Int]
    let fraction: Double
    let frequency: Int
    let outstanding: Int

    func presentValues(_ rate: Double) -> [Double] {
        let first = 1 + fraction * rate / Double(frequency)
        let growth = 1 + rate / Double(frequency)
        var factor = 1.0
        return flows.map { flow in
            let value = Double(flow) / (first * factor)
            factor *= growth
            return value
        }
    }
    func dirty(_ rate: Double) -> Double {
        var total = 0.0
        for value in presentValues(rate) { total += value }
        return total * 100 / Double(outstanding)
    }
    func solve(_ target: Double) -> Double { bisection(low: 0, high: 1, target: target, function: dirty) }
    func inRange(_ target: Double) -> Bool { dirty(0) > target && target > dirty(1) }
    func risk(_ rate: Double) -> RiskMeasures {
        let growth = 1 + rate / Double(frequency)
        var total = 0.0
        var weighted = 0.0
        var curvature = 0.0
        for (index, value) in presentValues(rate).enumerated() {
            let years = (Double(index) + fraction) / Double(frequency)
            total += value
            weighted += years * value
            curvature += years * (years + 1 / Double(frequency)) * value
        }
        let macaulay = weighted / total
        return RiskMeasures(macaulay: macaulay, modified: macaulay / growth, convexity: curvature / (total * growth * growth), dv01: (dirty(rate - 0.0001) - dirty(rate + 0.0001)) / 2)
    }
}
