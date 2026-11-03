import Foundation

struct Params {
    let values: [String: String]
    var minSupport: Int { Int(values["min_support"]!)! }
    var minConfidence: Fraction { parseFraction(values["min_confidence"]!) }
    var minLift: Fraction { parseFraction(values["min_lift"]!) }
    var maxSize: Int { Int(values["max_size"]!)! }
    var categorySupport: Int { Int(values["category_min_support"]!)! }
    var sequenceSupport: Int { Int(values["sequence_min_support"]!)! }
    var splitDay: Int { Int(values["split_day"]!)! }
    var trainSupport: Int { Int(values["train_min_support"]!)! }
    var testSupport: Int { Int(values["test_min_support"]!)! }
    var top: Int { Int(values["recommend_top"]!)! }
    var matrixSize: Int { Int(values["matrix_size"]!)! }
    var groupLift: Fraction { parseFraction(values["group_min_lift"]!) }
    var negativeLift: Fraction { parseFraction(values["negative_max_lift"]!) }
    var negativeExpected: Int { Int(values["negative_min_expected"]!)! }
    var trendThreshold: Fraction { parseFraction(values["trend_threshold"]!) }
}
func parseFraction(_ text: String) -> Fraction { let parts = text.split(separator: "/"); return Fraction(Int(parts[0])!, Int(parts[1])!) }
func readParams() throws -> Params {
    let pairs = try readLines("input/params.txt").map { line -> (String, String) in let words = line.split(separator: " ").map(String.init); return (words[0], words[1]) }
    return Params(values: Dictionary(uniqueKeysWithValues: pairs))
}
func median(_ values: [Int]) -> Fraction {
    let ordered = values.sorted()
    let middle = ordered.count / 2
    return ordered.count % 2 == 1 ? Fraction(ordered[middle]) : Fraction(ordered[middle - 1] + ordered[middle], 2)
}
func splitItems(_ items: [String], _ mask: Int) -> ([String], [String]) {
    let first = items.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
    let second = items.enumerated().filter { mask & (1 << $0.offset) == 0 }.map(\.element)
    return (first, second)
}
func recommend(_ held: Set<String>, _ candidates: [String], _ limit: Int) -> [String] {
    var selected: [String] = []
    for candidate in candidates {
        if selected.count == limit { break }
        if !held.contains(candidate) && !selected.contains(candidate) { selected.append(candidate) }
    }
    return selected
}
func ruleCandidates(_ rules: [Rule], _ held: Set<String>) -> [String] { rules.filter { $0.consequent.count == 1 && contains(held, $0.antecedent) }.map { $0.consequent[0] } }
final class Dataset {
    var errors: [String] = []
    var products: [String: Product] = [:]
    var transactions: [Transaction] = []
    var itemRows = 0
    var transactionLines = 0
    var adopted = 0
    var rejected = 0
    var duplicates = 0
    var baskets: [Transaction] { transactions.filter { !$0.counts.isEmpty } }
    init() throws {
        let items = try readRecords("items.csv")
        itemRows = items.count
        for (index, row) in items.enumerated() {
            let price = Int(row[2])!
            let problem: String?
            if products[row[0]] != nil { problem = "duplicate item \(row[0])" }
            else if price == 0 { problem = "bad price \(price)" }
            else { problem = nil }
            if let problem { errors.append("items.csv line \(index + 2): \(problem)") }
            else { products[row[0]] = Product(name: row[0], category: row[1], price: price) }
        }
        let rows = try readRecords("transactions.csv")
        transactionLines = rows.count
        var known: Set<String> = []
        for (index, row) in rows.enumerated() {
            let tid = row[0], customer = row[1], day = Int(row[2])!, item = row[3]
            var problem: String? = nil
            if known.contains(tid) && tid != transactions.last!.tid { problem = "tid \(tid) not contiguous" }
            else {
                if known.insert(tid).inserted { transactions.append(Transaction(tid, customer, day)) }
                let current = transactions.last!
                if customer != current.customer { problem = "tid \(tid) customer \(customer) differs from \(current.customer)" }
                else if day != current.day { problem = "tid \(tid) day \(day) differs from \(current.day)" }
                else if products[item] == nil { problem = "unknown item \(item)" }
            }
            if let problem { errors.append("transactions.csv line \(index + 2): \(problem)"); rejected += 1 }
            else { adopted += 1; if transactions.last!.add(item) { duplicates += 1 } }
        }
    }
}
struct Level {
    let number: Int
    let candidates: Int
    let excluded: Int
    let pruned: Int
    let counted: Int
    let items: [[String]]
}
struct AprioriResult {
    var levels: [Level] = []
    var supports: [[String]: Int] = [:]
    var singles: [String: Int] = [:]
}
func runApriori(_ index: BasketIndex, _ universe: [String], _ minimum: Int, _ maxSize: Int, _ taxonomy: [String: String]? = nil) -> AprioriResult {
    var result = AprioriResult()
    func addLevel(_ number: Int, _ candidates: Int, _ excluded: Int, _ pruned: Int, _ items: [[String]]) -> [[String]] {
        let counts = countSupports(index, items)
        let frequent = items.filter { counts[$0]! >= minimum }.sorted(by: itemsBefore)
        result.levels.append(Level(number: number, candidates: candidates, excluded: excluded, pruned: pruned, counted: items.count, items: frequent))
        for item in frequent { result.supports[item] = counts[item]! }
        if number == 1 { for (item, count) in counts { result.singles[item[0]] = count } }
        return frequent
    }
    let singles = universe.sorted().map { [$0] }
    var previous = addLevel(1, singles.count, 0, 0, singles)
    var size = 2
    while size <= maxSize && !previous.isEmpty {
        let level = generateCandidates(previous, size, taxonomy)
        previous = addLevel(size, level.joined, level.excluded, level.pruned, level.items)
        size += 1
    }
    return result
}
func makeRules(_ supports: [[String]: Int], _ total: Int, _ params: Params, _ required: Set<String>? = nil) -> RuleSet {
    var generated = 0
    var kept: [Rule] = []
    func support(_ items: [String]) -> Int { items.isEmpty ? total : supports[items]! }
    for (items, count) in supports {
        if items.count < 2 { continue }
        if let required, !items.contains(where: { required.contains($0) }) { continue }
        for mask in 1..<((1 << items.count) - 1) {
            let (first, second) = splitItems(items, mask)
            generated += 1
            let rule = Rule(items, first, second, count, total, support(first), support(second))
            if !meets(rule.confidence, rule.lift, params) { continue }
            var reference = Fraction(0)
            for subsetMask in 0..<((1 << first.count) - 1) {
                let subset = splitItems(first, subsetMask).0
                reference = max(reference, Fraction(support((subset + second).sorted()), support(subset)))
            }
            rule.improvement = rule.confidence - reference
            kept.append(rule)
        }
    }
    kept.sort(by: rulesBefore)
    for (index, rule) in kept.enumerated() { rule.rank = index + 1 }
    return RuleSet(generated: generated, rules: kept)
}
struct Sequence {
    let first: String
    let second: String
    let count: Int
    let base: Int
    let confidence: Fraction
    let lift: Fraction
    let gap: Fraction
}
struct Repeat {
    let name: String
    let customers: Int
    let intervals: [Int]
    var mean: Fraction { Fraction(intervals.reduce(0, +), intervals.count) }
}
final class Tally {
    var cases = 0
    var covered = 0
    var topHits = 0
    var hits = 0
    var baselineHits = 0
    func add(_ held: String, _ suggested: [String], _ baseline: [String]) {
        cases += 1
        if !suggested.isEmpty { covered += 1 }
        if suggested.first == held { topHits += 1 }
        if suggested.contains(held) { hits += 1 }
        if baseline.contains(held) { baselineHits += 1 }
    }
    func describe() -> String { "cases \(cases) covered \(covered) hit1 \(topHits) hit \(hits) rate \(fractionText(Fraction(hits, cases))) baseline \(baselineHits) rate \(fractionText(Fraction(baselineHits, cases)))" }
}
struct RuleCheck {
    let rule: Rule
    let together: Int
    let first: Int
    let confidence: Fraction?
    let lift: Fraction?
    let verdict: String
}
struct ProductGroup {
    let members: [String]
    let edges: Int
    let core: String
    let revenue: Int
}
struct Substitute {
    let first: String
    let second: String
    let count: Int
    let expected: Fraction
    let lift: Fraction
}
struct Trend {
    let name: String
    let units: Int
    let slope: Fraction
    let relative: Fraction?
    let verdict: String
}
struct CustomerSummary {
    let name: String
    let baskets: Int
    let days: Int
    let first: Int
    let last: Int
    let products: Int
    let units: Int
    let revenue: Int
    let favorite: String
    let segment: String
    let offer: [String]
}

