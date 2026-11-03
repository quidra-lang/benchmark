import Foundation

struct Parameters {
    var seed = 0
    var end = 0
    var cutTime = 0
    var comparisons: [(String, String)] = []
    var cuts: [[Int]] = []
    var predicates: [Int] = []
}
func readParameters() throws -> Parameters {
    var result = Parameters()
    for line in try String(contentsOfFile: "input/params.txt", encoding: .ascii).split(separator: "\n") {
        let fields = line.components(separatedBy: " ")
        switch fields[0] {
        case "SEED": result.seed = Int(fields[1])!
        case "END": result.end = Int(fields[1])!
        case "CUTCOUNT": result.cutTime = Int(fields[1])!
        case "COMPARE": result.comparisons.append((fields[1], fields[2]))
        case "CUT": result.cuts.append(fields.dropFirst().map { Int($0)! })
        default: result.predicates.append(Int(fields[1])!)
        }
    }
    return result
}
func yes(_ value: Bool) -> String { value ? "yes" : "no" }
func messageName(_ index: Int) -> String { "m\(index + 1)" }
enum EventType: Int { case local, noFunds, send, broadcast, receive; var text: String { ["LOCAL", "NOFUNDS", "SEND", "BCAST", "RECV"][rawValue] } }
enum EventDetails { case local(String), noFunds(Int, Int), sent(Int, Int?), received(Int) }
struct Event {
    let number: Int
    let localNumber: Int
    let process: Int
    let type: EventType
    let details: EventDetails
    let time: Int
    let lamport: Int
    let vector: [Int]
    let balance: Int
}
enum MessageKind: String { case point = "P2P", broadcast = "BCAST" }
final class Message {
    let source: Int
    let kind: MessageKind
    let tag: String
    let amount: Int
    let stamp: [Int]?
    let sendEvent: Int
    let sendTime: Int
    var copies: [Int] = []
    init(_ source: Int, _ kind: MessageKind, _ tag: String, _ amount: Int, _ stamp: [Int]?, _ sendEvent: Int, _ sendTime: Int) { self.source = source; self.kind = kind; self.tag = tag; self.amount = amount; self.stamp = stamp; self.sendEvent = sendEvent; self.sendTime = sendTime }
}
final class MessageCopy {
    let message: Int
    let source: Int
    let destination: Int
    let kind: MessageKind
    let tag: String
    let amount: Int
    let stamp: [Int]?
    let sendEvent: Int
    let packet: Packet
    var causalWait = false
    var missing: [Int] = []
    var receiveEvent: Int?
    var deliveryTime: Int?
    init(_ index: Int, _ message: Message, _ destination: Int, _ packet: Packet) { self.message = index; source = message.source; self.destination = destination; kind = message.kind; tag = message.tag; amount = message.amount; stamp = message.stamp; sendEvent = message.sendEvent; self.packet = packet }
}
enum TimelineEntry { case event(Int), snapshot(Int, Int, String) }
enum ScheduledPayload { case action(Action), arrival(Packet) }
struct QueueItem: Comparable {
    let time: Int
    let process: Int
    let creation: Int
    let payload: ScheduledPayload
    static func == (a: QueueItem, b: QueueItem) -> Bool { a.creation == b.creation }
    static func < (a: QueueItem, b: QueueItem) -> Bool { [a.time, a.process, a.creation].lexicographicallyPrecedes([b.time, b.process, b.creation]) }
}
struct SchedulingQueue {
    var items: [QueueItem] = []
    var first: QueueItem? { items.first }
    mutating func push(_ item: QueueItem) { items.append(item); var i = items.count - 1; while i > 0 { let parent = (i - 1) / 2; if !(items[i] < items[parent]) { break }; items.swapAt(i, parent); i = parent } }
    mutating func pop() -> QueueItem {
        let first = items[0], last = items.removeLast()
        if items.isEmpty { return first }
        items[0] = last
        var i = 0
        while 2 * i + 1 < items.count { let left = 2 * i + 1, right = left + 1, child = right < items.count && items[right] < items[left] ? right : left; if !(items[child] < items[i]) { break }; items.swapAt(i, child); i = child }
        return first
    }
}
final class Simulation {
    let names: [String]
    let params: Parameters
    let raw: Bool
    let processes: [ProcessState]
    let channels: [ChannelKey: Channel]
    let channelOrder: [ChannelKey]
    var generator: MINSTD
    var queue = SchedulingQueue()
    var creationNumber = 0
    var currentTime = 0
    var messages: [Message] = []
    var copies: [MessageCopy] = []
    var events: [Event] = []
    var snapshots: [Snapshot] = []
    var snapshotByName: [String: Int] = [:]
    var timeline: [TimelineEntry] = []
    var initialTotal: Int { processes.reduce(0) { $0 + $1.initial } }
    init(_ topology: Topology, _ scripts: [Script], _ params: Parameters, raw: Bool = false) {
        names = topology.names; self.params = params; self.raw = raw; processes = scripts.map { ProcessState($0, topology.names.count) }; channels = Dictionary(uniqueKeysWithValues: topology.channels.map { ($0.key, Channel($0, topology.names.count)) }); channelOrder = topology.channels.map { $0.key }; generator = MINSTD(state: params.seed)
        for item in scheduledActions(scripts, params.end) { enqueue(item.time, item.process, .action(item.action)) }
    }
    func enqueue(_ time: Int, _ process: Int, _ payload: ScheduledPayload) { creationNumber += 1; queue.push(QueueItem(time: time, process: process, creation: creationNumber, payload: payload)) }
    func dispatch(_ body: PacketBody, _ source: Int, _ destination: Int, _ vector: [Int]? = nil) -> Packet {
        let key = ChannelKey(source: source, destination: destination), packet = channels[key]!.dispatch(body, currentTime, vector, &generator)
        enqueue(packet.arrival, destination, .arrival(packet))
        return packet
    }
    @discardableResult func recordEvent(_ p: Int, _ kind: EventType, _ details: EventDetails, _ sender: Int? = nil) -> Int {
        let process = processes[p]
        if let sender { receiveEvent(process, p, events[sender]) } else { nonreceiveEvent(process, p) }
        let index = events.count, event = Event(number: index + 1, localNumber: process.events.count + 1, process: p, type: kind, details: details, time: currentTime, lamport: process.lamport, vector: process.vector, balance: process.balance)
        events.append(event); process.events.append(index); process.types[kind.rawValue] += 1; process.minimumBalance = min(process.minimumBalance, process.balance); timeline.append(.event(index))
        return index
    }
    func sendMessage(_ p: Int, _ action: Action, _ sender: Int?) {
        let process = processes[p]
        func resolve(_ destination: Destination) -> Int { switch destination { case .process(let index): return index; case .sender: return sender! } }
        let destination: Int?, tag: String, amount: Int, kind: MessageKind, eventType: EventType
        switch action {
        case .transfer(let target, let value):
            let resolved = resolve(target)
            if value > process.balance { process.refused += 1; recordEvent(p, .noFunds, .noFunds(resolved, value)); return }
            process.balance -= value; process.outgoing += value; destination = resolved; tag = "transfer"; amount = value; kind = .point; eventType = .send
        case .send(let target, let value): destination = resolve(target); tag = value; amount = 0; kind = .point; eventType = .send
        case .broadcast(let value): destination = nil; tag = value; amount = 0; kind = .broadcast; eventType = .broadcast; process.broadcast[p] += 1
        default: return
        }
        let index = messages.count, message = Message(p, kind, tag, amount, kind == .broadcast ? process.broadcast : nil, events.count, currentTime)
        messages.append(message)
        let sending = recordEvent(p, eventType, .sent(index, destination)), destinations = kind == .broadcast ? names.indices.filter { $0 != p } : [destination!]
        for target in destinations {
            let copyIndex = copies.count, packet = dispatch(.copy(copyIndex), p, target, events[sending].vector)
            copies.append(MessageCopy(index, message, target, packet)); message.copies.append(copyIndex)
        }
    }
    func perform(_ p: Int, _ action: Action, _ sender: Int? = nil) {
        switch action { case .local(let label): recordEvent(p, .local, .local(label)); case .snapshot(let name): initiateSnapshot(p, name); default: sendMessage(p, action, sender) }
    }
    func startSnapshot(_ name: String) -> Int {
        if let index = snapshotByName[name] { return index }
        let index = snapshots.count
        snapshots.append(Snapshot(name, currentTime, names.count, channelOrder)); snapshotByName[name] = index
        return index
    }
    func recordSnapshot(_ index: Int, _ p: Int, _ reason: String) {
        let snapshot = snapshots[index]
        snapshot.record(p, processes[p], currentTime, reason); timeline.append(.snapshot(currentTime, p, snapshot.name))
        for target in names.indices where target != p { let key = ChannelKey(source: p, destination: target); _ = dispatch(.marker(index), p, target); snapshot.markers[key] = MarkerTimes(sent: currentTime, accepted: nil) }
    }
    func initiateSnapshot(_ p: Int, _ name: String) {
        let index = startSnapshot(name), snapshot = snapshots[index]
        if snapshot.records[p] != nil { snapshot.ignored.append((p, currentTime)); return }
        recordSnapshot(index, p, "initiate")
    }
    func acceptMarker(_ index: Int, _ packet: Packet) {
        let snapshot = snapshots[index], destination = packet.key.destination
        if snapshot.records[destination] == nil { recordSnapshot(index, destination, "marker \(names[packet.key.source])") }
        snapshot.acceptMarker(packet.key, currentTime)
    }
    func deliver(_ index: Int) {
        let copy = copies[index], p = copy.destination, process = processes[p]
        if copy.kind == .broadcast { process.broadcast[copy.source] += 1 }
        process.balance += copy.amount; process.incoming += copy.amount
        let event = recordEvent(p, .receive, .received(index), copy.sendEvent)
        copy.receiveEvent = event; copy.deliveryTime = currentTime; process.delivered.append(index)
        for reaction in process.script.reactions where reaction.tag == copy.tag { perform(p, reaction.action, copy.source) }
    }
    func canDeliver(_ index: Int) -> Bool { let copy = copies[index]; return broadcastDeliverable(copy.stamp!, processes[copy.destination].broadcast, copy.source) }
    func releaseCausalWaits(_ p: Int) {
        let process = processes[p]
        while let position = process.holdback.firstIndex(where: { canDeliver($0) }) { let index = process.holdback.remove(at: position); deliver(index) }
    }
    func accept(_ packet: Packet) {
        let key = packet.key, p = key.destination, process = processes[p]
        process.nextSequence[key.source] += 1
        switch packet.body {
        case .marker(let index): acceptMarker(index, packet)
        case .copy(let index):
            for snapshot in snapshots where snapshot.records[p] != nil && !snapshot.accepted.contains(key) { snapshot.channelStates[key]!.append(index) }
            let copy = copies[index]
            if copy.kind == .point || raw { deliver(index); return }
            if canDeliver(index) { deliver(index); releaseCausalWaits(p) }
            else { copy.causalWait = true; copy.missing = missingIndices(copy.stamp!, process.broadcast, key.source); process.holdback.append(index) }
        }
    }
    func arrive(_ packet: Packet) {
        let key = packet.key, process = processes[key.destination]
        if raw { accept(packet) }
        else if packet.sequence != process.nextSequence[key.source] { packet.fifoWait = true; process.reorder[key.source][packet.sequence] = packet; channels[key]!.buffered += 1 }
        else {
            accept(packet)
            while let next = process.reorder[key.source].removeValue(forKey: process.nextSequence[key.source]) { accept(next) }
        }
        process.maximumHeld = max(process.maximumHeld, process.heldCount)
    }
    func run() { while let first = queue.first, first.time <= params.end { let item = queue.pop(); currentTime = item.time; switch item.payload { case .action(let action): perform(item.process, action); case .arrival(let packet): arrive(packet) } } }
}

