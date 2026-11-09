struct CurveFlow { let days: Int; let amount: Double }
struct Pillar { let maturity: Int; let coupon: Int; let frequency: Int }

struct ZeroCurve {
    let days: [Int]
    let rates: [Double]

    func zeroRate(_ day: Int) -> Double {
        if day <= days[0] { return rates[0] }
        if day >= days[days.count - 1] { return rates[rates.count - 1] }
        let index = days.firstIndex { $0 >= day }!
        if days[index] == day { return rates[index] }
        let weight = Double(day - days[index - 1]) / Double(days[index] - days[index - 1])
        return rates[index - 1] + (rates[index] - rates[index - 1]) * weight
    }
    func discount(_ day: Int, spread: Double = 0) -> Double {
        let rate = zeroRate(day) + spread
        var growth = 1.0
        for _ in 0..<(day / 365) { growth *= 1 + rate }
        return 1 / (growth * (1 + rate * Double(day % 365) / 365))
    }
    func forward(start: Int, end: Int) -> Double { (discount(start) / discount(end) - 1) * 365 / Double(end - start) }
    func shifted(_ deltas: [Double]) -> ZeroCurve { ZeroCurve(days: days, rates: rates.indices.map { rates[$0] + deltas[$0] }) }
    func presentValue(_ flows: [CurveFlow], spread: Double = 0) -> Double {
        var total = 0.0
        for flow in flows { total += flow.amount * discount(flow.days, spread: spread) }
        return total
    }
    func zSpread(_ flows: [CurveFlow], target: Double) -> Double {
        bisection(low: -0.5, high: 0.5, target: target) { presentValue(flows, spread: $0) }
    }
}

func bootstrap(settlement: Int, pillars: [Pillar]) -> ZeroCurve {
    var days: [Int] = []
    var rates: [Double] = []
    for pillar in pillars {
        let dates = couponSchedule(issue: settlement, maturity: pillar.maturity, frequency: pillar.frequency)
        let flows = (1..<dates.count).map { index -> CurveFlow in
            let fraction = yearFraction("30/360", start: dates[index - 1], end: dates[index])
            let coupon = Double(pillar.coupon) * Double(fraction.numerator) / (10000 * Double(fraction.denominator))
            return CurveFlow(days: dates[index] - settlement, amount: coupon + (index == dates.count - 1 ? 1 : 0))
        }
        days.append(pillar.maturity - settlement)
        let rate = bisection(low: 0, high: 1, target: 1) { ZeroCurve(days: days, rates: rates + [$0]).presentValue(flows) }
        rates.append(rate)
    }
    return ZeroCurve(days: days, rates: rates)
}
