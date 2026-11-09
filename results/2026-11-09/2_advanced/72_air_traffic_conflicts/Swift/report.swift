import Foundation

func decimal(_ value: Double, _ digits: Int = 3) -> String {
    let scale = (0..<digits).reduce(1) { value, _ in value * 10 }, rounded = Int(floor(abs(value) * Double(scale) + 0.5))
    let sign = value < 0 && rounded != 0 ? "-" : "", whole = sign + String(rounded / scale)
    if digits == 0 { return whole }
    let fraction = String(rounded % scale)
    return whole + "." + String(repeating: "0", count: digits - fraction.count) + fraction
}
func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : String(value) }
func chart(_ rows: [String]) -> [String] { let border = "+" + String(repeating: "-", count: rows[0].count) + "+"; return [border] + rows.map { "|" + $0 + "|" } + [border] }
func writeLines(_ name: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}
