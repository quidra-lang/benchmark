import Foundation

enum SurvivalColumn {
    case survival, lower, upper
}

struct Percentile {
    let number: Int
    let time: Int?
    let lower: Int?
    let upper: Int?
}

struct RestrictedMean {
    let estimate: Double
    let error: Double
    var lower: Double { estimate - z95 * error }
    var upper: Double { estimate + z95 * error }
}

struct CollectionSummary {
    let rows: [KMRow]
    let life: [LifeRow]
    let subjects: Int
    let events: Int
    let maximum: Int
    let personDays: Int
    let rate: Double
    let rateLower: Double
    let rateUpper: Double
    let followup: Int?
    let lifeMedian: Double?
    let percentiles: [Percentile]
    let rmst: RestrictedMean
}

func number(_ value: Double?, digits: Int = 4) -> String {
    guard let value else { return "NA" }
    let text = String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    return text == "-0.0000" || text == "-0.0" ? String(text.dropFirst()) : text
}

func day(_ value: Int?) -> String { value.map(String.init) ?? "NA" }
func padded(_ text: String, _ width: Int) -> String { String(repeating: " ", count: max(0, width - text.count)) + text }

func percentileTime(_ rows: [KMRow], _ threshold: Double, _ column: SurvivalColumn = .survival) -> Int? {
    for row in rows {
        let value: Double?
        if row.survival == 0 { value = 0 }
        else {
            switch column {
            case .survival: value = row.survival
            case .lower: value = row.lower
            case .upper: value = row.upper
            }
        }
        if let value, value <= threshold { return row.time }
    }
    return nil
}

func restrictedMean(_ rows: [KMRow], _ tau: Int) -> RestrictedMean {
    let selected = rows.filter { $0.time <= tau }
    let times = [0] + selected.map { $0.time } + [tau]
    let survival = [1.0] + selected.map { $0.survival }
    let rectangles = survival.indices.map { survival[$0] * Double(times[$0 + 1] - times[$0]) }
    var tails = Array(repeating: 0.0, count: rectangles.count)
    tails[tails.count - 1] = rectangles.last!
    if tails.count >= 2 {
        for index in (0..<(tails.count - 1)).reversed() { tails[index] = rectangles[index] + tails[index + 1] }
    }
    var variance = 0.0
    for (index, row) in selected.enumerated() {
        variance += tails[index + 1] * tails[index + 1] * (Double(row.events) / Double(row.risk * (row.risk - row.events)))
    }
    return RestrictedMean(estimate: tails[0], error: sqrt(variance))
}

func collectionSummary(_ subjects: [Subject], _ parameters: Parameters) -> CollectionSummary {
    let rows = kaplanMeier(subjects)
    let life = lifeTable(subjects, parameters.lifeWidth, parameters.lifeCount)
    let events = subjects.reduce(0) { $0 + $1.event }
    let personDays = subjects.reduce(0) { $0 + $1.time }
    let rate = Double(1000 * events) / Double(personDays)
    let eta = z95 / sqrt(Double(events))
    let reverse = subjects.map { subject -> Subject in
        var result = subject
        result.event = 1 - subject.event
        return result
    }
    let followup = percentileTime(kaplanMeier(reverse), 0.5)
    var lifeMedian: Double?
    var previous = 1.0
    for row in life {
        if row.survival <= 0.5 {
            lifeMedian = Double(row.start) + Double(parameters.lifeWidth) * (previous - 0.5) / (previous - row.survival)
            break
        }
        previous = row.survival
    }
    let percentiles = [(25, 0.75), (50, 0.5), (75, 0.25)].map { percentile, threshold in
        Percentile(number: percentile, time: percentileTime(rows, threshold), lower: percentileTime(rows, threshold, .lower),
                    upper: percentileTime(rows, threshold, .upper))
    }
    return CollectionSummary(rows: rows, life: life, subjects: subjects.count, events: events, maximum: subjects.map { $0.time }.max()!,
                              personDays: personDays, rate: rate, rateLower: exp(log(rate) - eta), rateUpper: exp(log(rate) + eta),
                              followup: followup, lifeMedian: lifeMedian, percentiles: percentiles, rmst: restrictedMean(rows, parameters.tau))
}

