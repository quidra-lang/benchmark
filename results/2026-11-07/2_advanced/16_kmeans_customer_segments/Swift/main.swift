import Foundation

struct Minstd {
    var state: Int64

    mutating func draw() -> Int64 {
        state = 48271 * state % 2147483647
        return state
    }
}

func nearestGaps(_ points: [Point], _ chosen: [Int]) -> [Double] {
    points.map { point in chosen.map { squaredDistance(point, points[$0]) }.min()! }
}

func maximin(_ points: [Point], _ k: Int, _ run: Int) -> [Int] {
    let center = meanPoint(points)
    let spread = points.map { squaredDistance($0, center) }
    let order = points.indices.sorted { spread[$0] == spread[$1] ? $0 < $1 : spread[$0] < spread[$1] }
    var chosen = [order[run - 1]]
    while chosen.count < k {
        let gaps = nearestGaps(points, chosen)
        var best = 0
        for index in points.indices.dropFirst() where gaps[index] > gaps[best] { best = index }
        chosen.append(best)
    }
    return chosen
}

func initialSeeds(_ method: String, _ points: [Point], _ k: Int, _ run: Int, _ generator: inout Minstd) -> [Int] {
    if method == "maximin" { return maximin(points, k, run) }
    var chosen: [Int] = []
    if method == "forgy" {
        while chosen.count < k {
            let index = Int(generator.draw() % Int64(points.count))
            if !chosen.contains(index) { chosen.append(index) }
        }
        return chosen
    }
    chosen.append(Int(generator.draw() % Int64(points.count)))
    while chosen.count < k {
        let gaps = nearestGaps(points, chosen)
        let threshold = (Double(generator.draw()) / 2147483647) * orderedSum(gaps)
        var total = 0.0
        var next: Int?
        for (index, gap) in gaps.enumerated() {
            total += gap
            if total > threshold { next = index; break }
        }
        chosen.append(next ?? gaps.lastIndex(where: { $0 > 0 })!)
    }
    return chosen
}

struct Improvement {
    let labels: [Int]
    let passes: Int
    let transfers: Int
    let sse: Double
}

func improve(_ points: [Point], _ original: [Int], _ k: Int, _ maximum: Int) -> Improvement {
    var labels = original
    var sizes = clusterSizes(labels, k)
    var centers = clusterCenters(points, labels, k)
    var passes = 0
    var transfers = 0
    var moved = true
    while moved && passes < maximum {
        moved = false
        passes += 1
        for (index, point) in points.enumerated() {
            let own = labels[index]
            if sizes[own] == 1 { continue }
            let removal = (Double(sizes[own]) / Double(sizes[own] - 1)) * squaredDistance(point, centers[own])
            var target: Int?
            var targetCost = 0.0
            for cluster in 0..<k where cluster != own {
                let cost = (Double(sizes[cluster]) / Double(sizes[cluster] + 1)) * squaredDistance(point, centers[cluster])
                if target == nil || cost < targetCost { target = cluster; targetCost = cost }
            }
            if targetCost < removal {
                let next = target!
                labels[index] = next
                sizes[own] -= 1
                sizes[next] += 1
                centers[own] = clusterCenter(points, labels, own)
                centers[next] = clusterCenter(points, labels, next)
                transfers += 1
                moved = true
            }
        }
    }
    return Improvement(labels: labels, passes: passes, transfers: transfers,
        sse: withinSSE(points, labels, clusterCenters(points, labels, k)))
}

struct Run {
    let method: String
    let number: Int
    let seeds: [Int]
    let lloyd: LloydResult
    let lloydSSE: Double
    let improved: Improvement

    init(_ method: String, _ number: Int, _ seeds: [Int], _ points: [Point], _ maximum: Int) {
        self.method = method
        self.number = number
        self.seeds = seeds
        let result = runLloyd(points, seeds.map { points[$0] }, maximum)
        lloyd = result
        lloydSSE = withinSSE(points, result.labels, result.centers)
        improved = improve(points, result.labels, seeds.count, maximum)
    }
}

struct Solution {
    let k: Int
    let members: [[Int]]
    let sizes: [Int]
    let labels: [Int]
    let centers: [Point]
    let sse: Double