final class MarketAnalysis {
    let params: Params
    let data: Dataset
    let products: [String: Product]
    let names: [String]
    let taxonomy: [String: String]
    let categories: [String]
    let baskets: [Transaction]
    let itemSets: [Set<String>]
    let index: BasketIndex
    let extended: BasketIndex
    let total: Int
    let customerBaskets: [String: [Transaction]]
    let customers: [String]
    let histories: [String: [String: [Int]]]
    let buyers: [String: Int]
    let firstDay: Int
    let lastDay: Int
    let units: [String: Int]
    let revenue: [String: Int]
    let totalRevenue: Int
    var main = AprioriResult()
    var frequent: [[String]: Int] { main.supports }
    var counts: [String: Int] { main.singles }
    var pairs: [[String]] { frequent.keys.filter { $0.count == 2 } }
    var growth = GrowthResult(header: 0, nodes: 0)
    var mainRules = RuleSet(generated: 0, rules: [])
    var categoryRun = AprioriResult()
    var categoryRules = RuleSet(generated: 0, rules: [])
    var training: [Transaction] = []
    var testing: [Transaction] = []
    var trainRun = AprioriResult()
    var testRun = AprioriResult()
    var trainRules: [Rule] = []
    var testRules: [Rule] = []
    var checks: [RuleCheck] = []
    var emerging: [Rule] = []
    var heldOut: [String: Int] = [:]
    var heldHits: [String: Int] = [:]
    var tallies: [Int: Tally] = [:]
    let overall = Tally()
    var sequences: [Sequence] = []
    var repeats: [Repeat] = []
    var sequencePairs = 0
    var closed: [[String]] = []
    var maximal: [[String]] = []
    var generators: [[String]] = []
    var groups: [ProductGroup] = []
    var substitutes: [Substitute] = []
    var customerSummaries: [CustomerSummary] = []

