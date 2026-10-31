import Foundation

let groupNames = ["mean", "median", "trimmed_mean", "sd"]
let pairNames = ["mean_diff", "median_ratio", "hodges_lehmann", "cohen_d"]
let testNames = ["mean", "median", "ranksum", "absdev"]

struct Summary {
    let estimate: Double
    let values: [Double]
    let ordered: [Double]
    let se: Double
    let bias: Double
    let low: Double
    let high: Double
    let basicLow: Double
    let basicHigh: Double

    init(_ estimate: Double, _ values: [Double], _ ranks: [Int]) {
        let spread = meanAndSE(values)
        let sorted = values.sorted()
        self.estimate = estimate
        self.values = values
        ordered = sorted
        se = spread.se
        bias = spread.average - estimate
        low = sorted[ranks[0] - 1]
        high = sorted[ranks[1] - 1]
        basicLow = 2 * estimate - sorted[ranks[1] - 1]
        basicHigh = 2 * estimate - sorted[ranks[0] - 1]
    }

    func csvLine(_ name: String, _ statistic: String) -> String {
        ([name, statistic] + [estimate, se, bias, low, high, basicLow, basicHigh].map(real)).joined(separator: ",")
    }

    var intervalText: String {
        "se \(real(se)) bias \(real(bias)) percentile \(real(low)) \(real(high)) basic \(real(basicLow)) \(real(basicHigh))"
    }
}

struct GroupBootstrap {
    let group: Int
    let indices: [[Int]]
    let samples: [[Int64]]
    let summaries: [Summary]

    init(_ group: Int, _ values: [Int64], _ indices: [[Int]], _ ranks: [Int]) {
        let samples = indices.map { replicate in replicate.map { values[$0] } }
        let estimates = groupStatistics(values)
        let statistics = samples.map(groupStatistics)
        self.group = group
        self.indices = indices
        self.samples = samples
        summaries = (0..<4).map { column in Summary(estimates[column], statistics.map { $0[column] }, ranks) }
    }
}

struct PairBootstrap {
    let first: Int
    let second: Int
    let name: String
    let summaries: [Summary]
}

struct Jackknife {
    let values: [Double]
    let average: Double
    let variance: Double
    let bias: Double

    init(_ estimate: Double, _ values: [Double]) {
        let spread = jackknifeSpread(values)
        self.values = values
        average = spread.average
        variance = spread.variance
        bias = Double(values.count - 1) * (spread.average - estimate)
    }
}

struct Tally {
    let observed: Int64
    var extreme = 0
    var greater = 0

    mutating func count(_ value: Int64) {
        if abs(value) >= abs(observed) { extreme += 1 }
        if value >= observed { greater += 1 }
    }

    func text(_ offset: Int, _ denominator: Int) -> String {
        "extreme \(extreme) greater \(greater) p_two \(pValue(extreme + offset, denominator)) p_greater \(pValue(greater + offset, denominator))"
    }
}

struct DisplayRange {
    let low: Int64
    let delta: Int64

    init(_ values: [Int64]) {
        let minimum = values.min()!
        low = minimum
        delta = 100 * (values.max()! - minimum)
    }

    func position(_ value: Int64) -> Int { Int((120 * (value - 100 * low) + delta) / (2 * delta)) }
}

func jackknifeSpread(_ values: [Double]) -> (average: Double, variance: Double) {
    let count = Double(values.count)
    let average = sequentialSum(values) / count
    let squares = sequentialSum(values.map { ($0 - average) * ($0 - average) })
    return (average, (count - 1) * squares / count)
}