    init(_ points: [Point], _ original: [Int], _ k: Int) {
        var groups = (0..<k).map { cluster in original.indices.filter { original[$0] == cluster } }
        groups.sort { $0.count == $1.count ? $0[0] < $1[0] : $0.count > $1.count }
        var assigned = Array(repeating: 0, count: original.count)
        for (cluster, group) in groups.enumerated() { for index in group { assigned[index] = cluster } }
        let centers = clusterCenters(points, assigned, k)
        self.k = k
        members = groups
        sizes = groups.map { $0.count }
        labels = assigned
        self.centers = centers
        sse = withinSSE(points, assigned, centers)
    }
}

struct Candidate {
    let k: Int
    let runs: [Run]
    let methodBests: [Int]
    let best: Int
    let solution: Solution
    var silhouettes: [Double] = []
    var silhouette = 0.0
    var harabasz = 0.0
    var bouldin = 0.0
    var elbow = 0.0
    var hartigan: Double? = nil
    var ruleNumbers: [Int] = []
    var names: [String] = []
}

func rfmScores(_ customers: [Customer]) -> [[Int]] {
    customers.map { customer in
        let older = customers.filter { $0.recency > customer.recency }.count
        let fewer = customers.filter { $0.frequency < customer.frequency }.count
        let smaller = customers.filter { $0.spend < customer.spend }.count
        return [older, fewer, smaller].map { 1 + 5 * $0 / customers.count }
    }
}

func gini(_ spends: [Int64]) -> Double {
    let ordered = spends.sorted()
    let count = Int64(spends.count)
    let total = ordered.reduce(0, +)
    let weighted = ordered.enumerated().reduce(Int64(0)) { $0 + Int64($1.offset + 1) * $1.element }
    return Double(2 * weighted - (count + 1) * total) / Double(count * total)
}

func lowerMedian<T: Comparable>(_ values: [T]) -> T { values.sorted()[(values.count - 1) / 2] }

func categoryTotals(_ customers: [Customer]) -> [String: Int64] {
    var totals: [String: Int64] = [:]
    for customer in customers { for (category, spend) in customer.categorySpend { totals[category, default: 0] += spend } }
    return totals
}

func categoryRanking(_ totals: [String: Int64]) -> [String] {
    totals.keys.filter { totals[$0]! > 0 }.sorted {
        totals[$0] == totals[$1] ? asciiLess($0, $1) : totals[$0]! > totals[$1]!
    }
}

func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
func integers(_ values: [Int]) -> String { values.map(String.init).joined(separator: " ") }

func joinBlocks(_ blocks: [[String]]) -> [String] {
    var lines: [String] = []
    for block in blocks {
        if !lines.isEmpty { lines.append("") }
        lines += block
    }
    return lines
}

final class Analysis {
    let params: Params
    let data: TransactionData
    let rules: [NamingRule]
    var generator: Minstd
    let referenceOrders: [Order]
    let customerOrders: [String: [Order]]
    let customers: [Customer]
    let means: Point
    let sds: Point
    let points: [Point]
    let customerNumbers: [String: Int]
    var candidates: [Candidate] = []
    var votes: [(criterion: String, index: Int)] = []
    var selected = 0
    var finalVotes = 0
    var distances: [Double] = []
    var others: [(segment: Int, distance: Double)] = []
    var scores: [[Int]] = []
    var codes: [String] = []
    var totalSpend: Int64 = 0
    var overallCategories: [String: Int64] = [:]
    var segmentSpends: [Int64] = []
    var segmentCategories: [[String: Int64]] = []
    var rankings: [[String]] = []
    var segmentSSE: [Double] = []
    var jaccards: [[Double]] = []

    init(_ params: Params, _ data: TransactionData, _ rules: [NamingRule]) {
        self.params = params
        self.data = data
        self.rules = rules
        generator = Minstd(state: params.seed)
        let orders = groupOrders(data.validRows, 1, params.referenceDay)
        referenceOrders = orders
        customerOrders = ordersByCustomer(orders)
        let customers = eligibleCustomers(orders, params.referenceDay)
        self.customers = customers
        customerNumbers = Dictionary(uniqueKeysWithValues: customers.enumerated().map { ($0.element.id, $0.offset) })
        let transformed = customers.map(\.transformed)
        let standardized = standardization(transformed)
        means = standardized.means
        sds = standardized.sds
        points = transformed.map { standardize($0, standardized.means, standardized.sds) }
    }

