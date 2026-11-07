enum LZToken {
    case literal(UInt8), match(distance: Int, length: Int)
}

struct BytePrefix: Hashable {
    let first: UInt8
    let second: UInt8
    let third: UInt8
}

func tokenize(_ data: [UInt8], offsetBits: Int, lengthBits: Int) -> [LZToken] {
    let window = 1 << offsetBits
    let lookahead = (1 << lengthBits) + 2
    var prefixes: [BytePrefix: [Int]] = [:]
    var tokens: [LZToken] = []
    var position = 0
    func prefix(_ index: Int) -> BytePrefix { BytePrefix(first: data[index], second: data[index + 1], third: data[index + 2]) }
    while position < data.count {
        let limit = min(lookahead, data.count - position)
        var distance = 0
        var longest = 0
        if limit >= 3 {
            let key = prefix(position)
            let candidates = prefixes[key, default: []].filter { $0 >= position - window }
            prefixes[key] = candidates
            for start in candidates.reversed() {
                let candidateDistance = position - start
                var length = 3
                while length < limit && data[position + length] == data[position + length - candidateDistance] { length += 1 }
                if length > longest { distance = candidateDistance; longest = length }
                if longest == limit { break }
            }
        }
        let consumed: Int
        if longest >= 3 {
            tokens.append(.match(distance: distance, length: longest))
            consumed = longest
        } else {
            tokens.append(.literal(data[position]))
            consumed = 1
        }
        let end = min(position + consumed, max(0, data.count - 2))
        if position < end {
            for start in position..<end { prefixes[prefix(start), default: []].append(start) }
        }
        position += consumed
    }
    return tokens
}

func copyMatch(_ output: inout [UInt8], _ distance: Int, _ length: Int, _ originalSize: Int) throws {
    if distance > output.count { throw DecodeError(.badOffset, output.count) }
    if output.count + length > originalSize { throw DecodeError(.overrun, output.count) }
    for _ in 0..<length { output.append(output[output.count - distance]) }
}
