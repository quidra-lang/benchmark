import Foundation

enum FieldValue: Equatable {
    case number(Int)
    case text(String)
    case present
}

class FieldStore {
    var fields: [String: [FieldValue]] = [:]

    func has(_ name: String) -> Bool { !(fields[name] ?? []).isEmpty }
    func values(_ name: String) -> [FieldValue] { fields[name] ?? [] }
    func set(_ name: String, _ value: Int) { fields[name] = [.number(value)] }
    func set(_ name: String, _ value: String) { fields[name] = [.text(value)] }
    func mark(_ name: String) { fields[name] = [.present] }
    func add(_ name: String, _ value: Int) { fields[name, default: []].append(.number(value)) }
    func add(_ name: String, _ value: String) { fields[name, default: []].append(.text(value)) }

    func numberValue(_ name: String) -> Int? {
        if case let .number(value)? = fields[name]?.first { return value }
        return nil
    }

    func stringValue(_ name: String) -> String? {
        if case let .text(value)? = fields[name]?.first { return value }
        return nil
    }

    func int(_ name: String) -> Int { numberValue(name)! }

    func strings(_ name: String) -> [String] {
        values(name).compactMap { if case let .text(value) = $0 { return value }; return nil }
    }

    func numbers(_ name: String) -> [Int] {
        values(name).compactMap { if case let .number(value) = $0 { return value }; return nil }
    }
}

enum FieldType {
    case integer
    case hex2
    case hex4
    case ipv4
    case mac
    case string
    case presence
}

let fieldOrder: [(String, FieldType)] = [
    ("frame.number", .integer), ("frame.time", .integer), ("frame.len", .integer),
    ("frame.protocols", .string), ("frame.malformed", .string), ("frame.bad_checksum", .presence),
    ("eth.dst", .mac), ("eth.src", .mac), ("eth.type", .hex4),
    ("arp.opcode", .integer), ("arp.src.hw", .mac), ("arp.src.ip", .ipv4),
    ("arp.dst.hw", .mac), ("arp.dst.ip", .ipv4),
    ("ip.hdr_len", .integer), ("ip.tos", .hex2), ("ip.len", .integer), ("ip.id", .hex4),
    ("ip.flags.df", .integer), ("ip.flags.mf", .integer), ("ip.frag_offset", .integer),
    ("ip.ttl", .integer), ("ip.proto", .integer), ("ip.checksum", .hex4),
    ("ip.checksum.status", .string), ("ip.src", .ipv4), ("ip.dst", .ipv4), ("ip.fragment", .presence),
    ("icmp.type", .integer), ("icmp.code", .integer), ("icmp.checksum", .hex4),
    ("icmp.checksum.status", .string), ("icmp.id", .integer), ("icmp.seq", .integer),
    ("udp.srcport", .integer), ("udp.dstport", .integer), ("udp.length", .integer),
    ("udp.checksum", .hex4), ("udp.checksum.status", .string),
    ("tcp.srcport", .integer), ("tcp.dstport", .integer), ("tcp.stream", .integer),
    ("tcp.seq", .integer), ("tcp.seq_raw", .integer), ("tcp.ack", .integer), ("tcp.ack_raw", .integer),
    ("tcp.hdr_len", .integer), ("tcp.flags", .hex2), ("tcp.flags.fin", .integer),
    ("tcp.flags.syn", .integer), ("tcp.flags.rst", .integer), ("tcp.flags.psh", .integer),
    ("tcp.flags.ack", .integer), ("tcp.flags.urg", .integer), ("tcp.window", .integer),
    ("tcp.window.calc", .integer), ("tcp.checksum", .hex4), ("tcp.checksum.status", .string),
    ("tcp.urgent", .integer), ("tcp.option", .string), ("tcp.options.mss", .integer),
    ("tcp.options.wscale", .integer), ("tcp.options.malformed", .presence), ("tcp.len", .integer),
    ("tcp.analysis.retransmission", .presence), ("tcp.analysis.out_of_order", .presence),
    ("tcp.analysis.lost_segment", .presence), ("tcp.analysis.duplicate_ack", .presence),
    ("dns.id", .hex4), ("dns.flags", .hex4), ("dns.flags.response", .integer),
    ("dns.flags.opcode", .integer), ("dns.flags.rcode", .integer), ("dns.count.queries", .integer),
    ("dns.count.answers", .integer), ("dns.count.auth_rr", .integer), ("dns.count.add_rr", .integer),
    ("dns.qry.name", .string), ("dns.qry.type", .integer), ("dns.answer", .string),
    ("dns.authority", .string), ("dns.additional", .string), ("dns.a", .ipv4), ("data.len", .integer)
]
let fieldTypes = Dictionary(uniqueKeysWithValues: fieldOrder)
let aliases: [String: (FieldType, String, String)] = [
    "eth.addr": (.mac, "eth.dst", "eth.src"), "ip.addr": (.ipv4, "ip.src", "ip.dst"),
    "udp.port": (.integer, "udp.srcport", "udp.dstport"), "tcp.port": (.integer, "tcp.srcport", "tcp.dstport")
]
let protocolFields = ["eth", "arp", "ip", "icmp", "udp", "tcp", "dns", "data"]
let checksumLayers = [("ip", "IPv4"), ("icmp", "ICMP"), ("udp", "UDP"), ("tcp", "TCP")]
let comparisons: Set<String> = ["==", "!=", "<", ">", "<=", ">="]