func seriesLines(_ kind: String, _ name: String, _ values: [Int64], _ display: DisplayRange, _ withStems: Bool) -> [String] {
    let count = values.count
    let average = mean(values)
    let deviation = sd(values)
    let moments = centralMoments(values)
    let clipped = winsorized(values)
    let first = quantileNumerator(values, 25)
    let third = quantileNumerator(values, 75)
    let outliers = values.indices.filter { 200 * values[$0] < 5 * first - 3 * third || 200 * values[$0] > 5 * third - 3 * first }
    let inside = values.indices.filter { !outliers.contains($0) }.map { values[$0] }
    let low = inside.min()!
    let high = inside.max()!
    var band = Array(repeating: Character("."), count: 61)
    for position in display.position(100 * low)...display.position(100 * high) { band[position] = "-" }
    for position in display.position(first)...display.position(third) { band[position] = "=" }
    band[display.position(quantileNumerator(values, 50))] = "|"
    for index in outliers { band[display.position(100 * values[index])] = "o" }
    let percentiles = [(5, "p05"), (10, "p10"), (90, "p90"), (95, "p95")].map { percent, label in
        "\(label) \(real(Double(quantileNumerator(values, percent)) / 10000))"
    }.joined(separator: " ")
    var lines = ["\(kind) \(name)", "n \(count)", "mean \(real(average))", "median \(real(median(values)))",
        "trimmed_mean \(real(trimmedMean(values))) trim \(trimCount(count))",
        "winsorized_mean \(real(mean(clipped))) winsorized_sd \(real(sd(clipped)))", "sd \(real(deviation))",
        "se_mean \(real(deviation / sqrt(Double(count))))", "cv \(real(deviation / average))",
        "skewness \(real(moments[1] / (moments[0] * sqrt(moments[0]))))",
        "kurtosis \(real(moments[2] / (moments[0] * moments[0]) - 3))", "mad \(real(mad(values)))",
        "min \(real(Double(values.min()!) / 100))", "q1 \(real(Double(first) / 10000))",
        "q3 \(real(Double(third) / 10000))", "iqr \(real(Double(third - first) / 10000))",
        "max \(real(Double(values.max()!) / 100))", "percentiles \(percentiles)",
        "whiskers \(real(Double(low) / 100)) \(real(Double(high) / 100))",
        "outliers \(numberList(outliers.map { $0 + 1 }))", "box \(String(band))"]
    if withStems {
        let ordered = values.sorted()
        for stem in (ordered.first! / 100)...(ordered.last! / 100) {
            let leaves = ordered.filter { $0 / 100 == stem }.map { String(($0 % 100) / 10) }.joined()
            lines.append(leaves.isEmpty ? "stem \(stem)" : "stem \(stem) \(leaves)")
        }
    }
    return lines
}

func splitStatistics(_ values: [Int64], _ ranks: [Int64], _ order: [Int], _ size: Int) -> [Int64] {
    let first = order.prefix(size).map { values[$0] }
    let second = order.dropFirst(size).map { values[$0] }
    let firstCenter = doubledMedian(first)
    let secondCenter = doubledMedian(second)
    let rankTotal = order.prefix(size).reduce(Int64(0)) { $0 + ranks[$1] }
    let firstDeviation = first.reduce(Int64(0)) { $0 + abs(2 * $1 - firstCenter) }
    let secondDeviation = second.reduce(Int64(0)) { $0 + abs(2 * $1 - secondCenter) }
    return [contrast(total(first), first.count, total(second), second.count), firstCenter - secondCenter,
        rankTotal - Int64(first.count * (first.count + second.count + 1)),
        contrast(firstDeviation, first.count, secondDeviation, second.count)]
}

func groupDeltas(_ samples: [[Int64]], _ pairs: [(Int, Int)]) -> [(Int64, Int64)] {
    pairs.map { first, second in
        (abs(contrast(total(samples[first]), samples[first].count, total(samples[second]), samples[second].count)),
            Int64(samples[first].count * samples[second].count))
    }
}

func deltaAtLeast(_ first: (Int64, Int64), _ second: (Int64, Int64)) -> Bool { first.0 * second.1 >= second.0 * first.1 }

func hyperbolicTangent(_ value: Double) -> Double {
    let growth = exp(2 * value)
    return (growth - 1) / (growth + 1)
}

final class Study {
    let data: Dataset
    var generator: Minstd
    let ranks: [Int]
    let zLow: Double

    init(_ data: Dataset) {
        self.data = data
        generator = Minstd(state: data.settings.seed)
        let low = (data.settings.bootstrap + 1) * (100 - data.settings.confidence) / 200
        ranks = [low, data.settings.bootstrap + 1 - low]
        zLow = phiInverse(Double(100 - data.settings.confidence) / 200)
    }

