import Foundation

final class Reader {
    let data: [UInt8]
    var position: Int
    init(_ data: [UInt8], position: Int = 0) { self.data = data; self.position = position }
    func read(_ count: Int) -> [UInt8] { defer { position += count }; return Array(data[position..<(position + count)]) }
    func byte() -> Int { defer { position += 1 }; return Int(data[position]) }
    func uleb() -> Int {
        var value = 0, shift = 0
        while true { let b = byte(); value |= (b & 127) << shift; if b < 128 { return value }; shift += 7 }
    }
    func zigzag() -> Int { let value = uleb(); return value % 2 == 0 ? value / 2 : -(value + 1) / 2 }
    func integer(signed: Bool = false) -> Int {
        let value = read(4).enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
        return signed && value >= (1 << 31) ? value - (1 << 32) : value
    }
}
func uleb(_ value: Int) -> [UInt8] {
    var remaining = value, bytes: [UInt8] = []
    while remaining >= 128 { bytes.append(UInt8(remaining % 128 + 128)); remaining /= 128 }
    bytes.append(UInt8(remaining)); return bytes
}
func zigzag(_ value: Int) -> [UInt8] { uleb(value >= 0 ? 2 * value : -2 * value - 1) }
func littleEndian(_ value: Int, count: Int = 4) -> [UInt8] {
    let value = value < 0 ? value + (1 << 32) : value
    return (0..<count).map { UInt8((value >> (8 * $0)) & 255) }
}
func pack(_ values: [Int], width: Int) -> [UInt8] {
    var output: [UInt8] = [], buffer = 0, occupied = 0
    for value in values {
        buffer |= value << occupied; occupied += width
        while occupied >= 8 { output.append(UInt8(buffer & 255)); buffer >>= 8; occupied -= 8 }
    }
    return output
}
func unpack(_ reader: Reader, width: Int, count: Int) -> [Int] {
    var values: [Int] = [], buffer = 0, occupied = 0
    let mask = (1 << width) - 1
    for _ in 0..<count {
        while occupied < width { buffer |= reader.byte() << occupied; occupied += 8 }
        values.append(buffer & mask); buffer >>= width; occupied -= width
    }
    return values
}
func adler32(_ bytes: [UInt8]) -> Int {
    var a = 1, b = 0
    for byte in bytes { a = (a + Int(byte)) % 65521; b = (b + a) % 65521 }
    return b * 65536 + a
}
func hybridEncode(_ values: [Int], width: Int) -> [UInt8] {
    var runs = Array(repeating: 1, count: values.count)
    for index in values.indices.reversed() where index + 1 < values.count && values[index] == values[index + 1] { runs[index] += runs[index + 1] }
    var bytes: [UInt8] = [], index = 0
    while index < values.count {
        if runs[index] >= 8 {
            bytes += uleb(2 * runs[index]) + littleEndian(values[index], count: (width + 7) / 8)
            index += runs[index]
        } else {
            var end = index, groups = 0
            repeat { end += 8; groups += 1 } while end < values.count && groups < 63 && runs[end] < 8
            let block = Array(values[index..<min(end, values.count)]) + Array(repeating: 0, count: max(0, end - values.count))
            bytes += uleb(2 * groups + 1) + pack(block, width: width)
            index = end
        }
    }
    return bytes
}
func hybridDecode(_ reader: Reader, width: Int, count: Int) -> [Int] {
    var values: [Int] = []
    while values.count < count {
        let header = reader.uleb()
        if header % 2 == 0 {
            let value = reader.read((width + 7) / 8).enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
            values += Array(repeating: value, count: header / 2)
        } else { values += unpack(reader, width: width, count: (header - 1) / 2 * 8) }
    }
    return Array(values.prefix(count))
}