func kmTableLines(_ name: String, _ subjects: [Subject], _ summary: CollectionSummary, _ parameters: Parameters) -> [String] {
    var lines = ["group \(name) subjects \(summary.subjects) events \(summary.events) censored \(summary.subjects - summary.events) max_time \(summary.maximum)",
                 "person_days \(summary.personDays) rate \(number(summary.rate)) lower \(number(summary.rateLower)) upper \(number(summary.rateUpper))",
                 "followup_median \(day(summary.followup))", "life_table_median \(number(summary.lifeMedian))"]
    for percentile in summary.percentiles {
        lines.append("percentile \(percentile.number) time \(day(percentile.time)) lower \(day(percentile.lower)) upper \(day(percentile.upper))")
    }
    let rmst = summary.rmst
    lines.append("rmst tau \(parameters.tau) estimate \(number(rmst.estimate)) se \(number(rmst.error)) lower \(number(rmst.lower)) upper \(number(rmst.upper))")
    for time in parameters.reportTimes {
        let row = rowAt(summary.rows, time)
        let risk = subjects.filter { $0.time >= time }.count
        let events = subjects.filter { $0.time <= time && $0.event == 1 }.count
        lines.append("at \(time) at_risk \(risk) events \(events) survival \(number(row.survival)) std_err \(number(row.error)) "
            + "lower \(number(row.lower)) upper \(number(row.upper)) cum_hazard \(number(row.hazard)) hazard_se \(number(row.hazardError))")
    }
    let columns = ["time", "at_risk", "events", "censored", "survival", "std_err", "lower", "upper", "cum_haz", "haz_se"]
    lines.append(columns.map { padded($0, 9) }.joined())
    for row in summary.rows {
        let fields = [String(row.time), String(row.risk), String(row.events), String(row.censored), number(row.survival),
                      number(row.error), number(row.lower), number(row.upper), number(row.hazard), number(row.hazardError)]
        lines.append(fields.map { padded($0, 9) }.joined())
    }
    return lines
}

func lifeTableLines(_ names: [String], _ summaries: [String: CollectionSummary]) -> [String] {
    var lines = ["group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard"]
    for name in names {
        for row in summaries[name]!.life {
            let fields = [name, "\(row.start)-\(row.end)", String(row.risk), String(row.events), String(row.withdrawn),
                          number(Double(row.exposedTwice) / 2, digits: 1), number(row.q), number(row.survival), number(row.error), number(row.hazard)]
            lines.append(fields.joined(separator: ","))
        }
    }
    return lines
}

func baselineSummary(_ name: String, _ subjects: [Subject]) -> String {
    let count = subjects.count
    let mean = Double(subjects.reduce(0) { $0 + $1.age }) / Double(count)
    let deviation = sqrt(total(subjects.map { (Double($0.age) - mean) * (Double($0.age) - mean) }) / Double(count - 1))
    let ages = subjects.map { $0.age }.sorted()
    let median = Double(ages[(count - 1) / 2] + ages[count / 2]) / 2
    let males = subjects.filter { $0.sex == "M" }.count
    let stages = (1...4).map { stage in subjects.filter { $0.stage == stage }.count }
    return "  group \(name) subjects \(count) age_mean \(number(mean)) age_sd \(number(deviation)) age_median \(number(median, digits: 1)) "
        + "male \(males) stage " + stages.map(String.init).joined(separator: " ")
}