func seconds(_ time: Int) -> String {
    String(time / 1_000_000) + "." + String(format: "%06d", time % 1_000_000)
}

func optional(_ value: Int?) -> String { value.map(String.init) ?? "-" }

func notation(_ type: FieldType, _ value: FieldValue) -> String {
    if case let .text(text) = value { return text }
    guard case let .number(number) = value else { return "" }
    switch type {
    case .hex2:
        return "0x" + String(format: "%02x", number)
    case .hex4:
        return "0x" + String(format: "%04x", number)
    case .ipv4:
        return ipv4Notation(number)
    case .mac:
        return macNotation(number)
    default:
        return String(number)
    }
}

func shown(_ packet: Packet, _ name: String) -> String {
    notation(fieldTypes[name]!, packet.values(name)[0])
}

func endpointText(_ endpoint: Endpoint) -> String {
    ipv4Notation(endpoint.address) + (endpoint.port.map { ":\($0)" } ?? "")
}

func fieldType(_ name: String) -> FieldType? {
    if let type = fieldTypes[name] { return type }
    if let alias = aliases[name] { return alias.0 }
    return protocolFields.contains(name) ? .presence : nil
}

func fieldValues(_ packet: Packet, _ name: String) -> [FieldValue] {
    if let alias = aliases[name] { return packet.values(alias.1) + packet.values(alias.2) }
    return packet.values(name)
}

func dissect(_ packet: Packet, _ baseTime: Int) throws {
    if !packet.badDump {
        var next: String? = "eth"
        var payload = packet.data
        while let name = next {
            packet.layers.append(name)
            do {
                let layer: Layer
                switch name {
                case "eth": layer = try dissectEthernet(payload)
                case "arp": layer = try dissectARP(payload)
                case "ip": layer = try dissectIPv4(payload)
                case "icmp": layer = try dissectICMP(payload)
                case "udp": layer = try dissectUDP(payload, packet.int("ip.src"), packet.int("ip.dst"))
                case "tcp": layer = try dissectTCP(payload, packet.int("ip.src"), packet.int("ip.dst"))
                default: layer = try dissectDNS(payload)
                }
                packet.fields.merge(layer.fields) { _, new in new }
                next = layer.next
                payload = layer.payload
                if next == nil { packet.remaining = layer.remaining }
            } catch let error as Malformed {
                packet.reason = error.reason
                packet.remaining = []
                break
            }
        }
    }
    if packet.reason == nil && !packet.remaining.isEmpty {
        packet.layers.append("data")
        packet.set("data.len", packet.remaining.count)
    }
    packet.set("frame.number", packet.number)
    packet.set("frame.time", packet.time - baseTime)
    packet.set("frame.len", packet.length)
    if !packet.layers.isEmpty { packet.set("frame.protocols", packet.layers.joined(separator: ":")) }
    if let reason = packet.reason { packet.set("frame.malformed", reason) }
    if checksumLayers.contains(where: { packet.stringValue($0.0 + ".checksum.status") == "bad" }) {
        packet.mark("frame.bad_checksum")
    }
}

