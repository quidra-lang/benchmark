let playfairAlphabet = Array("ABCDEFGHIKLMNOPQRSTUVWXYZ".utf8)

func normalizePlayfair(_ letters: [UInt8]) -> [UInt8] {
    letters.map { $0 == 74 ? 73 : $0 }
}

func playfairSquare(_ key: [UInt8]) -> [UInt8] {
    var seen = Array(repeating: false, count: 26)
    var square: [UInt8] = []
    for letter in normalizePlayfair(key) + playfairAlphabet {
        let value = Int(letter - 65)
        if !seen[value] {
            seen[value] = true
            square.append(letter)
        }
    }
    return square
}

func preparePlayfair(_ letters: [UInt8]) -> [UInt8] {
    let text = normalizePlayfair(letters)
    var pairs: [UInt8] = []
    var index = 0
    while index < text.count {
        let first = text[index]
        pairs.append(first)
        if index + 1 < text.count && text[index + 1] != first {
            pairs.append(text[index + 1])
            index += 2
        } else {
            pairs.append(first == 88 ? 81 : 88)
            index += 1
        }
    }
    return pairs
}

func isValidPlayfairCiphertext(_ letters: [UInt8]) -> Bool {
    guard letters.count % 2 == 0 else { return false }
    let text = normalizePlayfair(letters)
    return stride(from: 0, to: text.count, by: 2).allSatisfy { text[$0] != text[$0 + 1] }
}

func playfair(_ letters: [UInt8], key: [UInt8], decrypt: Bool) -> [UInt8] {
    let square = playfairSquare(key)
    var positions = Array(repeating: 0, count: 26)
    for (index, letter) in square.enumerated() {
        positions[Int(letter - 65)] = index
    }
    let pairs = decrypt ? normalizePlayfair(letters) : preparePlayfair(letters)
    let step = decrypt ? 4 : 1
    var result: [UInt8] = []
    result.reserveCapacity(pairs.count)
    for index in stride(from: 0, to: pairs.count, by: 2) {
        let first = positions[Int(pairs[index] - 65)]
        let second = positions[Int(pairs[index + 1] - 65)]
        var rowA = first / 5
        var columnA = first % 5
        var rowB = second / 5
        var columnB = second % 5
        if rowA == rowB {
            columnA = (columnA + step) % 5
            columnB = (columnB + step) % 5
        } else if columnA == columnB {
            rowA = (rowA + step) % 5
            rowB = (rowB + step) % 5
        } else {
            swap(&columnA, &columnB)
        }
        result.append(square[rowA * 5 + columnA])
        result.append(square[rowB * 5 + columnB])
    }
    return result
}
