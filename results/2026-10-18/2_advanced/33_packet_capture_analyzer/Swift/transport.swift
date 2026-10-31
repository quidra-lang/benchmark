func pseudoHeader(_ source: Int, _ destination: Int, _ proto: Int, _ length: Int) -> [UInt8] {
    let sourceBytes = (0..<4).map { UInt8((source >> ((3 - $0) * 8)) & 255) }
    let destinationBytes = (0..<4).map { UInt8((destination >> ((3 - $0) * 8)) & 255) }
    return sourceBytes + destinationBytes + [0, UInt8(proto), UInt8(length / 256), UInt8(length % 256)]
}

func dissectICMP(_ message: [UInt8]) throws -> Layer {
    if message.count < 8 { throw Malformed("icmp: truncated") }
    let layer = Layer()
    let type = Int(message[0])
    layer.set("icmp.type", type)
    layer.set("icmp.code", Int(message[1]))
    layer.set("icmp.checksum", readInteger(message, 2, 2))
    layer.set("icmp.checksum.status", checksumStatus(message))
    if type == 0 || type == 8 {
        layer.set("icmp.id", readInteger(message, 4, 2))
        layer.set("icmp.seq", readInteger(message, 6, 2))
    }
    layer.remaining = Array(message.dropFirst(8))
    return layer
}

func dissectUDP(_ datagram: [UInt8], _ source: Int, _ destination: Int) throws -> Layer {
    if datagram.count < 8 { throw Malformed("udp: truncated") }
    let length = readInteger(datagram, 4, 2)
    if length < 8 || length > datagram.count { throw Malformed("udp: bad length \(length)") }
    let sourcePort = readInteger(datagram, 0, 2)
    let destinationPort = readInteger(datagram, 2, 2)
    let checksum = readInteger(datagram, 6, 2)
    let status = checksum == 0 ? "none"
        : checksumStatus(pseudoHeader(source, destination, 17, length) + Array(datagram.prefix(length)))
    let layer = Layer()
    layer.set("udp.srcport", sourcePort)
    layer.set("udp.dstport", destinationPort)
    layer.set("udp.length", length)
    layer.set("udp.checksum", checksum)
    layer.set("udp.checksum.status", status)
    let payload = Array(datagram[8..<length])
    if sourcePort == 53 || destinationPort == 53 {
        layer.next = "dns"
        layer.payload = payload
    } else {
        layer.remaining = payload
    }
    return layer
}

func parseOptions(_ options: [UInt8], _ layer: Layer) {
    let lengths = [2: [4], 3: [3], 4: [2], 5: [10, 18, 26, 34], 8: [10]]
    var index = 0
    while index < options.count {
        let kind = Int(options[index])
        if kind == 0 {
            layer.add("tcp.option", "EOL")
            return
        }
        if kind == 1 {
            layer.add("tcp.option", "NOP")
            index += 1
            continue
        }
        let length = index + 1 < options.count ? Int(options[index + 1]) : 0
        if length < 2 || index + length > options.count || (lengths[kind].map { !$0.contains(length) } ?? false) {
            layer.mark("tcp.options.malformed")
            return
        }
        let body = Array(options[(index + 2)..<(index + length)])
        let text: String
        switch kind {
        case 2:
            let mss = readInteger(body, 0, 2)
            layer.set("tcp.options.mss", mss)
            text = "MSS \(mss)"
        case 3:
            layer.set("tcp.options.wscale", Int(body[0]))
            text = "WS \(body[0])"
        case 4:
            text = "SACK_PERM"
        case 5:
            text = "SACK" + stride(from: 0, to: body.count, by: 8).map {
                " \(readInteger(body, $0, 4))-\(readInteger(body, $0 + 4, 4))"
            }.joined()
        case 8:
            text = "TS \(readInteger(body, 0, 4)) \(readInteger(body, 4, 4))"
        default:
            text = "kind \(kind) len \(length)"
        }
        layer.add("tcp.option", text)
        index += length
    }
}

func dissectTCP(_ segment: [UInt8], _ source: Int, _ destination: Int) throws -> Layer {
    if segment.count < 20 { throw Malformed("tcp: truncated header") }
    let headerLength = Int(segment[12]) / 16 * 4
    if headerLength < 20 { throw Malformed("tcp: bad header length \(headerLength)") }
    if headerLength > segment.count { throw Malformed("tcp: truncated header") }
    let flags = Int(segment[13])
    let layer = Layer()
    layer.set("tcp.srcport", readInteger(segment, 0, 2))
    layer.set("tcp.dstport", readInteger(segment, 2, 2))
    layer.set("tcp.seq_raw", readInteger(segment, 4, 4))
    layer.set("tcp.hdr_len", headerLength)
    layer.set("tcp.flags", flags)
    for (bit, name) in ["fin", "syn", "rst", "psh", "ack", "urg"].enumerated() {
        layer.set("tcp.flags." + name, (flags >> bit) & 1)
    }
    layer.set("tcp.window", readInteger(segment, 14, 2))
    layer.set("tcp.checksum", readInteger(segment, 16, 2))
    layer.set("tcp.checksum.status", checksumStatus(pseudoHeader(source, destination, 6, segment.count) + segment))
    layer.set("tcp.urgent", readInteger(segment, 18, 2))
    layer.set("tcp.len", segment.count - headerLength)
    if flags & 16 != 0 { layer.set("tcp.ack_raw", readInteger(segment, 8, 4)) }
    parseOptions(Array(segment[20..<headerLength]), layer)
    layer.remaining = Array(segment.dropFirst(headerLength))
    return layer
}