func optionSummary(_ options: [String]) -> String {
    var result = ""
    for option in options {
        let words = option.split(separator: " ").map(String.init)
        switch words[0] {
        case "MSS": result += " MSS=\(words[1])"
        case "WS": result += " WS=\(1 << Int(words[1])!)"
        case "SACK_PERM": result += " SACK_PERM"
        case "TS": result += " TSval=\(words[1]) TSecr=\(words[2])"
        default: break
        }
    }
    return result
}

func tcpInfo(_ packet: Packet) -> String {
    var text = ""
    if let duplicate = packet.duplicateAck {
        text = "[TCP Dup ACK \(duplicate.number)#\(duplicate.count)] "
    } else if packet.has("tcp.analysis.retransmission") {
        text = "[TCP Retransmission] "
    } else if packet.has("tcp.analysis.out_of_order") {
        text = "[TCP Out-Of-Order] "
    } else if packet.has("tcp.analysis.lost_segment") {
        text = "[TCP Previous segment not captured] "
    }
    let flags = packet.int("tcp.flags")
    let names = ["FIN", "SYN", "RST", "PSH", "ACK", "URG", "ECE", "CWR"].enumerated()
        .filter { flags >> $0.offset & 1 == 1 }.map { $0.element }
    let flagText = names.isEmpty ? "<None>" : names.joined(separator: ", ")
    text += "\(packet.int("tcp.srcport")) -> \(packet.int("tcp.dstport")) [\(flagText)] Seq=\(packet.int("tcp.seq"))"
    if packet.int("tcp.flags.ack") == 1 { text += " Ack=\(packet.int("tcp.ack"))" }
    text += " Win=\(packet.int("tcp.window.calc")) Len=\(packet.int("tcp.len"))"
    return text + optionSummary(packet.strings("tcp.option"))
}

func dnsInfo(_ packet: Packet) -> String {
    var parts = [packet.int("dns.flags.response") == 1 ? "Response" : "Query", shown(packet, "dns.id")]
    let code = packet.int("dns.flags.rcode")
    if code != 0 { parts.append(dnsRcodeName(code)) }
    for (name, type) in zip(packet.strings("dns.qry.name"), packet.numbers("dns.qry.type")) {
        parts += [dnsTypeName(type), name]
    }
    for record in packet.strings("dns.answer") {
        let fields = record.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
        parts += [fields[1], fields[4]]
    }
    return parts.joined(separator: " ")
}

func basicInfo(_ packet: Packet, _ proto: String) -> String {
    if let reason = packet.reason { return reason }
    switch proto {
    case "ETH":
        return "EtherType " + shown(packet, "eth.type")
    case "ARP":
        switch packet.int("arp.opcode") {
        case 1: return "Who has \(shown(packet, "arp.dst.ip"))? Tell \(shown(packet, "arp.src.ip"))"
        case 2: return "\(shown(packet, "arp.src.ip")) is at \(shown(packet, "arp.src.hw"))"
        default: return "Opcode \(packet.int("arp.opcode"))"
        }
    case "IPv4":
        if packet.has("ip.fragment") {
            return "Fragment id=\(shown(packet, "ip.id")) off=\(packet.int("ip.frag_offset"))"
                + (packet.int("ip.flags.mf") == 1 ? " MF" : "")
        }
        return "Protocol \(packet.int("ip.proto"))"
    case "ICMP":
        let type = packet.int("icmp.type")
        if type == 0 || type == 8 {
            let label = type == 8 ? "request" : "reply"
            return "Echo \(label) id=\(packet.int("icmp.id")) seq=\(packet.int("icmp.seq"))"
        }
        return "Type \(type) code \(packet.int("icmp.code"))"
    case "UDP":
        return "\(packet.int("udp.srcport")) -> \(packet.int("udp.dstport")) Len=\(packet.int("udp.length") - 8)"
    case "TCP":
        return tcpInfo(packet)
    default:
        return dnsInfo(packet)
    }
}

