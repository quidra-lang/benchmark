import Foundation

struct CommandError: Error { let message: String }
func fail(_ message: String) throws -> Never { throw CommandError(message: message) }
enum MarketKind: String { case twoSided = "MARKET", roommate = "ROOMS", housing = "HOUSES" }
enum Side { case proposer, receiver }
enum Source: String { case gs = "GS", gsr = "GSR", boston = "BOSTON", egalitarian = "EGALITARIAN", minRegret = "MINREGRET" }
typealias Preference = [Int]
typealias Matching = [Int]
struct Saved { let source: Source; let matching: Matching }

func rank(_ preference: Preference, _ partner: Int) -> Int { preference.firstIndex(of: partner).map { $0 + 1 } ?? (preference.count + 1) }
func listText(_ names: [String], _ indices: [Int]) -> String { indices.isEmpty ? "-" : indices.map { names[$0] }.joined(separator: " ") }
struct Market {
    let name: String
    let kind: MarketKind
    let names: [String]
    let proposers: Int
    let houses: [String]
    var preferences: [Preference]
    var capacities: [Int]
    var current: Saved?

    init(_ name: String, _ kind: MarketKind, _ names: [String], proposers: Int = 0, houses: [String] = []) {
        self.name = name
        self.kind = kind
        self.names = names
        self.proposers = proposers
        self.houses = houses
        preferences = names.map { _ in [] }
        capacities = names.map { _ in 1 }
        current = nil
    }
    func requireKind(_ expected: MarketKind) throws { if kind != expected { try fail("WRONG TYPE \(name)") } }
    func agent(_ name: String, side: Side? = nil) throws -> Int {
        guard let index = names.firstIndex(of: name) else { try fail("UNKNOWN AGENT \(name)") }
        if side == .proposer && index >= proposers { try fail("NOT PROPOSER \(name)") }
        if side == .receiver && index < proposers { try fail("NOT RECEIVER \(name)") }
        return index
    }
    func effective(_ agent: Int) -> Preference {
        let preference = preferences[agent]
        if let own = preference.firstIndex(of: agent) { return Array(preference.prefix(own + 1)) }
        return preference + [agent]
    }
    func partnerName(_ partner: Int) -> String { partner < 0 ? "*" : names[partner] }
}
func pairText(_ market: Market, _ matching: Matching) -> String {
    (0..<market.proposers).map { "\(market.names[$0])-\(market.partnerName(matching[$0]))" }.joined(separator: " ")
}
func rotationText(_ market: Market, _ matching: Matching, _ rotation: [Int]) -> String {
    rotation.map { "\(market.names[$0])-\(market.names[matching[$0]])" }.joined(separator: " ")
}
func allocationText(_ market: Market, _ allocation: [Int]) -> String {
    market.names.indices.map { "\(market.names[$0])-\(allocation[$0] < 0 ? "*" : market.houses[allocation[$0]])" }.joined(separator: " ")
}
func partnersOf(_ matching: Matching, _ receiver: Int) -> [Int] { matching.indices.filter { matching[$0] == receiver } }

