func letterCounts(_ letters: [UInt8]) -> [Int] {
    var counts = Array(repeating: 0, count: 26)
    for letter in letters { counts[Int(letter - 65)] += 1 }
    return counts
}

func coincidenceIndex(_ letters: [UInt8]) -> Int {
    guard letters.count >= 2 else { return 0 }
    let sum = letterCounts(letters).reduce(Int64(0)) { total, count in
        total + Int64(count) * Int64(count - 1)
    }
    return Int(100_000 * sum / Int64(letters.count * (letters.count - 1)))
}

func textColumns(_ letters: [UInt8], period: Int) -> [[UInt8]] {
    var columns = Array(repeating: [UInt8](), count: period)
    for (index, letter) in letters.enumerated() { columns[index % period].append(letter) }
    return columns
}

func columnIndices(_ letters: [UInt8], period: Int) -> [Int] {
    textColumns(letters, period: period).map(coincidenceIndex)
}

func greatestCommonDivisor(_ first: Int, _ second: Int) -> Int {
    var a = first
    var b = second
    while b != 0 { (a, b) = (b, a % b) }
    return a
}

struct RepeatedTrigram {
    let text: String
    let positions: [Int]
    let gaps: [Int]
    let gcd: Int

    init(text: String, positions: [Int]) {
        self.text = text
        self.positions = positions
        gaps = zip(positions, positions.dropFirst()).map { $1 - $0 }
        gcd = gaps.reduce(0, greatestCommonDivisor)
    }
}

func repeatedTrigrams(_ letters: [UInt8]) -> [RepeatedTrigram] {
    guard letters.count >= 3 else { return [] }
    var positions: [String: [Int]] = [:]
    for index in 0..<(letters.count - 2) {
        let trigram = asciiString(Array(letters[index..<(index + 3)]))
        positions[trigram, default: []].append(index + 1)
    }
    return positions.keys.sorted().compactMap { trigram in
        let found = positions[trigram]!
        return found.count >= 2 ? RepeatedTrigram(text: trigram, positions: found) : nil
    }
}

func percentage(_ count: Int, total: Int) -> String {
    let tenths = (2000 * count + total) / (2 * total)
    return "\(tenths / 10).\(tenths % 10)"
}

func pairCounts(_ letters: [UInt8], step: Int) -> [(text: String, count: Int)] {
    guard letters.count >= 2 else { return [] }
    var counts: [String: Int] = [:]
    for index in stride(from: 0, to: letters.count - 1, by: step) {
        let pair = asciiString(Array(letters[index..<(index + 2)]))
        counts[pair, default: 0] += 1
    }
    return counts.map { (text: $0.key, count: $0.value) }.sorted {
        $0.count == $1.count ? $0.text < $1.text : $0.count > $1.count
    }
}