    func descriptiveLines() -> [String] {
        let everything = data.groups.flatMap(\.values)
        var lines = ["groups \(data.groups.count) observations \(everything.count)"]
        let display = DisplayRange(everything)
        for group in data.groups { lines += seriesLines("group", group.name, group.values, display, true) }
        let paired = data.paired
        lines.append("paired subjects \(paired.differences.count)")
        let pairedDisplay = DisplayRange(paired.before + paired.after)
        lines += seriesLines("series", "before", paired.before, pairedDisplay, false)
        lines += seriesLines("series", "after", paired.after, pairedDisplay, false)
        lines += seriesLines("series", "diff", paired.differences, DisplayRange(paired.differences), false)
        return lines
    }

    func pairedBootstrap() -> (Summary, Summary) {
        let paired = data.paired
        var means: [Double] = []
        var correlations: [Double] = []
        for indices in ordinaryIndices(&generator, paired.differences.count, data.settings.bootstrap) {
            means.append(mean(indices.map { paired.differences[$0] }))
            correlations.append(correlation(indices.map { paired.before[$0] }, indices.map { paired.after[$0] }))
        }
        return (Summary(mean(paired.differences), means, ranks), Summary(correlation(paired.before, paired.after), correlations, ranks))
    }

    func histogramLines(_ name: String, _ statistic: String, _ summary: Summary) -> [String] {
        let bins = data.settings.bins
        let low = summary.ordered.first!
        let high = summary.ordered.last!
        var counts = Array(repeating: 0, count: bins)
        for value in summary.values { counts[binNumber(value, low, high, bins)] += 1 }
        let top = counts.max()!
        var marks = Array(repeating: [String](), count: bins)
        marks[binNumber(summary.low, low, high, bins)].append("L")
        var estimateBin = "none"
        if low <= summary.estimate && summary.estimate <= high {
            let index = binNumber(summary.estimate, low, high, bins)
            marks[index].append("E")
            estimateBin = String(index + 1)
        }
        marks[binNumber(summary.high, low, high, bins)].append("H")
        let convergence = (1...4).map { quarter -> String in
            let size = quarter * data.settings.bootstrap / 4
            return "\(size):\(real(meanAndSE(Array(summary.values.prefix(size))).se))"
        }.joined(separator: " ")
        var lines = ["histogram \(name) \(statistic) min \(real(low)) max \(real(high)) width \(real((high - low) / Double(bins))) top \(top) estimate_bin \(estimateBin)",
            "convergence \(convergence)"]
        for (index, count) in counts.enumerated() {
            var parts = ["bin", String(index + 1), real(low + (high - low) * Double(index) / Double(bins)), String(count)]
            if count > 0 { parts.append(bar(count, top)) }
            parts += marks[index]
            lines.append(parts.joined(separator: " "))
        }
        return lines
    }

