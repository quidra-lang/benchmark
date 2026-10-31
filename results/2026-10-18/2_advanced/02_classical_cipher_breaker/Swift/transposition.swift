func railNumber(_ position: Int, rails: Int) -> Int {
    let cycle = 2 * rails - 2
    let offset = position % cycle
    return min(offset, cycle - offset)
}

func railOrder(length: Int, rails: Int) -> [Int] {
    var positions = Array(repeating: [Int](), count: rails)
    for position in 0..<length {
        positions[railNumber(position, rails: rails)].append(position)
    }
    return positions.flatMap { $0 }
}

func railFence(_ text: [UInt8], rails: Int, decrypt: Bool) -> [UInt8] {
    let order = railOrder(length: text.count, rails: rails)
    if !decrypt { return order.map { text[$0] } }
    var result = text
    for (index, position) in order.enumerated() {
        result[position] = text[index]
    }
    return result
}

func columnOrder(_ key: [UInt8]) -> [Int] {
    key.indices.sorted {
        key[$0] == key[$1] ? $0 < $1 : key[$0] < key[$1]
    }
}

func columnRanks(_ key: [UInt8]) -> [Int] {
    var ranks = Array(repeating: 0, count: key.count)
    for (rank, column) in columnOrder(key).enumerated() {
        ranks[column] = rank + 1
    }
    return ranks
}

func rankString(_ key: [UInt8]) -> String {
    columnRanks(key).map(String.init).joined()
}

func columnar(_ text: [UInt8], key: [UInt8], decrypt: Bool) -> [UInt8] {
    let width = key.count
    let order = columnOrder(key)
    if !decrypt {
        return order.flatMap { column in
            stride(from: column, to: text.count, by: width).map { text[$0] }
        }
    }
    var columns = Array(repeating: [UInt8](), count: width)
    var start = 0
    for column in order {
        let length = text.count / width + (column < text.count % width ? 1 : 0)
        columns[column] = Array(text[start..<(start + length)])
        start += length
    }
    return text.indices.map { columns[$0 % width][$0 / width] }
}
