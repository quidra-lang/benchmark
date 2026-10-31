func gcd(_ first: Int, _ second: Int) -> Int {
    var a = first, b = second
    while b != 0 { let remainder = a % b; a = b; b = remainder }
    return a
}
func decimal(_ numerator: Int, _ denominator: Int, _ places: Int) -> String {
    if denominator == 0 { return "-" }
    let scale = (0..<places).reduce(1) { value, _ in value * 10 }
    let value = (2 * numerator * scale + denominator) / (2 * denominator)
    let digits = String(value % scale)
    return "\(value / scale)." + String(repeating: "0", count: places - digits.count) + digits
}
func fraction(_ numerator: Int, _ denominator: Int) -> String { if denominator == 0 { return "-" }; let divisor = gcd(numerator, denominator); return "\(numerator / divisor)/\(denominator / divisor)" }
func percentile(_ times: [Int], _ q: Int) -> Int { times[(q * times.count + 99) / 100 - 1] }
func histogram(_ times: [Int], _ width: Int) -> [String] {
    let first = times[0] / width
    var counts = Array(repeating: 0, count: times.last! / width - first + 1)
    for time in times { counts[time / width - first] += 1 }
    let maximum = counts.max()!
    return counts.enumerated().map { index, count in
        let low = (first + index) * width, stars = (80 * count + maximum) / (2 * maximum)
        return "  \(low)-\(low + width - 1) \(count)" + (stars == 0 ? "" : " " + String(repeating: "*", count: stars))
    }
}
