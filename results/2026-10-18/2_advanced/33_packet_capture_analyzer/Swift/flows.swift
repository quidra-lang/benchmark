enum AnalysisMark: String, CaseIterable {
    case retransmission
    case outOfOrder = "out_of_order"
    case lostSegment = "lost_segment"
    case duplicateAck = "duplicate_ack"
}

struct Endpoint: Hashable, Comparable {
    let address: Int
    let port: Int?

    static func < (a: Endpoint, b: Endpoint) -> Bool {
        a.address == b.address ? (a.port ?? -1) < (b.port ?? -1) : a.address < b.address
    }
}

struct EndpointPair: Hashable {
    let first: Endpoint
    let second: Endpoint

    init(_ a: Endpoint, _ b: Endpoint) {
        first = min(a, b)
        second = max(a, b)
    }
}

struct ReceivedInterval: Hashable {
    let start: Int
    let size: Int
}

final class PreviousAck {
    let ack: Int
    let window: Int
    let number: Int
    var count = 0

    init(_ ack: Int, _ window: Int, _ number: Int) {
        self.ack = ack
        self.window = window
        self.number = number
    }
}

final class StreamSide {
    let name: String
    var isn: Int?
    var mss: Int?
    var wscale: Int?
    var base: Int?
    var expected: Int?
    var advancedAt: Int?
    var intervals: Set<ReceivedInterval> = []
    var previousAck: PreviousAck?
    var packets = 0
    var payload = 0
    var marks = Dictionary(uniqueKeysWithValues: AnalysisMark.allCases.map { ($0, 0) })

    init(_ name: String) { self.name = name }
}

enum TCPState: String {
    case synSent = "SYN_SENT"
    case synReceived = "SYN_RECEIVED"
    case established = "ESTABLISHED"
    case finWait = "FIN_WAIT"
    case closing = "CLOSING"
    case closed = "CLOSED"
    case reset = "RESET"
}

struct StreamEvent {
    let number: Int
    let side: String
    let mark: AnalysisMark
    let sequence: Int
    let length: Int
}

final class TCPStream {
    let number: Int
    let client: Endpoint
    let server: Endpoint
    var state: TCPState
    var history: [(TCPState, Int)]
    let start: Int
    var end: Int
    var packets = 0
    var bytes = 0
    var syn: Int?
    var synAck: Int?
    var handshakeAck: Int?
    var events: [StreamEvent] = []
    var closer: Int?
    var finalAck: Int?
    let sides = [StreamSide("client"), StreamSide("server")]

    init(_ number: Int, _ client: Endpoint, _ server: Endpoint, _ state: TCPState, _ packet: Packet) {
        self.number = number
        self.client = client
        self.server = server
        self.state = state
        history = [(state, packet.number)]
        start = packet.time
        end = packet.time
    }

    func recordSYN(_ side: Int, _ packet: Packet) {
        sides[side].isn = packet.int("tcp.seq_raw")
        sides[side].mss = packet.numberValue("tcp.options.mss")
        sides[side].wscale = packet.numberValue("tcp.options.wscale")
        if side == 0 { syn = packet.number } else { synAck = packet.number }
    }

    func changeState(_ next: TCPState, _ packet: Int) {
        state = next
        history.append((next, packet))
    }
}

final class StreamTracker {
    var streams: [TCPStream] = []
    var latest: [EndpointPair: Int] = [:]
    let modulus = 1 << 32

