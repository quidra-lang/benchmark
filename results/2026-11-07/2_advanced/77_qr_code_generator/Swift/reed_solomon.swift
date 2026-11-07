import Foundation

struct Correction {
    let syndromes: [Int]
    let corrected: [Int]?
    let positions: [Int]
}

final class ReedSolomon {
    var exp = Array(repeating: 1, count: 255)
    var log = Array(repeating: 0, count: 256)
    var generators: [Int: [Int]] = [:]

    init() {
        for exponent in 1..<255 {
            let doubled = exp[exponent - 1] * 2
            exp[exponent] = doubled >= 256 ? doubled ^ 0x11d : doubled
        }
        for (exponent, element) in exp.enumerated() { log[element] = exponent }
    }

    func multiply(_ a: Int, _ b: Int) -> Int { a == 0 || b == 0 ? 0 : exp[(log[a] + log[b]) % 255] }
    func divide(_ a: Int, _ b: Int) -> Int { a == 0 ? 0 : exp[(log[a] - log[b] + 255) % 255] }

    func generator(_ degree: Int) -> [Int] {
        if let cached = generators[degree] { return cached }
        var coefficients = [1]
        for exponent in 0..<degree {
            var product = Array(repeating: 0, count: coefficients.count + 1)
            for (index, coefficient) in coefficients.enumerated() {
                product[index] ^= coefficient
                product[index + 1] ^= multiply(coefficient, exp[exponent])
            }
            coefficients = product
        }
        generators[degree] = coefficients
        return coefficients
    }

    func parity(_ data: [Int], degree: Int) -> [Int] {
        let polynomial = generator(degree)
        var remainder = data + Array(repeating: 0, count: degree)
        for index in data.indices {
            let leading = remainder[index]
            if leading != 0 {
                for (offset, coefficient) in polynomial.enumerated() { remainder[index + offset] ^= multiply(leading, coefficient) }
            }
        }
        return Array(remainder.suffix(degree))
    }

    func syndromes(_ words: [Int], degree: Int) -> [Int] {
        (0..<degree).map { exponent in words.reduce(0) { multiply($0, exp[exponent]) ^ $1 } }
    }

    func evaluate(_ coefficients: [Int], at argument: Int) -> Int {
        coefficients.reversed().reduce(0) { multiply($0, argument) ^ $1 }
    }

    func correct(_ received: [Int], degree: Int) -> Correction {
        let original = syndromes(received, degree: degree)
        if original.allSatisfy({ $0 == 0 }) { return Correction(syndromes: original, corrected: received, positions: []) }
        func failed() -> Correction { Correction(syndromes: original, corrected: nil, positions: []) }
        var locator = [1] + Array(repeating: 0, count: degree), previous = locator
        var length = 0, shift = 1, beta = 1
        for step in 0..<degree {
            var discrepancy = original[step]
            for index in 1..<(length + 1) { discrepancy ^= multiply(locator[index], original[step - index]) }
            if discrepancy == 0 { shift += 1; continue }
            let saved = locator, multiplier = divide(discrepancy, beta)
            for index in 0..<(degree + 1 - shift) { locator[index + shift] ^= multiply(multiplier, previous[index]) }
            if 2 * length <= step {
                length = step + 1 - length
                previous = saved
                beta = discrepancy
                shift = 1
            } else { shift += 1 }
        }
        if length > degree / 2 { return failed() }
        locator = Array(locator.prefix(length + 1))
        let count = received.count
        var positions: [Int] = []
        for index in received.indices {
            let inverse = exp[(255 - (count - 1 - index)) % 255]
            if evaluate(locator, at: inverse) == 0 { positions.append(index) }
        }
        if positions.count != length { return failed() }
        var omega = Array(repeating: 0, count: degree)
        for (index, syndrome) in original.enumerated() {
            for offset in 0..<(min(length, degree - 1 - index) + 1) { omega[index + offset] ^= multiply(syndrome, locator[offset]) }
        }
        var derivative = Array(repeating: 0, count: length)
        for exponent in stride(from: 1, through: length, by: 2) { derivative[exponent - 1] = locator[exponent] }
        var corrected = received
        for index in positions {
            let location = exp[(count - 1 - index) % 255], inverse = exp[(255 - (count - 1 - index)) % 255]
            let denominator = evaluate(derivative, at: inverse)
            if denominator == 0 { return failed() }
            corrected[index] ^= multiply(location, divide(evaluate(omega, at: inverse), denominator))
        }
        if syndromes(corrected, degree: degree).contains(where: { $0 != 0 }) { return failed() }
        return Correction(syndromes: original, corrected: corrected, positions: positions.filter { corrected[$0] != received[$0] })
    }
}
