import Foundation

struct Malformed: Error {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

final class Layer: FieldStore {
    var next: String?
    var payload: [UInt8] = []
    var remaining: [UInt8] = []
}

func readInteger(_ data: [UInt8], _ index: Int, _ count: Int) -> Int {
    var value = 0
    for byte in data[index..<(index + count)] { value = value * 256 + Int(byte) }
    return value
}

func checksumStatus(_ data: [UInt8]) -> String {
    var sum = 0
    for i in stride(from: 0, to: data.count, by: 2) {
        sum += Int(data[i]) * 256 + (i + 1 < data.count ? Int(data[i + 1]) : 0)
    }
    while sum > 65535 { sum = sum % 65536 + sum / 65536 }
    return sum == 65535 ? "good" : "bad"
}

func macNotation(_ value: Int) -> String {
    (0..<6).map { String(format: "%02x", (value >> ((5 - $0) * 8)) & 255) }.joined(separator: ":")
}

func ipv4Notation(_ value: Int) -> String {
    (0..<4).map { String((value >> ((3 - $0) * 8)) & 255) }.joined(separator: ".")
}

func dissectEthernet(_ frame: [UInt8]) throws -> Layer {
    if frame.count < 14 { throw Malformed("eth: truncated") }
    let layer = Layer()
    let type = readInteger(frame, 12, 2)
    layer.set("eth.dst", readInteger(frame, 0, 6))
    layer.set("eth.src", readInteger(frame, 6, 6))
    layer.set("eth.type", type)
    let payload = Array(frame.dropFirst(14))
    if type == 2054 || type == 2048 {
        layer.next = type == 2054 ? "arp" : "ip"
        layer.payload = payload
    } else {
        layer.remaining = payload
    }
    return layer
}

func dissectARP(_ message: [UInt8]) throws -> Layer {
    if message.count < 28 { throw Malformed("arp: truncated") }
    if readInteger(message, 0, 2) != 1 || readInteger(message, 2, 2) != 2048
        || message[4] != 6 || message[5] != 4 {
        throw Malformed("arp: unsupported format")
    }
    let layer = Layer()
    layer.set("arp.opcode", readInteger(message, 6, 2))
    layer.set("arp.src.hw", readInteger(message, 8, 6))
    layer.set("arp.src.ip", readInteger(message, 14, 4))
    layer.set("arp.dst.hw", readInteger(message, 18, 6))
    layer.set("arp.dst.ip", readInteger(message, 24, 4))
    return layer
}

func dissectIPv4(_ datagram: [UInt8]) throws -> Layer {
    let available = datagram.count
    if available < 20 { throw Malformed("ip: truncated header") }
    let version = Int(datagram[0]) / 16
    if version != 4 { throw Malformed("ip: bad version \(version)") }
    let headerLength = Int(datagram[0]) % 16 * 4
    if headerLength < 20 { throw Malformed("ip: bad header length \(headerLength)") }
    if available < headerLength { throw Malformed("ip: truncated header") }
    let total = readInteger(datagram, 2, 2)
    if total < headerLength { throw Malformed("ip: bad total length \(total)") }
    if total > available {
        throw Malformed("ip: truncated (total length \(total), available \(available))")
    }
    let flags = readInteger(datagram, 6, 2)
    let moreFragments = flags / 8192 % 2
    let fragmentOffset = flags % 8192 * 8
    let proto = Int(datagram[9])
    let layer = Layer()
    layer.set("ip.hdr_len", headerLength)
    layer.set("ip.tos", Int(datagram[1]))
    layer.set("ip.len", total)
    layer.set("ip.id", readInteger(datagram, 4, 2))
    layer.set("ip.flags.df", flags / 16384 % 2)
    layer.set("ip.flags.mf", moreFragments)
    layer.set("ip.frag_offset", fragmentOffset)
    layer.set("ip.ttl", Int(datagram[8]))
    layer.set("ip.proto", proto)
    layer.set("ip.checksum", readInteger(datagram, 10, 2))
    layer.set("ip.checksum.status", checksumStatus(Array(datagram.prefix(headerLength))))
    layer.set("ip.src", readInteger(datagram, 12, 4))
    layer.set("ip.dst", readInteger(datagram, 16, 4))
    let payload = Array(datagram[headerLength..<total])
    if moreFragments == 1 || fragmentOffset != 0 {
        layer.mark("ip.fragment")
        layer.remaining = payload
    } else if let next = [1: "icmp", 17: "udp", 6: "tcp"][proto] {
        layer.next = next
        layer.payload = payload
    } else {
        layer.remaining = payload
    }
    return layer
}