    func track(_ packet: Packet) {
        let source = Endpoint(address: packet.int("ip.src"), port: packet.int("tcp.srcport"))
        let destination = Endpoint(address: packet.int("ip.dst"), port: packet.int("tcp.dstport"))
        let syn = packet.int("tcp.flags.syn") == 1
        let ackSet = packet.int("tcp.flags.ack") == 1
        let fin = packet.int("tcp.flags.fin") == 1
        let rst = packet.int("tcp.flags.rst") == 1
        let seq = packet.int("tcp.seq_raw")
        let ack = packet.numberValue("tcp.ack_raw")
        let length = packet.int("tcp.len")
        let window = packet.int("tcp.window")
        let key = EndpointPair(source, destination)
        var stream = latest[key].map { streams[$0] }
        if stream == nil || ((stream!.state == .closed || stream!.state == .reset) && syn && !ackSet) {
            let state: TCPState = syn ? (ackSet ? .synReceived : .synSent) : .established
            let client = syn && ackSet ? destination : source
            let server = syn && ackSet ? source : destination
            let opened = TCPStream(streams.count, client, server, state, packet)
            if syn { opened.recordSYN(ackSet ? 1 : 0, packet) }
            streams.append(opened)
            latest[key] = opened.number
            stream = opened
        }
        let current = stream!
        packet.set("tcp.stream", current.number)
        let sideIndex = source == current.client ? 0 : 1
        let side = current.sides[sideIndex]
        let other = current.sides[1 - sideIndex]
        if side.base == nil { side.base = seq }
        if ackSet && other.base == nil { other.base = ack! }
        let relative = (seq - side.base! + modulus) % modulus
        packet.set("tcp.seq", relative)
        if ackSet { packet.set("tcp.ack", (ack! - other.base! + modulus) % modulus) }
        let size = length + (syn ? 1 : 0) + (fin ? 1 : 0)
        var mark: AnalysisMark?
        if size > 0 {
            if let expected = side.expected, relative != expected {
                if relative > expected {
                    mark = .lostSegment
                } else if side.intervals.contains(ReceivedInterval(start: relative, size: size)) {
                    mark = .retransmission
                } else {
                    mark = packet.time - side.advancedAt! < 3000 ? .outOfOrder : .retransmission
                }
            }
            side.intervals.insert(ReceivedInterval(start: relative, size: size))
            if side.expected == nil || relative + size > side.expected! {
                side.expected = relative + size
                side.advancedAt = packet.time
            }
        } else if ackSet && !rst, let previous = side.previousAck,
            previous.ack == ack! && previous.window == window {
            mark = .duplicateAck
            previous.count += 1
            packet.duplicateAck = (previous.number, previous.count)
        }
        if ackSet && mark != .duplicateAck { side.previousAck = PreviousAck(ack!, window, packet.number) }
        if let mark {
            packet.mark("tcp.analysis." + mark.rawValue)
            side.marks[mark, default: 0] += 1
            current.events.append(StreamEvent(
                number: packet.number, side: side.name, mark: mark, sequence: relative, length: size
            ))
        }
        let scaled = current.sides[0].wscale != nil && current.sides[1].wscale != nil && !syn
        packet.set("tcp.window.calc", scaled ? window * (1 << side.wscale!) : window)
        let state = current.state
        if rst {
            if state != .closed && state != .reset { current.changeState(.reset, packet.number) }
        } else if state == .synSent && sideIndex == 1 && syn && ackSet
            && ack! == (current.sides[0].isn! + 1) % modulus {
            current.changeState(.synReceived, packet.number)
            current.recordSYN(1, packet)
        } else if state == .synReceived && sideIndex == 0 && ackSet && !syn
            && ack! == (current.sides[1].isn! + 1) % modulus {
            current.changeState(.established, packet.number)
            current.handshakeAck = packet.number
        } else if state == .established && fin {
            current.changeState(.finWait, packet.number)
            current.closer = sideIndex
        } else if state == .finWait && fin && sideIndex != current.closer! {
            current.changeState(.closing, packet.number)
            current.finalAck = (seq + length + 1) % modulus
        } else if state == .closing && sideIndex == current.closer! && ackSet && ack! == current.finalAck! {
            current.changeState(.closed, packet.number)
        }
        side.packets += 1
        side.payload += length
        current.packets += 1
        current.bytes += packet.length
        current.end = packet.time
    }
}

enum ConversationKind: Int {
    case ipv4
    case tcp
    case udp
    var name: String { ["ipv4", "tcp", "udp"][rawValue] }
}