struct DeferredResult { let matching: Matching; let proposals: Int; let history: [String] }
func deferred(_ market: Market, reverse: Bool = false, verbose: Bool = false) -> DeferredResult {
    let count = market.names.count
    var next = Array(repeating: 0, count: count), counts = Array(repeating: 0, count: count)
    var holding = Array(repeating: [Int](), count: count), queued = Array(repeating: false, count: count)
    let able = { (agent: Int) in counts[agent] < market.capacities[agent] && next[agent] < market.preferences[agent].count }
    let proposing = reverse ? Array(market.proposers..<count) : Array(0..<market.proposers)
    var queue = proposing.filter(able), history: [String] = []
    for agent in queue { queued[agent] = true }
    var head = 0, proposals = 0
    while head < queue.count {
        let proposer = queue[head]
        head += 1
        queued[proposer] = false
        let receiver = market.preferences[proposer][next[proposer]]
        let preference = market.preferences[receiver]
        next[proposer] += 1
        proposals += 1
        var action = "REJECT"
        if preference.contains(proposer) {
            if holding[receiver].count < market.capacities[receiver] {
                holding[receiver].append(proposer)
                counts[proposer] += 1
                action = "HOLD"
            } else {
                let worst = holding[receiver].indices.max { rank(preference, holding[receiver][$0]) < rank(preference, holding[receiver][$1]) }!
                let rejected = holding[receiver][worst]
                if rank(preference, proposer) < rank(preference, rejected) {
                    holding[receiver][worst] = proposer
                    counts[proposer] += 1
                    counts[rejected] -= 1
                    action = "HOLD REJECT \(market.names[rejected])"
                    if able(rejected) && !queued[rejected] { queue.append(rejected); queued[rejected] = true }
                }
            }
        }
        if verbose { history.append("PROPOSE \(market.names[proposer]) \(market.names[receiver]) \(action)") }
        if able(proposer) { queue.append(proposer); queued[proposer] = true }
    }
    var matching = Array(repeating: -1, count: market.proposers)
    let receiving = reverse ? Array(0..<market.proposers) : Array(market.proposers..<count)
    for receiver in receiving {
        for proposer in holding[receiver] {
            if reverse { matching[receiver] = proposer }
            else { matching[proposer] = receiver }
        }
    }
    return DeferredResult(matching: matching, proposals: proposals, history: history)
}
struct BostonResult { let matching: Matching; let applications: Int }
func boston(_ market: Market) -> BostonResult {
    var matching = Array(repeating: -1, count: market.proposers), remaining = market.capacities
    let rounds = market.preferences.prefix(market.proposers).map(\.count).max()!
    var applications = 0
    for round in 0..<rounds {
        var applied = Array(repeating: -1, count: market.proposers)
        for proposer in 0..<market.proposers where matching[proposer] < 0 && round < market.preferences[proposer].count {
            applied[proposer] = market.preferences[proposer][round]
            applications += 1
        }
        for receiver in market.proposers..<market.names.count {
            for proposer in market.preferences[receiver] where remaining[receiver] > 0 && applied[proposer] == receiver {
                matching[proposer] = receiver
                remaining[receiver] -= 1
            }
        }
    }
    return BostonResult(matching: matching, applications: applications)
}

