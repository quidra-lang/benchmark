import Foundation

final class Packet: FieldStore {
    let number: Int
    let time: Int
    let length: Int
    var data: [UInt8] = []
    var reason: String?
    var badDump = false
    var layers: [String] = []
    var remaining: [UInt8] = []
    var duplicateAck: (number: Int, count: Int)?

    init(_ number: Int, _ time: Int, _ length: Int) {
        self.number = number
        self.time = time
        self.length = length
    }
}

func readLines(_ path: String) throws -> [String] {
    let text = try String(contentsOfFile: path, encoding: .ascii)
    return text.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
}

func lowerHex(_ character: UInt8) -> Bool {
    (48...57).contains(character) || (97...102).contains(character)
}

func loadDump(_ packet: Packet, _ lines: [(Int, String)]) {
    var bytes: [UInt8] = []
    for (number, line) in lines {
        let characters = Array(line.utf8)
        var valid = characters.count >= 8
        if valid {
            valid = characters.prefix(4).allSatisfy(lowerHex) && characters[4] == 32 && characters[5] == 32
        }
        let fields = valid ? String(decoding: characters.dropFirst(6), as: UTF8.self)
            .split(separator: " ", omittingEmptySubsequences: false).map(String.init) : []
        valid = valid && (1...16).contains(fields.count)
            && fields.allSatisfy { $0.utf8.count == 2 && $0.utf8.allSatisfy(lowerHex) }
        if !valid {
            packet.reason = "dump: bad line \(number)"
            packet.badDump = true
            return
        }
        let offset = Int(String(decoding: characters.prefix(4), as: UTF8.self), radix: 16)!
        if offset != bytes.count {
            packet.reason = "dump: offset mismatch at line \(number)"
            packet.badDump = true
            return
        }
        bytes += fields.map { UInt8($0, radix: 16)! }
    }
    if bytes.count != packet.length {
        packet.reason = "dump: length mismatch (header \(packet.length), data \(bytes.count))"
        packet.badDump = true
    } else {
        packet.data = bytes
    }
}

func readCapture(_ path: String) throws -> [Packet] {
    var packets: [Packet] = []
    var dataLines: [[(Int, String)]] = []
    for (index, line) in try readLines(path).enumerated() {
        if line.hasPrefix("PACKET ") {
            let fields = line.split(separator: " ").dropFirst().map { Int($0)! }
            packets.append(Packet(fields[0], fields[1], fields[2]))
            dataLines.append([])
        } else if !line.isEmpty {
            dataLines[dataLines.count - 1].append((index + 1, line))
        }
    }
    for (packet, lines) in zip(packets, dataLines) { loadDump(packet, lines) }
    return packets
}

func hexDumpLines(_ data: [UInt8]) -> [String] {
    stride(from: 0, to: data.count, by: 16).map { offset in
        let piece = data[offset..<min(data.count, offset + 16)]
        let hex = piece.map { String(format: "%02x", Int($0)) }.joined(separator: " ")
        let padding = String(repeating: " ", count: 47 - hex.count)
        let text = String(piece.map { byte -> Character in
            (32...126).contains(byte) ? Character(UnicodeScalar(Int(byte))!) : "."
        })
        return String(format: "%04x", offset) + "  " + hex + padding + "  |" + text + "|"
    }
}