    func bcaLine(_ statistic: String, _ summary: Summary, _ jackknife: Jackknife) -> String {
        let count = data.settings.bootstrap
        let below = summary.values.filter { $0 < summary.estimate }.count
        let z0 = phiInverse(Double(below) / Double(count))
        let deviations = jackknife.values.map { jackknife.average - $0 }
        let squares = sequentialSum(deviations.map { $0 * $0 })
        let cubes = sequentialSum(deviations.map { $0 * $0 * $0 })
        let acceleration = cubes / (6 * squares * sqrt(squares))
        func alpha(_ z: Double) -> Double { phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z))) }
        let low = min(max(Int(floor(Double(count + 1) * alpha(zLow))), 1), count)
        let high = min(max(count + 1 - Int(floor(Double(count + 1) * (1 - alpha(-zLow)))), 1), count)
        return "bca \(statistic) below \(below) z0 \(real(z0)) acceleration \(real(acceleration)) ranks \(low) \(high) interval \(real(summary.ordered[low - 1])) \(real(summary.ordered[high - 1]))"
    }

    func groupJackknifeLines(_ bootstrap: GroupBootstrap) -> [String] {
        let group = data.groups[bootstrap.group]
        let values = group.values
        let count = values.count
        let statistics = (0..<count).map { groupStatistics(without(values, $0)) }
        let jackknives = (0..<4).map { column in Jackknife(bootstrap.summaries[column].estimate, statistics.map { $0[column] }) }
        var lines = ["group \(group.name) n \(count)"]
        for column in 0..<4 {
            let jackknife = jackknives[column]
            lines.append("jackknife \(groupNames[column]) estimate \(real(bootstrap.summaries[column].estimate)) average \(real(jackknife.average)) bias \(real(jackknife.bias)) se \(real(sqrt(jackknife.variance)))")
        }
        for column in 0..<4 { lines.append(bcaLine(groupNames[column], bootstrap.summaries[column], jackknives[column])) }
        let omitted = (0..<count).map { index in bootstrap.indices.indices.filter { !bootstrap.indices[$0].contains(index) } }
        let errors = (0..<4).map { column in
            omitted.map { replicates in meanAndSE(replicates.map { bootstrap.summaries[column].values[$0] }).se }
        }
        for column in 0..<4 {
            let spread = jackknifeSpread(errors[column])
            lines.append("after_bootstrap \(groupNames[column]) se \(real(bootstrap.summaries[column].se)) average \(real(spread.average)) se_of_se \(real(sqrt(spread.variance)))")
        }
        let sizes = omitted.map { $0.count }
        lines.append("without min \(sizes.min()!) max \(sizes.max()!)")
        let sum = total(values)
        let ranking = values.indices.sorted {
            let first = abs(Int64(count) * values[$0] - sum)
            let second = abs(Int64(count) * values[$1] - sum)
            return first == second ? $0 < $1 : first > second
        }
        for (rank, index) in ranking.prefix(5).enumerated() {
            let influence = Double(count - 1) * (jackknives[0].average - jackknives[0].values[index])
            let summary = bootstrap.summaries[0]
            let shifted = omitted[index].map { summary.values[$0] - summary.estimate }.sorted()
            let quantiles = [5, 50, 95].map { real(shifted[($0 * sizes[index] + 99) / 100 - 1]) }
            lines.append("influence \(rank + 1) obs \(index + 1) value \(real(Double(values[index]) / 100)) l \(real(influence)) without \(sizes[index]) se \(real(errors[0][index])) q05 \(quantiles[0]) q50 \(quantiles[1]) q95 \(quantiles[2])")
        }
        return lines
    }

    func pairJackknifeLines(_ pair: PairBootstrap) -> [String] {
        let x = data.groups[pair.first].values
        let y = data.groups[pair.second].values
        let first = x.indices.map { pairStatistics(without(x, $0), y) }
        let second = y.indices.map { pairStatistics(x, without(y, $0)) }
        return (0..<4).map { column in
            let estimate = pair.summaries[column].estimate
            let first = Jackknife(estimate, first.map { $0[column] })
            let second = Jackknife(estimate, second.map { $0[column] })
            var bias = 0.0
            bias += first.bias
            bias += second.bias
            var variance = 0.0
            variance += first.variance
            variance += second.variance
            return "pair \(pair.name) \(pairNames[column]) estimate \(real(estimate)) bias \(real(bias)) se \(real(sqrt(variance)))"
        }
    }

    func permutationLines(_ x: [Int64], _ y: [Int64]) -> (lines: [String], extremes: [Int]) {
        let permutations = data.settings.permutations
        let combined = x + y
        let ranks = doubledRanks(combined)
        let positions = Array(combined.indices)
        let observed = splitStatistics(combined, ranks, positions, x.count)
        var tallies = observed.map { Tally(observed: $0) }
        for _ in 0..<permutations {
            var order = positions
            generator.shuffle(&order)
            let values = splitStatistics(combined, ranks, order, x.count)
            for column in 0..<4 { tallies[column].count(values[column]) }
        }
        let k = x.count
        let m = y.count
        let rankTotal = total(Array(ranks.prefix(k)))
        let results = tallies.map { $0.text(1, permutations + 1) }
        return (["permutation n \(k) \(m) perms \(permutations)", "mean diff \(real(meanDifference(x, y))) \(results[0])",
            "median diff \(real(Double(observed[1]) / 200)) \(results[1])",
            "ranksum w \(real(Double(rankTotal) / 2)) u \(real(Double(rankTotal - Int64(k * (k + 1))) / 2)) \(results[2])",
            "absdev diff \(real(Double(observed[3]) / Double(200 * k * m))) \(results[3])"], tallies.map(\.extreme))
    }

    func powerLine(_ x: [Int64], _ y: [Int64]) -> String {
        let settings = data.settings
        let k = x.count
        let m = y.count
        var rejections = 0
        for _ in 0..<settings.powerSims {
            let first = resampleIndices(&generator, k).map { x[$0] }
            let second = resampleIndices(&generator, m).map { y[$0] }
            let observed = abs(contrast(total(first), k, total(second), m))
            let combined = first + second
            let sum = total(combined)
            var count = 0
            for _ in 0..<settings.powerPerms {
                var shuffled = combined
                generator.shuffle(&shuffled)
                let head = total(Array(shuffled.prefix(k)))
                if abs(contrast(head, k, sum - head, m)) >= observed { count += 1 }
            }
            if 100 * (count + 1) <= (100 - settings.confidence) * (settings.powerPerms + 1) { rejections += 1 }
        }
        let power = Double(rejections) / Double(settings.powerSims)
        return "power sims \(settings.powerSims) perms \(settings.powerPerms) rejections \(rejections) power \(real(power)) se \(real(sqrt(power * (1 - power) / Double(settings.powerSims))))"
    }

    func exactLines(_ x: [Int64], _ y: [Int64]) -> [String] {
        let size = data.settings.pilot
        let combined = Array(x.prefix(size)) + Array(y.prefix(size))
        let ranks = doubledRanks(combined)
        let sum = total(combined)
        var means: [Int64] = []
        var ranksums: [Int64] = []
        for choice in positionChoices(2 * size, size) {
            let chosen = choice.reduce(Int64(0)) { $0 + combined[$1] }
            means.append(contrast(chosen, size, sum - chosen, size))
            ranksums.append(choice.reduce(Int64(0)) { $0 + ranks[$1] } - Int64(size * (2 * size + 1)))
        }
        let splits = means.count
        var meanTally = Tally(observed: means[0])
        var rankTally = Tally(observed: ranksums[0])
        for (meanValue, rankValue) in zip(means, ranksums) {
            meanTally.count(meanValue)
            rankTally.count(rankValue)
        }
        let rankTotal = total(Array(ranks.prefix(size)))
        let counts = valueCounts(means.map { abs($0) })
        var cumulative = 0
        var critical: (value: Int64, count: Int)?
        for value in counts.keys.sorted(by: >) {
            cumulative += counts[value]!
            if 100 * cumulative > (100 - data.settings.confidence) * splits { break }
            critical = (value, cumulative)
        }
        let criticalLine = critical.map {
            "critical diff \(real(Double($0.value) / Double(100 * size * size))) attained \(pValue($0.count, splits))"
        } ?? "critical diff none attained none"
        return ["exact size \(size) splits \(splits)",
            "mean diff \(real(meanDifference(Array(x.prefix(size)), Array(y.prefix(size))))) \(meanTally.text(0, splits))",
            "ranksum w \(real(Double(rankTotal) / 2)) u \(real(Double(rankTotal - Int64(size * (size + 1))) / 2)) \(rankTally.text(0, splits))", criticalLine]
    }

    func studentizedLines(_ pair: PairBootstrap, _ ordinary: [GroupBootstrap]) -> [String] {
        let x = data.groups[pair.first].values
        let y = data.groups[pair.second].values
        let k = Double(x.count)
        let m = Double(y.count)
        let estimate = meanDifference(x, y)
        let firstSD = sd(x)
        let secondSD = sd(y)
        let firstVariance = firstSD * firstSD / k
        let secondVariance = secondSD * secondSD / m
        let se0 = sqrt(firstVariance + secondVariance)
        let t = estimate / se0
        let first = ordinary[pair.first].summaries[3].values
        let second = ordinary[pair.second].summaries[3].values
        let statistics = pair.summaries[0].values.enumerated().map { index, difference in
            (difference - estimate) / sqrt(first[index] * first[index] / k + second[index] * second[index] / m)
        }
        let extreme = statistics.filter { abs($0) >= abs(t) }.count
        let ordered = statistics.sorted()
        let lower = estimate - ordered[ranks[1] - 1] * se0
        let upper = estimate - ordered[ranks[0] - 1] * se0
        let degrees = (firstVariance + secondVariance) * (firstVariance + secondVariance) /
            (firstVariance * firstVariance / (k - 1) + secondVariance * secondVariance / (m - 1))
        let greater = x.reduce(0) { count, first in count + y.filter { first > $0 }.count }
        let equal = x.reduce(0) { count, first in count + y.filter { first == $0 }.count }
        let d = cohenD(x, y)
        let hedges = d * (1 - 3 / (4 * (k + m - 2) - 1))
        let cles = Double(2 * greater + equal) / (2 * k * m)
        return ["bootstrap_t t \(real(t)) df \(real(degrees)) extreme \(extreme) p \(pValue(extreme + 1, data.settings.bootstrap + 1)) interval \(real(lower)) \(real(upper))",
            "effect pooled_sd \(real(pooledSD(x, y))) cohen_d \(real(d)) hedges_g \(real(hedges)) cles \(real(cles))"]
    }

    func pairTestLines(_ pair: PairBootstrap, _ ordinary: [GroupBootstrap]) -> (lines: [String], extremes: [Int]) {
        let first = data.groups[pair.first]
        let second = data.groups[pair.second]
        var lines = ["compare \(first.name) \(second.name)"]
        let permutation = permutationLines(first.values, second.values)
        lines += permutation.lines
        lines.append(powerLine(first.values, second.values))
        lines += exactLines(first.values, second.values)
        lines += studentizedLines(pair, ordinary)
        return (lines, permutation.extremes)
    }

    func holmLines(_ extremes: [[Int]]) -> [String] {
        let settings = data.settings
        let count = data.pairs.count
        var lines: [String] = []
        for column in 0..<4 {
            let order = data.pairs.indices.sorted {
                extremes[$0][column] == extremes[$1][column] ? $0 < $1 : extremes[$0][column] < extremes[$1][column]
            }
            var adjusted = 0
            for (rank, index) in order.enumerated() {
                let extreme = extremes[index][column]
                adjusted = max(adjusted, min(settings.permutations + 1, (count - rank) * (extreme + 1)))
                let rejected = 100 * adjusted <= (100 - settings.confidence) * (settings.permutations + 1)
                let pair = data.pairs[index]
                lines.append("holm \(testNames[column]) rank \(rank + 1) \(data.groups[pair.first].name) \(data.groups[pair.second].name) p \(pValue(extreme + 1, settings.permutations + 1)) adjusted \(pValue(adjusted, settings.permutations + 1)) \(rejected ? "reject" : "retain")")
            }
        }
        return lines
    }

    func pairedLines(_ meanSummary: Summary, _ correlationSummary: Summary) -> [String] {
        let paired = data.paired
        let differences = paired.differences
        let count = differences.count
        let positive = differences.filter { $0 > 0 }.count
        let negative = differences.filter { $0 < 0 }.count
        let average = mean(differences)
        let deviation = sd(differences)
        let r = correlation(paired.before, paired.after)
        let z = 0.5 * log((1 + r) / (1 - r))
        let halfWidth = -zLow / sqrt(Double(count - 3))
        return ["paired subjects \(count) positive \(positive) negative \(negative) zero \(count - positive - negative)",
            "paired before \(real(mean(paired.before))) after \(real(mean(paired.after))) diff \(real(average)) sd_diff \(real(deviation)) t \(real(average / (deviation / sqrt(Double(count))))) dz \(real(average / deviation))",
            "paired_bootstrap \(meanSummary.intervalText)",
            "correlation r \(real(r)) \(correlationSummary.intervalText) fisher \(real(hyperbolicTangent(z - halfWidth))) \(real(hyperbolicTangent(z + halfWidth)))"]
    }

    func signFlipLines() -> [String] {
        let differences = data.paired.differences
        let magnitudes = differences.filter { $0 != 0 }.map { abs($0) }
        let ranks = doubledRanks(magnitudes)
        var rankOf: [Int64: Int64] = [:]
        for (value, rank) in zip(magnitudes, ranks) { rankOf[value] = rank }
        let signed = differences.map { value -> Int64 in
            value > 0 ? rankOf[value]! : value < 0 ? -rankOf[-value]! : 0
        }
        var meanTally = Tally(observed: total(differences))
        var rankTally = Tally(observed: total(signed))
        let permutations = data.settings.permutations
        for _ in 0..<permutations {
            let signs: [Int64] = differences.map { _ in generator.draw() % 2 == 1 ? -1 : 1 }
            meanTally.count(zip(signs, differences).reduce(Int64(0)) { $0 + $1.0 * $1.1 })
            rankTally.count(zip(signs, signed).reduce(Int64(0)) { $0 + $1.0 * $1.1 })
        }
        let wPlus = signed.filter { $0 > 0 }.reduce(0, +)
        return ["signflip flips \(permutations)", "mean diff \(real(mean(differences))) \(meanTally.text(1, permutations + 1))",
            "signedrank w_plus \(real(Double(wPlus) / 2)) \(rankTally.text(1, permutations + 1))"]
    }

    func welchLine(_ samples: [[Int64]]) -> String {
        let groups = samples.count
        let means = samples.map(mean)
        let weights = samples.map { sample -> Double in
            let deviation = sd(sample)
            return Double(sample.count) / (deviation * deviation)
        }
        let totalWeight = sequentialSum(weights)
        let center = sequentialSum(zip(weights, means).map { weight, value in weight * value }) / totalWeight
        let spread = sequentialSum(zip(weights, means).map { weight, value in weight * ((value - center) * (value - center)) }) / Double(groups - 1)
        var lambda = 0.0
        for (weight, sample) in zip(weights, samples) {
            let share = 1 - weight / totalWeight
            lambda += share * share / Double(sample.count - 1)
        }
        let f = spread / (1 + Double(2 * (groups - 2)) * lambda / Double(groups * groups - 1))
        let df = Double(groups * groups - 1) / (3 * lambda)
        return "welch f \(real(f)) df \(groups - 1) \(real(df))"
    }

    func anovaPermutationLines(_ samples: [[Int64]], _ ranks: [Int64], _ f: Double, _ h: Double, _ correction: Double) -> [String] {
        let count = samples.reduce(0) { $0 + $1.count }
        let sizes = samples.map { $0.count }
        let groups = samples.count
        let combined = samples.flatMap { $0 }
        let pairs = (0..<groups).flatMap { first in ((first + 1)..<groups).map { (first, $0) } }
        let observed = groupDeltas(samples, pairs)
        var fExtreme = 0
        var hExtreme = 0
        var extremes = Array(repeating: 0, count: pairs.count)
        var maxima = Array(repeating: 0, count: pairs.count)
        let positions = Array(0..<count)
        let permutations = data.settings.permutations
        for _ in 0..<permutations {
            var order = positions
            generator.shuffle(&order)
            let parts = splitList(order, sizes)
            let samples = parts.map { part in part.map { combined[$0] } }
            let squares = sumsOfSquares(samples)
            if fStatistic(squares.between, squares.within, groups, count) >= f - 0.000000001 * f { fExtreme += 1 }
            let rankSums = parts.map { part in part.reduce(Int64(0)) { $0 + ranks[$1] } }
            if hStatistic(rankSums, sizes, correction) >= h - 0.000000001 * h { hExtreme += 1 }
            let deltas = groupDeltas(samples, pairs)
            var largest = deltas[0]
            for delta in deltas.dropFirst() where !deltaAtLeast(largest, delta) { largest = delta }
            for (index, bound) in observed.enumerated() {
                if deltaAtLeast(deltas[index], bound) { extremes[index] += 1 }
                if deltaAtLeast(largest, bound) { maxima[index] += 1 }
            }
        }
        var lines = ["anova_permutation perms \(permutations) f_extreme \(fExtreme) f_p \(pValue(fExtreme + 1, permutations + 1)) h_extreme \(hExtreme) h_p \(pValue(hExtreme + 1, permutations + 1))"]
        for (index, pair) in pairs.enumerated() {
            lines.append("pairwise \(data.groups[pair.0].name) \(data.groups[pair.1].name) diff \(real(meanDifference(samples[pair.0], samples[pair.1]))) extreme \(extremes[index]) p \(pValue(extremes[index] + 1, permutations + 1)) maxt \(maxima[index]) adjusted \(pValue(maxima[index] + 1, permutations + 1))")
        }
        return lines
    }

    func anovaLines(_ ordinary: [GroupBootstrap]) -> [String] {
        let samples = data.groups.map(\.values)
        let sizes = samples.map { $0.count }
        let groups = samples.count
        let count = sizes.reduce(0, +)
        let squares = sumsOfSquares(samples)
        let between = squares.between
        let within = squares.within
        let f = fStatistic(between, within, groups, count)
        let eta = between / (between + within)
        let msw = within / Double(count - groups)
        let omega = (between - Double(groups - 1) * msw) / (between + within + msw)
        let etaValues = (0..<data.settings.bootstrap).map { replicate -> Double in
            let squares = sumsOfSquares(ordinary.map { $0.samples[replicate] })
            return squares.between / (squares.between + squares.within)
        }
        let etaSummary = Summary(eta, etaValues, self.ranks)
        let combined = samples.flatMap { $0 }
        let ranks = doubledRanks(combined)
        let rankSums = splitList(ranks, sizes).map(total)
        let ties = valueCounts(combined).values.filter { $0 >= 2 }
        let tieTotal = ties.reduce(Int64(0)) { $0 + Int64($1 * $1 * $1 - $1) }
        let correction = 1 - Double(tieTotal) / Double(count * count * count - count)
        let h = hStatistic(rankSums, sizes, correction)
        var lines = ["anova groups \(groups) observations \(count) ssb \(real(between)) ssw \(real(within)) df \(groups - 1) \(count - groups) f \(real(f)) eta_squared \(real(eta)) omega_squared \(real(omega))",
            "eta_bootstrap \(etaSummary.intervalText)", welchLine(samples), "kruskal h \(real(h)) tie_groups \(ties.count)"]
        lines += anovaPermutationLines(samples, ranks, f, h, correction)
        return lines
    }

    func run() -> [(String, [String])] {
        let count = data.settings.bootstrap
        var ordinary: [GroupBootstrap] = []
        var balanced: [GroupBootstrap] = []
        for (index, group) in data.groups.enumerated() {
            let indices = ordinaryIndices(&generator, group.values.count, count)
            ordinary.append(GroupBootstrap(index, group.values, indices, ranks))
        }
        for (index, group) in data.groups.enumerated() {
            let indices = balancedIndices(&generator, group.values.count, count)
            balanced.append(GroupBootstrap(index, group.values, indices, ranks))
        }
        let (meanSummary, correlationSummary) = pairedBootstrap()
        let pairs = data.pairs.map { pair -> PairBootstrap in
            let estimates = pairStatistics(data.groups[pair.first].values, data.groups[pair.second].values)
            let statistics = zip(ordinary[pair.first].samples, ordinary[pair.second].samples).map { first, second in pairStatistics(first, second) }
            return PairBootstrap(first: pair.first, second: pair.second,
                name: "\(data.groups[pair.first].name)-\(data.groups[pair.second].name)",
                summaries: (0..<4).map { column in Summary(estimates[column], statistics.map { $0[column] }, ranks) })
        }
        var testLines: [String] = []
        var extremes: [[Int]] = []
        for pair in pairs {
            let result = pairTestLines(pair, ordinary)
            testLines += result.lines
            extremes.append(result.extremes)
        }
        testLines += holmLines(extremes)
        testLines += pairedLines(meanSummary, correlationSummary)
        testLines += signFlipLines()
        testLines += anovaLines(ordinary)
        var bootstrapLines = ["group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi"]
        var jackknifeLines: [String] = []
        var histogramLines: [String] = []
        for (plain, even) in zip(ordinary, balanced) {
            let name = data.groups[plain.group].name
            for column in 0..<4 { bootstrapLines.append(plain.summaries[column].csvLine(name, groupNames[column])) }
            for column in 0..<4 { bootstrapLines.append(even.summaries[column].csvLine(name, "balanced_" + groupNames[column])) }
            jackknifeLines += groupJackknifeLines(plain)
            for column in 0..<4 { histogramLines += self.histogramLines(name, groupNames[column], plain.summaries[column]) }
        }
        for pair in pairs {
            for column in 0..<4 {
                bootstrapLines.append(pair.summaries[column].csvLine(pair.name, pairNames[column]))
                histogramLines += self.histogramLines(pair.name, pairNames[column], pair.summaries[column])
            }
            jackknifeLines += pairJackknifeLines(pair)
        }
        return [("descriptives.txt", descriptiveLines()), ("bootstrap.csv", bootstrapLines),
            ("jackknife.txt", jackknifeLines), ("tests.txt", testLines), ("histograms.txt", histogramLines)]
    }
}

let study = Study(try loadDataset("input"))
let files = study.run()
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
for (name, lines) in files { try writeLines("output/\(name)", lines) }