func kruskalWallis(_ subjects: [Subject], _ groups: [String], _ collections: [String: [Subject]]) -> Double {
    let ranked = subjects.sorted { $0.age == $1.age ? $0.id < $1.id : $0.age < $1.age }
    var ranks: [Int: Double] = [:]
    var ties = 0
    var first = 0
    while first < ranked.count {
        var last = first + 1
        while last < ranked.count && ranked[last].age == ranked[first].age { last += 1 }
        let rank = Double(first + 1 + last) / 2
        for subject in ranked[first..<last] { ranks[subject.id] = rank }
        let size = last - first
        ties += size * size * size - size
        first = last
    }
    var weighted = 0.0
    for group in groups {
        let members = collections[group]!
        let rankSum = total(members.map { ranks[$0.id]! })
        weighted += rankSum * rankSum / Double(members.count)
    }
    let count = subjects.count
    let raw = 12 * weighted / Double(count * (count + 1)) - Double(3 * (count + 1))
    return raw / (1 - Double(ties) / Double(count * count * count - count))
}

func contingencyTest(_ subjects: [Subject], _ groups: [String], _ collections: [String: [Subject]],
                     _ variable: String) -> (statistic: Double, degrees: Int) {
    let levels = Set(subjects.map { $0.level(variable) }).sorted()
    let counts = levels.map { level in subjects.filter { $0.level(variable) == level }.count }
    var statistic = 0.0
    for group in groups {
        let members = collections[group]!
        for (index, level) in levels.enumerated() {
            let observed = members.filter { $0.level(variable) == level }.count
            let expected = Double(members.count * counts[index]) / Double(subjects.count)
            statistic += (Double(observed) - expected) * (Double(observed) - expected) / expected
        }
    }
    return (statistic, (groups.count - 1) * (levels.count - 1))
}

func baselineLines(_ subjects: [Subject], _ groups: [String], _ collections: [String: [Subject]]) -> [String] {
    var lines = ["baseline"] + (groups + ["all"]).map { baselineSummary($0, collections[$0]!) }
    let statistic = kruskalWallis(subjects, groups, collections)
    lines.append("  age kruskal_wallis chisq \(number(statistic)) df \(groups.count - 1) p \(number(chiSquareP(statistic, groups.count - 1)))")
    for variable in ["sex", "stage"] {
        let test = contingencyTest(subjects, groups, collections, variable)
        lines.append("  \(variable) chisq \(number(test.statistic)) df \(test.degrees) p \(number(chiSquareP(test.statistic, test.degrees)))")
    }
    return lines
}

func groupLines(_ test: GroupTest) -> [String] {
    test.totals.groups.indices.map { index in
        let observed = test.totals.observed[index]
        let expected = test.totals.expected[index]
        return "  group \(test.totals.groups[index]) events \(test.totals.events[index]) observed \(number(observed)) "
            + "expected \(number(expected)) o_minus_e \(number(observed - expected)) variance \(number(test.totals.covariance[index][index]))"
    }
}

func testFields(_ test: GroupTest) -> String { "chisq \(number(test.statistic)) df \(test.degrees) p \(number(test.p))" }

func overallLines(_ subjects: [Subject], _ groups: [String]) -> [String] {
    var lines: [String] = []
    let tests = TestWeight.allCases.map { weightedTest(subjects, groups, $0, subjects.count) }
    for (weight, test) in zip(TestWeight.allCases, tests) {
        lines.append("test \(weight.rawValue) \(testFields(test))")
        lines += groupLines(test)
    }
    let logrank = tests[0].totals
    let trend = total(groups.indices.map { Double($0 + 1) * (logrank.observed[$0] - logrank.expected[$0]) })
    let variance = total(groups.indices.map { g in
        total(groups.indices.map { h in Double((g + 1) * (h + 1)) * logrank.covariance[g][h] })
    })
    let statistic = trend * trend / variance
    lines.append("test logrank_trend chisq \(number(statistic)) df 1 p \(number(chiSquareP(statistic, 1)))")
    return lines
}

