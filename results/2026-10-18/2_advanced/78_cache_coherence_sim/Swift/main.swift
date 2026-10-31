import Foundation

final class Event {
    let number: Int, sourceLine: Int, cycle: Int, core: Int
    let operation: Operation
    let address: Int, block: Int, word: Int
    var distance: Int?
    init(number: Int, sourceLine: Int, cycle: Int, core: Int, operation: Operation, address: Int, lineSize: Int) {
        self.number = number; self.sourceLine = sourceLine; self.cycle = cycle; self.core = core
        self.operation = operation; self.address = address; block = address / lineSize; word = address % lineSize / 4
    }
}

func validateTrace(_ lines: [String], config: Configuration) -> ([Event], [(Int, String)]) {
    var events: [Event] = [], rejected: [(Int, String)] = [], latest = 0
    for (index, line) in lines.enumerated() {
        let f = line.components(separatedBy: " ")
        var reason: String?
        if ![3, 4].contains(f.count) || f.contains("") { reason = "fields" }
        else if !decimalInteger(f[0], maximum: 7) { reason = "cycle" }
        else if !decimalInteger(f[1]) || Int(f[1])! >= config.cores { reason = "core" }
        else if Operation(rawValue: f[2]) == nil || (f[2] == "FENCE" ? f.count != 3 : f.count != 4) { reason = "op" }
        else if f[2] != "FENCE" && (!validHexAddress(f[3]) || Int(f[3], radix: 16)! % 4 != 0 || Int(f[3], radix: 16)! > 0x7fffffff) { reason = "address" }
        else if Int(f[0])! < latest { reason = "order" }
        if let reason { rejected.append((index + 1, reason)); continue }
        latest = Int(f[0])!
        events.append(Event(number: events.count + 1, sourceLine: index + 1, cycle: latest, core: Int(f[1])!,
            operation: Operation(rawValue: f[2])!, address: f[2] == "FENCE" ? 0 : Int(f[3], radix: 16)!, lineSize: config.line))
    }
    return (events, rejected)
}

func perCoreEvents(_ events: [Event], cores: Int) -> [[Event]] {
    var result = Array(repeating: [Event](), count: cores)
    for event in events { result[event.core].append(event) }
    return result
}

struct Fenwick {
    var tree: [Int]
    init(_ count: Int) { tree = Array(repeating: 0, count: count + 1) }
    mutating func add(_ index: Int, _ delta: Int) {
        var p = index
        while p < tree.count { tree[p] += delta; p += p & -p }
    }
    func prefix(_ index: Int) -> Int {
        var p = index, sum = 0
        while p > 0 { sum += tree[p]; p -= p & -p }
        return sum
    }
}

func reuseAnalysis(_ events: [Event], config: Configuration) -> [String] {
    let capacities = [config.capacity / 4, config.capacity / 2, config.capacity, 2 * config.capacity, 4 * config.capacity]
    var lines: [String] = []
    for (core, ordered) in perCoreEvents(events, cores: config.cores).enumerated() {
        let accesses = ordered.filter { $0.operation != .fence }
        var stack = Fenwick(accesses.count), last: [Int: Int] = [:], cold = 0, distances: [Int] = []
        var misses = Array(repeating: 0, count: capacities.count)
        for (index, event) in accesses.enumerated() {
            if let previous = last[event.block] {
                let distance = last.count - stack.prefix(previous) + 1
                event.distance = distance; distances.append(distance); stack.add(previous, -1)
            } else { cold += 1; event.distance = nil }
            for (column, capacity) in capacities.enumerated() where event.distance == nil || event.distance! > capacity { misses[column] += 1 }
            last[event.block] = index + 1
            stack.add(index + 1, 1)
        }
        var next = Array(repeating: accesses.count + 1, count: accesses.count), positions: [Int: Int] = [:]
        for index in accesses.indices.reversed() {
            next[index] = positions[accesses[index].block] ?? accesses.count + 1
            positions[accesses[index].block] = index
        }
        var resident: Set<Int> = [], upcoming: [Int: Int] = [:], optimal = 0
        for (index, event) in accesses.enumerated() {
            let block = event.block
            upcoming[block] = next[index]
            if resident.contains(block) { continue }
            optimal += 1
            if resident.count == config.capacity {
                var victim: Int?
                for line in resident {
                    if victim == nil || upcoming[line]! > upcoming[victim!]!
                        || (upcoming[line] == upcoming[victim!] && line < victim!) { victim = line }
                }
                resident.remove(victim!)
            }
            resident.insert(block)
        }
        let histogram = rangeCounts(distances, labels: ["1", "2-4", "5-16", "17-64", "65-256", "257+"], limits: [1, 4, 16, 64, 256])
        lines.append("reuse c\(core) accesses \(accesses.count) lines \(last.count) distance \(histogram) cold \(cold)")
        lines.append("mrc c\(core) lru " + zip(capacities, misses).map { "\($0.0):\($0.1)" }.joined(separator: " ") + " opt \(config.capacity):\(optimal)")
    }
    return lines
}