    init(_ params: Params, _ data: Dataset) {
        self.params = params
        self.data = data
        products = data.products
        names = data.products.keys.sorted()
        self.taxonomy = data.products.mapValues(\.category)
        categories = Set(data.products.values.map(\.category)).sorted()
        baskets = data.baskets
        itemSets = data.baskets.map(\.products)
        index = BasketIndex(data.baskets.map(\.products))
        let taxonomy = data.products.mapValues(\.category)
        extended = BasketIndex(data.baskets.map { extendedBasket($0.products, taxonomy) })
        total = data.baskets.count
        let grouped = Dictionary(grouping: data.baskets, by: \.customer)
        customerBaskets = grouped
        customers = grouped.keys.sorted()
        let histories = grouped.mapValues { baskets -> [String: [Int]] in
            var days: [String: Set<Int>] = [:]
            for basket in baskets { for name in basket.products { days[name, default: []].insert(basket.day) } }
            return days.mapValues { $0.sorted() }
        }
        self.histories = histories
        buyers = Dictionary(uniqueKeysWithValues: data.products.keys.map { name in (name, histories.values.filter { $0[name] != nil }.count) })
        firstDay = data.baskets.map(\.day).min()!
        lastDay = data.baskets.map(\.day).max()!
        let units = Dictionary(uniqueKeysWithValues: data.products.keys.map { name in (name, data.baskets.reduce(0) { $0 + $1.counts[name, default: 0] }) })
        self.units = units
        let revenue = data.products.mapValues { units[$0.name]! * $0.price }
        self.revenue = revenue
        totalRevenue = revenue.values.reduce(0, +)
    }
    func run() {
        main = runApriori(index, names, params.minSupport, params.maxSize)
        growth = fpGrowth(itemSets.map { Pattern(items: $0.sorted(), weight: 1) }, params.minSupport, params.maxSize)
        mainRules = makeRules(frequent, total, params)
        categoryRun = runApriori(extended, names + categories, params.categorySupport, params.maxSize, taxonomy)
        categoryRules = makeRules(categoryRun.supports, total, params, Set(categories))
        var nonClosed: Set<[String]> = []
        var nonMaximal: Set<[String]> = []
        for (items, count) in frequent where items.count > 1 {
            for subset in smallerSubsets(items) { nonMaximal.insert(subset); if frequent[subset] == count { nonClosed.insert(subset) } }
        }
        let ordered = frequent.keys.sorted(by: sizeBefore)
        closed = ordered.filter { !nonClosed.contains($0) }
        maximal = ordered.filter { !nonMaximal.contains($0) }
        generators = ordered.filter { items in smallerSubsets(items).allSatisfy { ($0.isEmpty ? total : frequent[$0]!) > frequent[items]! } }
        analyzeSequences()
        analyzeValidation()
        groups = buildGroups()
        substitutes = buildSubstitutes()
        customerSummaries = customers.map { customer in
            let baskets = customerBaskets[customer]!
            let days = Set(baskets.map(\.day)).sorted()
            var categoryUnits: [String: Int] = [:]
            for basket in baskets { for (name, count) in basket.counts { categoryUnits[taxonomy[name]!, default: 0] += count } }
            let favorite = categoryUnits.keys.sorted { categoryUnits[$0]! == categoryUnits[$1]! ? $0 < $1 : categoryUnits[$0]! > categoryUnits[$1]! }.first!
            let segment: String
            if days.first! > lastDay - 28 { segment = "NEW" }
            else if baskets.count >= 4 && lastDay - days.last! <= 14 { segment = "LOYAL" }
            else if lastDay - days.last! > 28 { segment = "AT_RISK" }
            else { segment = "REGULAR" }
            let held = Set(histories[customer]!.keys)
            let revenue = baskets.reduce(0) { total, basket in total + basket.counts.reduce(0) { $0 + $1.value * products[$1.key]!.price } }
            return CustomerSummary(name: customer, baskets: baskets.count, days: days.count, first: days.first!, last: days.last!, products: held.count, units: baskets.reduce(0) { $0 + $1.units }, revenue: revenue, favorite: favorite, segment: segment, offer: recommend(held, ruleCandidates(mainRules.rules, held), params.top))
        }
    }
    func analyzeSequences() {
        for first in names {
            for second in names {
                var gaps: [Int] = []
                for history in histories.values {
                    guard let a = history[first], let b = history[second], a.first! < b.last! else { continue }
                    var shortest = Int.max
                    for earlier in a { for later in b where earlier < later { shortest = min(shortest, later - earlier) } }
                    gaps.append(shortest)
                }
                if !gaps.isEmpty { sequencePairs += 1 }
                if gaps.count >= params.sequenceSupport { sequences.append(Sequence(first: first, second: second, count: gaps.count, base: buyers[first]!, confidence: Fraction(gaps.count, buyers[first]!), lift: liftOf(customers.count, gaps.count, buyers[first]!, buyers[second]!), gap: median(gaps))) }
            }
        }
        sequences.sort { a, b in
            if a.count != b.count { return a.count > b.count }
            if a.confidence != b.confidence { return a.confidence > b.confidence }
            return a.first == b.first ? a.second < b.second : a.first < b.first
        }
        for name in names {
            var intervals: [Int] = []
            var customers = 0
            for history in histories.values {
                guard let days = history[name], days.count > 1 else { continue }
                customers += 1
                intervals += zip(days, days.dropFirst()).map { pair in pair.1 - pair.0 }
            }
            if !intervals.isEmpty { repeats.append(Repeat(name: name, customers: customers, intervals: intervals)) }
        }
        repeats.sort { $0.mean == $1.mean ? $0.name < $1.name : $0.mean < $1.mean }
    }
    func analyzeValidation() {
        training = baskets.filter { $0.day <= params.splitDay }
        testing = baskets.filter { $0.day > params.splitDay }
        let trainIndex = BasketIndex(training.map(\.products))
        let testIndex = BasketIndex(testing.map(\.products))
        trainRun = runApriori(trainIndex, names, params.trainSupport, params.maxSize)
        testRun = runApriori(testIndex, names, params.testSupport, params.maxSize)
        trainRules = makeRules(trainRun.supports, training.count, params).rules
        testRules = makeRules(testRun.supports, testing.count, params).rules
        checks = trainRules.map { rule in
            let a = testIndex.count(rule.antecedent), b = testIndex.count(rule.consequent), c = testIndex.count(rule.items)
            let confidence = a == 0 || b == 0 ? nil : Fraction(c, a)
            let lift = a == 0 || b == 0 ? nil : liftOf(testing.count, c, a, b)
            let verdict: String
            if let confidence, let lift { verdict = meets(confidence, lift, params) ? "HOLD" : "FAIL" }
            else { verdict = "UNSEEN" }
            return RuleCheck(rule: rule, together: c, first: a, confidence: confidence, lift: lift, verdict: verdict)
        }
        emerging = testRules.filter { test in !trainRules.contains { $0.antecedent == test.antecedent && $0.consequent == test.consequent } }
        let popularity = names.sorted { trainRun.singles[$0]! == trainRun.singles[$1]! ? $0 < $1 : trainRun.singles[$0]! > trainRun.singles[$1]! }
        for name in names { heldOut[name] = 0; heldHits[name] = 0 }
        for basket in testing where basket.products.count >= 2 {
            for held in basket.products.sorted() {
                let atHand = basket.products.subtracting([held])
                let suggestion = recommend(atHand, ruleCandidates(trainRules, atHand), params.top)
                let baseline = recommend(atHand, popularity, params.top)
                if tallies[basket.products.count] == nil { tallies[basket.products.count] = Tally() }
                tallies[basket.products.count]!.add(held, suggestion, baseline)
                overall.add(held, suggestion, baseline)
                heldOut[held]! += 1
                if suggestion.contains(held) { heldHits[held]! += 1 }
            }
        }
    }
    func pairLift(_ pair: [String]) -> Fraction { liftOf(total, frequent[pair]!, counts[pair[0]]!, counts[pair[1]]!) }
    func buildGroups() -> [ProductGroup] {
        let edges = pairs.filter { pairLift($0) >= params.groupLift }
        var neighbors = Dictionary(uniqueKeysWithValues: names.map { ($0, Set<String>()) })
        for edge in edges { neighbors[edge[0]]!.insert(edge[1]); neighbors[edge[1]]!.insert(edge[0]) }
        var visited: Set<String> = []
        var groups: [ProductGroup] = []
        for name in names {
            if visited.contains(name) || neighbors[name]!.isEmpty { continue }
            var stack = [name]
            var members: [String] = []
            visited.insert(name)
            while let current = stack.popLast() {
                members.append(current)
                for neighbor in neighbors[current]! where visited.insert(neighbor).inserted { stack.append(neighbor) }
            }
            members.sort()
            let core = members.sorted { a, b in
                if neighbors[a]!.count != neighbors[b]!.count { return neighbors[a]!.count > neighbors[b]!.count }
                return counts[a]! == counts[b]! ? a < b : counts[a]! > counts[b]!
            }.first!
            groups.append(ProductGroup(members: members, edges: edges.filter { members.contains($0[0]) }.count, core: core, revenue: members.reduce(0) { $0 + revenue[$1]! }))
        }
        return groups.sorted { $0.members.count == $1.members.count ? $0.members[0] < $1.members[0] : $0.members.count > $1.members.count }
    }
    func buildSubstitutes() -> [Substitute] {
        let singles = main.levels[0].items.map { $0[0] }
        var result: [Substitute] = []
        for first in singles.indices {
            for second in (first + 1)..<singles.count {
                let a = singles[first], b = singles[second]
                let expected = counts[a]! * counts[b]!
                if expected < params.negativeExpected * total { continue }
                let together = index.count([a, b])
                let lift = liftOf(total, together, counts[a]!, counts[b]!)
                if lift <= params.negativeLift { result.append(Substitute(first: a, second: b, count: together, expected: Fraction(expected, total), lift: lift)) }
            }
        }
        return result.sorted { a, b in
            if a.lift != b.lift { return a.lift < b.lift }
            if a.expected != b.expected { return a.expected > b.expected }
            return a.first == b.first ? a.second < b.second : a.first < b.first
        }
    }
}