    var finalCandidate: Candidate { candidates[selected] }
    func ids(_ numbers: [Int]) -> String { numbers.map { customers[$0].id }.joined(separator: " ") }

    func search(_ k: Int) -> Candidate {
        var runs: [Run] = []
        var methodBests: [Int] = []
        for method in params.methods {
            var best = runs.count
            for number in 1...params.restarts {
                let seeds = initialSeeds(method, points, k, number, &generator)
                let index = runs.count
                runs.append(Run(method, number, seeds, points, params.maxIterations))
                if fourDecimal(runs[index].improved.sse) < fourDecimal(runs[best].improved.sse) { best = index }
            }
            methodBests.append(best)
        }
        var best = methodBests[0]
        for index in methodBests.dropFirst() where fourDecimal(runs[index].improved.sse) < fourDecimal(runs[best].improved.sse) { best = index }
        return Candidate(k: k, runs: runs, methodBests: methodBests, best: best,
            solution: Solution(points, runs[best].improved.labels, k))
    }

    func analyze() {
        for k in params.kMin...params.kMax { candidates.append(search(k)) }
        let table = distanceTable(points)
        let first = candidates[0].solution.sse
        let last = candidates.last!.solution.sse
        for index in candidates.indices {
            var candidate = candidates[index]
            let solution = candidate.solution
            candidate.silhouettes = silhouettes(table, solution.labels, solution.sizes)
            candidate.silhouette = orderedSum(candidate.silhouettes) / Double(customers.count)
            candidate.harabasz = calinskiHarabasz(points, solution.centers, solution.sizes, solution.sse)
            candidate.bouldin = daviesBouldin(points, solution.labels, solution.centers, solution.sizes)
            candidate.elbow = elbow(candidate.k, params.kMin, params.kMax, solution.sse, first, last)
            if index + 1 < candidates.count { candidate.hartigan = hartigan(solution.sse, candidates[index + 1].solution.sse, customers.count, candidate.k) }
            for center in solution.centers {
                let number = ruleNumber(rules, center)
                let repeats = candidate.ruleNumbers.filter { $0 == number }.count
                candidate.ruleNumbers.append(number)
                let name = rules[number].name
                candidate.names.append(repeats == 0 ? name : "\(name)_\(repeats + 1)")
            }
            candidates[index] = candidate
        }
        chooseK()
        describeFinal()
        subsampleJaccards()
    }

    func chooseK() {
        var elbow = 1
        var silhouette = 0
        var harabasz = 0
        var bouldin = 0
        for index in candidates.indices {
            let candidate = candidates[index]
            if index > 0 && index + 1 < candidates.count && fourDecimal(candidate.elbow) > fourDecimal(candidates[elbow].elbow) { elbow = index }
            if fourDecimal(candidate.silhouette) > fourDecimal(candidates[silhouette].silhouette) { silhouette = index }
            if fourDecimal(candidate.harabasz) > fourDecimal(candidates[harabasz].harabasz) { harabasz = index }
            if fourDecimal(candidate.bouldin) < fourDecimal(candidates[bouldin].bouldin) { bouldin = index }
        }
        let hartigan = candidates.firstIndex { $0.hartigan != nil && $0.hartigan! <= 10 } ?? candidates.count - 1
        votes = [("elbow", elbow), ("silhouette", silhouette), ("calinski_harabasz", harabasz),
            ("davies_bouldin", bouldin), ("hartigan", hartigan)]
        var counts = Array(repeating: 0, count: candidates.count)
        for vote in votes { counts[vote.index] += 1 }
        for index in candidates.indices.dropFirst() {
            if counts[index] > counts[selected] || (counts[index] == counts[selected] && fourDecimal(candidates[index].silhouette) > fourDecimal(candidates[selected].silhouette)) { selected = index }
        }
        finalVotes = counts[selected]
    }