struct Pair: Hashable {
    let first: Int
    let second: Int
    init(_ first: Int, _ second: Int) { self.first = first; self.second = second }
}

struct WordSharing {
    var readers: Set<Int> = [], writers: Set<Int> = []
}

final class LineSharing {
    var cores: Set<Int> = [], writers: Set<Int> = []
    var reads = 0, writes = 0
    var words: [Int: WordSharing] = [:]
    var shared: Bool { cores.count >= 2 && !writers.isEmpty }
    var trueSharing: Bool { words.values.contains { !$0.writers.isEmpty && $0.readers.union($0.writers).count >= 2 } }
}

func staticSharing(_ events: [Event]) -> [Int: LineSharing] {
    var lines: [Int: LineSharing] = [:]
    for event in events where event.operation != .fence {
        let info = lines[event.block] ?? LineSharing()
        lines[event.block] = info
        info.cores.insert(event.core)
        var word = info.words[event.word, default: WordSharing()]
        if event.operation == .write { info.writers.insert(event.core); info.writes += 1; word.writers.insert(event.core) }
        else { info.reads += 1; word.readers.insert(event.core) }
        info.words[event.word] = word
    }
    return lines
}

struct ProcessedAccess {
    let event: Event
    let issue: Int
    let latency: Int
    let service: String
    let miss: String?
    let hit: Bool
}

struct WordState {
    var writer: Int
    var readers: Set<Int> = []
}

final class Simulation {
    let config: Configuration
    let scenario: Scenario
    let primary: Bool
    let l1: [Cache], l2: Cache, bus: Bus
    let cores: [Counters]
    let eventLists: [[Event]]
    var indices: [Int], ready: [Int], writeCompletion: [Int]
    var seen: [Set<Int>]
    var invalidations: [Pair: Set<Int>] = [:]
    let l2Counts = Counters()
    var accesses: [ProcessedAccess] = []
    var watchLines: [String] = []
    var handoffs: [Int: Int] = [:], lastWriter: [Int: Int] = [:]
    var wordState: [Pair: WordState] = [:]
    var communications: [[Int]]
    var trueMisses: [Int: Int] = [:], falseMisses: [Int: Int] = [:]
    var total: Counters { totalCounters(cores) }
    var finish: Int { cores.map(\.finish).max()! }

    init(config: Configuration, scenario: Scenario, events: [Event]) {
        self.config = config; self.scenario = scenario; primary = scenario.name == config.primary
        l1 = (0..<config.cores).map { _ in Cache(sets: config.l1Sets, ways: config.l1Ways, replacement: scenario.l1) }
        l2 = Cache(sets: config.l2Sets, ways: config.l2Ways, replacement: scenario.l2)
        bus = Bus(config.tb)
        cores = (0..<config.cores).map { _ in Counters() }
        eventLists = perCoreEvents(events, cores: config.cores)
        indices = Array(repeating: 0, count: config.cores); ready = indices; writeCompletion = indices
        seen = Array(repeating: [], count: config.cores)
        communications = Array(repeating: indices, count: config.cores)
    }