func stratifiedLines(_ subjects: [Subject], _ groups: [String], _ variable: String) -> [String] {
    let levels = Set(subjects.map { $0.level(variable) }).sorted()
    let strata = levels.map { level in subjects.filter { $0.level(variable) == level } }
    var lines: [String] = []
    for weight in TestWeight.allCases {
        let tests = strata.map { weightedTest($0, groups, weight, subjects.count) }
        let combined = combineStrata(tests, groups)
        lines.append("stratified \(weight.rawValue) by \(variable) \(testFields(combined))")
        for index in levels.indices {
            let events = strata[index].reduce(0) { $0 + $1.event }
            lines.append("  stratum \(levels[index]) subjects \(strata[index].count) events \(events) "
                + "chisq \(number(tests[index].statistic)) p \(number(tests[index].p))")
        }
        lines += groupLines(combined)
    }
    return lines
}

func landmarkLines(_ subjects: [Subject], _ groups: [String], _ landmark: Int) -> [String] {
    let selected = subjects.filter { $0.time > landmark }
    let test = weightedTest(selected, groups, .logrank, subjects.count)
    return ["landmark \(landmark) subjects \(selected.count) \(testFields(test))"] + groupLines(test)
}

struct TwoGroupComparison {
    let test: GroupTest
    let ratio: Double
    let logRatio: Double
    let variance: Double
    let lower: Double
    let upper: Double
}

func twoGroupComparison(_ subjects: [Subject], _ groups: [String], _ population: Int) -> TwoGroupComparison {
    let test = weightedTest(subjects, groups, .logrank, population)
    let observed = test.totals.observed
    let expected = test.totals.expected
    let ratio = (observed[1] / expected[1]) / (observed[0] / expected[0])
    let variance = 1 / expected[0] + 1 / expected[1]
    let logarithm = log(ratio)
    return TwoGroupComparison(test: test, ratio: ratio, logRatio: logarithm, variance: variance,
                               lower: exp(logarithm - z95 * sqrt(variance)), upper: exp(logarithm + z95 * sqrt(variance)))
}

func pairwiseLines(_ subjects: [Subject], _ groups: [String]) -> [String] {
    var pairs: [[String]] = []
    for first in groups.indices {
        for second in (first + 1)..<groups.count { pairs.append([groups[first], groups[second]]) }
    }
    let tests = pairs.map { pair in twoGroupComparison(subjects.filter { pair.contains($0.group) }, pair, subjects.count) }
    let order = tests.indices.sorted { tests[$0].test.p == tests[$1].test.p ? $0 < $1 : tests[$0].test.p < tests[$1].test.p }
    var adjusted = Array(repeating: 0.0, count: pairs.count)
    var previous = 0.0
    for (rank, index) in order.enumerated() {
        let candidate = Double(pairs.count - rank) * tests[index].test.p
        previous = max(previous, min(1, candidate))
        adjusted[index] = previous
    }
    var lines = ["pairwise logrank adjust holm"]
    for index in pairs.indices {
        let test = tests[index]
        lines.append("  \(pairs[index][0]) \(pairs[index][1]) chisq \(number(test.test.statistic)) p \(number(test.test.p)) "
            + "p_holm \(number(adjusted[index])) hr \(number(test.ratio)) lower \(number(test.lower)) upper \(number(test.upper))")
    }
    return lines
}