func exposedRotations(_ market: Market, _ matching: Matching) -> [[Int]] {
    var owner = Array(repeating: -1, count: market.names.count), successor = Array(repeating: -1, count: market.proposers)
    for proposer in 0..<market.proposers where matching[proposer] >= 0 { owner[matching[proposer]] = proposer }
    for proposer in 0..<market.proposers {
        if matching[proposer] < 0 { continue }
        let preference = market.preferences[proposer]
        for receiver in preference.dropFirst(rank(preference, matching[proposer])) {
            let ranking = market.preferences[receiver]
            if ranking.contains(proposer) && (owner[receiver] < 0 || rank(ranking, proposer) < rank(ranking, owner[receiver])) {
                successor[proposer] = owner[receiver]
                break
            }
        }
    }
    var covered: Set<Int> = [], rotations: [[Int]] = []
    for start in 0..<market.proposers where !covered.contains(start) {
        var path: [Int] = [], point = start
        while point >= 0 && !path.contains(point) { path.append(point); point = successor[point] }
        if point == start { covered.formUnion(path); rotations.append(path) }
    }
    return rotations
}
struct Metrics { let cost: Int; let regret: Int }
func metrics(_ market: Market, _ matching: Matching) -> Metrics {
    var cost = 0, regret = 0
    for proposer in 0..<market.proposers {
        let receiver = matching[proposer]
        if receiver < 0 { continue }
        let first = rank(market.preferences[proposer], receiver), second = rank(market.preferences[receiver], proposer)
        cost += first + second
        regret = max(regret, max(first, second))
    }
    return Metrics(cost: cost, regret: regret)
}
struct Entry { let matching: Matching; let origin: Int?; let via: Int? }
struct Lattice { let entries: [Entry]; let rotations: [String] }
func enumerate(_ market: Market) throws -> Lattice {
    guard market.capacities.dropFirst(market.proposers).allSatisfy({ $0 == 1 }) else { try fail("NOT ONE TO ONE") }
    let initial = deferred(market).matching
    var entries = [Entry(matching: initial, origin: nil, via: nil)], rotations: [String] = []
    var seen: Set<Matching> = [initial], index = 0
    while index < entries.count {
        let matching = entries[index].matching
        for rotation in exposedRotations(market, matching) {
            let notation = rotationText(market, matching, rotation)
            let identifier: Int
            if let found = rotations.firstIndex(of: notation) { identifier = found }
            else { identifier = rotations.count; rotations.append(notation) }
            var following = matching
            for i in rotation.indices { following[rotation[i]] = matching[rotation[(i + 1) % rotation.count]] }
            if seen.contains(following) { continue }
            if entries.count == 50 { try fail("TOO MANY MATCHINGS") }
            seen.insert(following)
            entries.append(Entry(matching: following, origin: index + 1, via: identifier + 1))
        }
        index += 1
    }
    return Lattice(entries: entries, rotations: rotations)
}
func checkPairs(_ market: Market, _ pairs: [String]) throws -> [String] {
    if market.kind == .housing { try fail("WRONG TYPE \(market.name)") }
    var matching = Array(repeating: -1, count: market.names.count), counts = Array(repeating: 0, count: market.names.count)
    for word in pairs {
        let pair = word.split(separator: "-").map(String.init)
        let first = try market.agent(pair[0], side: market.kind == .twoSided ? .proposer : nil)
        let second = try market.agent(pair[1], side: market.kind == .twoSided ? .receiver : nil)
        if matching[first] >= 0 { try fail("DUPLICATE AGENT \(pair[0])") }
        if market.kind == .twoSided {
            counts[second] += 1
            if counts[second] > market.capacities[second] { try fail("OVER CAPACITY \(pair[1])") }
        } else {
            if first == second || matching[second] >= 0 { try fail("DUPLICATE AGENT \(pair[1])") }
            matching[second] = first
        }
        matching[first] = second
    }
    var unacceptable: [String] = [], blocking: [String] = []
    if market.kind == .twoSided {
        for proposer in 0..<market.proposers {
            let receiver = matching[proposer], preference = market.preferences[proposer]
            if receiver >= 0 && (!preference.contains(receiver) || !market.preferences[receiver].contains(proposer)) {
                unacceptable.append("UNACCEPTABLE \(market.names[proposer]) \(market.names[receiver])")
            }
            for other in market.proposers..<market.names.count {
                let ranking = market.preferences[other]
                if receiver == other || !preference.contains(other) || !ranking.contains(proposer) { continue }
                if rank(preference, other) >= rank(preference, receiver) { continue }
                var worst = 0
                for partner in 0..<market.proposers where matching[partner] == other { worst = max(worst, rank(ranking, partner)) }
                if counts[other] < market.capacities[other] || rank(ranking, proposer) < worst {
                    blocking.append("BLOCKING \(market.names[proposer]) \(market.names[other])")
                }
            }
        }
    } else {
        for first in market.names.indices {
            for second in (first + 1)..<market.names.count {
                let mutual = market.preferences[first].contains(second) && market.preferences[second].contains(first)
                let notation = "\(market.names[first]) \(market.names[second])"
                if matching[first] == second {
                    if !mutual { unacceptable.append("UNACCEPTABLE \(notation)") }
                } else if mutual && rank(market.preferences[first], second) < rank(market.preferences[first], matching[first])
                    && rank(market.preferences[second], first) < rank(market.preferences[second], matching[second]) {
                    blocking.append("BLOCKING \(notation)")
                }
            }
        }
    }
    if unacceptable.isEmpty && blocking.isEmpty { return ["CHECK \(market.name) STABLE"] }
    return ["CHECK \(market.name) UNSTABLE unacceptable=\(unacceptable.count) blocking=\(blocking.count)"] + unacceptable + blocking
}
func removePair(_ lists: inout [Preference], _ first: Int, _ second: Int) {
    lists[first].removeAll { $0 == second }
    lists[second].removeAll { $0 == first }
}
func tableLines(_ market: Market, _ lists: [Preference]) -> [String] {
    market.names.indices.map { "TABLE \(market.names[$0]) \(listText(market.names, lists[$0]))" }
}

