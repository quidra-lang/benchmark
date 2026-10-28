import Foundation

struct RiskSet {
    let time: Int
    let risk: Int
    let events: Int
    let censored: Int
}

struct KMRow {
    let time: Int
    let risk: Int
    let events: Int
    let censored: Int
    let survival: Double
    let error: Double?
    let lower: Double?
    let upper: Double?
    let hazard: Double
    let hazardError: Double
}

struct LifeRow {
    let start: Int
    let end: Int
    let risk: Int
    let events: Int
    let withdrawn: Int
    let exposedTwice: Int
    let q: Double
    let survival: Double
    let error: Double
    let hazard: Double
}

func riskSets(_ subjects: [Subject]) -> [RiskSet] {
    let atTimes = Dictionary(grouping: subjects, by: { $0.time })
    var risk = subjects.count
    var rows: [RiskSet] = []
    for time in atTimes.keys.sorted() {
        let members = atTimes[time]!
        let events = members.reduce(0) { $0 + $1.event }
        rows.append(RiskSet(time: time, risk: risk, events: events, censored: members.count - events))
        risk -= members.count
    }
    return rows
}

func kaplanMeier(_ subjects: [Subject]) -> [KMRow] {
    let eventTimes = riskSets(subjects).filter { $0.events > 0 }
    var survival = 1.0
    var greenwood: Double? = 0
    var hazard = 0.0
    var hazardVariance = 0.0
    var rows: [KMRow] = []
    for (index, row) in eventTimes.enumerated() {
        let n = row.risk
        let d = row.events
        survival *= Double(n - d) / Double(n)
        if n == d { greenwood = nil }
        else if let value = greenwood { greenwood = value + Double(d) / Double(n * (n - d)) }
        let error: Double?
        let lower: Double?
        let upper: Double?
        if survival == 0 { error = nil; lower = nil; upper = nil }
        else {
            error = survival * sqrt(greenwood!)
            let logarithm = log(survival)
            let omega = z95 * sqrt(greenwood!) / (-logarithm)
            lower = exp(logarithm * exp(omega))
            upper = exp(logarithm * exp(-omega))
        }
        hazard += Double(d) / Double(n)
        hazardVariance += Double(d) / Double(n * n)
        let nextTime = index + 1 < eventTimes.count ? eventTimes[index + 1].time : nil
        let censored = subjects.filter {
            $0.event == 0 && $0.time >= row.time && (nextTime == nil || $0.time < nextTime!)
        }.count
        rows.append(KMRow(time: row.time, risk: n, events: d, censored: censored, survival: survival,
                           error: error, lower: lower, upper: upper, hazard: hazard, hazardError: sqrt(hazardVariance)))
    }
    return rows
}

func rowAt(_ rows: [KMRow], _ time: Int) -> KMRow {
    rows.last { $0.time <= time } ?? KMRow(time: 0, risk: 0, events: 0, censored: 0, survival: 1,
                                         error: 0, lower: nil, upper: nil, hazard: 0, hazardError: 0)
}

func lifeTable(_ subjects: [Subject], _ width: Int, _ count: Int) -> [LifeRow] {
    var survival = 1.0
    var variance = 0.0
    var rows: [LifeRow] = []
    for interval in 0..<count {
        let start = interval * width
        let end = start + width
        let risk = subjects.filter { $0.time >= start }.count
        let events = subjects.filter { start <= $0.time && $0.time < end && $0.event == 1 }.count
        let withdrawn = subjects.filter { start <= $0.time && $0.time < end && $0.event == 0 }.count
        let f = 2 * risk - withdrawn
        survival *= Double(f - 2 * events) / Double(f)
        variance += Double(4 * events) / Double(f * (f - 2 * events))
        rows.append(LifeRow(start: start, end: end, risk: risk, events: events, withdrawn: withdrawn, exposedTwice: f,
                             q: Double(2 * events) / Double(f), survival: survival, error: survival * sqrt(variance),
                             hazard: Double(2000 * events) / Double(width * (f - events))))
    }
    return rows
}