    func lineStates(_ block: Int) -> [CacheState] { l1.map { $0.state(block) } + [l2.state(block)] }
    func issue(_ core: Int, _ kind: TransactionKind, _ block: Int, requested: Int) -> Transaction {
        let tx = bus.assign(core: core, kind: kind, block: block, requested: requested)
        cores[core][kind.rawValue] += 1
        if kind == .writeback { l2Counts["writebacks"] += 1 }
        return tx
    }

    func snoopOthers(_ tx: Transaction, word: Int) {
        for (core, cache) in l1.enumerated() where core != tx.core {
            let old = cache.state(tx.block)
            if old == .invalid { continue }
            let (updated, supplies, flush) = snoop(scenario.coherence, old: old, transaction: tx.kind)
            tx.snoops.append("c\(core):\(old.rawValue)>\(updated.rawValue)"); tx.snoopHits += 1
            if updated == .invalid {
                cache.remove(tx.block); tx.invalidations += 1
                cores[tx.core]["invalidations_sent"] += 1; cores[core]["invalidations_received"] += 1
                invalidations[Pair(core, tx.block)] = [word]
            } else { cache.change(tx.block, updated) }
            if supplies { tx.supplier = core; cores[core]["supplied"] += 1 }
            if flush { tx.flush = true }
        }
        if tx.flush { l2Counts["flushes"] += 1 }
    }

    func accessL2(_ tx: Transaction) {
        l2Counts["lookups"] += 1
        tx.l2Hit = l2.state(tx.block) != .invalid
        if tx.l2Hit! { l2Counts["hits"] += 1; l2.touch(tx.block) }
        else {
            l2Counts["misses"] += 1
            if let old = l2.fill(tx.block, .clean) {
                var copies: [String] = [], dirty = old.state == .dirty
                for (core, cache) in l1.enumerated() {
                    let state = cache.state(old.block)
                    if state == .invalid { continue }
                    cache.remove(old.block)
                    copies.append("c\(core):\(state.rawValue)"); cores[core]["back_invalidations"] += 1
                    if state.dirtyL1 { dirty = true }
                }
                tx.eviction = Eviction(block: old.block, copies: copies, dirty: dirty)
                l2Counts["evictions"] += 1
                if dirty { l2Counts["dirty_evictions"] += 1 }
            }
        }
        if tx.flush || tx.kind == .write { l2.change(tx.block, .dirty) }
    }

    func transaction(_ core: Int, _ kind: TransactionKind, _ block: Int, word: Int, requested: Int) -> (Int, Transaction) {
        let tx = issue(core, kind, block, requested: requested)
        snoopOthers(tx, word: word)
        if kind != .upgrade { accessL2(tx) }
        var completion = tx.start + config.tb
        if kind == .upgrade { return (completion, tx) }
        if kind != .write, let supplier = tx.supplier { tx.source = "c\(supplier)" }
        else {
            completion += config.t2
            if !tx.l2Hit! { completion += config.tm }
            if kind != .write { tx.source = tx.l2Hit! ? "L2" : "mem" }
        }
        return (completion, tx)
    }

    func communicate(_ event: Event) {
        let key = Pair(event.block, event.word), core = event.core
        if event.operation == .write {
            if let former = lastWriter[event.block], former != core { handoffs[event.block, default: 0] += 1 }
            lastWriter[event.block] = core
            wordState[key] = WordState(writer: core)
        } else if var state = wordState[key], state.writer != core && !state.readers.contains(core) {
            communications[state.writer][core] += 1; state.readers.insert(core); wordState[key] = state
        }
    }