func subgroupLines(_ subjects: [Subject], _ groups: [String], _ variables: [String]) -> [String] {
    var lines = ["subgroups reference " + groups[0]]
    for variable in variables {
        let levels = Set(subjects.map { $0.level(variable) }).sorted()
        for group in groups.dropFirst() {
            var tests: [TwoGroupComparison] = []
            for level in levels {
                let selected = subjects.filter { $0.level(variable) == level && ($0.group == groups[0] || $0.group == group) }
                let test = twoGroupComparison(selected, [groups[0], group], subjects.count)
                tests.append(test)
                let events = selected.reduce(0) { $0 + $1.event }
                lines.append("  \(variable) \(level) \(group) subjects \(selected.count) events \(events) hr \(number(test.ratio)) "
                    + "lower \(number(test.lower)) upper \(number(test.upper)) p \(number(test.test.p))")
            }
            let weights = tests.map { 1 / $0.variance }
            let mean = total(tests.indices.map { weights[$0] * tests[$0].logRatio }) / total(weights)
            let statistic = total(tests.indices.map { weights[$0] * (tests[$0].logRatio - mean) * (tests[$0].logRatio - mean) })
            lines.append("  \(variable) \(group) heterogeneity chisq \(number(statistic)) df \(levels.count - 1) "
                + "p \(number(chiSquareP(statistic, levels.count - 1)))")
        }
    }
    return lines
}

func differenceFields(_ difference: Double, _ error: Double) -> String {
    let statistic = difference / error
    return "difference \(number(difference)) se \(number(error)) lower \(number(difference - z95 * error)) "
        + "upper \(number(difference + z95 * error)) z \(number(statistic)) p \(number(chiSquareP(statistic * statistic, 1)))"
}

func rmstDifferenceLines(_ groups: [String], _ summaries: [String: CollectionSummary], _ tau: Int) -> [String] {
    let control = summaries[groups[0]]!.rmst
    return ["rmst_difference tau \(tau) reference \(groups[0])"] + groups.dropFirst().map { group in
        let current = summaries[group]!.rmst
        return "  \(group) " + differenceFields(current.estimate - control.estimate,
                                               sqrt(current.error * current.error + control.error * control.error))
    }
}

func rateRatioLines(_ groups: [String], _ summaries: [String: CollectionSummary]) -> [String] {
    let control = summaries[groups[0]]!
    return ["rate_ratio reference " + groups[0]] + groups.dropFirst().map { group in
        let summary = summaries[group]!
        let ratio = summary.rate / control.rate
        let error = sqrt(1 / Double(summary.events) + 1 / Double(control.events))
        let logarithm = log(ratio)
        let statistic = logarithm / error
        return "  \(group) ratio \(number(ratio)) lower \(number(exp(logarithm - z95 * error))) "
            + "upper \(number(exp(logarithm + z95 * error))) z \(number(statistic)) p \(number(chiSquareP(statistic * statistic, 1)))"
    }
}

func survivalDifferenceLines(_ groups: [String], _ summaries: [String: CollectionSummary], _ times: [Int]) -> [String] {
    var lines = ["survival_difference reference " + groups[0]]
    for time in times {
        let control = rowAt(summaries[groups[0]]!.rows, time)
        for group in groups.dropFirst() {
            let row = rowAt(summaries[group]!.rows, time)
            let error = sqrt(row.error! * row.error! + control.error! * control.error!)
            lines.append("  at \(time) \(group) " + differenceFields(row.survival - control.survival, error))
        }
    }
    return lines
}

func comparisonSections(_ subjects: [Subject], _ parameters: Parameters, _ collections: [String: [Subject]],
                        _ summaries: [String: CollectionSummary]) -> [[String]] {
    let groups = parameters.groups
    return [baselineLines(subjects, groups, collections), overallLines(subjects, groups),
            stratifiedLines(subjects, groups, parameters.strata), landmarkLines(subjects, groups, parameters.landmark),
            pairwiseLines(subjects, groups), subgroupLines(subjects, groups, parameters.subgroups),
            rmstDifferenceLines(groups, summaries, parameters.tau), rateRatioLines(groups, summaries),
            survivalDifferenceLines(groups, summaries, parameters.reportTimes)]
}

func covariateVectors(_ subjects: [Subject], _ names: [String]) -> [[Int]] {
    subjects.map { subject in names.map { name in
        switch name {
        case "age": return subject.age
        case "male": return subject.sex == "M" ? 1 : 0
        case "stage": return subject.stage
        default: return subject.group == name ? 1 : 0
        }
    } }
}

