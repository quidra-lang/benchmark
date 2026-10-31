import Foundation

func put(_ band: inout [Character], _ position: Double, _ symbol: Character) { band[Int(min(60, max(0, position)))] = symbol }
func variableBand(_ limits: Limits, _ value: Double, _ signalled: Bool) -> String {
    var band = Array(repeating: Character("."), count: 61)
    func position(_ value: Double) -> Double { floor(60 * ((value - limits.lcl) / (limits.ucl - limits.lcl)) + 0.5) }
    put(&band, 0, ":"); put(&band, 60, ":"); put(&band, position(limits.cl), "|"); put(&band, position(value), signalled ? "*" : "o")
    return String(band)
}
func cusumBand(_ upper: Double, _ lower: Double, _ threshold: Double, _ highSignal: Bool, _ lowSignal: Bool) -> String {
    var band = Array(repeating: Character("."), count: 61)
    put(&band, 0, ":"); put(&band, 60, ":"); put(&band, 30, "|")
    if lower > 0 { put(&band, 30 - min(30, floor(30 * (lower / threshold) + 0.5)), lowSignal ? "*" : "-") }
    if upper > 0 { put(&band, 30 + min(30, floor(30 * (upper / threshold) + 0.5)), highSignal ? "*" : "+") }
    return String(band)
}
func smoothBand(_ width: Double, _ rowWidth: Double, _ value: Double, _ center: Double, _ signalled: Bool) -> String {
    var band = Array(repeating: Character("."), count: 61)
    let edge = min(30, floor(30 * (rowWidth / width) + 0.5))
    put(&band, 30, "|"); put(&band, 30 - edge, ":"); put(&band, 30 + edge, ":")
    put(&band, 30 + floor(30 * ((value - center) / width) + 0.5), signalled ? "*" : "o")
    return String(band)
}
func standardBand(_ z: Double, _ okay: Bool) -> String {
    var band = Array(repeating: Character("."), count: 61)
    put(&band, 0, ":"); put(&band, 60, ":"); put(&band, 30, "|"); put(&band, 30 + floor(10 * z + 0.5), okay ? "o" : "*")
    return String(band)
}