func roommates(_ market: Market, verbose: Bool) throws -> [String] {
    try market.requireKind(.roommate)
    let count = market.names.count
    for agent in market.names.indices where market.preferences[agent].count < count - 1 { try fail("INCOMPLETE \(market.names[agent])") }
    var lists = market.preferences, held = Array(repeating: -1, count: count), queue = Array(0..<count)
    var head = 0, proposals = 0, failure: Int?
    while head < queue.count {
        let proposer = queue[head]
        head += 1
        let receiver = lists[proposer][0]
        if held[receiver] >= 0 { queue.append(held[receiver]) }
        held[receiver] = proposer
        proposals += 1
        let preference = lists[receiver]
        for other in preference.dropFirst(preference.firstIndex(of: proposer)! + 1) { removePair(&lists, receiver, other) }
        failure = lists.firstIndex(where: { $0.isEmpty })
        if failure != nil { break }
    }
    var history = failure == nil && verbose ? tableLines(market, lists) : []
    var rotations = 0
    while failure == nil {
        guard let start = lists.firstIndex(where: { $0.count >= 2 }) else { break }
        var path: [Int] = [], point = start
        while !path.contains(point) { path.append(point); point = lists[lists[point][1]].last! }
        let rotation = Array(path.dropFirst(path.firstIndex(of: point)!))
        let front = rotation.map { lists[$0][0] }
        rotations += 1
        let pairs = rotation.indices.map { "\(market.names[rotation[$0]])-\(market.names[front[$0]])" }
        history.append("ROTATION \(rotations) \(pairs.joined(separator: " "))")
        var removals: [(Int, Int)] = []
        for index in rotation.indices {
            let receiver = front[(index + 1) % front.count], agent = rotation[index]
            let preference = lists[receiver]
            for other in preference.dropFirst(preference.firstIndex(of: agent)! + 1) { removals.append((receiver, other)) }
        }
        for (first, second) in removals { removePair(&lists, first, second) }
        if verbose { history += tableLines(market, lists) }
        failure = lists.firstIndex(where: { $0.isEmpty })
    }
    let output = ["ROOMMATES \(market.name) proposals=\(proposals)"] + history
    if let agent = failure { return output + ["NO STABLE MATCHING \(market.names[agent])"] }
    let pairs = market.names.indices.filter { $0 < lists[$0][0] }.map { "\(market.names[$0])-\(market.names[lists[$0][0]])" }
    return output + ["MATCHING \(pairs.joined(separator: " "))"]
}
func ttc(_ market: Market) -> [String] {
    var remaining = Set(market.names.indices), allocation = Array(repeating: -1, count: market.names.count), cycles: [String] = []
    while !remaining.isEmpty {
        var pointing = Array(repeating: -1, count: market.names.count)
        for agent in market.names.indices where remaining.contains(agent) {
            pointing[agent] = market.effective(agent).first(where: { remaining.contains($0) })!
        }
        var path: [Int] = [], point = remaining.min()!
        while !path.contains(point) { path.append(point); point = pointing[point] }
        let cycle = Array(path.dropFirst(path.firstIndex(of: point)!))
        for agent in cycle { allocation[agent] = pointing[agent]; remaining.remove(agent) }
        let parts = cycle.map { "\(market.names[$0]):\(market.houses[allocation[$0]])" }
        cycles.append("CYCLE \(cycles.count + 1) \(parts.joined(separator: " "))")
    }
    return ["TTC \(market.name) cycles=\(cycles.count)"] + cycles + ["ALLOCATION \(allocationText(market, allocation))"]
}
func serial(_ market: Market, _ names: [String]) throws -> [String] {
    var order: [Int] = []
    for name in names {
        let agent = try market.agent(name)
        if order.contains(agent) { try fail("DUPLICATE AGENT \(name)") }
        order.append(agent)
    }
    guard order.count == market.names.count else { try fail("BAD ORDER") }
    var remaining = Set(market.houses.indices), allocation = Array(repeating: -1, count: market.names.count), assigned = 0
    for agent in order {
        if let house = market.preferences[agent].first(where: { remaining.contains($0) }) {
            allocation[agent] = house
            remaining.remove(house)
            assigned += 1
        }
    }
    let worse = market.names.indices.filter { !market.effective($0).contains(allocation[$0]) }
    return ["SERIAL \(market.name) assigned=\(assigned)", "ALLOCATION \(allocationText(market, allocation))", "WORSE \(listText(market.names, worse))"]
}
func hospitalReport(_ market: Market) -> [String] {
    let resident = deferred(market).matching, hospital = deferred(market, reverse: true).matching
    let unmatched = (0..<market.proposers).filter { resident[$0] < 0 }
    var rural = (0..<market.proposers).allSatisfy { (resident[$0] >= 0) == (hospital[$0] >= 0) }
    var output = ["HR \(market.name) residents=\(market.proposers) hospitals=\(market.names.count - market.proposers)",
        "RESIDENT-OPTIMAL \(pairText(market, resident))", "HOSPITAL-OPTIMAL \(pairText(market, hospital))", "UNMATCHED \(listText(market.names, unmatched))"]
    for receiver in market.proposers..<market.names.count {
        let first = partnersOf(resident, receiver), second = partnersOf(hospital, receiver), capacity = market.capacities[receiver]
        let same = first == second
        output.append("HOSPITAL \(market.names[receiver]) cap=\(capacity) resident=\(first.count) hospital=\(second.count) same=\(same ? "YES" : "NO")")
        if first.count != second.count || (first.count < capacity && !same) { rural = false }
    }
    return output + [rural ? "RURAL HOLDS" : "RURAL FAILS"]
}
func manipulate(_ market: Market, _ proposer: Int) -> [String] {
    let truth = market.preferences[proposer]
    let baselineB = boston(market).matching[proposer], baselineG = deferred(market).matching[proposer]
    let swaps = max(0, truth.count - 1)
    var output = ["MANIPULATE \(market.name) \(market.names[proposer]) boston=\(market.partnerName(baselineB)) gs=\(market.partnerName(baselineG)) swaps=\(swaps)"]
    for index in 0..<swaps {
        var trial = market
        trial.preferences[proposer].swapAt(index, index + 1)
        let outcomes = [("BOSTON", boston(trial).matching[proposer], baselineB), ("GS", deferred(trial).matching[proposer], baselineG)]
        for (label, partner, baseline) in outcomes where rank(truth, partner) < rank(truth, baseline) {
            output.append("IMPROVE \(label) \(index + 1) \(market.names[truth[index]]) \(market.names[truth[index + 1]]) result=\(market.partnerName(partner))")
        }
    }
    if output.count == 1 { output.append("NO IMPROVEMENT") }
    return output
}
func gcd(_ first: Int, _ second: Int) -> Int {
    var a = first, b = second
    while b != 0 { (a, b) = (b, a % b) }
    return a
}
func statistics(_ market: Market) throws -> [String] {
    guard let saved = market.current else { try fail("NO MATCHING") }
    var proposerRanks: [Int] = [], receiverRanks: [Int] = [], occupied: Set<Int> = []
    for proposer in 0..<market.proposers {
        let receiver = saved.matching[proposer]
        if receiver < 0 { continue }
        proposerRanks.append(rank(market.preferences[proposer], receiver))
        receiverRanks.append(rank(market.preferences[receiver], proposer))
        occupied.insert(receiver)
    }
    let pairs = proposerRanks.count
    var output = ["STATS \(market.name) source=\(saved.source.rawValue) pairs=\(pairs)"]
    let summaries = [("PROPOSERS", proposerRanks, market.proposers - pairs), ("RECEIVERS", receiverRanks, market.names.count - market.proposers - occupied.count)]
    for (label, ranks, unmatched) in summaries {
        let sum = ranks.reduce(0, +), first = ranks.filter { $0 == 1 }.count
        var average = "-", truncated = "-"
        if pairs > 0 {
            let divisor = gcd(sum, pairs), cents = 100 * sum / pairs
            average = "\(sum / divisor)/\(pairs / divisor)"
            truncated = "\(cents / 100).\(cents % 100 < 10 ? "0" : "")\(cents % 100)"
        }
        output.append("\(label) sum=\(sum) average=\(average) truncated=\(truncated) first=\(first) unmatched=\(unmatched)")
    }
    return output
}
func showMarket(_ market: Market) -> [String] {
    let detail = market.kind == .twoSided ? "proposers=\(market.proposers) receivers=\(market.names.count - market.proposers)" : "agents=\(market.names.count)"
    var rows = ["SHOW \(market.name) \(market.kind.rawValue) \(detail)"]
    for agent in market.names.indices {
        var prefix: String
        if market.kind == .twoSided {
            prefix = agent < market.proposers ? "PROPOSER \(market.names[agent])" : "RECEIVER \(market.names[agent]) cap=\(market.capacities[agent])"
        } else {
            prefix = "AGENT \(market.names[agent])"
            if market.kind == .housing { prefix += " house=\(market.houses[agent])" }
        }
        rows.append(prefix + " " + listText(market.kind == .housing ? market.houses : market.names, market.preferences[agent]))
    }
    if market.kind == .twoSided { rows.append("CURRENT \(market.current?.source.rawValue ?? "-")") }
    return rows
}
func newMarket(_ command: String, _ name: String, _ args: [String]) throws -> Market {
    if command == "RANDOM" {
        let count = Int(args[0])!
        var state = Int64(args[1])!
        let names = ["P", "R"].flatMap { prefix in (1...count).map { "\(prefix)\($0)" } }
        var market = Market(name, .twoSided, names, proposers: count)
        for agent in names.indices {
            var preference = agent < count ? Array(count..<(2 * count)) : Array(0..<count)
            for length in stride(from: count, through: 2, by: -1) {
                state = 48271 * state % 2147483647
                preference.swapAt(length - 1, Int(state % Int64(length)))
            }
            market.preferences[agent] = preference
        }
        return market
    }
    let kind: MarketKind = command == "ROOMS" ? .roommate : command == "HOUSES" ? .housing : .twoSided
    var names: [String] = [], houses: [String] = [], proposers = 0
    for word in args {
        if word == "|" { proposers = names.count; continue }
        let pair = word.split(separator: ":").map(String.init)
        if names.contains(pair[0]) { try fail("DUPLICATE AGENT \(pair[0])") }
        if kind == .housing {
            if houses.contains(pair[1]) { try fail("DUPLICATE HOUSE \(pair[1])") }
            houses.append(pair[1])
        }
        names.append(pair[0])
    }
    return Market(name, kind, names, proposers: proposers, houses: houses)
}
func executeMarket(_ market: inout Market, _ command: String, _ args: [String]) throws -> [String] {
    let name = market.name
    if command == "SHOW" { return showMarket(market) }
    if command == "PREF" {
        let agent = try market.agent(args[0])
        let names = market.kind == .housing ? market.houses : market.names
        var preference: Preference = []
        for word in args.dropFirst() {
            guard let choice = names.firstIndex(of: word) else { try fail("BAD CHOICE \(word)") }
            if (market.kind == .roommate && choice == agent) || (market.kind == .twoSided && ((agent < market.proposers) == (choice < market.proposers))) {
                try fail("BAD CHOICE \(word)")
            }
            if preference.contains(choice) { try fail("DUPLICATE CHOICE \(word)") }
            preference.append(choice)
        }
        market.preferences[agent] = preference
        if market.kind == .twoSided { market.current = nil }
        return ["PREF \(name) \(args[0]) length=\(preference.count)"]
    }
    if command == "CHECK" { return try checkPairs(market, args) }
    if command == "ROOMMATES" { return try roommates(market, verbose: args.count == 1) }
    if command == "TTC" || command == "SERIAL" {
        try market.requireKind(.housing)
        if command == "TTC" { return ttc(market) }
        return try serial(market, args)
    }
    try market.requireKind(.twoSided)
    if command == "CAPACITY" {
        let receiver = try market.agent(args[0], side: .receiver), capacity = Int(args[1])!
        market.capacities[receiver] = capacity
        market.current = nil
        return ["CAPACITY \(name) \(args[0]) \(capacity)"]
    }
    if command == "GS" || command == "GSR" {
        let run = deferred(market, reverse: command == "GSR", verbose: args.count == 1)
        market.current = Saved(source: command == "GS" ? .gs : .gsr, matching: run.matching)
        return ["\(command) \(name) proposals=\(run.proposals)"] + run.history + ["MATCHING \(pairText(market, run.matching))"]
    }
    if command == "BOSTON" {
        let run = boston(market)
        market.current = Saved(source: .boston, matching: run.matching)
        return ["BOSTON \(name) applications=\(run.applications)", "MATCHING \(pairText(market, run.matching))"]
    }
    if command == "HR" { return hospitalReport(market) }
    if command == "MANIPULATE" { return try manipulate(market, market.agent(args[0], side: .proposer)) }
    if command == "STATS" { return try statistics(market) }
    let lattice = try enumerate(market)
    if command == "LATTICE" {
        var output = ["LATTICE \(name) matchings=\(lattice.entries.count) rotations=\(lattice.rotations.count)"]
        for (index, entry) in lattice.entries.enumerated() {
            let measure = metrics(market, entry.matching)
            let origin = entry.origin.map(String.init) ?? "-", via = entry.via.map(String.init) ?? "-"
            output.append("MATCHING \(index + 1) from=\(origin) via=\(via) cost=\(measure.cost) regret=\(measure.regret) \(pairText(market, entry.matching))")
        }
        for (index, rotation) in lattice.rotations.enumerated() { output.append("ROTATION \(index + 1) \(rotation)") }
        return output
    }
    let values = lattice.entries.map { entry -> Int in
        let measure = metrics(market, entry.matching)
        return command == "EGALITARIAN" ? measure.cost : measure.regret
    }
    let best = values.indices.min { values[$0] < values[$1] }!
    let matching = lattice.entries[best].matching, label = command == "EGALITARIAN" ? "cost" : "regret"
    market.current = Saved(source: command == "EGALITARIAN" ? .egalitarian : .minRegret, matching: matching)
    return ["\(command) \(name) matching=\(best + 1) \(label)=\(values[best])", "MATCHING \(pairText(market, matching))"]
}
final class Laboratory {
    private var markets: [String: Market] = [:]