func coefficientFields(_ coefficient: Double, _ error: Double) -> String {
    let statistic = coefficient / error
    return "coef \(number(coefficient)) se \(number(error)) z \(number(statistic)) p \(number(chiSquareP(statistic * statistic, 1))) "
        + "hr \(number(exp(coefficient))) lower \(number(exp(coefficient - z95 * error))) upper \(number(exp(coefficient + z95 * error)))"
}

func coefficientLines(_ names: [String], _ beta: [Double], _ covariance: Matrix) -> [String] {
    var lines = names.indices.map { "term \(names[$0]) " + coefficientFields(beta[$0], sqrt(covariance[$0][$0])) }
    let groups = names.indices.filter { !["age", "male", "stage"].contains(names[$0]) }
    for first in groups.indices {
        for second in (first + 1)..<groups.count {
            let a = groups[first]
            let b = groups[second]
            let coefficient = beta[b] - beta[a]
            let error = sqrt(covariance[b][b] + covariance[a][a] - 2 * covariance[a][b])
            lines.append("contrast \(names[b]) vs \(names[a]) " + coefficientFields(coefficient, error))
        }
    }
    return lines
}

func coxTestLines(_ subjects: [Subject], _ vectors: [[Int]], _ names: [String], _ model: CoxFit) -> [String] {
    let beta = model.beta
    let finalEvaluation = model.finalEvaluation
    let null = model.null
    let size = names.count
    let likelihoodRatio = 2 * (finalEvaluation.logLikelihood - null.logLikelihood)
    let wald = total(beta.indices.map { c in beta[c] * total(beta.indices.map { finalEvaluation.information[c][$0] * beta[$0] }) })
    let solution = solve(null.information, null.score)
    let score = total(beta.indices.map { null.score[$0] * solution[$0] })
    var lines = [("likelihood_ratio", likelihoodRatio), ("wald", wald), ("score", score)].map { name, statistic in
        "\(name) chisq \(number(statistic)) df \(size) p \(number(chiSquareP(statistic, size)))"
    }
    for column in names.indices {
        let likelihood: Double
        if size == 1 { likelihood = null.logLikelihood }
        else {
            let reduced = vectors.map { vector in vector.indices.filter { $0 != column }.map { vector[$0] } }
            likelihood = fitCox(subjects, reduced).finalEvaluation.logLikelihood
        }
        let statistic = 2 * (finalEvaluation.logLikelihood - likelihood)
        lines.append("drop \(names[column]) loglik \(number(likelihood)) chisq \(number(statistic)) df 1 p \(number(chiSquareP(statistic, 1)))")
    }
    return lines
}

func concordanceLine(_ subjects: [Subject], _ vectors: [[Int]], _ predictors: [Double]) -> String {
    var comparable = 0
    var concordant = 0
    var tied = 0
    for i in subjects.indices where subjects[i].event == 1 {
        for j in subjects.indices where i != j {
            if subjects[i].time < subjects[j].time || (subjects[i].time == subjects[j].time && subjects[j].event == 0) {
                comparable += 1
                if vectors[i] == vectors[j] { tied += 1 }
                else if predictors[i] > predictors[j] { concordant += 1 }
            }
        }
    }
    let value = Double(2 * concordant + tied) / Double(2 * comparable)
    return "concordance \(number(value)) comparable \(comparable) concordant \(concordant) tied \(tied)"
}