    func access(_ event: Event, issue: Int) {
        let core = event.core, block = event.block, word = event.word, cache = l1[event.core], counter = cores[event.core]
        let before = primary ? config.watch.map(lineStates) : []
        let old = cache.state(block), hit = old != .invalid
        counter["accesses"] += 1; counter[event.operation == .read ? "reads" : "writes"] += 1
        counter[hit ? "hits" : "misses"] += 1
        let otherHasLine = l1.enumerated().contains { $0.offset != core && $0.element.state(block) != .invalid }
        let (kind, new) = requester(scenario.coherence, old: old, operation: event.operation, otherHasLine: otherHasLine)
        var miss: String?
        if hit { cache.touch(block) }
        else {
            if !seen[core].contains(block) { miss = "compulsory" }
            else if let record = invalidations[Pair(core, block)] {
                miss = "coherence"
                if record.contains(word) { counter["true_sharing"] += 1; trueMisses[block, default: 0] += 1 }
                else { counter["false_sharing"] += 1; falseMisses[block, default: 0] += 1 }
            } else { miss = event.distance! > config.capacity ? "capacity" : "conflict" }
            counter[miss!] += 1
        }
        seen[core].insert(block)
        if event.operation == .write {
            for other in 0..<config.cores where other != core {
                let key = Pair(other, block)
                if invalidations[key] != nil { invalidations[key]!.insert(word) }
            }
        }
        if primary { communicate(event) }
        let completion: Int, service: String
        if let kind {
            let (end, tx) = transaction(core, kind, block, word: word, requested: issue + config.t1)
            completion = end
            service = kind == .upgrade ? "upgrade" : kind == .write ? "through" : tx.supplier != nil ? "cache" : tx.l2Hit! ? "l2" : "memory"
        } else { completion = issue + config.t1; service = "l1" }
        if old != .invalid { cache.change(block, new) }
        else if new != .invalid {
            let evicted = cache.fill(block, new)
            invalidations.removeValue(forKey: Pair(core, block))
            if let evicted, evicted.state.dirtyL1 {
                _ = self.issue(core, .writeback, evicted.block, requested: bus.free)
                l2.touch(evicted.block); l2.change(evicted.block, .dirty)
            }
        }
        let latency = completion - issue
        counter[service] += 1; counter["latency"] += latency
        if event.operation == .read { counter["read_latency"] += latency; ready[core] = completion }
        else { counter["write_latency"] += latency; ready[core] = issue + config.t1; writeCompletion[core] = max(writeCompletion[core], completion) }
        counter.finish = max(counter.finish, completion)
        accesses.append(ProcessedAccess(event: event, issue: issue, latency: latency, service: service, miss: miss, hit: hit))
        if primary {
            for (index, watched) in config.watch.enumerated() {
                let after = lineStates(watched)
                if watched != block && before[index] == after { continue }
                let states = (0..<config.cores).map { "c\($0):\(after[$0].rawValue)" }.joined(separator: " ")
                watchLines.append("\(event.number) \(issue) c\(core) \(event.operation.rawValue) \(hexAddress(event.address)) "
                    + "line \(hexAddress(watched * config.line)) \(states) L2:\(after.last!.rawValue)")
            }
        }
    }

    func run() {
        while true {
            var choice: (Int, Int, Event)?
            for (core, ordered) in eventLists.enumerated() where indices[core] < ordered.count {
                let event = ordered[indices[core]], issue = max(ordered[indices[core]].cycle, ready[core])
                if choice == nil || issue < choice!.0 { choice = (issue, core, event) }
            }
            guard let (issue, core, event) = choice else { break }
            indices[core] += 1
            if event.operation == .fence {
                let completion = max(issue, writeCompletion[core])
                cores[core]["fences"] += 1; cores[core]["fence_stall"] += completion - issue
                cores[core].finish = max(cores[core].finish, completion); ready[core] = completion
            } else { access(event, issue: issue) }
        }
    }
}

