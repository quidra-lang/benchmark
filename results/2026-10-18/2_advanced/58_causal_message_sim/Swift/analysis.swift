import Foundation

func graphEdges(_ events: [Event], _ processes: [ProcessState], _ copies: [MessageCopy]) -> [[Int]] {
    var edges = Array(repeating: [Int](), count: events.count)
    for (i, event) in events.enumerated() { let local = processes[event.process].events; if event.localNumber < local.count { edges[i].append(local[event.localNumber]) } }
    for copy in copies { if let receive = copy.receiveEvent { edges[copy.sendEvent].append(receive) } }
    return edges
}
func graphPath(_ source: Int, _ target: Int, _ edges: [[Int]]) -> [Int]? {
    var parent = Array<Int?>(repeating: nil, count: edges.count), seen = Array(repeating: false, count: edges.count), queue = [source], cursor = 0
    seen[source] = true
    while cursor < queue.count && !seen[target] {
        let current = queue[cursor]; cursor += 1
        for next in edges[current] where !seen[next] { seen[next] = true; parent[next] = current; queue.append(next) }
    }
    if !seen[target] { return nil }
    var path: [Int] = [], current: Int? = target
    while let value = current { path.append(value); current = parent[value] }
    return Array(path.reversed())
}
struct ConcurrencyStatistics { let pairs: Int; let ordered: Int; let concurrent: Int; let sameLamport: Int; let inversions: Int; let byPair: [ChannelKey: Int] }
func concurrencyStatistics(_ events: [Event]) -> ConcurrencyStatistics {
    var ordered = 0, concurrent = 0, same = 0, inversions = 0, byPair: [ChannelKey: Int] = [:]
    for (i, a) in events.enumerated() {
        for b in events.dropFirst(i + 1) {
            if relation(a.vector, b.vector) == "||" {
                concurrent += 1; if a.lamport == b.lamport { same += 1 }
                if a.process != b.process { byPair[ChannelKey(source: min(a.process, b.process), destination: max(a.process, b.process)), default: 0] += 1 }
            } else { ordered += 1 }
            if (a.time - b.time) * (a.lamport - b.lamport) < 0 { inversions += 1 }
        }
    }
    return ConcurrencyStatistics(pairs: events.count * (events.count - 1) / 2, ordered: ordered, concurrent: concurrent, sameLamport: same, inversions: inversions, byPair: byPair)
}
struct DeliveryPair { let process: Int; let first: Int; let second: Int }
func racesAndViolations(_ processes: [ProcessState], _ copies: [MessageCopy], _ events: [Event]) -> (races: [DeliveryPair], violations: [DeliveryPair]) {
    var races: [DeliveryPair] = [], violations: [DeliveryPair] = []
    for (p, process) in processes.enumerated() {
        let delivered = process.delivered
        for i in delivered.indices {
            let a = delivered[i], vector = events[copies[a].sendEvent].vector
            if i + 1 < delivered.count { let b = delivered[i + 1]; if relation(vector, events[copies[b].sendEvent].vector) == "||" { races.append(DeliveryPair(process: p, first: a, second: b)) } }
            for b in delivered.dropFirst(i + 1) { if happensBefore(events[copies[b].sendEvent].vector, vector) { violations.append(DeliveryPair(process: p, first: a, second: b)) } }
        }
    }
    return (races, violations)
}
func consistentCut(_ cut: [Int], _ processes: [ProcessState], _ events: [Event]) -> Bool {
    for i in cut.indices where cut[i] > 0 { if !lessEqual(events[processes[i].events[cut[i] - 1]].vector, cut) { return false } }
    return true
}
struct PredicateResult { let cuts: Int; let possibly: Bool; let definitely: Bool }
struct CutEnumeration { let limits: [Int]; let product: Int; let consistent: Int; let levels: [Int]; let predicates: [PredicateResult] }
func enumerateCuts(_ processes: [ProcessState], _ events: [Event], _ time: Int, _ thresholds: [Int]) -> CutEnumeration {
    let count = processes.count, limits = processes.map { process in process.events.filter { events[$0].time <= time }.count }, total = processes.reduce(0) { $0 + $1.initial }
    var strides = Array(repeating: 1, count: count), product = 1
    for i in 0..<count { strides[i] = product; product *= limits[i] + 1 }
    func decode(_ code: Int) -> [Int] { (0..<count).map { code / strides[$0] % (limits[$0] + 1) } }
    var consistent = Array(repeating: false, count: product), transit = Array(repeating: 0, count: product), levels = Array(repeating: 0, count: limits.reduce(0, +) + 1), valid = 0, matches = Array(repeating: 0, count: thresholds.count)
    for code in 0..<product {
        let cut = decode(code)
        if !consistentCut(cut, processes, events) { continue }
        consistent[code] = true; valid += 1; levels[cut.reduce(0, +)] += 1
        transit[code] = total - processes.indices.reduce(0) { $0 + processes[$1].balanceAtCut(cut[$1], events) }
        for i in thresholds.indices where transit[code] >= thresholds[i] { matches[i] += 1 }
    }
    let predicates = thresholds.enumerated().map { i, threshold -> PredicateResult in
        var reachable = Array(repeating: false, count: product)
        reachable[0] = consistent[0] && transit[0] < threshold
        for code in 0..<product where reachable[code] {
            let cut = decode(code)
            for p in 0..<count where cut[p] < limits[p] { let next = code + strides[p]; if consistent[next] && transit[next] < threshold { reachable[next] = true } }
        }
        return PredicateResult(cuts: matches[i], possibly: matches[i] > 0, definitely: !reachable[product - 1])
    }
    return CutEnumeration(limits: limits, product: product, consistent: valid, levels: levels, predicates: predicates)
}
