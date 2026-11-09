import Foundation

enum Method: Int, CaseIterable, Hashable {
    case plain, dictionary, rle, delta, deltaLength
    var name: String { ["PLAIN", "DICTIONARY", "RLE", "DELTA_BINARY_PACKED", "DELTA_LENGTH_BYTE_ARRAY"][rawValue] }
    init(name: String) { self = Self.allCases.first { $0.name == name }! }
}
func candidates(_ type: ColumnType) -> [Method] {
    switch type { case .int, .date: return [.plain, .dictionary, .delta]; case .string: return [.plain, .dictionary, .deltaLength]; case .bool: return [.plain, .rle] }
}
func bits(_ value: Int) -> Int { Int.bitWidth - value.leadingZeroBitCount }
func deltaEncode(_ values: [Int]) -> [UInt8] {
    var output = uleb(128) + uleb(4) + uleb(values.count) + zigzag(values.first ?? 0)
    let deltas = values.indices.dropFirst().map { values[$0] - values[$0 - 1] }
    for start in stride(from: 0, to: deltas.count, by: 128) {
        let block = Array(deltas[start..<min(start + 128, deltas.count)]), minimum = deltas[start..<min(start + 128, deltas.count)].min()!
        output += zigzag(minimum)
        let miniblocks = stride(from: 0, to: 128, by: 32).map { offset in
            offset >= block.count ? [] : block[offset..<min(offset + 32, block.count)].map { $0 - minimum }
        }
        let widths = miniblocks.map { bits($0.max() ?? 0) }
        output += widths.map(UInt8.init)
        for (miniblock, width) in zip(miniblocks, widths) where !miniblock.isEmpty {
            output += pack(miniblock + Array(repeating: 0, count: 32 - miniblock.count), width: width)
        }
    }
    return output
}
func deltaDecode(_ reader: Reader) -> [Int] {
    let block = reader.uleb(), miniblocks = reader.uleb(), count = reader.uleb(), first = reader.zigzag()
    var values = count == 0 ? [] : [first]
    while values.count < count {
        let minimum = reader.zigzag(), widths = (0..<miniblocks).map { _ in reader.byte() }
        for width in widths {
            if values.count == count { break }
            let differences = unpack(reader, width: width, count: block / miniblocks)
            for difference in differences.prefix(min(block / miniblocks, count - values.count)) { values.append(values.last! + minimum + difference) }
        }
    }
    return values
}
func encodeValues(_ type: ColumnType, method: Method, values: [Value], dictionary: [Value] = []) -> [UInt8] {
    switch method {
    case .plain:
        switch type {
        case .int, .date: return values.flatMap { littleEndian($0.intValue) }
        case .string: return values.flatMap { littleEndian($0.stringValue.utf8.count) + Array($0.stringValue.utf8) }
        case .bool:
            return pack(values.map { $0.boolValue ? 1 : 0 } + Array(repeating: 0, count: (8 - values.count % 8) % 8), width: 1)
        }
    case .dictionary:
        let ranks = Dictionary(uniqueKeysWithValues: dictionary.enumerated().map { ($0.element, $0.offset) }), width = bits(dictionary.count - 1)
        return [UInt8(width)] + hybridEncode(values.map { ranks[$0]! }, width: width)
    case .rle:
        let encoded = hybridEncode(values.map { $0.boolValue ? 1 : 0 }, width: 1)
        return littleEndian(encoded.count) + encoded
    case .delta: return deltaEncode(values.map(\.intValue))
    case .deltaLength: return deltaEncode(values.map { $0.stringValue.utf8.count }) + values.flatMap { Array($0.stringValue.utf8) }
    }
}
func decodeValues(_ reader: Reader, type: ColumnType, method: Method, count: Int, dictionary: [Value] = []) -> [Value] {
    switch method {
    case .plain:
        switch type {
        case .int, .date: return (0..<count).map { _ in .integer(reader.integer(signed: true)) }
        case .string: return (0..<count).map { _ in .string(String(bytes: reader.read(reader.integer()), encoding: .ascii)!) }
        case .bool: return unpack(reader, width: 1, count: (count + 7) / 8 * 8).prefix(count).map { .boolean($0 != 0) }
        }
    case .dictionary: return hybridDecode(reader, width: reader.byte(), count: count).map { dictionary[$0] }
    case .rle:
        let encoded = Reader(reader.read(reader.integer()))
        return hybridDecode(encoded, width: 1, count: count).map { .boolean($0 != 0) }
    case .delta: return deltaDecode(reader).map(Value.integer)
    case .deltaLength: return deltaDecode(reader).map { .string(String(bytes: reader.read($0), encoding: .ascii)!) }
    }
}
struct Bounds {
    let low: Value
    let high: Value
}
func encodeStatistics(_ type: ColumnType, _ bounds: Bounds?) -> [UInt8] {
    guard let bounds else { return [0] }
    var output: [UInt8] = [1]
    for value in [bounds.low, bounds.high] {
        switch type {
        case .int, .date: output += zigzag(value.intValue)
        case .string: output += uleb(value.stringValue.utf8.count) + Array(value.stringValue.utf8)
        case .bool: output.append(value.boolValue ? 1 : 0)
        }
    }
    return output
}
func decodeStatistics(_ reader: Reader, type: ColumnType) -> Bounds? {
    if reader.byte() == 0 { return nil }
    let values: [Value] = (0..<2).map { _ in
        switch type {
        case .int, .date: return .integer(reader.zigzag())
        case .string: return .string(String(bytes: reader.read(reader.uleb()), encoding: .ascii)!)
        case .bool: return .boolean(reader.byte() != 0)
        }
    }
    return Bounds(low: values[0], high: values[1])
}