func scenarioReport(_ state: Simulation) -> [String] {
    let config = state.config, scenario = state.scenario, total = state.total
    var lines = ["scenario \(scenario.name) \(scenario.coherence.rawValue) \(scenario.l1.rawValue) \(scenario.l2.rawValue)"]
    for (core, counters) in state.cores.enumerated() { lines += sixLines("c\(core)", counters) }
    lines += sixLines("total", total)
    let l2 = state.l2Counts, transactions = state.bus.transactions, count = transactions.count, busy = state.bus.busy
    lines.append("l2 " + ["lookups", "hits", "misses", "flushes", "writebacks", "evictions", "dirty_evictions"].map { "\($0) \(l2[$0])" }.joined(separator: " "))
    lines.append("bus transactions \(count) busy \(busy) wait \(state.bus.wait) utilization \(decimal(100 * busy, state.finish))")
    let dataBytes = config.line * (total["BusRd"] + total["BusRdX"] + total["WB"]) + 4 * total["BusWr"]
    lines.append("traffic command_bytes \(8 * count) data_bytes \(dataBytes) memory_bytes \(config.line * (l2["misses"] + l2["dirty_evictions"]))")
    let snoops = transactions.filter { $0.kind != .writeback }
    var fanout = Array(repeating: 0, count: config.cores)
    for tx in snoops where tx.kind == .readExclusive || tx.kind == .upgrade || tx.kind == .write { fanout[tx.invalidations] += 1 }
    lines.append("snoops probes \((config.cores - 1) * snoops.count) hits \(snoops.reduce(0) { $0 + $1.snoopHits }) fanout "
        + fanout.enumerated().map { "\($0.offset):\($0.element)" }.joined(separator: " "))
    let histogram = rangeCounts(state.accesses.map(\.latency), labels: ["1", "2-9", "10-29", "30-99", "100-299", "300+"], limits: [1, 9, 29, 99, 299])
    lines.append("latencies reads \(total["read_latency"]) writes \(total["write_latency"]) histogram \(histogram)")
    return lines
}

func rankScenarios(_ states: [Simulation]) -> [String] {
    let ordered = states.sorted {
        if $0.finish != $1.finish { return $0.finish < $1.finish }
        if $0.bus.transactions.count != $1.bus.transactions.count { return $0.bus.transactions.count < $1.bus.transactions.count }
        return $0.scenario.order < $1.scenario.order
    }
    return ["ranking"] + ordered.enumerated().map { index, state in
        let total = state.total
        return "\(index + 1) \(state.scenario.name) finish \(state.finish) transactions \(state.bus.transactions.count) "
            + "amat \(fraction(total["latency"], total["accesses"])) \(decimal(total["latency"], total["accesses"]))"
    }
}

func hotLines(_ state: Simulation) -> [String] {
    var counts: [Int: Counters] = [:], cores: [Int: Set<Int>] = [:]
    for tx in state.bus.transactions {
        let counter = counts[tx.block] ?? Counters()
        counts[tx.block] = counter
        counter[tx.kind.rawValue] += 1; counter["transactions"] += 1; counter["invalidations"] += tx.invalidations
        cores[tx.block, default: []].insert(tx.core)
    }
    for item in state.accesses {
        if let miss = item.miss {
            let counter = counts[item.event.block] ?? Counters()
            counts[item.event.block] = counter
            counter["misses"] += 1
            if miss == "coherence" { counter["coherence"] += 1 }
        }
    }
    let ordered = counts.keys.filter { counts[$0]!["transactions"] > 0 }.sorted {
        counts[$0]!["transactions"] == counts[$1]!["transactions"] ? $0 < $1 : counts[$0]!["transactions"] > counts[$1]!["transactions"]
    }
    var lines = ["hot " + state.scenario.name]
    for (index, block) in ordered.prefix(state.config.top).enumerated() {
        let counter = counts[block]!
        lines.append("\(index + 1) \(hexAddress(block * state.config.line)) transactions \(counter["transactions"]) "
            + transactionKinds.map { "\($0.rawValue) \(counter[$0.rawValue])" }.joined(separator: " ")
            + " misses \(counter["misses"]) coherence \(counter["coherence"]) invalidations \(counter["invalidations"]) cores \(coreString(cores[block]!))")
    }
    return lines
}

