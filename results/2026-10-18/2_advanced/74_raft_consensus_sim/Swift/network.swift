import Foundation

enum MessageType: String, CaseIterable { case rv = "RV", rvr = "RVR", ae = "AE", aer = "AER", tn = "TN" }
enum Payload {
    case voteRequest(Int, Int), voteResponse(Bool), appendRequest(Int, Int, [Entry], Int), appendResponse(Bool, Int), timeoutNow
    var kind: MessageType { switch self { case .voteRequest: return .rv; case .voteResponse: return .rvr; case .appendRequest: return .ae; case .appendResponse: return .aer; case .timeoutNow: return .tn } }
}
struct Message { let source: Int; let destination: Int; let term: Int; let payload: Payload; var kind: MessageType { payload.kind } }
enum MessageField: Int, CaseIterable {
    case sent, delivered, inflight, partition, rule, loss, down
    var name: String { ["sent", "delivered", "inflight", "partition", "rule", "loss", "down"][rawValue] }
}
struct MessageStatistics {
    private var counts = Array(repeating: 0, count: 7)
    subscript(_ field: MessageField) -> Int { get { counts[field.rawValue] } set { counts[field.rawValue] = newValue } }
}
struct LinkKey: Hashable { let source: Int; let destination: Int }
struct DropRule { let kind: MessageType?; let first: Int; let last: Int }
final class Link {
    var delay: Int
    var loss = 0, passed = 0
    var drops: [DropRule] = []
    var stats = MessageStatistics()
    init(_ delay: Int) { self.delay = delay }
}
struct Envelope { let serial: Int; let message: Message }
final class Network {
    let nodes: Int
    var links: [LinkKey: Link] = [:]
    var groups: [Int]
    var total = MessageStatistics()
    var byType: [MessageType: MessageStatistics] = [:]
    private var queue: [Int: [Envelope]] = [:]
    private var serial = 0
    init(_ nodes: Int) throws {
        self.nodes = nodes; groups = Array(repeating: 0, count: nodes + 1)
        let lines = try inputLines("network.txt"), delay = Int(lines[0][1])!
        for source in 1...nodes { for destination in 1...nodes where source != destination { links[LinkKey(source: source, destination: destination)] = Link(delay) } }
        for fields in lines.dropFirst() {
            for source in 1...nodes { for destination in 1...nodes where source != destination {
                if fields[1] != "*" && Int(fields[1])! != source { continue }; if fields[2] != "*" && Int(fields[2])! != destination { continue }
                let link = links[LinkKey(source: source, destination: destination)]!
                switch fields[0] { case "DELAY": link.delay = Int(fields[3])!; case "LOSS": link.loss = Int(fields[3])!; default: link.drops.append(DropRule(kind: MessageType(rawValue: fields[3]), first: Int(fields[4])!, last: Int(fields[5])!)) }
            } }
        }
    }
    func partition(_ partitions: [[Int]]) { for (index, partition) in partitions.enumerated() { for node in partition { groups[node] = index } } }
    func heal() { groups = Array(repeating: 0, count: nodes + 1) }
    func separated(_ first: Int, _ second: Int) -> Bool { groups[first] != groups[second] }
    private func count(_ message: Message, _ field: MessageField, _ amount: Int = 1) {
        total[field] += amount; byType[message.kind, default: MessageStatistics()][field] += amount
        links[LinkKey(source: message.source, destination: message.destination)]!.stats[field] += amount
    }
    func send(_ time: Int, _ source: Int, _ destination: Int, _ term: Int, _ payload: Payload) {
        let message = Message(source: source, destination: destination, term: term, payload: payload), link = links[LinkKey(source: source, destination: destination)]!
        serial += 1; count(message, .sent)
        if separated(source, destination) { count(message, .partition); return }
        if link.drops.contains(where: { ($0.kind == nil || $0.kind == message.kind) && $0.first <= time && time <= $0.last }) { count(message, .rule); return }
        link.passed += 1
        if link.loss > 0 && link.passed % link.loss == 0 { count(message, .loss); return }
        count(message, .inflight); queue[time + link.delay, default: []].append(Envelope(serial: serial, message: message))
    }
    func arrivals(_ time: Int) -> [Message] { (queue.removeValue(forKey: time) ?? []).sorted { $0.message.source == $1.message.source ? $0.serial < $1.serial : $0.message.source < $1.message.source }.map { $0.message } }
    func deliver(_ message: Message, _ destinationUp: Bool) -> Bool {
        count(message, .inflight, -1)
        if !destinationUp { count(message, .down); return false }
        if separated(message.source, message.destination) { count(message, .partition); return false }
        count(message, .delivered); return true
    }
}
