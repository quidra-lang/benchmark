import Foundation

func fractionText(_ value: Fraction) -> String {
    let numerator = abs(value.numerator)
    let scaled = 10000 * numerator / value.denominator
    let decimal = "\(scaled / 10000)." + String(repeating: "0", count: 4 - String(scaled % 10000).count) + String(scaled % 10000)
    let sign = value.numerator < 0 ? "-" : ""
    return "\(sign)\(numerator)/\(value.denominator)=\(scaled > 0 ? sign : "")\(decimal)"
}
func percentText(_ part: Int, _ whole: Int) -> String {
    let scaled = 10000 * part / whole
    return "\(scaled / 100)." + String(format: "%02d", scaled % 100) + "%"
}
func money(_ cents: Int) -> String { "\(cents / 100)." + String(format: "%02d", cents % 100) }
func itemsetText(_ items: [String]) -> String { items.joined(separator: "+") }
func ruleArrow(_ rule: Rule) -> String { "\(itemsetText(rule.antecedent)) -> \(itemsetText(rule.consequent))" }
func rulesCsv(_ rules: [Rule]) -> [String] {
    ["rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement"] + rules.map { rule in [String(rule.rank), itemsetText(rule.antecedent), itemsetText(rule.consequent), String(rule.count), fractionText(rule.support), fractionText(rule.confidence), fractionText(rule.lift), fractionText(rule.leverage), rule.conviction.map(fractionText) ?? "INF", fractionText(rule.improvement)].joined(separator: ",") }
}
func writeReport(_ name: String, _ lines: [String]) throws {
    try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/\(name)", atomically: true, encoding: .utf8)
}