func eventName(_ event: Event, _ names: [String]) -> String { "\(names[event.process]).\(event.localNumber)" }
func eventLine(_ event: Event, _ simulation: Simulation) -> String {
    let names = simulation.names
    let info: String
    switch event.details {
    case .local(let label): info = label
    case .noFunds(let destination, let amount): info = "to \(names[destination]) amount \(amount) balance \(event.balance)"
    case .sent(let index, let destination):
        let message = simulation.messages[index]
        if event.type == .broadcast { info = "\(messageName(index)) tag \(message.tag)" }
        else { info = "\(messageName(index)) to \(names[destination!]) tag \(message.tag)" + (message.amount > 0 ? " amount \(message.amount) balance \(event.balance)" : "") }
    case .received(let index):
        let copy = simulation.copies[index]
        info = "\(messageName(copy.message)) from \(names[copy.source]) tag \(copy.tag)" + (copy.amount > 0 ? " amount \(copy.amount) balance \(event.balance)" : "")
    }
    return "\(event.number) t=\(event.time) \(eventName(event, names)) \(event.type.text) \(info) L=\(event.lamport) V=\(vectorText(event.vector))"
}
func traceLines(_ simulation: Simulation) -> [String] {
    let delivered = simulation.copies.filter { $0.receiveEvent != nil }.count
    var lines = simulation.events.map { eventLine($0, simulation) } + ["SUMMARY events \(simulation.events.count) messages \(simulation.messages.count) copies \(simulation.copies.count) delivered \(delivered) undelivered \(simulation.copies.count - delivered) draws \(simulation.generator.draws)"]
    for (i, process) in simulation.processes.enumerated() { lines.append("FINAL \(simulation.names[i]) events \(process.events.count) L=\(process.lamport) V=\(vectorText(process.vector)) B=\(vectorText(process.broadcast)) balance \(process.balance) in \(process.incoming) out \(process.outgoing) refused \(process.refused) min \(process.minimumBalance)") }
    for (i, process) in simulation.processes.enumerated() { let counts = process.types; lines.append("COUNTS \(simulation.names[i]) local \(counts[0]) nofunds \(counts[1]) send \(counts[2]) bcast \(counts[3]) recv \(counts[4])") }
    return lines
}
func waitMode(_ copy: MessageCopy, _ names: [String]) -> String {
    if !copy.causalWait { return copy.packet.fifoWait ? "fifo" : "direct" }
    return (copy.packet.fifoWait ? "fifo+causal " : "causal ") + copy.missing.map { names[$0] }.joined(separator: ",")
}
func broadcastHistory(_ process: ProcessState, _ events: [Event], _ copies: [MessageCopy]) -> [Int] {
    process.events.compactMap { index in
        let event = events[index]
        if case .sent(let message, _) = event.details, event.type == .broadcast { return message }
        if case .received(let copy) = event.details, copies[copy].kind == .broadcast { return copies[copy].message }
        return nil
    }
}
func deliveriesLines(_ simulation: Simulation) -> [String] {
    var lines: [String] = []
    let names = simulation.names, copies = simulation.copies, messages = simulation.messages
    for (p, process) in simulation.processes.enumerated() {
        lines.append("PROCESS " + names[p])
        var modes = [0, 0, 0, 0], totalWait = 0, maximumWait = 0
        for (number, index) in process.delivered.enumerated() {
            let copy = copies[index], wait = copy.deliveryTime! - copy.packet.arrival, mode = (copy.packet.fifoWait ? 1 : 0) + (copy.causalWait ? 2 : 0)
            modes[mode] += 1; totalWait += wait; maximumWait = max(maximumWait, wait)
            lines.append("\(number + 1) \(messageName(copy.message)) from \(names[copy.source]) \(copy.kind.rawValue) tag \(copy.tag) sent \(messages[copy.message].sendTime) arrived \(copy.packet.arrival) delivered \(copy.deliveryTime!) wait \(wait) \(waitMode(copy, names))")
        }
        for copy in copies where copy.destination == p && copy.packet.arrival <= simulation.params.end && copy.receiveEvent == nil {
            let place = process.reorder[copy.source][copy.packet.sequence] != nil ? "fifo" : "causal " + copy.missing.map { names[$0] }.joined(separator: ",")
            lines.append("HELD \(messageName(copy.message)) from \(names[copy.source]) \(copy.kind.rawValue) tag \(copy.tag) sent \(messages[copy.message].sendTime) arrived \(copy.packet.arrival) \(place)")
        }
        for copy in copies where copy.destination == p && copy.packet.arrival > simulation.params.end { lines.append("TRANSIT \(messageName(copy.message)) from \(names[copy.source]) \(copy.kind.rawValue) tag \(copy.tag) sent \(messages[copy.message].sendTime) arrival \(copy.packet.arrival)") }
        lines.append("TOTAL delivered \(process.delivered.count) direct \(modes[0]) fifo \(modes[1]) causal \(modes[2]) both \(modes[3]) wait \(totalWait) max_wait \(maximumWait) max_held \(process.maximumHeld)")
        let history = broadcastHistory(process, simulation.events, copies)
        lines.append("BCASTS " + (history.isEmpty ? "none" : history.map { messageName($0) }.joined(separator: " ")))
    }
    for key in simulation.channelOrder { let channel = simulation.channels[key]!; lines.append("CHANNEL \(names[key.source])->\(names[key.destination]) \(channel.definition.fifo ? "FIFO" : "NONFIFO") \(channel.delayText) messages \(channel.messages) markers \(channel.markers) buffered \(channel.buffered) max_delay \(channel.maximumDelay) entries \(channel.entries)") }
    for tag in Set(copies.map { $0.tag }).sorted() {
        let tagged = copies.filter { $0.tag == tag }, completed = tagged.filter { $0.receiveEvent != nil }, latencies = completed.map { $0.deliveryTime! - messages[$0.message].sendTime }
        lines.append("TAG \(tag) copies \(tagged.count) delivered \(completed.count) latency \(latencies.reduce(0, +)) max \(latencies.max() ?? 0)")
    }
    let broadcasts = messages.indices.filter { messages[$0].kind == .broadcast }
    for index in broadcasts {
        let message = messages[index], times = message.copies.compactMap { copies[$0].deliveryTime }, stable = times.count == message.copies.count ? String(times.max()!) : "none"
        lines.append("STABLE \(messageName(index)) \(names[message.source]) tag \(message.tag) sent \(message.sendTime) stable \(stable)")
    }
    let histories = simulation.processes.map { broadcastHistory($0, simulation.events, copies) }
    var disagreements = 0
    for (i, first) in broadcasts.enumerated() {
        for second in broadcasts.dropFirst(i + 1) {
            var earlier: [String] = [], later: [String] = []
            for p in names.indices { if let a = histories[p].firstIndex(of: first), let b = histories[p].firstIndex(of: second) { if a < b { earlier.append(names[p]) } else { later.append(names[p]) } } }
            if !earlier.isEmpty && !later.isEmpty { disagreements += 1; lines.append("DISAGREE \(messageName(first)) \(messageName(second)) \(earlier.joined(separator: ",")) \(later.joined(separator: ","))") }
        }
    }
    lines.append("DISAGREEMENTS \(disagreements)")
    return lines
}
func consistentVerdict(_ details: CutDetails, _ simulation: Simulation) -> String { details.consistent ? "yes" : "no " + details.orphans.map { copyLabel(simulation.copies[$0], simulation.names) }.joined(separator: " ") }
func snapshotsLines(_ normal: Simulation, _ comparison: Simulation) -> [String] {
    var lines: [String] = []
    for (simulation, raw) in [(normal, false), (comparison, true)] {
        for snapshot in simulation.snapshots {
            let cut = snapshot.cut, details = cutDetails(cut, simulation.processes, simulation.events, simulation.copies), recorded = snapshot.recordedCopies(simulation.channelOrder), channelsTotal = recorded.channels.reduce(0) { $0 + simulation.copies[$1].amount }, balances = snapshot.records.reduce(0) { $0 + $1!.balance }, money = balances + channelsTotal
            if raw { lines.append("RAW \(snapshot.name) completed \(snapshot.completion!) cut \(vectorText(cut)) consistent \(consistentVerdict(details, simulation)) money \(money) conserved \(yes(money == simulation.initialTotal))"); continue }
            lines.append("SNAPSHOT \(snapshot.name) started \(snapshot.start) completed \(snapshot.completion!)")
            for p in simulation.names.indices {
                let record = snapshot.records[p]!, pending = record.pending.map { messageName(simulation.copies[$0].message) }
                lines.append("RECORD \(simulation.names[p]) t=\(record.time) \(record.reason) balance \(record.balance) L=\(record.lamport) V=\(vectorText(record.vector)) pending \(pending.isEmpty ? "none" : pending.joined(separator: " "))")
            }
            for key in simulation.channelOrder {
                let state = snapshot.channelStates[key]!, marker = snapshot.markers[key]!, values = state.map { index -> String in let copy = simulation.copies[index]; return messageName(copy.message) + (copy.amount > 0 ? ":\(copy.amount)" : "") }
                lines.append("CHANNEL \(simulation.names[key.source])->\(simulation.names[key.destination]) marker \(marker.sent) \(marker.accepted!) state \(values.isEmpty ? "empty" : values.joined(separator: " "))")
            }
            for item in snapshot.ignored { lines.append("IGNORED \(simulation.names[item.process]) t=\(item.time)") }
            lines += ["CUT \(vectorText(cut)) consistent \(consistentVerdict(details, simulation)) vector \(yes(snapshot.vectorConsistent))", "TRANSIT channels \(recorded.channels.count) pending \(recorded.pending.count) cut \(details.transit.count) match \(yes(transitMatch(recorded.channels, recorded.pending, details.transit)))", "MONEY balances \(balances) channels \(channelsTotal) total \(money) initial \(simulation.initialTotal) conserved \(yes(money == simulation.initialTotal))"]
        }
    }
    return lines
}

