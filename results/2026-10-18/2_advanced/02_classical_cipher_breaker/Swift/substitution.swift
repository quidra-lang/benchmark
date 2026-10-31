let affineMultipliers = [1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25]

func modulo(_ value: Int, _ modulus: Int = 26) -> Int {
    let remainder = value % modulus
    return remainder < 0 ? remainder + modulus : remainder
}

func replaceLetters(_ text: [UInt8], values: [Int]) -> [UInt8] {
    var result = text
    var index = 0
    for position in result.indices where isLetter(result[position]) {
        let base = result[position] <= 90 ? 65 : 97
        result[position] = UInt8(base + values[index])
        index += 1
    }
    return result
}

func caesar(_ text: [UInt8], shift: Int, decrypt: Bool) -> [UInt8] {
    let offset = decrypt ? -shift : shift
    let values = letterString(text).map { modulo(Int($0 - 65) + offset) }
    return replaceLetters(text, values: values)
}

func modularInverse(_ multiplier: Int) -> Int {
    (1...25).first { multiplier * $0 % 26 == 1 }!
}

func affine(_ text: [UInt8], multiplier: Int, offset: Int, decrypt: Bool) -> [UInt8] {
    let factor = decrypt ? modularInverse(multiplier) : multiplier
    let values = letterString(text).map { letter in
        let value = Int(letter - 65)
        return decrypt ? modulo(factor * (value - offset)) : modulo(factor * value + offset)
    }
    return replaceLetters(text, values: values)
}

func vigenere(_ text: [UInt8], key: [UInt8], decrypt: Bool) -> [UInt8] {
    let shifts = key.map { Int($0 - 65) }
    let direction = decrypt ? -1 : 1
    let values = letterString(text).enumerated().map { index, letter in
        modulo(Int(letter - 65) + direction * shifts[index % shifts.count])
    }
    return replaceLetters(text, values: values)
}

func autokey(_ text: [UInt8], key: [UInt8], decrypt: Bool) -> [UInt8] {
    let shifts = key.map { Int($0 - 65) }
    let input = letterString(text).map { Int($0 - 65) }
    var values: [Int] = []
    values.reserveCapacity(input.count)
    for (index, value) in input.enumerated() {
        let shift: Int
        if index < shifts.count {
            shift = shifts[index]
        } else {
            shift = decrypt ? values[index - shifts.count] : input[index - shifts.count]
        }
        values.append(modulo(value + (decrypt ? -shift : shift)))
    }
    return replaceLetters(text, values: values)
}
