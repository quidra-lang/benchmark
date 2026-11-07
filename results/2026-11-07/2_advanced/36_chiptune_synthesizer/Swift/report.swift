func hexadecimal(_ value: Int, width: Int = 1) -> String {
    let text = String(value, radix: 16, uppercase: true)
    return String(repeating: "0", count: max(0, width - text.count)) + text
}

func hexLines(_ samples: [Int]) -> [String] {
    stride(from: 0, to: samples.count, by: 32).map { start in
        samples[start..<min(start + 32, samples.count)].map { hexadecimal($0, width: 2) }.joined()
    }
}

func adler32Text(_ values: [Int]) -> String {
    var a = 1
    var b = 0
    for value in values {
        a = (a + value) % 65521
        b = (b + a) % 65521
    }
    return hexadecimal((b << 16) | a, width: 8)
}

func integerSquareRoot(_ value: Int) -> Int {
    if value < 2 { return value }
    var current = value
    var following = (current + value / current) / 2
    while following < current {
        current = following
        following = (current + value / current) / 2
    }
    return current
}

func peak<C: Collection>(_ values: C, center: Int) -> Int where C.Element == Int {
    values.map { abs($0 - center) }.max() ?? 0
}

func rootMeanSquare<C: Collection>(_ values: C, center: Int) -> Int where C.Element == Int {
    guard !values.isEmpty else { return 0 }
    let squares = values.reduce(0) { total, value in total + (value - center) * (value - center) }
    return integerSquareRoot(squares / values.count)
}

func zeroCrossings(_ samples: [Int]) -> Int {
    zip(samples, samples.dropFirst()).filter { ($0.0 < 128) != ($0.1 < 128) }.count
}