func proportionalHazardsLines(_ subjects: [Subject], _ vectors: [[Int]], _ names: [String], _ evaluation: CoxEvaluation) -> [String] {
    let events = subjects.indices.filter { subjects[$0].event == 1 }.sorted {
        subjects[$0].time == subjects[$1].time ? subjects[$0].id < subjects[$1].id : subjects[$0].time < subjects[$1].time
    }
    let count = events.count
    let meanTime = Double(events.reduce(0) { $0 + subjects[$1].time }) / Double(count)
    var lines: [String] = []
    for column in names.indices {
        let residuals = events.map { index -> Double in
            let sums = evaluation.eventSums[subjects[index].time]!
            return Double(vectors[index][column]) - sums.s1[column] / sums.s0
        }
        let meanResidual = total(residuals) / Double(count)
        var sxy = 0.0
        var sxx = 0.0
        var syy = 0.0
        for (index, residual) in zip(events, residuals) {
            let x = residual - meanResidual
            let y = Double(subjects[index].time) - meanTime
            sxy += x * y
            sxx += x * x
            syy += y * y
        }
        let correlation = sxy / sqrt(sxx * syy)
        let statistic = 0.5 * log((1 + correlation) / (1 - correlation)) * sqrt(Double(count - 3))
        lines.append("ph_check \(names[column]) rho \(number(correlation)) z \(number(statistic)) p \(number(chiSquareP(statistic * statistic, 1)))")
    }
    return lines
}

struct BaselineHazard {
    let time: Int
    let cumulative: Double
}

func baselineHazard(_ evaluation: CoxEvaluation) -> [BaselineHazard] {
    var cumulative = 0.0
    return evaluation.eventSums.keys.sorted().map { time in
        let sums = evaluation.eventSums[time]!
        cumulative += Double(sums.events) / sums.s0
        return BaselineHazard(time: time, cumulative: cumulative)
    }
}

func hazardAt(_ rows: [BaselineHazard], _ time: Int) -> Double { rows.last { $0.time <= time }?.cumulative ?? 0 }

func residualLines(_ subjects: [Subject], _ evaluation: CoxEvaluation, _ hazard: [BaselineHazard], _ count: Int) -> [String] {
    let residuals = subjects.indices.map { index -> (subject: Subject, martingale: Double, deviance: Double) in
        let subject = subjects[index]
        let martingale = Double(subject.event) - hazardAt(hazard, subject.time) * exp(evaluation.predictors[index])
        var deviance = subject.event == 1 ? sqrt(-2 * (martingale + log(1 - martingale))) : sqrt(-2 * martingale)
        if !(martingale > 0) { deviance = -deviance }
        return (subject, martingale, deviance)
    }.sorted { abs($0.deviance) == abs($1.deviance) ? $0.subject.id < $1.subject.id : abs($0.deviance) > abs($1.deviance) }
    return ["residuals top \(count)"] + residuals.prefix(count).map {
        "  id \($0.subject.id) group \($0.subject.group) time \($0.subject.time) event \($0.subject.event) "
            + "martingale \(number($0.martingale)) deviance \(number($0.deviance))"
    }
}

func adjustedSurvivalLines(_ vectors: [[Int]], _ names: [String], _ beta: [Double], _ groups: [String],
                           _ times: [Int], _ hazard: [BaselineHazard]) -> [String] {
    var means: [String: Double] = [:]
    var fields: [String] = []
    for column in names.indices where ["age", "male", "stage"].contains(names[column]) {
        let mean = Double(vectors.reduce(0) { $0 + $1[column] }) / Double(vectors.count)
        means[names[column]] = mean
        fields.append("\(names[column]) \(number(mean))")
    }
    var lines = ["adjusted_survival mean " + (fields.isEmpty ? "none" : fields.joined(separator: " "))]
    let risks = groups.map { group -> Double in
        let representative = names.map { means[$0] ?? ($0 == group ? 1 : 0) }
        return exp(total(beta.indices.map { beta[$0] * representative[$0] }))
    }
    for time in times {
        let cumulative = hazardAt(hazard, time)
        let values = groups.indices.map { "\(groups[$0]) \(number(exp(-cumulative * risks[$0])))" }
        lines.append("  at \(time) " + values.joined(separator: " "))
    }
    let medians = groups.indices.map { index -> String in
        let median = hazard.first { exp(-$0.cumulative * risks[index]) <= 0.5 }?.time
        return groups[index] + " " + day(median)
    }
    lines.append("  median " + medians.joined(separator: " "))
    return lines
}