    func describeFinal() {
        let solution = finalCandidate.solution
        for (point, label) in zip(points, solution.labels) {
            let squared = solution.centers.map { squaredDistance(point, $0) }
            let other = solution.centers.indices.filter { $0 != label }.min {
                squared[$0] == squared[$1] ? $0 < $1 : squared[$0] < squared[$1]
            }!
            distances.append(sqrt(squared[label]))
            others.append((other, sqrt(squared[other])))
        }
        scores = rfmScores(customers)
        codes = scores.map { $0.map(String.init).joined() }
        totalSpend = customers.reduce(0) { $0 + $1.spend }
        overallCategories = categoryTotals(customers)
        for (segment, members) in solution.members.enumerated() {
            let customers = members.map { self.customers[$0] }
            segmentSpends.append(customers.reduce(0) { $0 + $1.spend })
            let totals = categoryTotals(customers)
            rankings.append(categoryRanking(totals))
            segmentCategories.append(totals)
            var within = 0.0
            for number in members { within += squaredDistance(points[number], solution.centers[segment]) }
            segmentSSE.append(within)
        }
    }

    func subsampleJaccards() {
        let solution = finalCandidate.solution
        let size = customers.count * params.subsamplePercent / 100
        jaccards = Array(repeating: [], count: solution.k)
        for _ in 0..<params.subsamples {
            var order = Array(customers.indices)
            for index in 0..<size {
                let other = index + Int(generator.draw() % Int64(customers.count - index))
                order.swapAt(index, other)
            }
            let sample = order.prefix(size).sorted()
            let points = sample.map { self.points[$0] }
            let result = runLloyd(points, solution.centers, params.maxIterations)
            for segment in 0..<solution.k {
                var best = 0.0
                for cluster in 0..<solution.k {
                    var both = 0
                    var either = 0
                    for (number, label) in zip(sample, result.labels) {
                        let member = solution.labels[number] == segment
                        if member && label == cluster { both += 1 }
                        if member || label == cluster { either += 1 }
                    }
                    if either > 0 { best = max(best, Double(both) / Double(either)) }
                }
                jaccards[segment].append(best)
            }
        }
    }

    func recommendation(_ number: Int) -> String {
        let label = finalCandidate.solution.labels[number]
        return rankings[label].first { customers[number].categorySpend[$0, default: 0] <= 0 } ?? "-"
    }

    func featuresLines() -> [String] {
        var lines = ["customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure"]
        for (customer, point) in zip(customers, points) {
            var fields = [customer.id, String(customer.recency), String(customer.frequency), amount(customer.spend),
                real(customer.basket), String(customer.categories), String(customer.tenure)]
            fields += point.map(real)
            lines.append(fields.joined(separator: ","))
        }
        return lines
    }

    func runSummary(_ run: Run) -> String { "\(run.method) restart \(run.number) sse \(real(run.improved.sse))" }

    func runsLines() -> [String] {
        joinBlocks(candidates.map { candidate in
            var lines = ["k \(candidate.k)"]
            for run in candidate.runs {
                lines.append("run \(run.method) \(run.number) seeds \(ids(run.seeds)) iterations \(run.lloyd.iterations) converged \(yesNo(run.lloyd.converged)) reseeds \(run.lloyd.reseeds) sse \(real(run.lloydSSE)) passes \(run.improved.passes) transfers \(run.improved.transfers) refined \(real(run.improved.sse))")
            }
            for index in candidate.methodBests { lines.append("best \(runSummary(candidate.runs[index]))") }
            lines.append("chosen \(runSummary(candidate.runs[candidate.best]))")
            lines.append("sizes \(integers(candidate.solution.sizes))")
            return lines
        })
    }

