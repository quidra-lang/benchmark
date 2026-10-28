import Foundation

func dnsTypeName(_ type: Int) -> String {
    [1: "A", 2: "NS", 5: "CNAME", 6: "SOA", 12: "PTR", 15: "MX", 16: "TXT", 28: "AAAA"][type]
        ?? "TYPE\(type)"
}

func dnsRcodeName(_ code: Int) -> String {
    let names = ["NoError", "FormErr", "ServFail", "NXDomain", "NotImp", "Refused"]
    return code < names.count ? names[code] : "RCODE\(code)"
}

func dnsLabelText(_ bytes: [UInt8]) -> String {
    bytes.map { byte in
        if (33...126).contains(byte) && byte != 46 && byte != 92 {
            return String(UnicodeScalar(Int(byte))!)
        }
        return "\\" + String(format: "%03d", Int(byte))
    }.joined()
}

func ipv6Notation(_ bytes: [UInt8]) -> String {
    let groups = stride(from: 0, to: 16, by: 2).map { readInteger(bytes, $0, 2) }
    var bestStart: Int?
    var bestLength = 1
    var index = 0
    while index < groups.count {
        if groups[index] != 0 {
            index += 1
            continue
        }
        var end = index
        while end < groups.count && groups[end] == 0 { end += 1 }
        if end - index > bestLength {
            bestStart = index
            bestLength = end - index
        }
        index = end
    }
    let texts = groups.map { String($0, radix: 16) }
    guard let start = bestStart else { return texts.joined(separator: ":") }
    return texts.prefix(start).joined(separator: ":") + "::"
        + texts.dropFirst(start + bestLength).joined(separator: ":")
}

struct DNSReader {
    let message: [UInt8]

    func chunk(_ position: Int, _ count: Int) throws -> [UInt8] {
        if position + count > message.count { throw Malformed("dns: truncated") }
        return Array(message[position..<(position + count)])
    }

    func integer(_ position: Int, _ count: Int) throws -> Int {
        readInteger(try chunk(position, count), 0, count)
    }

    func name(_ start: Int) throws -> (String, Int) {
        var position = start
        var labels: [String] = []
        var pointers = 0
        var after: Int?
        while true {
            let length = try integer(position, 1)
            if length == 0 {
                if after == nil { after = position + 1 }
                break
            }
            if length >= 192 {
                let low = try integer(position + 1, 1)
                if after == nil { after = position + 2 }
                pointers += 1
                if pointers > 16 { throw Malformed("dns: compression loop") }
                let target = (length - 192) * 256 + low
                if target >= message.count { throw Malformed("dns: pointer out of range") }
                position = target
            } else if length >= 64 {
                throw Malformed("dns: bad label type")
            } else {
                labels.append(dnsLabelText(try chunk(position + 1, length)))
                position += length + 1
            }
        }
        return (labels.isEmpty ? "<root>" : labels.joined(separator: "."), after!)
    }

    func rdata(_ type: Int, _ start: Int, _ length: Int) throws -> (String, Int) {
        switch type {
        case 1:
            return (ipv4Notation(try integer(start, 4)), start + 4)
        case 28:
            return (ipv6Notation(try chunk(start, 16)), start + 16)
        case 2, 5, 12:
            return try name(start)
        case 15:
            let preference = try integer(start, 2)
            let (exchange, end) = try name(start + 2)
            return ("\(preference) \(exchange)", end)
        case 6:
            let (primary, next) = try name(start)
            let (mailbox, last) = try name(next)
            var position = last
            var fields = [primary, mailbox]
            for _ in 0..<5 {
                fields.append(String(try integer(position, 4)))
                position += 4
            }
            return (fields.joined(separator: " "), position)
        default:
            return ("\(length) bytes", start + length)
        }
    }

    func record(_ start: Int, _ section: String, _ layer: Layer) throws -> Int {
        let (recordName, position) = try name(start)
        let fixed = try chunk(position, 10)
        let type = readInteger(fixed, 0, 2)
        let recordClass = readInteger(fixed, 2, 2)
        let ttl = readInteger(fixed, 4, 4)
        let length = readInteger(fixed, 8, 2)
        let dataStart = position + 10
        if dataStart + length > message.count { throw Malformed("dns: truncated") }
        let (text, end) = try rdata(type, dataStart, length)
        if end != dataStart + length { throw Malformed("dns: bad rdata length") }
        let className = recordClass == 1 ? "IN" : "CLASS\(recordClass)"
        layer.add(section, "\(recordName) \(dnsTypeName(type)) \(className) \(ttl) \(text)")
        if section == "dns.answer" && type == 1 { layer.add("dns.a", readInteger(message, dataStart, 4)) }
        return dataStart + length
    }
}

func dissectDNS(_ message: [UInt8]) throws -> Layer {
    let reader = DNSReader(message: message)
    let header = try reader.chunk(0, 12)
    let flags = readInteger(header, 2, 2)
    let counts = stride(from: 4, to: 12, by: 2).map { readInteger(header, $0, 2) }
    let layer = Layer()
    layer.set("dns.id", readInteger(header, 0, 2))
    layer.set("dns.flags", flags)
    layer.set("dns.flags.response", flags / 32768 % 2)
    layer.set("dns.flags.opcode", flags / 2048 % 16)
    layer.set("dns.flags.rcode", flags % 16)
    let countFields = ["dns.count.queries", "dns.count.answers", "dns.count.auth_rr", "dns.count.add_rr"]
    for (field, count) in zip(countFields, counts) { layer.set(field, count) }
    var position = 12
    for _ in 0..<counts[0] {
        let (name, after) = try reader.name(position)
        let tail = try reader.chunk(after, 4)
        layer.add("dns.qry.name", name)
        layer.add("dns.qry.type", readInteger(tail, 0, 2))
        position = after + 4
    }
    for (section, count) in zip(["dns.answer", "dns.authority", "dns.additional"], counts.dropFirst()) {
        for _ in 0..<count { position = try reader.record(position, section, layer) }
    }
    return layer
}
