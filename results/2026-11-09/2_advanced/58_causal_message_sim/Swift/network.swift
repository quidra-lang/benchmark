import Foundation

struct ChannelKey: Hashable, Comparable {
    let source: Int
    let destination: Int
    static func < (a: ChannelKey, b: ChannelKey) -> Bool { a.source == b.source ? a.destination < b.destination : a.source < b.source }
}
struct ChannelDefinition { let key: ChannelKey; let fifo: Bool; let minimum: Int; let maximum: Int }
struct Topology { let names: [String]; let channels: [ChannelDefinition] }
struct MINSTD {
    var state: Int
    var draws = 0
    mutating func draw() -> Int { state = 48271 * state % 2147483647; draws += 1; return state }
}
enum PacketBody { case copy(Int), marker(Int) }
final class Packet {
    let body: PacketBody
    let key: ChannelKey
    let sequence: Int
    let dispatched: Int
    let arrival: Int
    var fifoWait = false
    init(_ body: PacketBody, _ key: ChannelKey, _ sequence: Int, _ dispatched: Int, _ arrival: Int) { self.body = body; self.key = key; self.sequence = sequence; self.dispatched = dispatched; self.arrival = arrival }
}
final class Channel {
    let definition: ChannelDefinition
    var sequence = 0
    var lastArrival = 0
    var messages = 0
    var markers = 0
    var buffered = 0
    var maximumDelay = 0
    var entries = 0
    var previousVector: [Int]
    init(_ definition: ChannelDefinition, _ count: Int) { self.definition = definition; previousVector = Array(repeating: 0, count: count) }
    func dispatch(_ body: PacketBody, _ time: Int, _ vector: [Int]?, _ generator: inout MINSTD) -> Packet {
        sequence += 1
        let low = definition.minimum, high = definition.maximum, delay = low == high ? low : low + generator.draw() % (high - low + 1)
        let arrival = definition.fifo ? max(time + delay, lastArrival) : time + delay
        lastArrival = max(lastArrival, arrival); maximumDelay = max(maximumDelay, arrival - time)
        switch body {
        case .marker: markers += 1
        case .copy:
            messages += 1
            let next = vector!
            entries += next.indices.filter { next[$0] != previousVector[$0] }.count; previousVector = next
        }
        return Packet(body, definition.key, sequence, time, arrival)
    }
    var delayText: String { definition.minimum == definition.maximum ? String(definition.minimum) : "\(definition.minimum)-\(definition.maximum)" }
}
func readTopology() throws -> Topology {
    let rows = try String(contentsOfFile: "input/topology.txt", encoding: .ascii).split(separator: "\n").map { $0.components(separatedBy: " ") }, names = Array(rows[0].dropFirst())
    let indices = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($0.element, $0.offset) })
    let definitions = rows.dropFirst().map { row in ChannelDefinition(key: ChannelKey(source: indices[row[1]]!, destination: indices[row[2]]!), fifo: row[3] == "FIFO", minimum: Int(row[4])!, maximum: Int(row.count == 6 ? row[5] : row[4])!) }.sorted { $0.key < $1.key }
    return Topology(names: names, channels: definitions)
}