func summaryLine(_ packet: Packet) -> String {
    let source: String
    let destination: String
    if packet.has("ip.src") {
        source = shown(packet, "ip.src")
        destination = shown(packet, "ip.dst")
    } else if packet.has("eth.src") {
        source = shown(packet, "eth.src")
        destination = shown(packet, "eth.dst")
    } else {
        source = "-"
        destination = "-"
    }
    let labels = ["eth": "ETH", "arp": "ARP", "ip": "IPv4", "icmp": "ICMP", "udp": "UDP", "tcp": "TCP", "dns": "DNS"]
    let proto = packet.layers.last(where: { $0 != "data" }).map { labels[$0]! } ?? "DUMP"
    var info = basicInfo(packet, proto)
    if packet.has("tcp.options.malformed") { info += " [bad TCP options]" }
    for (layer, label) in checksumLayers where packet.stringValue(layer + ".checksum.status") == "bad" {
        info += " [bad \(label) checksum]"
    }
    return "\(packet.number) \(seconds(packet.int("frame.time"))) \(source) -> \(destination) \(proto) \(packet.length) \(info)"
}

struct FilterError: Error {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

struct FilterToken {
    let kind: String
    let text: String
    let column: Int
}

func wordCharacter(_ byte: UInt8) -> Bool {
    (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
        || byte == 46 || byte == 95 || byte == 58
}

func filterTokens(_ expression: String) throws -> [FilterToken] {
    let bytes = Array(expression.utf8)
    let twoCharacter: Set<String> = ["==", "!=", "<=", ">=", "&&", "||"]
    let keywords = ["and": "&&", "or": "||", "not": "!"]
    var tokens: [FilterToken] = []
    var index = 0
    while index < bytes.count {
        let column = index + 1
        let character = bytes[index]
        let pair = index + 1 < bytes.count ? String(decoding: bytes[index...(index + 1)], as: UTF8.self) : ""
        if character == 32 {
            index += 1
        } else if twoCharacter.contains(pair) {
            tokens.append(FilterToken(kind: pair, text: pair, column: column))
            index += 2
        } else if [40, 41, 33, 60, 62].contains(Int(character)) {
            let text = String(UnicodeScalar(Int(character))!)
            tokens.append(FilterToken(kind: text, text: text, column: column))
            index += 1
        } else if character == 34 {
            var end = index + 1
            while end < bytes.count && bytes[end] != 34 { end += 1 }
            if end == bytes.count { throw FilterError("unterminated string at column \(column)") }
            let text = String(decoding: bytes[index...end], as: UTF8.self)
            tokens.append(FilterToken(kind: "string", text: text, column: column))
            index = end + 1
        } else if wordCharacter(character) {
            var end = index
            while end < bytes.count && wordCharacter(bytes[end]) { end += 1 }
            let text = String(decoding: bytes[index..<end], as: UTF8.self)
            tokens.append(FilterToken(kind: keywords[text] ?? "word", text: text, column: column))
            index = end
        } else {
            throw FilterError("invalid character '\(String(UnicodeScalar(Int(character))!))' at column \(column)")
        }
    }
    return tokens
}

func allDigits(_ text: String, _ minimum: Int, _ maximum: Int) -> Bool {
    (minimum...maximum).contains(text.utf8.count) && text.utf8.allSatisfy { (48...57).contains($0) }
}

func allHex(_ text: String, _ minimum: Int, _ maximum: Int) -> Bool {
    (minimum...maximum).contains(text.utf8.count)
        && text.utf8.allSatisfy { lowerHex($0) || (65...70).contains($0) }
}

func convertValue(_ type: FieldType, _ token: FilterToken) -> FieldValue? {
    if type == .string {
        return token.kind == "string" ? .text(String(token.text.dropFirst().dropLast())) : nil
    }
    if token.kind != "word" { return nil }
    let text = token.text
    switch type {
    case .integer, .hex2, .hex4:
        if allDigits(text, 1, 15) { return .number(Int(text)!) }
        if text.hasPrefix("0x") && allHex(String(text.dropFirst(2)), 1, 12) {
            return .number(Int(text.dropFirst(2), radix: 16)!)
        }
    case .ipv4:
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 4 && parts.allSatisfy({ allDigits($0, 1, 3) && Int($0)! <= 255 }) {
            return .number(parts.reduce(0) { $0 * 256 + Int($1)! })
        }
    case .mac:
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 6 && parts.allSatisfy({ allHex($0, 2, 2) }) {
            return .number(parts.reduce(0) { $0 * 256 + Int($1, radix: 16)! })
        }
    default:
        break
    }
    return nil
}

indirect enum FilterExpression {
    case existence(String)
    case comparison(String, String, FieldValue)
    case negation(FilterExpression)
    case conjunction(FilterExpression, FilterExpression)
    case disjunction(FilterExpression, FilterExpression)
}

final class FilterParser {
    let tokens: [FilterToken]
    var position = 0
    var nextKind: String? { position < tokens.count ? tokens[position].kind : nil }

    init(_ tokens: [FilterToken]) { self.tokens = tokens }

    func unexpected(_ token: FilterToken) -> FilterError {
        FilterError("unexpected '\(token.text)' at column \(token.column)")
    }

    func take() throws -> FilterToken {
        if position == tokens.count { throw FilterError("unexpected end of filter") }
        let token = tokens[position]
        position += 1
        return token
    }

    func parse() throws -> FilterExpression {
        let node = try expression()
        if position < tokens.count { throw unexpected(tokens[position]) }
        return node
    }

    func expression() throws -> FilterExpression {
        var node = try product()
        while nextKind == "||" {
            _ = try take()
            node = .disjunction(node, try product())
        }
        return node
    }

    func product() throws -> FilterExpression {
        var node = try negation()
        while nextKind == "&&" {
            _ = try take()
            node = .conjunction(node, try negation())
        }
        return node
    }

    func negation() throws -> FilterExpression {
        if nextKind == "!" {
            _ = try take()
            return .negation(try negation())
        }
        let token = try take()
        if token.kind == "(" {
            let node = try expression()
            let closing = try take()
            if closing.kind != ")" { throw unexpected(closing) }
            return node
        }
        if token.kind == "word" { return try test(token.text) }
        throw unexpected(token)
    }

    func test(_ name: String) throws -> FilterExpression {
        guard let type = fieldType(name) else { throw FilterError("unknown field \(name)") }
        guard let kind = nextKind, comparisons.contains(kind) else { return .existence(name) }
        let operation = try take().kind
        if type == .presence || (type == .string && operation != "==" && operation != "!=") {
            throw FilterError("operator \(operation) not allowed for \(name)")
        }
        let token = try take()
        if token.kind != "word" && token.kind != "string" { throw unexpected(token) }
        guard let value = convertValue(type, token) else {
            throw FilterError("invalid value \(token.text) for \(name)")
        }
        return .comparison(name, operation, value)
    }
}

func compare(_ first: FieldValue, _ operation: String, _ second: FieldValue) -> Bool {
    if operation == "==" { return first == second }
    guard case let .number(a) = first, case let .number(b) = second else { return false }
    switch operation {
    case "<": return a < b
    case ">": return a > b
    case "<=": return a <= b
    default: return a >= b
    }
}

func evaluate(_ expression: FilterExpression, _ packet: Packet) -> Bool {
    switch expression {
    case let .negation(node):
        return !evaluate(node, packet)
    case let .conjunction(first, second):
        return evaluate(first, packet) && evaluate(second, packet)
    case let .disjunction(first, second):
        return evaluate(first, packet) || evaluate(second, packet)
    case let .existence(name):
        return protocolFields.contains(name) ? packet.layers.contains(name) : !fieldValues(packet, name).isEmpty
    case let .comparison(name, operation, expected):
        let values = fieldValues(packet, name)
        if values.isEmpty { return false }
        if operation == "!=" { return values.allSatisfy { $0 != expected } }
        return values.contains { compare($0, operation, expected) }
    }
}

func filterBlock(_ expression: String, _ packets: [Packet], _ summaries: [String]) throws -> [String] {
    var lines = ["", "filter " + expression]
    do {
        let tree = try FilterParser(filterTokens(expression)).parse()
        let matched = packets.filter { evaluate(tree, $0) }
        lines += matched.map { summaries[$0.number - 1] }
        lines.append("matched \(matched.count) of \(packets.count)")
    } catch let error as FilterError {
        lines.append("error: " + error.reason)
    }
    return lines
}

func detailLines(_ packets: [Packet], _ number: Int) -> [String] {
    if number < 1 || number > packets.count { return ["packet \(number) not found"] }
    let packet = packets[number - 1]
    var lines = ["packet \(number)"]
    for layer in ["frame"] + packet.layers {
        lines.append(layer)
        for (name, type) in fieldOrder where name.hasPrefix(layer + ".") {
            for value in packet.values(name) {
                lines.append("  " + name + (type == .presence ? "" : " = " + notation(type, value)))
            }
        }
        if layer == "data" { lines += hexDumpLines(packet.remaining).map { "  " + $0 } }
    }
    return lines
}

struct DNSTransactions {
    let queries: [Packet]
    let responses: [Packet]
    let responseTimes: [Int]
    let unanswered: Int

    init(_ packets: [Packet]) {
        var queries: [Packet] = []
        var responses: [Packet] = []
        var times: [Int] = []
        var pending: [Packet] = []
        for packet in packets where packet.has("dns.id") {
            if packet.int("dns.flags.response") == 0 {
                queries.append(packet)
                pending.append(packet)
            } else {
                responses.append(packet)
                if let index = pending.firstIndex(where: { query in
                    query.int("dns.id") == packet.int("dns.id")
                        && query.int("ip.src") == packet.int("ip.dst")
                        && query.int("udp.srcport") == packet.int("udp.dstport")
                        && query.int("ip.dst") == packet.int("ip.src")
                        && query.int("udp.dstport") == packet.int("udp.srcport")
                }) {
                    times.append(packet.time - pending[index].time)
                    pending.remove(at: index)
                }
            }
        }
        self.queries = queries
        self.responses = responses
        responseTimes = times
        unanswered = pending.count
    }
}

func protocolStatsLines(_ packets: [Packet], _ dns: DNSTransactions) -> [String] {
    let duration = packets.last!.time - packets[0].time
    var lines = [
        "packets \(packets.count)", "bytes \(packets.reduce(0) { $0 + $1.length })", "duration \(seconds(duration))",
        "hierarchy"
    ]
    let hierarchy = [("eth", 0), ("arp", 2), ("ip", 2), ("icmp", 4), ("udp", 4), ("dns", 6), ("tcp", 4)]
    for (name, indent) in hierarchy {
        let members = packets.filter { $0.layers.contains(name) }
        lines.append(String(repeating: " ", count: indent) + "\(name) \(members.count) \(members.reduce(0) { $0 + $1.length })")
    }
    lines.append("checksums")
    for (layer, _) in checksumLayers {
        let statuses = packets.compactMap { $0.stringValue(layer + ".checksum.status") }
        var line = "\(layer) good \(statuses.filter { $0 == "good" }.count) bad \(statuses.filter { $0 == "bad" }.count)"
        if layer == "udp" { line += " none \(statuses.filter { $0 == "none" }.count)" }
        lines.append(line)
    }
    lines += ["malformed", "dump \(packets.filter { $0.badDump }.count)"]
    for name in ["eth", "arp", "ip", "icmp", "udp", "tcp", "dns"] {
        let count = packets.filter { !$0.badDump && $0.reason != nil && $0.layers.last == name }.count
        lines.append("\(name) \(count)")
    }
    lines.append("tcp analysis")
    for mark in AnalysisMark.allCases {
        let count = packets.filter { $0.has("tcp.analysis." + mark.rawValue) }.count
        lines.append("\(mark.rawValue) \(count)")
    }
    lines += [
        "dns", "queries \(dns.queries.count)", "responses \(dns.responses.count)",
        "transactions \(dns.responseTimes.count)", "unanswered \(dns.unanswered)"
    ]
    if let minimum = dns.responseTimes.min(), let maximum = dns.responseTimes.max() {
        lines.append("response_time min \(seconds(minimum)) max \(seconds(maximum))")
    } else {
        lines.append("response_time -")
    }
    let rcodes = dns.responses.map { $0.int("dns.flags.rcode") }
    for code in 0..<16 {
        let count = rcodes.filter { $0 == code }.count
        if count > 0 { lines.append("rcode \(dnsRcodeName(code)) \(count)") }
    }
    lines.append("names")
    var names: [String: Int] = [:]
    for query in dns.queries {
        for name in query.strings("dns.qry.name") { names[name, default: 0] += 1 }
    }
    for (name, count) in names.sorted(by: { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }) {
        lines.append("\(name) \(count)")
    }
    return lines
}

func conversationLines(_ conversations: [Conversation], _ baseTime: Int) -> [String] {
    var lines = [
        "type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration"
    ]
    for conversation in conversations {
        let counts = [
            conversation.packets, conversation.bytes, conversation.packetsAToB, conversation.bytesAToB,
            conversation.packetsBToA, conversation.bytesBToA
        ].map(String.init)
        lines.append(([
            conversation.kind.name, endpointText(conversation.endpointA), endpointText(conversation.endpointB)
        ] + counts + [
            seconds(conversation.firstTime - baseTime), seconds(conversation.lastTime - conversation.firstTime)
        ]).joined(separator: ","))
    }
    return lines
}

func endpointLines(_ endpoints: [EndpointTotals]) -> [String] {
    ["address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes"] + endpoints.map { endpoint in
        let counts = [
            endpoint.packets, endpoint.bytes, endpoint.txPackets, endpoint.txBytes, endpoint.rxPackets, endpoint.rxBytes
        ].map(String.init)
        return ([ipv4Notation(endpoint.address)] + counts).joined(separator: ",")
    }
}

func sideLine(_ side: StreamSide) -> String {
    let counts = AnalysisMark.allCases.map { "\($0.rawValue) \(side.marks[$0]!)" }.joined(separator: " ")
    return "\(side.name) packets \(side.packets) payload \(side.payload) \(counts)"
}

func streamLines(_ stream: TCPStream, _ packets: [Packet]) -> [String] {
    var rtt = "-"
    if let syn = stream.syn, let ack = stream.handshakeAck { rtt = seconds(packets[ack - 1].time - packets[syn - 1].time) }
    let client = stream.sides[0]
    let server = stream.sides[1]
    let states = stream.history.map { "\($0.0.rawValue) \($0.1)" }.joined(separator: ", ")
    var lines = [
        "stream \(stream.number) \(endpointText(stream.client)) -> \(endpointText(stream.server))",
        "packets \(stream.packets) bytes \(stream.bytes) start \(seconds(stream.start - packets[0].time)) "
            + "duration \(seconds(stream.end - stream.start))",
        "states \(states)",
        "handshake syn \(optional(stream.syn)) syn_ack \(optional(stream.synAck)) "
            + "ack \(optional(stream.handshakeAck)) rtt \(rtt)",
        "options client mss \(optional(client.mss)) wscale \(optional(client.wscale)) "
            + "server mss \(optional(server.mss)) wscale \(optional(server.wscale))",
        sideLine(client), sideLine(server)
    ]
    for event in stream.events {
        lines.append(
            "event \(event.number) \(event.side) \(event.mark.rawValue) seq \(event.sequence) len \(event.length)"
        )
    }
    return lines
}

func joinedBlocks(_ blocks: [[String]]) -> [String] {
    var lines: [String] = []
    for (index, block) in blocks.enumerated() {
        if index > 0 { lines.append("") }
        lines += block
    }
    return lines
}

func writeLines(_ name: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try text.write(toFile: "output/" + name, atomically: true, encoding: .ascii)
}

let packets = try readCapture("input/capture.txt")
let requests = try readLines("input/filters.txt")
let filters = requests.filter { $0.hasPrefix("FILTER ") }.map { String($0.dropFirst(7)) }
let detailNumbers = requests.filter { $0.hasPrefix("DETAIL ") }.map { Int($0.dropFirst(7))! }
let baseTime = packets[0].time
for packet in packets { try dissect(packet, baseTime) }
let tracker = StreamTracker()
for packet in packets where packet.has("tcp.srcport") { tracker.track(packet) }
let summaries = packets.map(summaryLine)
var summary = summaries
for expression in filters { summary += try filterBlock(expression, packets, summaries) }
let details = joinedBlocks(detailNumbers.map { detailLines(packets, $0) })
let streams = joinedBlocks(tracker.streams.map { streamLines($0, packets) })
for (name, lines) in [
    ("summary.txt", summary), ("details.txt", details),
    ("conversations.csv", conversationLines(buildConversations(packets), baseTime)),
    ("endpoints.csv", endpointLines(buildEndpoints(packets))),
    ("protocol_stats.txt", protocolStatsLines(packets, DNSTransactions(packets))),
    ("tcp_streams.txt", streams)
] {
    try writeLines(name, lines)
}