    func selectionLines() -> [String] {
        var indices = ["indices"]
        var names = ["segments"]
        var stability = ["stability"]
        for (position, candidate) in candidates.enumerated() {
            let hartigan = candidate.hartigan.map(real) ?? "-"
            indices.append("k=\(candidate.k) sse \(real(candidate.solution.sse)) elbow \(real(candidate.elbow)) silhouette \(real(candidate.silhouette)) calinski_harabasz \(real(candidate.harabasz)) davies_bouldin \(real(candidate.bouldin)) hartigan \(hartigan)")
            let segments = zip(candidate.names, candidate.solution.sizes).map { name, size in "\(name):\(size)" }.joined(separator: " ")
            names.append("k=\(candidate.k) \(segments)")
            var parts = ["k=\(candidate.k)"]
            for (index, first) in candidate.methodBests.enumerated() {
                for second in candidate.methodBests.dropFirst(index + 1) {
                    let a = candidate.runs[first]
                    let b = candidate.runs[second]
                    parts.append("\(a.method):\(b.method) \(real(adjustedRandIndex(a.improved.labels, b.improved.labels)))")
                }
            }
            parts.append("final")
            for index in candidate.methodBests {
                let run = candidate.runs[index]
                parts.append("\(run.method) \(real(adjustedRandIndex(run.improved.labels, candidate.solution.labels)))")
            }
            if position + 1 < candidates.count { parts.append("next \(real(adjustedRandIndex(candidate.solution.labels, candidates[position + 1].solution.labels)))") }
            else { parts.append("next -") }
            stability.append(parts.joined(separator: " "))
        }
        var votes = ["votes"]
        votes += self.votes.map { "\($0.criterion) k=\(candidates[$0.index].k)" }
        votes.append("chosen k=\(finalCandidate.k) votes \(finalVotes)")
        return joinBlocks([indices, votes, names, stability])
    }

    func segmentsLines() -> [String] {
        let candidate = finalCandidate
        var lines = ["customer,segment,name,distance,other,other_distance,silhouette,recommend"]
        for (index, customer) in customers.enumerated() {
            let label = candidate.solution.labels[index]
            let other = others[index]
            lines.append("\(customer.id),\(label + 1),\(candidate.names[label]),\(real(distances[index])),\(other.segment + 1),\(real(other.distance)),\(real(candidate.silhouettes[index])),\(recommendation(index))")
        }
        return lines
    }

    func related(_ members: [Int], _ k: Int) -> String {
        guard params.kMin <= k && k <= params.kMax else { return "k=\(k) -" }
        let labels = candidates[k - params.kMin].solution.labels
        var counts = Array(repeating: 0, count: k)
        for number in members { counts[labels[number]] += 1 }
        var best = 0
        for index in 1..<k where counts[index] > counts[best] { best = index }
        return "k=\(k) segment \(best + 1) shared \(counts[best])"
    }

