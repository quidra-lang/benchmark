import Foundation

func isLetter(_ byte: UInt8) -> Bool {
    (65...90).contains(byte) || (97...122).contains(byte)
}

func uppercaseLetter(_ byte: UInt8) -> UInt8 {
    (97...122).contains(byte) ? byte - 32 : byte
}

func letterString(_ bytes: [UInt8]) -> [UInt8] {
    bytes.filter(isLetter).map(uppercaseLetter)
}

func letterString(_ text: String) -> [UInt8] {
    letterString(Array(text.utf8))
}

func asciiString(_ bytes: [UInt8]) -> String {
    String(decoding: bytes, as: UTF8.self)
}

struct Weights {
    let monograms: [Int]
    let bigrams: [[Int]]

    init(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        monograms = lines[1].split(separator: " ").map { Int($0)! }
        bigrams = lines[3..<29].map { line in
            line.split(separator: " ").map { Int($0)! }
        }
    }

    func monogramFitness(_ letters: [UInt8]) -> Int {
        letters.reduce(0) { $0 + monograms[Int($1 - 65)] }
    }

    func bigramFitness(_ letters: [UInt8]) -> Int {
        guard letters.count >= 2 else { return 0 }
        var total = 0
        for index in 1..<letters.count {
            total += bigrams[Int(letters[index - 1] - 65)][Int(letters[index] - 65)]
        }
        return total
    }
}