func rangeNotation(_ path: [Int], _ simulation: Simulation) -> String {
    if path.isEmpty { return "-" }
    var segments: [(Int, Int)] = [], first = path[0], last = path[0]
    for index in path.dropFirst() {
        let a = simulation.events[last], b = simulation.events[index]
        if a.process == b.process && b.localNumber == a.localNumber + 1 { last = index }
        else { segments.append((first, last)); first = index; last = index }
    }
    segments.append((first, last))
    return segments.map { a, b in a == b ? eventName(simulation.events[a], simulation.names) : eventName(simulation.events[a], simulation.names) + "-\(simulation.events[b].localNumber)" }.joined(separator: " ")
}
func longestChain(_ simulation: Simulation) -> [Int] {
    var current = 0
    for i in simulation.events.indices.dropFirst() { if simulation.events[i].lamport > simulation.events[current].lamport { current = i } }
    var chain = [current]
    while simulation.events[current].lamport > 1 {
        let event = simulation.events[current]
        var predecessor: Int?
        if case .received(let index) = event.details { let sending = simulation.copies[index].sendEvent; if simulation.events[sending].lamport == event.lamport - 1 { predecessor = sending } }
        current = predecessor ?? simulation.processes[event.process].events[event.localNumber - 2]; chain.append(current)
    }
    return Array(chain.reversed())
}
func analysisLines(_ simulation: Simulation, _ raw: Simulation) -> [String] {
    let events = simulation.events, names = simulation.names, copies = simulation.copies, edges = graphEdges(events, simulation.processes, copies)
    let indexed = Dictionary(uniqueKeysWithValues: events.enumerated().map { (eventName($0.element, names), $0.offset) })
    var lines: [String] = []
    for (firstName, secondName) in simulation.params.comparisons {
        let a = indexed[firstName]!, b = indexed[secondName]!, first = events[a], second = events[b], vectorRelation = relation(first.vector, second.vector)
        let forward = graphPath(a, b, edges), reverse = forward == nil ? graphPath(b, a, edges) : nil, graphRelation = forward != nil ? "->" : reverse != nil ? "<-" : "||"
        lines.append("COMPARE \(firstName) \(vectorRelation) \(secondName) L=\(first.lamport),\(second.lamport) graph \(graphRelation) agree \(yes(vectorRelation == graphRelation))")
        if let path = forward ?? reverse { var count = 0; for i in path.indices.dropFirst() { if events[path[i - 1]].process != events[path[i]].process { count += 1 } }; lines.append("PATH length \(path.count) messages \(count) \(rangeNotation(path, simulation))") }
        for event in [first, second] { let future = simulation.processes.map { process in process.events.filter { events[$0].vector[event.process] < event.localNumber }.count }; lines.append("WINDOW \(eventName(event, names)) past \(vectorText(event.vector)) future \(vectorText(future))") }
    }
    let summary = concurrencyStatistics(events)
    lines.append("CONCURRENCY events \(events.count) pairs \(summary.pairs) ordered \(summary.ordered) concurrent \(summary.concurrent) same_lamport \(summary.sameLamport) inversions \(summary.inversions)")
    for i in names.indices { for j in (i + 1)..<names.count { lines.append("PAIR \(names[i]) \(names[j]) \(summary.byPair[ChannelKey(source: i, destination: j)] ?? 0)") } }
    let chain = longestChain(simulation), pairs = racesAndViolations(simulation.processes, copies, events)
    lines.append("CHAIN length \(chain.count) \(rangeNotation(chain, simulation))")
    for pair in pairs.races { let a = copies[pair.first], b = copies[pair.second]; lines.append("RACE \(names[pair.process]) \(messageName(a.message)) \(names[a.source]) \(messageName(b.message)) \(names[b.source])") }
    lines.append("RACES \(pairs.races.count)")
    for pair in pairs.violations { let a = copies[pair.first], b = copies[pair.second]; lines.append("VIOLATION \(names[pair.process]) \(messageName(a.message)) \(names[a.source]) overtook \(messageName(b.message)) \(names[b.source])") }
    lines.append("VIOLATIONS causal \(pairs.violations.count) fifo \(pairs.violations.filter { copies[$0.first].source == copies[$0.second].source }.count)")
    let rawPairs = racesAndViolations(raw.processes, raw.copies, raw.events)
    lines.append("RAW events \(raw.events.count) delivered \(raw.copies.filter { $0.receiveEvent != nil }.count) causal \(rawPairs.violations.count) fifo \(rawPairs.violations.filter { raw.copies[$0.first].source == raw.copies[$0.second].source }.count)")
    for cut in simulation.params.cuts {
        let details = cutDetails(cut, simulation.processes, events, copies), verdict = details.consistent ? "consistent" : "inconsistent orphans " + details.orphans.map { copyLabel(copies[$0], names) }.joined(separator: " ")
        lines.append("CUT \(vectorText(cut)) \(verdict) transit \(details.transit.count) money \(details.money) initial \(simulation.initialTotal)")
    }
    let enumeration = enumerateCuts(simulation.processes, events, simulation.params.cutTime, simulation.params.predicates)
    lines += ["CUTCOUNT t=\(simulation.params.cutTime) events \(vectorText(enumeration.limits)) product \(enumeration.product) consistent \(enumeration.consistent)", "LEVELS " + enumeration.levels.map(String.init).joined(separator: " ")]
    for (i, threshold) in simulation.params.predicates.enumerated() { let record = enumeration.predicates[i]; lines.append("PREDICATE transit>=\(threshold) cuts \(record.cuts) possibly \(yes(record.possibly)) definitely \(yes(record.definitely))") }
    return lines
}
func trimmed(_ bytes: [UInt8]) -> String { var result = bytes; while result.last == 32 { result.removeLast() }; return String(decoding: result, as: UTF8.self) }
func diagramHeader(_ letter: String, _ names: [String]) -> String {
    var bytes = Array(repeating: UInt8(32), count: 8 * names.count - 1)
    bytes[4] = letter.utf8.first!
    for (p, name) in names.enumerated() { let column = 8 * (p + 1) - 2; for (offset, byte) in name.utf8.enumerated() { if column + offset >= bytes.count { bytes += Array(repeating: 32, count: column + offset + 1 - bytes.count) }; bytes[column + offset] = byte } }
    return trimmed(bytes)
}
func diagramEntry(_ value: Int, _ p: Int, _ type: EventType?, _ details: EventDetails?, _ snapshot: String?, _ simulation: Simulation) -> String {
    let last = 8 * simulation.names.count - 2, columns = simulation.names.indices.map { 8 * ($0 + 1) - 2 }, own = columns[p]
    var bytes = Array(repeating: UInt8(32), count: last + 1)
    let digits = Array(String(value).utf8)
    for (i, byte) in digits.enumerated() { bytes[5 - digits.count + i] = byte }
    for column in columns { bytes[column] = 124 }
    func write(_ position: Int, _ text: String) { for (offset, byte) in text.utf8.enumerated() { let index = position + offset; if index >= bytes.count { bytes += Array(repeating: 32, count: index + 1 - bytes.count) }; bytes[index] = byte } }
    if let snapshot { bytes[own] = 35; write(own + 1, snapshot) }
    else {
        bytes[own] = [UInt8(42), 120, 83, 66, 82][type!.rawValue]
        switch details! {
        case .sent(let message, _): write(own + 1, messageName(message))
        case .received(let index):
            let copy = simulation.copies[index], other = columns[copy.source], low = min(own, other), high = max(own, other)
            for index in (low + 1)..<high { bytes[index] = columns.contains(index) ? 43 : 45 }
            bytes[other < own ? high - 1 : low + 1] = other < own ? 62 : 60
            write(low + 2, messageName(copy.message)); bytes[own] = 82
        default: break
        }
    }
    return trimmed(bytes)
}
func diagramLines(_ simulation: Simulation) -> [String] {
    var lines = [diagramHeader("t", simulation.names)]
    for entry in simulation.timeline {
        switch entry {
        case .event(let index): let event = simulation.events[index]; lines.append(diagramEntry(event.time, event.process, event.type, event.details, nil, simulation))
        case .snapshot(let time, let p, let name): lines.append(diagramEntry(time, p, nil, nil, name, simulation))
        }
    }
    lines.append(diagramHeader("L", simulation.names))
    for event in simulation.events.sorted(by: { $0.lamport == $1.lamport ? $0.process < $1.process : $0.lamport < $1.lamport }) { lines.append(diagramEntry(event.lamport, event.process, event.type, event.details, nil, simulation)) }
    return lines
}
func saveOutput(_ name: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try text.write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}

let topology = try readTopology(), scripts = try readScripts(topology.names), params = try readParameters()
let normal = Simulation(topology, scripts, params), comparison = Simulation(topology, scripts, params, raw: true)
normal.run()
comparison.run()
try saveOutput("trace.txt", traceLines(normal))
try saveOutput("deliveries.txt", deliveriesLines(normal))
try saveOutput("snapshots.txt", snapshotsLines(normal, comparison))
try saveOutput("analysis.txt", analysisLines(normal, comparison))
try saveOutput("diagram.txt", diagramLines(normal))
