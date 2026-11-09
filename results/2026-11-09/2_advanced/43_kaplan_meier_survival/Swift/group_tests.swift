import Foundation

enum TestWeight: String, CaseIterable {
    case logrank, gehanWilcoxon = "gehan_wilcoxon", taroneWare = "tarone_ware"
}

struct TestTotals {
    let groups: [String]
    var events: [Int]
    var observed: [Double]
    var expected: [Double]
    var covariance: Matrix

    init(_ groups: [String]) {
        self.groups = groups
        events = Array(repeating: 0, count: groups.count)
        observed = Array(repeating: 0, count: groups.count)
        expected = observed
        covariance = Array(repeating: observed, count: groups.count)
    }
}

struct GroupTest {
    let totals: TestTotals
    let statistic: Double
    let degrees: Int
    let p: Double
}

func weightedTotals(_ subjects: [Subject], _ groups: [String], _ weight: TestWeight, _ populationSize: Int) -> TestTotals {
    var result = TestTotals(groups)
    let collections = groups.map { group in subjects.filter { $0.group == group } }
    let times = Set(subjects.filter { $0.event == 1 }.map { $0.time }).sorted()
    for time in times {
        let risk = collections.map { $0.filter { $0.time >= time }.count }
        let deaths = collections.map { $0.filter { $0.time == time && $0.event == 1 }.count }
        let n = risk.reduce(0, +)
        let d = deaths.reduce(0, +)
        let value: Double
        switch weight {
        case .logrank: value = 1
        case .gehanWilcoxon: value = Double(n) / Double(populationSize)
        case .taroneWare: value = sqrt(Double(n) / Double(populationSize))
        }
        for h in groups.indices {
            result.events[h] += deaths[h]
            result.observed[h] += value * Double(deaths[h])
            result.expected[h] += value * (Double(d * risk[h]) / Double(n))
            if n < 2 { continue }
            let factor = value * value * (Double(d * (n - d)) / Double((n - 1) * n * n))
            for other in groups.indices {
                let multiple = h == other ? risk[h] * (n - risk[h]) : -(risk[h] * risk[other])
                result.covariance[h][other] += factor * Double(multiple)
            }
        }
    }
    return result
}

func finishTest(_ totals: TestTotals) -> GroupTest {
    let degrees = totals.groups.count - 1
    let difference = (0..<degrees).map { totals.observed[$0] - totals.expected[$0] }
    let matrix = totals.covariance.prefix(degrees).map { Array($0.prefix(degrees)) }
    let solution = solve(matrix, difference)
    let statistic = total(zip(difference, solution).map { $0.0 * $0.1 })
    return GroupTest(totals: totals, statistic: statistic, degrees: degrees, p: chiSquareP(statistic, degrees))
}

func weightedTest(_ subjects: [Subject], _ groups: [String], _ weight: TestWeight, _ populationSize: Int) -> GroupTest {
    finishTest(weightedTotals(subjects, groups, weight, populationSize))
}

func combineStrata(_ strata: [GroupTest], _ groups: [String]) -> GroupTest {
    var result = TestTotals(groups)
    for stratum in strata {
        for h in groups.indices {
            result.events[h] += stratum.totals.events[h]
            result.observed[h] += stratum.totals.observed[h]
            result.expected[h] += stratum.totals.expected[h]
            for other in groups.indices { result.covariance[h][other] += stratum.totals.covariance[h][other] }
        }
    }
    return finishTest(result)
}