func intervalRows(_ state: Simulation) -> [String] {
    let width = state.config.interval, count = state.finish / width + 1
    var accesses = Array(repeating: Array(repeating: 0, count: state.config.cores), count: count)
    var misses = Array(repeating: 0, count: count), transactions = misses, busy = misses
    for item in state.accesses {
        let bucket = item.issue / width
        accesses[bucket][item.event.core] += 1
        if item.miss != nil { misses[bucket] += 1 }
    }
    for tx in state.bus.transactions {
        let first = tx.start, last = first + state.config.tb
        if first / width < count { transactions[first / width] += 1 }
        for bucket in (first / width)...((last - 1) / width) where bucket < count {
            busy[bucket] += max(0, min(last, (bucket + 1) * width) - max(first, bucket * width))
        }
    }
    return ["intervals \(state.scenario.name) \(width)"] + (0..<count).map { bucket in
        "\(bucket) \(bucket * width)-\((bucket + 1) * width - 1) accesses " + accesses[bucket].map(String.init).joined(separator: " ")
            + " misses \(misses[bucket]) transactions \(transactions[bucket]) busy \(busy[bucket]) utilization \(decimal(100 * busy[bucket], width))"
    }
}

func slowestRows(_ state: Simulation) -> [String] {
    let ordered = state.accesses.sorted { $0.latency == $1.latency ? $0.event.number < $1.event.number : $0.latency > $1.latency }
    return ["slowest " + state.scenario.name] + ordered.prefix(state.config.top).enumerated().map { index, item in
        let event = item.event
        return "\(index + 1) event \(event.number) cycle \(item.issue) c\(event.core) \(event.operation.rawValue) \(hexAddress(event.address)) latency \(item.latency) service \(item.service)"
    }
}

func regionRows(_ state: Simulation) -> [String] {
    let names = state.config.regions.map(\.name) + ["other"]
    let counters = Dictionary(uniqueKeysWithValues: names.map { ($0, Counters()) })
    func region(_ address: Int) -> String {
        state.config.regions.first { $0.start <= address && address <= $0.end }?.name ?? "other"
    }
    for item in state.accesses {
        let counter = counters[region(item.event.address)]!
        counter["accesses"] += 1; counter[item.event.operation == .read ? "reads" : "writes"] += 1; counter["latency"] += item.latency
        if item.hit { counter["hits"] += 1 } else { counter[item.miss!] += 1 }
    }
    for tx in state.bus.transactions { counters[region(tx.block * state.config.line)]!["transactions"] += 1 }
    return ["regions " + state.scenario.name] + names.map { name in
        let c = counters[name]!
        let amat = c["accesses"] == 0 ? "-" : fraction(c["latency"], c["accesses"]) + " " + decimal(c["latency"], c["accesses"])
        return "\(name) accesses \(c["accesses"]) reads \(c["reads"]) writes \(c["writes"]) hits \(c["hits"]) "
            + missKinds.map { "\($0) \(c[$0])" }.joined(separator: " ")
            + " transactions \(c["transactions"]) latency \(c["latency"]) amat \(amat)"
    }
}

