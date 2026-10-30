import Foundation

let alphanumeric = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".utf8)
let alphanumericValues = Dictionary(uniqueKeysWithValues: alphanumeric.enumerated().map { ($0.element, $0.offset) })

func binary(_ value: Int, width: Int) -> String {
    let digits = String(value, radix: 2)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
}

struct BitWriter {
    var bits: [Int] = []
    mutating func write(_ value: Int, width: Int) {
        for shift in (0..<width).reversed() { bits.append((value >> shift) & 1) }
    }
}

struct BitReader {
    let bits: [Int]
    var position = 0
    var remaining: Int { bits.count - position }
    mutating func read(_ width: Int) -> Int {
        var value = 0
        for _ in 0..<width { value = (value << 1) | bits[position]; position += 1 }
        return value
    }
}

func fromCodewords(_ words: [Int]) -> [Int] {
    var writer = BitWriter()
    for word in words { writer.write(word, width: 8) }
    return writer.bits
}

func toCodewords(_ bits: [Int]) -> [Int] {
    var reader = BitReader(bits: bits), words: [Int] = []
    while reader.remaining >= 8 { words.append(reader.read(8)) }
    return words
}

func hexadecimal(_ words: [Int]) -> String { words.map { String(format: "%02x", $0) }.joined() }