    func segmentProfile(_ segment: Int) -> [String] {
        let candidate = finalCandidate
        let solution = candidate.solution
        let members = solution.members[segment]
        let customers = members.map { self.customers[$0] }
        let size = members.count
        let center = solution.centers[segment]
        let spend = segmentSpends[segment]
        var lines = ["segment \(segment + 1) \(candidate.names[segment]) rule \(candidate.ruleNumbers[segment] + 1) size \(size) share \(real(Double(size) / Double(self.customers.count))) revenue \(amount(spend)) revenue_share \(real(Double(spend) / Double(totalSpend)))",
            "  center \(reals(center))"]
        let values = originalScale(center, means, sds)
        lines.append("  value " + zip(featureNames, values).map { name, value in "\(name) \(real(value))" }.joined(separator: " "))
        let featureOrder = center.indices.sorted { abs(center[$0]) == abs(center[$1]) ? $0 < $1 : abs(center[$0]) > abs(center[$1]) }
        let traits = featureOrder.prefix(2).map { (center[$0] > 0 ? "high_" : "low_") + featureNames[$0] }
        lines.append("  traits " + traits.joined(separator: " "))
        lines.append("  median recency \(lowerMedian(customers.map(\.recency))) frequency \(lowerMedian(customers.map(\.frequency))) monetary \(amount(lowerMedian(customers.map(\.spend)))) basket \(real(lowerMedian(customers.map(\.basket)))) categories \(lowerMedian(customers.map(\.categories))) tenure \(lowerMedian(customers.map(\.tenure)))")
        lines.append("  related \(related(members, solution.k - 1)) \(related(members, solution.k + 1))")
        let top = members.sorted { self.customers[$0].spend == self.customers[$1].spend ? $0 < $1 : self.customers[$0].spend > self.customers[$1].spend }
        var topParts = ["  top_customers"]
        for number in top.prefix(params.topCustomers) { topParts += [self.customers[number].id, amount(self.customers[number].spend)] }
        lines.append(topParts.joined(separator: " "))
        var gaps: [Double] = []
        var overdue = 0
        var bins = Array(repeating: 0, count: params.orderBins.count + 1)
        var gross: Int64 = 0
        var returned: Int64 = 0
        var cancelled = 0
        for customer in customers {
            if customer.frequency >= 2 {
                let activeDays = customer.tenure - customer.recency
                let intervals = customer.frequency - 1
                gaps.append(Double(activeDays) / Double(intervals))
                if customer.recency * intervals > params.overdueFactor * activeDays { overdue += 1 }
            }
            for order in customer.orders { bins[params.orderBins.filter { order.net >= $0 * 100 }.count] += 1 }
            for order in customerOrders[customer.id]! {
                if order.net <= 0 { cancelled += 1 }
                for row in order.rows {
                    if row.amount > 0 { gross += row.amount }
                    else { returned -= row.amount }
                }
            }
        }
        let meanGap = gaps.isEmpty ? "-" : real(mean(gaps))
        lines.append("  cadence customers \(gaps.count) mean_gap \(meanGap) overdue \(overdue)")
        lines.append("  order_sizes \(integers(bins))")
        lines.append("  sse \(real(segmentSSE[segment])) share \(real(segmentSSE[segment] / solution.sse))")
        lines.append("  gini \(real(gini(customers.map(\.spend))))")
        lines.append("  returns rate \(real(Double(returned) / Double(gross))) returned \(amount(returned)) cancelled \(cancelled)")
        let silhouettes = members.map { candidate.silhouettes[$0] }
        lines.append("  silhouette \(real(mean(silhouettes))) negative \(silhouettes.filter { $0 < 0 }.count)")
        let scoreMeans = (0..<3).map { column in Double(members.reduce(0) { $0 + scores[$1][column] }) / Double(size) }
        var codeCounts: [String: Int] = [:]
        for number in members { codeCounts[codes[number], default: 0] += 1 }
        let mode = codeCounts.keys.min { codeCounts[$0] == codeCounts[$1] ? asciiLess($0, $1) : codeCounts[$0]! > codeCounts[$1]! }!
        lines.append("  rfm r \(real(scoreMeans[0])) f \(real(scoreMeans[1])) m \(real(scoreMeans[2])) mode \(mode) \(codeCounts[mode]!)")
        var categoryParts = ["  categories"]
        for category in rankings[segment].prefix(params.topCategories) {
            let share = Double(segmentCategories[segment][category]!) / Double(spend)
            let lift = share / (Double(overallCategories[category]!) / Double(totalSpend))
            categoryParts += [category, real(share), real(lift)]
        }
        lines.append(categoryParts.joined(separator: " "))
        var outliers: [Int] = []
        if size >= 2 {
            let distances = members.map { self.distances[$0] }
            let limit = mean(distances) + params.outlierSD * sampleSD(distances)
            outliers = members.filter { self.distances[$0] > limit }
        }
        lines.append((["  outliers", String(outliers.count)] + outliers.map { self.customers[$0].id }).joined(separator: " "))
        return lines
    }

    func profilesLines() -> [String] {
        let solution = finalCandidate.solution
        let k = solution.k
        let numbers = integers(Array(1...k))
        var blocks = [["segments k=\(k) customers \(customers.count) revenue \(amount(totalSpend)) gini \(real(gini(customers.map(\.spend))))"]]
        for segment in 0..<k { blocks.append(segmentProfile(segment)) }
        var mix = ["category_mix \(numbers)"]
        for category in overallCategories.keys.sorted(by: asciiLess) {
            let shares = zip(segmentCategories, segmentSpends).map { totals, spend in Double(totals[category, default: 0]) / Double(spend) }
            mix.append(category + " " + reals(shares))
        }
        blocks.append(mix)
        var recency = ["rfm_recency \(numbers)"]
        for score in stride(from: 5, through: 1, by: -1) {
            var counts = Array(repeating: 0, count: k)
            for (number, scores) in scores.enumerated() where scores[0] == score { counts[solution.labels[number]] += 1 }
            recency.append("r=\(score) \(integers(counts))")
        }
        recency.append("ari rfm_codes \(real(adjustedRandIndex(codes, solution.labels)))")
        blocks.append(recency)
        var distances = ["center_distances"]
        for (index, center) in solution.centers.enumerated() {
            let values = solution.centers.map { sqrt(squaredDistance(center, $0)) }
            distances.append("\(index + 1) \(reals(values))")
        }
        blocks.append(distances)
        return joinBlocks(blocks)
    }

