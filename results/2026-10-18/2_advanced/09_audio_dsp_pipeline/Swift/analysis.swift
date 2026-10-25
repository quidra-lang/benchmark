func energy(_ samples: [Int]) -> Int { samples.reduce(0) { $0 + $1 * $1 } }
func integerSqrt(_ value: Int) -> Int {
    var low = 0, high = value + 1
    while high - low > 1 { let middle = (low + high) / 2; if middle <= value / middle { low = middle } else { high = middle } }
    return low
}
func rms(_ samples: [Int]) -> Int { integerSqrt(energy(samples) / samples.count) }
func zeroCrossings(_ samples: [Int]) -> Int { zip(samples, samples.dropFirst()).filter { ($0.0 < 0) != ($0.1 < 0) }.count }
func countClipped(_ samples: [Int]) -> Int { samples.filter { $0 == -32768 || $0 == 32767 }.count }
func crestFraction(_ samples: [Int]) -> String {
    let denominator = energy(samples)
    if denominator == 0 { return "none" }
    let numerator = peak(samples) * peak(samples) * samples.count
    var first = numerator, second = denominator
    while second != 0 { let remainder = first % second; first = second; second = remainder }
    return "\(numerator / first)/\(denominator / first)"
}
func autocorrelation(_ samples: [Int], _ lag: Int) -> Int { (0..<(samples.count - lag)).reduce(0) { $0 + samples[$1] * samples[$1 + lag] } }
func pitchLag(_ samples: [Int], _ low: Int, _ high: Int) -> Int? {
    var lag = low
    var value = autocorrelation(samples, low)
    if low < high { for candidate in (low + 1)...high { let correlation = autocorrelation(samples, candidate); if correlation > value { lag = candidate; value = correlation } } }
    return value > 0 ? lag : nil
}
