func floorDivide(_ value: Int, _ divisor: Int) -> Int { value / divisor - (value % divisor < 0 ? 1 : 0) }
func rdiv(_ numerator: Int, _ denominator: Int) -> Int { floorDivide(2 * numerator + denominator, 2 * denominator) }

func decimalDigits(_ value: Int, _ width: Int) -> String {
    let text = String(value)
    return String(repeating: "0", count: max(0, width - text.count)) + text
}

func two(_ value: Int) -> String {
    (value < 0 ? "-" : "") + String(abs(value) / 100) + "." + decimalDigits(abs(value) % 100, 2)
}

func four(_ value: Int) -> String { String(value / 10000) + "." + decimalDigits(value % 10000, 4) }

func fraction(_ numerator: Int, _ denominator: Int) -> String {
    var first = numerator
    var second = denominator
    while second != 0 { (first, second) = (second, first % second) }
    return "\(numerator / first)/\(denominator / first)"
}

func ratio(_ numerator: Int, _ denominator: Int) -> String {
    if denominator == 0 { return "\(numerator)/0 none" }
    return "\(numerator)/\(denominator) reduced=\(fraction(numerator, denominator)) percent=\(two(rdiv(10000 * numerator, denominator)))"
}

func maybeTwo(_ value: Int?) -> String { value.map(two) ?? "none" }
func missing(_ value: Int?) -> String { value.map(String.init) ?? "-" }