    func robustnessLines() -> [String] {
        let candidate = finalCandidate
        let solution = candidate.solution
        let size = customers.count * params.subsamplePercent / 100
        var subsamples = ["subsamples \(params.subsamples) size \(size)"]
        for (segment, values) in jaccards.enumerated() {
            subsamples.append("segment \(segment + 1) \(candidate.names[segment]) mean_jaccard \(real(mean(values))) min_jaccard \(real(values.min()!))")
        }
        var ablation = ["ablation"]
        for (feature, name) in featureNames.enumerated() {
            let points = self.points.map { point in point.indices.filter { $0 != feature }.map { point[$0] } }
            let seeds = maximin(points, solution.k, 1)
            let run = Run("maximin", 1, seeds, points, params.maxIterations)
            let index = adjustedRandIndex(run.improved.labels, solution.labels)
            ablation.append("without \(name) seeds \(ids(seeds)) iterations \(run.lloyd.iterations) converged \(yesNo(run.lloyd.converged)) transfers \(run.improved.transfers) sse \(real(run.improved.sse)) ari \(real(index))")
        }
        let members = solution.members[0]
        let points = members.map { self.points[$0] }
        let seeds = maximin(points, 2, 1)
        let run = Run("maximin", 1, seeds, points, params.maxIterations)
        let parts = Solution(points, run.improved.labels, 2)
        let before = segmentSSE[0]
        let after = run.improved.sse
        var drilldown = ["drilldown segment 1 \(candidate.names[0]) size \(members.count) seeds \(ids(seeds.map { members[$0] })) iterations \(run.lloyd.iterations) converged \(yesNo(run.lloyd.converged)) transfers \(run.improved.transfers)",
            "sse before \(real(before)) after \(real(after)) gain \(real(before - after))"]
        for part in 0..<2 { drilldown.append("part \(part + 1) size \(parts.sizes[part]) center \(reals(parts.centers[part]))") }
        return joinBlocks([subsamples, ablation, drilldown])
    }

    func periodLines() -> [String] {
        let solution = finalCandidate.solution
        var lines = ["periods \(params.periods) days \(params.periodDays)"]
        for period in 1...params.periods {
            let first = params.referenceDay - period * params.periodDays + 1
            let last = params.referenceDay - (period - 1) * params.periodDays
            var revenue = Array<Int64>(repeating: 0, count: solution.k)
            var active = Array(repeating: 0, count: solution.k)
            var acquired = Array(repeating: 0, count: solution.k)
            for (customer, label) in zip(customers, solution.labels) {
                let nets = customer.orders.filter { first <= $0.day && $0.day <= last }.map(\.net)
                if !nets.isEmpty { revenue[label] += nets.reduce(0, +); active[label] += 1 }
                let firstPurchase = params.referenceDay - customer.tenure
                if first <= firstPurchase && firstPurchase <= last { acquired[label] += 1 }
            }
            lines.append("period \(period) days \(first) \(last) revenue \(revenue.map(amount).joined(separator: " ")) active \(integers(active)) acquired \(integers(acquired))")
        }
        return lines
    }

    func migrationLines() -> [String] {
        let solution = finalCandidate.solution
        let orders = groupOrders(data.validRows, 1, params.snapshotDay)
        let snapshot = eligibleCustomers(orders, params.snapshotDay)
        var segments: [String: Int] = [:]
        for customer in snapshot {
            let point = standardize(customer.transformed, means, sds)
            segments[customer.id] = assign([point], solution.centers).labels[0]
        }
        var table = Array(repeating: Array(repeating: 0, count: solution.k), count: solution.k + 1)
        var moved: [String] = []
        var stayed = 0
        var new = 0
        for (customer, label) in zip(customers, solution.labels) {
            if let origin = segments[customer.id] {
                table[origin][label] += 1
                if origin == label { stayed += 1 }
                else { moved.append("\(customer.id) \(origin + 1) \(label + 1)") }
            } else { table[solution.k][label] += 1; new += 1 }
        }
        let lost = snapshot.filter { customerNumbers[$0.id] == nil }.count
        var lines = ["migration day \(params.snapshotDay) customers \(snapshot.count)", "from\\to \(integers(Array(1...solution.k)))"]
        for (origin, counts) in table.enumerated() {
            let name = origin == solution.k ? "none" : String(origin + 1)
            lines.append("\(name) \(integers(counts))")
        }
        lines.append("moved_customers")
        lines += moved
        lines.append("stayed \(stayed) moved \(moved.count) new \(new) lost \(lost)")
        return lines
    }