enum ConversationKey: Hashable {
    case ipv4(EndpointPair)
    case tcp(Int)
    case udp(EndpointPair)
}

final class Conversation {
    let kind: ConversationKind
    let endpointA: Endpoint
    let endpointB: Endpoint
    let firstNumber: Int
    let firstTime: Int
    var lastTime: Int
    var packetsAToB = 0
    var bytesAToB = 0
    var packetsBToA = 0
    var bytesBToA = 0
    var packets: Int { packetsAToB + packetsBToA }
    var bytes: Int { bytesAToB + bytesBToA }

    init(_ kind: ConversationKind, _ source: Endpoint, _ destination: Endpoint, _ packet: Packet) {
        self.kind = kind
        endpointA = source
        endpointB = destination
        firstNumber = packet.number
        firstTime = packet.time
        lastTime = packet.time
    }

    func count(_ source: Endpoint, _ packet: Packet) {
        if source == endpointA {
            packetsAToB += 1
            bytesAToB += packet.length
        } else {
            packetsBToA += 1
            bytesBToA += packet.length
        }
        lastTime = packet.time
    }
}

func buildConversations(_ packets: [Packet]) -> [Conversation] {
    var table: [ConversationKey: Conversation] = [:]
    for packet in packets where packet.has("ip.src") {
        let sourceIP = packet.int("ip.src")
        let destinationIP = packet.int("ip.dst")
        let sourceAddress = Endpoint(address: sourceIP, port: nil)
        let destinationAddress = Endpoint(address: destinationIP, port: nil)
        var views: [(ConversationKind, ConversationKey, Endpoint, Endpoint)] = [
            (.ipv4, .ipv4(EndpointPair(sourceAddress, destinationAddress)), sourceAddress, destinationAddress)
        ]
        if packet.has("tcp.stream") {
            let source = Endpoint(address: sourceIP, port: packet.int("tcp.srcport"))
            let destination = Endpoint(address: destinationIP, port: packet.int("tcp.dstport"))
            views.append((.tcp, .tcp(packet.int("tcp.stream")), source, destination))
        }
        if packet.has("udp.srcport") {
            let source = Endpoint(address: sourceIP, port: packet.int("udp.srcport"))
            let destination = Endpoint(address: destinationIP, port: packet.int("udp.dstport"))
            views.append((.udp, .udp(EndpointPair(source, destination)), source, destination))
        }
        for (kind, key, source, destination) in views {
            if table[key] == nil { table[key] = Conversation(kind, source, destination, packet) }
            table[key]!.count(source, packet)
        }
    }
    return table.values.sorted { a, b in
        if a.bytes != b.bytes { return a.bytes > b.bytes }
        if a.packets != b.packets { return a.packets > b.packets }
        if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
        return a.firstNumber < b.firstNumber
    }
}

final class EndpointTotals {
    let address: Int
    var txPackets = 0
    var txBytes = 0
    var rxPackets = 0
    var rxBytes = 0
    var packets: Int { txPackets + rxPackets }
    var bytes: Int { txBytes + rxBytes }

    init(_ address: Int) { self.address = address }
}

func buildEndpoints(_ packets: [Packet]) -> [EndpointTotals] {
    var table: [Int: EndpointTotals] = [:]
    for packet in packets where packet.has("ip.src") {
        let source = packet.int("ip.src")
        let destination = packet.int("ip.dst")
        if table[source] == nil { table[source] = EndpointTotals(source) }
        if table[destination] == nil { table[destination] = EndpointTotals(destination) }
        table[source]!.txPackets += 1
        table[source]!.txBytes += packet.length
        table[destination]!.rxPackets += 1
        table[destination]!.rxBytes += packet.length
    }
    return table.values.sorted { a, b in
        if a.bytes != b.bytes { return a.bytes > b.bytes }
        if a.packets != b.packets { return a.packets > b.packets }
        return a.address < b.address
    }
}