extension MarketAnalysis {
    func summaryLines() -> [String] {
        let sizes = itemSets.map(\.count)
        var lines = data.errors.map { "ERROR \($0)" }
        lines.append("ITEMS rows \(data.itemRows) adopted \(products.count) categories \(categories.count)")
        lines.append("TRANSACTIONS lines \(data.transactionLines) adopted \(data.adopted) rejected \(data.rejected) duplicates \(data.duplicates) transactions \(data.transactions.count) empty \(data.transactions.count - total)")
        lines.append("BASKETS count \(total) customers \(customers.count) first_day \(firstDay) last_day \(lastDay) average_size \(fractionText(Fraction(sizes.reduce(0, +), total))) largest \(sizes.max()!)")
        for size in 1...sizes.max()! {
            let count = sizes.filter { $0 == size }.count
            lines.append("SIZE \(size) baskets \(count) share \(percentText(count, total))")
        }
        lines.append("FREQUENT itemsets \(frequent.count) closed \(closed.count) maximal \(maximal.count) generators \(generators.count) levels \(main.levels.count)")
        let matched = growth.itemsets == frequent
        lines.append("FPGROWTH header \(growth.header) nodes \(growth.nodes) conditional_trees \(growth.conditionalTrees) conditional_nodes \(growth.conditionalNodes) itemsets \(growth.itemsets.count) \(matched ? "MATCH" : "MISMATCH")")
        if !matched {
            for (label, first, second) in [("ONLY_APRIORI", frequent, growth.itemsets), ("ONLY_FPGROWTH", growth.itemsets, frequent)] {
                for items in first.keys.sorted(by: sizeBefore) where first[items] != second[items] { lines.append("\(label) \(itemsetText(items)) \(first[items]!)") }
            }
        }
        lines.append("RULES generated \(mainRules.generated) passed \(mainRules.rules.count) productive \(mainRules.productive)")
        for level in categoryRun.levels { lines.append("CATEGORY_LEVEL \(level.number) candidates \(level.candidates) taxonomy \(level.excluded) pruned \(level.pruned) counted \(level.counted) frequent \(level.items.count)") }
        lines.append("CATEGORY_RULES itemsets \(categoryRun.supports.count) generated \(categoryRules.generated) passed \(categoryRules.rules.count) productive \(categoryRules.productive)")
        lines.append("SEQUENCES customers \(customers.count) multi_day \(customerSummaries.filter { $0.days >= 2 }.count) pairs \(sequencePairs) frequent \(sequences.count)")
        return lines
    }
    func itemsetLines() -> [String] {
        main.levels.flatMap { level in ["LEVEL \(level.number) candidates \(level.candidates) pruned \(level.pruned) counted \(level.counted) frequent \(level.items.count)"] + level.items.map { "\(itemsetText($0)) \(frequent[$0]!)" } }
    }
    func closedLines() -> [String] {
        [("CLOSED", closed), ("MAXIMAL", maximal), ("GENERATOR", generators)].flatMap { label, items in items.map { "\(label) \(itemsetText($0)) \(frequent[$0]!)" } }
    }
    func sequenceLines() -> [String] {
        var lines = sequences.enumerated().map { rank, sequence in "SEQ \(rank + 1) \(sequence.first) -> \(sequence.second) customers \(sequence.count) base \(sequence.base) confidence \(fractionText(sequence.confidence)) lift \(fractionText(sequence.lift)) gap \(fractionText(sequence.gap))" }
        for item in repeats { lines.append("REPEAT \(item.name) customers \(item.customers) intervals \(item.intervals.count) min \(item.intervals.min()!) max \(item.intervals.max()!) mean \(fractionText(item.mean)) median \(fractionText(median(item.intervals)))") }
        return lines
    }
    func validationLines() -> [String] {
        var lines = checks.map { check -> String in
            let rule = check.rule
            return "RULE \(rule.rank) \(ruleArrow(rule)) train \(rule.count) confidence \(fractionText(rule.confidence)) lift \(fractionText(rule.lift)) test \(check.together) of \(check.first) confidence \(check.confidence.map(fractionText) ?? "-") lift \(check.lift.map(fractionText) ?? "-") \(check.verdict)"
        }
        for rule in emerging { lines.append("EMERGING \(rule.rank) \(ruleArrow(rule)) test \(rule.count) confidence \(fractionText(rule.confidence)) lift \(fractionText(rule.lift))") }
        lines.append("VALIDATION train \(training.count) test \(testing.count) itemsets \(trainRun.supports.count) rules \(trainRules.count) hold \(checks.filter { $0.verdict == "HOLD" }.count) fail \(checks.filter { $0.verdict == "FAIL" }.count) unseen \(checks.filter { $0.verdict == "UNSEEN" }.count) emerging \(emerging.count)")
        for size in tallies.keys.sorted() { lines.append("RECOMMEND size \(size) \(tallies[size]!.describe())") }
        lines.append("RECOMMEND total \(overall.describe())")
        return lines
    }
    func partner(_ name: String) -> String {
        let eligible = pairs.filter { $0.contains(name) }.sorted { a, b in
            let first = pairLift(a), second = pairLift(b)
            if first != second { return first > second }
            if frequent[a]! != frequent[b]! { return frequent[a]! > frequent[b]! }
            return a.first { $0 != name }! < b.first { $0 != name }!
        }
        guard let pair = eligible.first else { return "none" }
        return "\(pair.first { $0 != name }!) \(fractionText(pairLift(pair)))"
    }
    func matrixLines(_ label: String, _ names: [String], _ index: BasketIndex, _ counts: [String: Int]) -> [String] {
        var lines = names.enumerated().map { position, name in "\(label) \(position + 1) \(name) baskets \(counts[name]!)" }
        func padded(_ text: String, _ width: Int) -> String { String(repeating: " ", count: max(0, width - text.count)) + text }
        lines.append("    " + (1...names.count).map { padded(String($0), 7) }.joined())
        for (row, first) in names.enumerated() {
            let cells = names.enumerated().map { column, second -> String in
                if row == column { return "-" }
                return String(100 * index.baskets.count * index.count([first, second]) / (counts[first]! * counts[second]!))
            }
            lines.append(padded(String(row + 1), 4) + cells.map { padded($0, 7) }.joined())
        }
        return lines
    }
    func itemLines() -> [String] {
        var lines: [String] = []
        let ranked = names.sorted { revenue[$0]! == revenue[$1]! ? $0 < $1 : revenue[$0]! > revenue[$1]! }
        for (position, name) in ranked.enumerated() {
            let product = products[name]!
            let strongest = mainRules.rules.first { $0.items.contains(name) }.map { "\($0.rank) \(ruleArrow($0))" } ?? "none"
            let containing = frequent.keys.filter { $0.contains(name) }.count
            lines.append("ITEM \(position + 1) \(name) \(product.category) price \(money(product.price)) units \(units[name]!) revenue \(money(revenue[name]!)) share \(percentText(revenue[name]!, totalRevenue)) baskets \(counts[name]!) support \(fractionText(Fraction(counts[name]!, total))) customers \(buyers[name]!) itemsets \(containing) heldout \(heldOut[name]!) hits \(heldHits[name]!) partner \(partner(name)) best \(strongest)")
        }
        let categoryRevenue = Dictionary(uniqueKeysWithValues: categories.map { category in (category, names.filter { taxonomy[$0]! == category }.reduce(0) { $0 + revenue[$1]! }) })
        for category in categories.sorted(by: { categoryRevenue[$0]! == categoryRevenue[$1]! ? $0 < $1 : categoryRevenue[$0]! > categoryRevenue[$1]! }) {
            let members = names.filter { taxonomy[$0]! == category }
            let count = categoryRun.singles[category]!
            let sold = members.reduce(0) { $0 + units[$1]! }
            lines.append("CATEGORY \(category) items \(members.count) units \(sold) revenue \(money(categoryRevenue[category]!)) share \(percentText(categoryRevenue[category]!, totalRevenue)) baskets \(count) support \(fractionText(Fraction(count, total)))")
        }
        lines.append("TOTAL items \(products.count) units \(units.values.reduce(0, +)) revenue \(money(totalRevenue)) baskets \(total) customers \(customers.count)")
        for (position, group) in groups.enumerated() { lines.append("GROUP \(position + 1) items \(group.members.count) edges \(group.edges) core \(group.core) revenue \(money(group.revenue)) share \(percentText(group.revenue, totalRevenue)) members \(itemsetText(group.members))") }
        for substitute in substitutes { lines.append("SUBSTITUTE \(substitute.first) \(substitute.second) count \(substitute.count) expected \(fractionText(substitute.expected)) lift \(fractionText(substitute.lift))") }
        let bySupport = names.sorted { counts[$0]! == counts[$1]! ? $0 < $1 : counts[$0]! > counts[$1]! }
        lines += matrixLines("MATRIX", Array(bySupport.prefix(params.matrixSize)), index, counts)
        let byCategorySupport = categories.sorted { categoryRun.singles[$0]! == categoryRun.singles[$1]! ? $0 < $1 : categoryRun.singles[$0]! > categoryRun.singles[$1]! }
        lines += matrixLines("CATEGORY_MATRIX", byCategorySupport, extended, categoryRun.singles)
        return lines
    }
    func trendLines() -> [String] {
        let weeks = (lastDay - 1) / 7 + 1
        var weekBaskets = Array(repeating: 0, count: weeks)
        var weekUnits = Array(repeating: 0, count: weeks)
        var weekCustomers = Array(repeating: Set<String>(), count: weeks)
        var series = Dictionary(uniqueKeysWithValues: (categories + names).map { ($0, Array(repeating: 0, count: weeks)) })
        for basket in baskets {
            let week = (basket.day - 1) / 7
            weekBaskets[week] += 1
            weekUnits[week] += basket.units
            weekCustomers[week].insert(basket.customer)
            for (name, count) in basket.counts { series[name]![week] += count; series[taxonomy[name]!]![week] += count }
        }
        func row(_ label: String, _ values: [Int]) -> String {
            label + String(repeating: " ", count: 17 - label.count) + values.map { value in let text = String(value); return String(repeating: " ", count: max(0, 6 - text.count)) + text }.joined()
        }
        var lines = [row("WEEK", Array(1...weeks)), row("BASKETS", weekBaskets), row("UNITS", weekUnits), row("CUSTOMERS", weekCustomers.map(\.count))]
        for name in categories + names { lines.append(row(name, series[name]!)) }
        let weekSum = (1...weeks).reduce(0, +)
        let squareSum = (1...weeks).reduce(0) { $0 + $1 * $1 }
        var trends = (categories + names).map { name -> Trend in
            let values = series[name]!
            let total = values.reduce(0, +)
            let weighted = values.enumerated().reduce(0) { $0 + ($1.offset + 1) * $1.element }
            let slope = Fraction(weeks * weighted - weekSum * total, weeks * squareSum - weekSum * weekSum)
            let relative = total == 0 ? nil : Fraction(slope.numerator * weeks, slope.denominator * total)
            let verdict: String
            if let relative { verdict = relative >= params.trendThreshold ? "RISING" : relative <= -params.trendThreshold ? "FALLING" : "FLAT" }
            else { verdict = "NONE" }
            return Trend(name: name, units: total, slope: slope, relative: relative, verdict: verdict)
        }
        trends.sort { a, b in
            switch (a.relative, b.relative) {
            case let (first?, second?): return first == second ? a.name < b.name : first > second
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.name < b.name
            }
        }
        for trend in trends { lines.append("TREND \(trend.name) units \(trend.units) slope \(fractionText(trend.slope)) relative \(trend.relative.map(fractionText) ?? "-") \(trend.verdict)") }
        return lines
    }
    func customerLines() -> [String] {
        var lines = customerSummaries.map { summary in
            "CUSTOMER \(summary.name) baskets \(summary.baskets) days \(summary.days) first \(summary.first) last \(summary.last) items \(summary.products) units \(summary.units) revenue \(money(summary.revenue)) average \(money(summary.revenue / summary.baskets)) favorite \(summary.favorite) segment \(summary.segment) offer \(summary.offer.isEmpty ? "none" : itemsetText(summary.offer))"
        }
        for segment in ["NEW", "LOYAL", "AT_RISK", "REGULAR"] {
            let members = customerSummaries.filter { $0.segment == segment }
            let revenue = members.reduce(0) { $0 + $1.revenue }
            lines.append("SEGMENT \(segment) customers \(members.count) revenue \(money(revenue)) share \(percentText(revenue, totalRevenue))")
        }
        return lines
    }
    func write() throws {
        for (name, lines) in [("summary.txt", summaryLines()), ("itemsets.txt", itemsetLines()), ("closed_maximal.txt", closedLines()), ("rules.csv", rulesCsv(mainRules.rules)), ("category_rules.csv", rulesCsv(categoryRules.rules)), ("sequences.txt", sequenceLines()), ("validation.txt", validationLines()), ("items_report.txt", itemLines()), ("trends.txt", trendLines()), ("customers.txt", customerLines())] { try writeReport(name, lines) }
    }
}

let analysis = try MarketAnalysis(readParams(), Dataset())
analysis.run()
try analysis.write()