func coxLines(_ subjects: [Subject], _ parameters: Parameters) -> [String] {
    let names = parameters.covariates
    let vectors = covariateVectors(subjects, names)
    let model = fitCox(subjects, vectors)
    let covariance = inverse(model.finalEvaluation.information)
    let events = subjects.reduce(0) { $0 + $1.event }
    var lines = ["cox covariates " + names.joined(separator: " ")
        + " subjects \(subjects.count) events \(events) event_times \(model.finalEvaluation.eventSums.count)"]
    for iteration in model.iterations {
        lines.append("iter \(iteration.number) loglik \(number(iteration.likelihood)) beta " + iteration.beta.map { number($0) }.joined(separator: " "))
    }
    lines.append("final loglik \(number(model.finalEvaluation.logLikelihood)) null_loglik \(number(model.null.logLikelihood))")
    lines += coefficientLines(names, model.beta, covariance)
    lines += coxTestLines(subjects, vectors, names, model)
    lines.append(concordanceLine(subjects, vectors, model.finalEvaluation.predictors))
    lines += proportionalHazardsLines(subjects, vectors, names, model.finalEvaluation)
    let hazard = baselineHazard(model.finalEvaluation)
    lines += residualLines(subjects, model.finalEvaluation, hazard, parameters.residuals)
    lines += adjustedSurvivalLines(vectors, names, model.beta, parameters.groups, parameters.reportTimes, hazard)
    return lines
}

func plotLines(_ parameters: Parameters, _ collections: [String: [Subject]], _ summaries: [String: CollectionSummary]) -> [String] {
    let groups = parameters.groups
    let legend = groups.indices.map { "\(String(UnicodeScalar(65 + $0)!)) \(groups[$0])" }.joined(separator: " ")
    let estimates = summaries.mapValues { $0.rows }
    var lines = ["km_plot width \(parameters.plotWidth) height \(parameters.plotHeight) time \(parameters.plotTime)", "legend " + legend]
    lines += curveLines(groups, collections, estimates, parameters.plotWidth, parameters.plotHeight, parameters.plotTime)
    lines.append("time 0 to \(parameters.plotTime) days, \(parameters.plotTime / parameters.plotWidth) days per column")
    let times = (0...parameters.plotDivisions).map { $0 * (parameters.plotTime / parameters.plotDivisions) }
    lines.append("at_risk " + times.map(String.init).joined(separator: " "))
    for group in groups {
        let counts = times.map { time in collections[group]!.filter { $0.time >= time }.count }
        lines.append(group + " " + counts.map(String.init).joined(separator: " "))
    }
    return lines
}

func joinSections(_ sections: [[String]]) -> [String] {
    var lines: [String] = []
    for section in sections {
        if !lines.isEmpty { lines.append("") }
        lines += section
    }
    return lines
}

func writeLines(_ filename: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + filename, atomically: true, encoding: .ascii)
}

let dataset = try readDataset()
let subjects = dataset.subjects
let parameters = dataset.parameters
let collectionNames = parameters.groups + ["all"]
var collections = Dictionary(uniqueKeysWithValues: parameters.groups.map { group in (group, subjects.filter { $0.group == group }) })
collections["all"] = subjects
let summaries = collections.mapValues { collectionSummary($0, parameters) }
let tables = collectionNames.map { kmTableLines($0, collections[$0]!, summaries[$0]!, parameters) }
try writeLines("km_tables.txt", joinSections(tables))
try writeLines("life_table.csv", lifeTableLines(collectionNames, summaries))
try writeLines("tests.txt", joinSections(comparisonSections(subjects, parameters, collections, summaries)))
try writeLines("cox.txt", coxLines(subjects, parameters))
try writeLines("km_plot.txt", plotLines(parameters, collections, summaries))