    func outcomeLines() -> [String] {
        let candidate = finalCandidate
        let solution = candidate.solution
        let first = params.referenceDay + 1
        let last = params.referenceDay + params.outcomeDays
        let purchases = ordersByCustomer(groupOrders(data.validRows, first, last).filter { $0.net > 0 })
        var lines = ["outcome days \(first) \(last)"]
        for (segment, members) in solution.members.enumerated() {
            var buyers = 0
            var spend: Int64 = 0
            for number in members {
                if let orders = purchases[customers[number].id] {
                    buyers += 1
                    spend += orders.reduce(0) { $0 + $1.net }
                }
            }
            lines.append("segment \(segment + 1) \(candidate.names[segment]) size \(members.count) buyers \(buyers) rate \(real(Double(buyers) / Double(members.count))) revenue \(amount(spend)) per_customer \(real((Double(spend) / 100) / Double(members.count)))")
        }
        let outsiders = purchases.keys.filter { customerNumbers[$0] == nil }
        let outsiderSpend = outsiders.reduce(Int64(0)) { sum, id in sum + purchases[id]!.reduce(0) { $0 + $1.net } }
        lines.append("unsegmented buyers \(outsiders.count) revenue \(amount(outsiderSpend))")
        return lines
    }

    func trackingLines() -> [String] { joinBlocks([periodLines(), migrationLines(), outcomeLines()]) }

    func summaryLines() -> [String] {
        let used = data.validRows.filter { $0.day <= params.referenceDay }
        let returns = used.filter { $0.amount < 0 }.count
        let later = data.validRows.filter { $0.day > params.referenceDay }.count
        let valid = referenceOrders.filter { $0.net > 0 }.count
        let excluded = data.customers.filter { customerNumbers[$0] == nil }.sorted(by: asciiLess)
        let dataLines = ["rows \(data.rowCount) duplicates \(data.duplicates) zero \(data.free) used \(used.count) returns \(returns) later \(later)",
            "orders \(referenceOrders.count) valid \(valid) cancelled \(referenceOrders.count - valid)",
            "customers \(data.customers.count) clustered \(customers.count) excluded \(excluded.count)",
            "excluded_ids \(excluded.isEmpty ? "-" : excluded.joined(separator: " "))"]
        let categories = overallCategories.keys.sorted(by: asciiLess).map { category -> String in
            let spend = overallCategories[category]!
            let buyers = customers.filter { $0.categorySpend[category, default: 0] > 0 }.count
            return "category \(category) revenue \(amount(spend)) share \(real(Double(spend) / Double(totalSpend))) customers \(buyers)"
        }
        let raw = customers.map(\.values)
        var features: [String] = []
        for (index, name) in featureNames.enumerated() {
            let column = raw.map { $0[index] }
            features.append("feature \(name) transform \(sqrtFeatures[index] ? "sqrt" : "none") raw_mean \(real(mean(column))) raw_sd \(real(sampleSD(column))) mean \(real(means[index])) sd \(real(sds[index]))")
        }
        var correlations = ["correlation " + featureNames.joined(separator: " ")]
        for (first, name) in featureNames.enumerated() {
            let values = featureNames.indices.map { correlation(points, first, $0) }
            correlations.append(name + " " + reals(values))
        }
        return joinBlocks([dataLines, categories, features, correlations])
    }
}

let analysis = Analysis(try readParams("input/params.txt"), try readTransactions("input/transactions.csv"),
    try readRules("input/segment_rules.txt"))
analysis.analyze()
try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
for (name, lines) in [("features.csv", analysis.featuresLines()), ("runs.txt", analysis.runsLines()),
    ("selection.txt", analysis.selectionLines()), ("segments.csv", analysis.segmentsLines()),
    ("profiles.txt", analysis.profilesLines()), ("robustness.txt", analysis.robustnessLines()),
    ("tracking.txt", analysis.trackingLines()), ("summary.txt", analysis.summaryLines())] {
    try writeLines("output/\(name)", lines)
}