func sharingOutput(_ sharing: [Int: LineSharing], state: Simulation) -> [String] {
    let shared = sharing.keys.filter { sharing[$0]!.shared }.sorted()
    var lines: [String] = [], trueLines = 0, totalTrue = 0, totalFalse = 0
    for block in shared {
        let info = sharing[block]!, trueMisses = state.trueMisses[block, default: 0], falseMisses = state.falseMisses[block, default: 0]
        if info.trueSharing { trueLines += 1 }; totalTrue += trueMisses; totalFalse += falseMisses
        let words = info.words.keys.sorted().map { word in
            "w\(word)=\(coreString(info.words[word]!.readers))/\(coreString(info.words[word]!.writers))"
        }.joined(separator: " ")
        lines.append("\(hexAddress(block * state.config.line)) \(info.trueSharing ? "true" : "false") cores \(coreString(info.cores)) "
            + "writers \(coreString(info.writers)) reads \(info.reads) writes \(info.writes) handoffs \(state.handoffs[block, default: 0]) "
            + "coherence \(trueMisses + falseMisses) true \(trueMisses) false \(falseMisses) words \(words)")
    }
    lines.append("lines \(shared.count) true_lines \(trueLines) false_lines \(shared.count - trueLines) coherence \(totalTrue + totalFalse) true \(totalTrue) false \(totalFalse)")
    lines.append("communication")
    for (core, vector) in state.communications.enumerated() { lines.append("c\(core) " + vector.map(String.init).joined(separator: " ")) }
    return lines
}

func finalStateOutput(_ state: Simulation) -> [String] {
    var lines: [String] = []
    func appendSets(_ cache: Cache, label: String) {
        for (set, ways) in cache.entries.enumerated() {
            let values = ways.map { line in line.map { hexAddress($0.block * state.config.line) + ":" + $0.state.rawValue } ?? "-" }.joined(separator: " ")
            lines.append("\(label) \(set) \(values) \(cache.replacement.rawValue.lowercased()) \(cache.order(set)) fills \(cache.fills[set]) evictions \(cache.evictions[set])")
        }
    }
    for (core, cache) in state.l1.enumerated() {
        appendSets(cache, label: "c\(core)")
        let resident = cache.lines
        lines.append("c\(core) lines \(resident.count) " + [CacheState.modified, .owned, .exclusive, .shared, .valid].map { state in
            state.rawValue + " " + String(resident.filter { $0.state == state }.count)
        }.joined(separator: " "))
    }
    appendSets(state.l2, label: "L2")
    let resident = state.l2.lines, inL1 = Set(state.l1.flatMap { $0.lines.map(\.block) }).count
    lines.append("L2 lines \(resident.count) dirty \(resident.filter { $0.state == .dirty }.count) clean \(resident.filter { $0.state == .clean }.count) in_l1 \(inL1)")
    return lines
}

let config = try Configuration()
let trace = try readLines("input/trace.txt")
let (events, rejected) = validateTrace(trace, config: config)
let reuse = reuseAnalysis(events, config: config)
let sharing = staticSharing(events)
let states = config.scenarios.map { scenario -> Simulation in
    let state = Simulation(config: config, scenario: scenario, events: events)
    state.run()
    return state
}
let primary = states.first { $0.scenario.name == config.primary }!
var configurationLines = ["trace lines \(trace.count) accepted \(events.count) rejected \(rejected.count)"]
configurationLines += rejected.map { "reject line \($0.0) \($0.1)" }
configurationLines.append("geometry cores \(config.cores) line \(config.line) l1 \(config.l1Size) \(config.l1Ways) sets \(config.l1Sets) l2 \(config.l2Size) \(config.l2Ways) sets \(config.l2Sets)")
configurationLines.append("latency l1 \(config.t1) l2 \(config.t2) memory \(config.tm) bus \(config.tb)")
let sections = [configurationLines, reuse] + states.map(scenarioReport)
    + [rankScenarios(states), hotLines(primary), intervalRows(primary), slowestRows(primary), regionRows(primary)]
var statistics: [String] = []
for section in sections { if !statistics.isEmpty { statistics.append("") }; statistics += section }
try writeLines("stats.txt", statistics)
try writeLines("bus_log.txt", primary.bus.transactions.map { primary.bus.line($0, lineSize: config.line) })
try writeLines("watch.txt", primary.watchLines)
try writeLines("sharing.txt", sharingOutput(sharing, state: primary))
try writeLines("final_state.txt", finalStateOutput(primary))