    func execute(_ line: String) throws -> [String] {
        let words = line.split(separator: " ").map(String.init)
        let command = words[0], name = words[1], args = Array(words.dropFirst(2))
        if ["MARKET", "ROOMS", "HOUSES", "RANDOM"].contains(command) {
            if markets[name] != nil { try fail("DUPLICATE MARKET \(name)") }
            let market = try newMarket(command, name, args)
            let response: String
            if command == "RANDOM" { response = "RANDOM \(name) n=\(market.proposers) seed=\(args[1])" }
            else if command == "MARKET" { response = "MARKET \(name) proposers=\(market.proposers) receivers=\(market.names.count - market.proposers)" }
            else { response = "\(command) \(name) agents=\(market.names.count)" }
            markets[name] = market
            return [response]
        }
        guard var market = markets[name] else { try fail("UNKNOWN MARKET \(name)") }
        let output = try executeMarket(&market, command, args)
        markets[name] = market
        return output
    }
}

let count = Int(readLine()!)!
let laboratory = Laboratory()
var output: [String] = []
for _ in 0..<count {
    do { output += try laboratory.execute(readLine()!) }
    catch let error as CommandError { output.append("ERROR \(error.message)") }
    catch { fatalError("Unexpected error: \(error)") }
}
print(output.joined(separator: "\n"))
