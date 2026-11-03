import Foundation

struct Settings {
    let minimumFollows: Int
    let sla: Int
    let observations: Int
    let dependency: Rational
    let relative: Rational
    let loop1: Rational
    let loop2: Rational
    let andThreshold: Rational
    init(_ values: [String: String]) { minimumFollows = Int(values["filter_min_follows"]!)!; sla = Int(values["sla_minutes"]!)!; observations = Int(values["positive_observations"]!)!; dependency = parseRational(values["dependency_threshold"]!); relative = parseRational(values["relative_to_best"]!); loop1 = parseRational(values["loop1_threshold"]!); loop2 = parseRational(values["loop2_threshold"]!); andThreshold = parseRational(values["and_threshold"]!) }
}
struct EventIdentity: Hashable { let caseID: String; let activity: String; let timestamp: String }
struct Variant { let number: Int; let trace: [String]; let cases: [CaseRecord]; let keep: Bool }
struct Prefix { var weight: Int; var followers: Set<String> }
struct Discovery { var net: PetriNet; let pairs: [CandidatePair]; let candidates: Int; let causal: Int; let starts: [String]; let ends: [String]; let activities: [String]; let relation: Relation }
struct NamedNet { let name: String; let net: PetriNet }
struct Firing { let before: [Int]; let transition: String; let after: [Int] }
struct Reachability { let markings: Int; let edges: Int; let unsafe: Int; let deadlocks: Int; let stuck: Int; let finalReached: Bool; let dead: [String]; let sound: Bool; let follows: Counts }
struct PrefixMark { let marking: [Int]? }
final class ProcessStudy {
    let rows: [RawRow]
    let settings: Settings
    let reference: PetriNet
    let errors: [String]
    let events: [Event]
    let cases: [CaseRecord]
    let activities: [String]
    let resources: [String]
    let log: Log
    let counts: Counts
    var variants: [Variant] = []
    var variantByCase: [String: Int] = [:]
    var filteredLog: Log = []
    var keptCases = 0
    var keptEvents = 0
    var nets: [NamedNet] = []
    var prefixes: [[String]: Prefix] = [:]
    var referenceReplays: [String: ReplayTotals] = [:]
    init(_ input: RawInputs, _ reference: PetriNet) {
        var adopted: Set<EventIdentity> = [], errors: [String] = [], events: [Event] = []
        for row in input.rows { guard let time = timestampMinutes(row.timestamp) else { errors.append("line \(row.line): bad timestamp \(row.timestamp)"); continue }; let identity = EventIdentity(caseID: row.caseID, activity: row.activity, timestamp: row.timestamp); if adopted.contains(identity) { errors.append("line \(row.line): duplicate event \(row.caseID) \(row.activity) \(row.timestamp)"); continue }; adopted.insert(identity); events.append(Event(line: row.line, caseID: row.caseID, activity: row.activity, timestamp: row.timestamp, resource: row.resource, time: time)) }
        let cases = groupCases(events), log = cases.map { WeightedTrace(trace: $0.trace, weight: 1) }
        rows = input.rows; settings = Settings(input.parameters); self.reference = reference; self.errors = errors; self.events = events; self.cases = cases; activities = Set(events.map { $0.activity }).sorted(); resources = Set(events.map { $0.resource }).sorted(); self.log = log; counts = directlyFollows(log)
    }
    func logSummary() -> [String] {
        let earliest = events.min { $0.time < $1.time }!, latest = events.max { $0.time < $1.time }!
        var lines = errors.map { "ERROR " + $0 }, eventCounts: [String: Int] = [:], caseCounts: [String: Int] = [:], starts: [String: Int] = [:], ends: [String: Int] = [:], rework: [String: Int] = [:], waits: [String: [Int]] = [:], workers: [String: Set<String>] = [:], weekdayEvents = Array(repeating: 0, count: 7), weekdayStarts = Array(repeating: 0, count: 7), weekdayEnds = Array(repeating: 0, count: 7)
        lines.append("LOG rows \(rows.count) adopted \(events.count) rejected \(errors.count) cases \(cases.count) activities \(activities.count) resources \(resources.count) first \(earliest.timestamp) last \(latest.timestamp)")
        for record in cases { var occurrences: [String: Int] = [:]; for activity in record.trace { occurrences[activity, default: 0] += 1 }; for (activity, count) in occurrences { caseCounts[activity, default: 0] += 1; if count >= 2 { rework[activity, default: 0] += 1 } }; starts[record.trace.first!, default: 0] += 1; ends[record.trace.last!, default: 0] += 1; weekdayStarts[(record.events.first!.time / 1440 + 3) % 7] += 1; weekdayEnds[(record.events.last!.time / 1440 + 3) % 7] += 1
            for (index, event) in record.events.enumerated() { eventCounts[event.activity, default: 0] += 1; workers[event.activity, default: []].insert(event.resource); weekdayEvents[(event.time / 1440 + 3) % 7] += 1; if index > 0 { waits[event.activity, default: []].append(event.time - record.events[index - 1].time) } }
        }
        for activity in activities { let values = waits[activity, default: []], waiting = values.isEmpty ? "-" : fraction(Rational(values.reduce(0, +), values.count)); lines.append("ACTIVITY \(activity) events \(eventCounts[activity, default: 0]) cases \(caseCounts[activity, default: 0]) start \(starts[activity, default: 0]) end \(ends[activity, default: 0]) rework \(rework[activity, default: 0]) wait \(waiting) resources \(workers[activity, default: []].count) model \(reference.inputs[activity] != nil ? "yes" : "no")") }
        let lengths = cases.map { $0.events.count }, durations = cases.map { $0.duration }
        for (label, values) in [("LENGTH", lengths), ("DURATION", durations)] { lines.append("\(label) min \(values.min()!) max \(values.max()!) mean \(fraction(Rational(values.reduce(0, +), values.count))) median \(fraction(median(values)))") }
        var days: [Int: Int] = [:]
        for duration in durations { days[duration / 1440, default: 0] += 1 }
        for day in 0...days.keys.max()! { let count = days[day, default: 0]; lines.append("DAYS \(day) cases \(count) share \(percentage(count, cases.count))") }
        let late = durations.filter { $0 > settings.sla }.count
        lines.append("SLA limit \(settings.sla) late \(late) share \(percentage(late, cases.count))")
        for (index, day) in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].enumerated() { lines.append("WEEKDAY \(day) events \(weekdayEvents[index]) starts \(weekdayStarts[index]) ends \(weekdayEnds[index])") }
        return lines
    }
    func buildVariants() {
        let grouped = Dictionary(grouping: cases, by: { $0.trace }), traces = grouped.keys.sorted { grouped[$0]!.count == grouped[$1]!.count ? $0.lexicographicallyPrecedes($1) : grouped[$0]!.count > grouped[$1]!.count }
        for (index, trace) in traces.enumerated() { let cases = grouped[trace]!, keep = (1..<trace.count).allSatisfy { counts[NamePair(trace[$0 - 1], trace[$0]), default: 0] >= settings.minimumFollows }; variants.append(Variant(number: index + 1, trace: trace, cases: cases, keep: keep)); for record in cases { variantByCase[record.identifier] = index + 1 }; if keep { filteredLog.append(WeightedTrace(trace: trace, weight: cases.count)) } }
        keptCases = filteredLog.reduce(0) { $0 + $1.weight }; keptEvents = filteredLog.reduce(0) { $0 + $1.trace.count * $1.weight }
    }
    func variantReport() -> [String] {
        var lines: [String] = []
        for variant in variants { let count = variant.cases.count, duration = Rational(variant.cases.reduce(0) { $0 + $1.duration }, count), late = variant.cases.filter { $0.duration > settings.sla }.count, fitness = referenceReplays[variant.cases[0].identifier]!.fitness(); lines.append("VARIANT \(variant.number) count \(count) share \(percentage(count, cases.count)) length \(variant.trace.count) first \(variant.cases[0].identifier) duration \(fraction(duration)) late \(late) fitness \(fraction(fitness)) \(variant.keep ? "KEEP" : "DROP") \(names(variant.trace))") }
        lines.append("FILTER min_follows \(settings.minimumFollows) variants \(filteredLog.count) of \(variants.count) cases \(keptCases) of \(cases.count) events \(keptEvents) of \(events.count)")
        return lines
    }
    func dfgReport() -> [String] {
        var starts: [String: Int] = [:], ends: [String: [Int]] = [:], waiting: [NamePair: [Int]] = [:], edgeCases: Counts = [:]
        for record in cases { starts[record.trace[0], default: 0] += 1; ends[record.trace.last!, default: []].append(record.duration); var present: Set<NamePair> = []; for index in 1..<record.events.count { let first = record.events[index - 1], second = record.events[index], pair = NamePair(first.activity, second.activity); waiting[pair, default: []].append(second.time - first.time); present.insert(pair) }; for pair in present { edgeCases[pair, default: 0] += 1 } }
        var lines: [String] = []
        for activity in starts.keys.sorted(by: { starts[$0]! == starts[$1]! ? $0 < $1 : starts[$0]! > starts[$1]! }) { lines.append("START \(activity) count \(starts[activity]!)") }
        for activity in ends.keys.sorted(by: { ends[$0]!.count == ends[$1]!.count ? $0 < $1 : ends[$0]!.count > ends[$1]!.count }) { let values = ends[activity]!; lines.append("END \(activity) count \(values.count) duration \(fraction(Rational(values.reduce(0, +), values.count)))") }
        for pair in counts.keys.sorted(by: { counts[$0]! == counts[$1]! ? $0 < $1 : counts[$0]! > counts[$1]! }) { let values = waiting[pair]!; lines.append("EDGE \(pair.first) \(pair.second) count \(counts[pair]!) cases \(edgeCases[pair]!) mean \(fraction(Rational(values.reduce(0, +), values.count))) min \(values.min()!) max \(values.max()!)") }
        lines += footprint(activities, { basicRelation(self.counts, $0, $1) })
        return lines
    }
    func discover(_ log: Log, _ activities: [String], _ relation: @escaping Relation) -> Discovery {
        var candidates: Set<CandidatePair> = [], pending: [CandidatePair] = [], causal = 0, cursor = 0
        for first in activities { for second in activities where relation(first, second) == "->" { causal += 1; if relation(first, first) == "#" && relation(second, second) == "#" { let pair = CandidatePair(first: [first], second: [second]); if candidates.insert(pair).inserted { pending.append(pair) } } } }
        while cursor < pending.count { let pair = pending[cursor]; cursor += 1; for activity in activities { for side in 0..<2 { if let extended = extendPair(pair, activity, side, relation), candidates.insert(extended).inserted { pending.append(extended) } } } }
        let maximal = candidates.filter { pair in !activities.contains { activity in (0..<2).contains { extendPair(pair, activity, $0, relation) != nil } } }.sorted(by: pairBefore), starts = Set(log.map { $0.trace[0] }).sorted(), ends = Set(log.map { $0.trace.last! }).sorted(), places = ["start"] + maximal.indices.map { "p\($0 + 1)" } + ["end"]
        var arcs = Set(starts.map { NamePair("start", $0) } + ends.map { NamePair($0, "end") })
        for (index, pair) in maximal.enumerated() { let place = "p\(index + 1)"; for activity in pair.first { arcs.insert(NamePair(activity, place)) }; for activity in pair.second { arcs.insert(NamePair(place, activity)) } }
        return Discovery(net: PetriNet(places, activities, arcs, "start", "end"), pairs: maximal, candidates: candidates.count, causal: causal, starts: starts, ends: ends, activities: activities, relation: relation)
    }
    func pairLine(_ discovery: Discovery) -> String { "PAIRS causal \(discovery.causal) candidates \(discovery.candidates) maximal \(discovery.pairs.count)" }
    func netLines(_ discovery: Discovery) -> [String] {
        let net = discovery.net
        var lines = ["PLACE start - \(names(discovery.starts))"]
        for (index, pair) in discovery.pairs.enumerated() { lines.append("PLACE p\(index + 1) \(names(pair.first.sorted())) \(names(pair.second.sorted()))") }
        lines.append("PLACE end \(names(discovery.ends)) -")
        for transition in net.transitions { lines.append("TRANSITION \(transition) in \(names(net.inputs[transition]!.map { net.places[$0] })) out \(names(net.outputs[transition]!.map { net.places[$0] }))") }
        lines.append("NET places \(net.places.count) transitions \(net.transitions.count) arcs \(net.arcs.count)")
        return lines
    }
    func mineWorkflows() -> [String] {
        let counts = directlyFollows(filteredLog), activities = Set(filteredLog.flatMap { $0.trace }).sorted(), loops = activities.filter { counts[NamePair($0, $0), default: 0] >= 1 }, basic: Relation = { basicRelation(counts, $0, $1) }, alpha = discover(filteredLog, activities, basic)
        var lines = ["LOG variants \(filteredLog.count) cases \(keptCases) activities \(names(activities))", "LOOPS \(names(loops))", "MINER alpha"] + footprint(activities, basic) + [pairLine(alpha)] + netLines(alpha)
        let loopSet = Set(loops), reduced = filteredLog.map { WeightedTrace(trace: $0.trace.filter { !loopSet.contains($0) }, weight: $0.weight) }, retained = activities.filter { !loopSet.contains($0) }, reducedCounts = directlyFollows(reduced), triangles = triangleCounts(reduced), relation: Relation = { plusRelation(reducedCounts, triangles, $0, $1) }
        var plus = discover(reduced, retained, relation), arcs = plus.net.arcs
        lines.append("MINER alpha_plus")
        for pair in triangles.keys.sorted() { lines.append("TRIANGLE \(pair.first) \(pair.second) count \(triangles[pair]!)") }
        lines += footprint(retained, relation) + [pairLine(plus)]
        for activity in loops { let before = Set(retained.filter { counts[NamePair($0, activity), default: 0] >= 1 }), after = Set(retained.filter { counts[NamePair(activity, $0), default: 0] >= 1 }); var place = "-"; if let index = plus.pairs.firstIndex(of: CandidatePair(first: before, second: after)) { place = "p\(index + 1)"; arcs.insert(NamePair(place, activity)); arcs.insert(NamePair(activity, place)) }; lines.append("LOOP \(activity) before \(names(before.sorted())) after \(names(after.sorted())) place \(place)") }
        plus.net = PetriNet(plus.net.places, activities, arcs, "start", "end"); lines += netLines(plus); nets = [NamedNet(name: "reference", net: reference), NamedNet(name: "alpha", net: alpha.net), NamedNet(name: "alpha_plus", net: plus.net)]
        return lines
    }
    func heuristicReport() -> [String] {
        let triangles = triangleCounts(log)
        var loops1: Set<String> = [], loops2: Set<NamePair> = [], lines: [String] = []
        for activity in activities { let count = counts[NamePair(activity, activity), default: 0]; if count == 0 { continue }; let measure = loopMeasure(count), accepted = count >= settings.observations && measure >= settings.loop1; if accepted { loops1.insert(activity) }; lines.append("L1 \(activity) count \(count) measure \(fraction(measure)) \(accepted ? "ACCEPT" : "REJECT")") }
        for first in activities.indices { for second in (first + 1)..<activities.count { let a = activities[first], b = activities[second], count = triangles[NamePair(a, b), default: 0] + triangles[NamePair(b, a), default: 0]; if loops1.contains(a) || loops1.contains(b) || count == 0 { continue }; let measure = loopMeasure(count), accepted = count >= settings.observations && measure >= settings.loop2; if accepted { loops2.insert(NamePair(a, b)) }; lines.append("L2 \(a) \(b) count \(count) measure \(fraction(measure)) \(accepted ? "ACCEPT" : "REJECT")") } }
        var measures: [NamePair: Rational] = [:], bestOut: [String: Rational] = [:], bestIn: [String: Rational] = [:]
        for pair in counts.keys where pair.first != pair.second { let measure = dependency(counts, pair.first, pair.second); measures[pair] = measure; bestOut[pair.first] = bestOut[pair.first].map { max($0, measure) } ?? measure; bestIn[pair.second] = bestIn[pair.second].map { max($0, measure) } ?? measure }
        var edges = Set(loops1.map { NamePair($0, $0) })
        for pair in measures.keys.sorted() { let measure = measures[pair]!, canonical = NamePair(min(pair.first, pair.second), max(pair.first, pair.second)), verdict: String; if loops2.contains(canonical) { verdict = "LOOP2" } else if counts[pair]! < settings.observations { verdict = "REJECT_COUNT" } else if measure < settings.dependency { verdict = "REJECT_MEASURE" } else if bestOut[pair.first]! - measure > settings.relative && bestIn[pair.second]! - measure > settings.relative { verdict = "REJECT_BEST" } else { verdict = "ACCEPT" }; if verdict == "LOOP2" || verdict == "ACCEPT" { edges.insert(pair) }; lines.append("DEP \(pair.first) \(pair.second) count \(counts[pair]!) reverse \(counts[NamePair(pair.second, pair.first), default: 0]) measure \(fraction(measure)) \(verdict)") }
        let inputs = Dictionary(uniqueKeysWithValues: activities.map { activity in (activity, edges.filter { $0.second == activity }.map { $0.first }.sorted()) }), outputs = Dictionary(uniqueKeysWithValues: activities.map { activity in (activity, edges.filter { $0.first == activity }.map { $0.second }.sorted()) })
        for activity in activities { lines.append("NODE \(activity) in \(names(inputs[activity]!)) out \(names(outputs[activity]!))") }
        for activity in activities { let successors = outputs[activity]!.filter { $0 != activity }, predecessors = inputs[activity]!.filter { $0 != activity }; for (label, values) in [("SPLIT", successors), ("JOIN", predecessors)] { for first in values.indices { for second in (first + 1)..<values.count { let a = values[first], b = values[second], measure = label == "SPLIT" ? splitMeasure(counts, activity, a, b) : joinMeasure(counts, activity, a, b); lines.append("\(label) \(activity) \(a) \(b) measure \(fraction(measure)) \(measure >= settings.andThreshold ? "AND" : "XOR")") } } } }
        lines.append("GRAPH activities \(activities.count) edges \(edges.count) loops1 \(loops1.count) loops2 \(loops2.count)")
        return lines
    }
}
extension ProcessStudy {
    func explore(_ net: PetriNet) -> Reachability {
        var markings: Set<[Int]> = [net.initialMarking], pending = [net.initialMarking], cursor = 0, edges: [Firing] = [], reverse: [[Int]: Set<[Int]>] = [:], enabledAt: [[Int]: [String]] = [:], everEnabled: Set<String> = [], unsafe = 0, deadlocks = 0
        while cursor < pending.count { let marking = pending[cursor], enabled = net.enabledTransitions(marking); cursor += 1; enabledAt[marking] = enabled; everEnabled.formUnion(enabled); if enabled.isEmpty && marking != net.finalMarking { deadlocks += 1 }; for transition in enabled { let after = net.fire(marking, transition); if after.contains(where: { $0 > 1 }) { unsafe += 1; continue }; edges.append(Firing(before: marking, transition: transition, after: after)); reverse[after, default: []].insert(marking); if markings.insert(after).inserted { pending.append(after) } } }
        var reachable: Set<[Int]> = [], reverseQueue: [[Int]] = []
        if markings.contains(net.finalMarking) { reachable.insert(net.finalMarking); reverseQueue.append(net.finalMarking) }
        cursor = 0
        while cursor < reverseQueue.count { let marking = reverseQueue[cursor]; cursor += 1; for before in reverse[marking, default: []] { if reachable.insert(before).inserted { reverseQueue.append(before) } } }
        let dead = net.transitions.filter { !everEnabled.contains($0) }, stuck = markings.count - reachable.count
        var follows: Counts = [:]
        for edge in edges { for successor in enabledAt[edge.after]! { follows[NamePair(edge.transition, successor)] = 1 } }
        return Reachability(markings: markings.count, edges: edges.count, unsafe: unsafe, deadlocks: deadlocks, stuck: stuck, finalReached: markings.contains(net.finalMarking), dead: dead, sound: unsafe == 0 && stuck == 0 && dead.isEmpty, follows: follows)
    }
    func reachabilityLine(_ name: String, _ result: Reachability) -> String { "REACHABILITY \(name) markings \(result.markings) edges \(result.edges) unsafe \(result.unsafe) deadlocks \(result.deadlocks) stuck \(result.stuck) final \(result.finalReached ? "yes" : "no") dead \(names(result.dead)) sound \(result.sound ? "yes" : "no")" }
    func footprintFitness(_ name: String, _ net: PetriNet, _ follows: Counts) -> [String] {
        let activities = Set(self.activities + net.transitions).sorted(), cells = activities.count * activities.count
        var differences: [(String, String, String, String)] = []
        for first in activities { for second in activities { let observed = basicRelation(counts, first, second), modeled = basicRelation(follows, first, second); if observed != modeled { differences.append((first, second, observed, modeled)) } } }
        var lines = ["FOOTPRINT \(name) activities \(activities.count) cells \(cells) differing \(differences.count) fitness \(fraction(Rational(cells - differences.count, cells)))"]
        if name == "reference" { for (first, second, observed, modeled) in differences where first <= second { lines.append("DIFF \(first) \(second) log \(observed) model \(modeled)") } }
        return lines
    }
    func buildPrefixes() { for record in cases { for length in 0...record.trace.count { let prefix = Array(record.trace.prefix(length)); var entry = prefixes[prefix] ?? Prefix(weight: 0, followers: []); entry.weight += 1; if length < record.trace.count { entry.followers.insert(record.trace[length]) }; prefixes[prefix] = entry } } }
    func precisionReport(_ name: String, _ net: PetriNet) -> [String] {
        var markings: [[String]: PrefixMark] = [:], fitting = 0, allowed = 0, escaping = 0, escapeWeights: [String: Int] = [:]
        for prefix in prefixes.keys.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            var marking: [Int]? = net.initialMarking
            if let transition = prefix.last { let parent = Array(prefix.dropLast()); if let previous = markings[parent]!.marking, net.inputs[transition] != nil && net.enabled(previous, transition) { marking = net.fire(previous, transition) } else { marking = nil } }
            markings[prefix] = PrefixMark(marking: marking)
            guard let marking else { continue }
            fitting += 1
            let entry = prefixes[prefix]!, enabled = Set(net.enabledTransitions(marking)), escapes = enabled.subtracting(entry.followers)
            allowed += entry.weight * enabled.count; escaping += entry.weight * escapes.count
            for transition in escapes { escapeWeights[transition, default: 0] += entry.weight }
        }
        let precision = allowed == 0 ? Rational(1) : Rational(allowed - escaping, allowed)
        var lines = ["PRECISION \(name) prefixes \(fitting) allowed \(allowed) escaping \(escaping) precision \(fraction(precision))"]
        for transition in escapeWeights.keys.sorted(by: { escapeWeights[$0]! == escapeWeights[$1]! ? $0 < $1 : escapeWeights[$0]! > escapeWeights[$1]! }) { lines.append("ESCAPE \(name) \(transition) weight \(escapeWeights[transition]!)") }
        return lines
    }
    func replayCase(_ net: PetriNet, _ record: CaseRecord) -> ReplayTotals {
        var result = ReplayTotals(net.places.count), tokens = Array(repeating: [Int](), count: net.places.count), consumed = Array(repeating: 0, count: net.places.count)
        tokens[net.initial].append(record.events[0].time); result.produced = 1
        for event in record.events { guard let inputs = net.inputs[event.activity] else { result.skipped += 1; continue }; for place in inputs { result.consumed += 1; if consumed[place] < tokens[place].count { let producedAt = tokens[place][consumed[place]]; consumed[place] += 1; result.waiting[place].append(event.time - producedAt); result.routes[place][event.activity, default: 0] += 1 } else { result.missing += 1; result.placeMissing[place] += 1 } }; for place in net.outputs[event.activity]! { tokens[place].append(event.time); result.produced += 1 } }
        result.consumed += 1
        if consumed[net.finalPlace] < tokens[net.finalPlace].count { consumed[net.finalPlace] += 1 } else { result.missing += 1; result.placeMissing[net.finalPlace] += 1 }
        for place in net.places.indices { let remaining = tokens[place].count - consumed[place]; result.placeRemaining[place] = remaining; result.remaining += remaining; result.deviating[place] = result.placeMissing[place] > 0 || remaining > 0 ? 1 : 0 }
        return result
    }
    func aggregateReplays(_ net: PetriNet) -> (total: ReplayTotals, results: [String: ReplayTotals], fitting: Int) {
        var total = ReplayTotals(net.places.count), results: [String: ReplayTotals] = [:], fitting = 0
        for record in cases { let result = replayCase(net, record); results[record.identifier] = result; if result.missing == 0 && result.remaining == 0 { fitting += 1 }; total.missing += result.missing; total.remaining += result.remaining; total.consumed += result.consumed; total.produced += result.produced; total.skipped += result.skipped; for place in net.places.indices { total.placeMissing[place] += result.placeMissing[place]; total.placeRemaining[place] += result.placeRemaining[place]; total.deviating[place] += result.deviating[place]; total.waiting[place] += result.waiting[place]; for (transition, count) in result.routes[place] { total.routes[place][transition, default: 0] += count } } }
        return (total, results, fitting)
    }
    func replayReport(_ name: String, _ net: PetriNet, _ total: ReplayTotals, _ fitting: Int) -> [String] {
        var lines = ["REPLAY \(name) cases \(cases.count) fitting \(fitting) skipped \(total.skipped) missing \(total.missing) remaining \(total.remaining) consumed \(total.consumed) produced \(total.produced) fitness \(fraction(total.fitness()))"]
        for (index, place) in net.places.enumerated() { let waiting = total.waiting[index], mean = waiting.isEmpty ? "-" : fraction(Rational(waiting.reduce(0, +), waiting.count)), maximum = waiting.max().map(String.init) ?? "-"; lines.append("PLACE \(name) \(place) missing \(total.placeMissing[index]) remaining \(total.placeRemaining[index]) deviating \(total.deviating[index]) tokens \(waiting.count) mean \(mean) max \(maximum)") }
        for (index, place) in net.places.enumerated() where net.routes[index].count >= 2 { let consumptions = net.routes[index].map { "\($0)=\(total.routes[index][$0, default: 0])" }.joined(separator: ","); lines.append("ROUTE \(name) \(place) \(consumptions)") }
        return lines
    }
    func conformanceReport() -> [String] {
        var lines = ["MODEL places \(reference.places.count) transitions \(reference.transitions.count) arcs \(reference.arcs.count)"], exploration: [Reachability] = []
        for named in nets { let result = explore(named.net); exploration.append(result); lines.append(reachabilityLine(named.name, result)) }
        for (index, named) in nets.enumerated() { lines += footprintFitness(named.name, named.net, exploration[index].follows) }
        buildPrefixes()
        for named in nets { lines += precisionReport(named.name, named.net) }
        for named in nets { let result = aggregateReplays(named.net); if named.name == "reference" { referenceReplays = result.results }; lines += replayReport(named.name, named.net, result.total, result.fitting) }
        return lines
    }
    func conformanceCSV() -> [String] { ["case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness"] + cases.map { record in let result = referenceReplays[record.identifier]!; return "\(record.identifier),\(variantByCase[record.identifier]!),\(record.events.count),\(result.skipped),\(result.missing),\(result.remaining),\(result.consumed),\(result.produced),\(fraction(result.fitness()))" } }
    func resourceReport() -> [String] {
        var events: [String: Int] = [:], caseCounts: [String: Int] = [:], work: [String: [String: Int]] = [:], handovers: Counts = [:], handoverCases: Counts = [:], subcontracting: Counts = [:], together: Counts = [:]
        for record in cases {
            let workers = record.events.map { $0.resource }, present = Set(workers).sorted()
            for resource in present { caseCounts[resource, default: 0] += 1 }
            for first in present.indices { for second in (first + 1)..<present.count { together[NamePair(present[first], present[second]), default: 0] += 1 } }
            for event in record.events { events[event.resource, default: 0] += 1; work[event.resource, default: [:]][event.activity, default: 0] += 1 }
            var pairs: Set<NamePair> = []
            for index in 1..<workers.count { let pair = NamePair(workers[index - 1], workers[index]); handovers[pair, default: 0] += 1; pairs.insert(pair) }
            for pair in pairs { handoverCases[pair, default: 0] += 1 }
            if workers.count >= 3 { for index in 0..<(workers.count - 2) where workers[index] == workers[index + 2] && workers[index] != workers[index + 1] { subcontracting[NamePair(workers[index], workers[index + 1]), default: 0] += 1 } }
        }
        var lines: [String] = []
        for (index, resource) in resources.enumerated() { let assignments = work[resource]!.keys.sorted().map { "\($0)=\(work[resource]![$0]!)" }.joined(separator: ","); lines.append("RESOURCE \(index + 1) \(resource) events \(events[resource]!) cases \(caseCounts[resource]!) work \(assignments)") }
        for pair in handovers.keys.sorted(by: { handovers[$0]! == handovers[$1]! ? $0 < $1 : handovers[$0]! > handovers[$1]! }) where pair.first != pair.second { lines.append("HANDOVER \(pair.first) \(pair.second) count \(handovers[pair]!) cases \(handoverCases[pair]!)") }
        lines += table(resources.map { first in resources.map { String(handovers[NamePair(first, $0), default: 0]) } }, 5)
        for pair in subcontracting.keys.sorted(by: { subcontracting[$0]! == subcontracting[$1]! ? $0 < $1 : subcontracting[$0]! > subcontracting[$1]! }) { lines.append("SUBCONTRACT \(pair.first) \(pair.second) count \(subcontracting[pair]!)") }
        for pair in together.keys.sorted(by: { together[$0]! == together[$1]! ? $0 < $1 : together[$0]! > together[$1]! }) { lines.append("TOGETHER \(pair.first) \(pair.second) cases \(together[pair]!)") }
        let total = handovers.values.reduce(0, +), own = handovers.filter { $0.key.first == $0.key.second }.values.reduce(0, +)
        lines.append("TOTAL handovers \(total) self \(own) other \(total - own)")
        return lines
    }
    func analyze() -> [(String, [String])] { buildVariants(); let workflows = mineWorkflows(), conformance = conformanceReport(); return [("log_summary.txt", logSummary()), ("variants.txt", variantReport()), ("dfg.txt", dfgReport()), ("alpha_net.txt", workflows), ("heuristic_net.txt", heuristicReport()), ("conformance.csv", conformanceCSV()), ("conformance.txt", conformance), ("resources.txt", resourceReport())] }
}
let study = try ProcessStudy(readInputs(), readModel())
try writeOutputs(study.analyze())
