import Foundation

func padded(_ value: String, _ width: Int, right: Bool = false) -> String { let spaces = String(repeating: " ", count: max(0, width - value.count)); return right ? value + spaces : spaces + value }
func decimal(_ numerator: Int, _ denominator: Int) -> String { let value = (2 * numerator * 10000 + denominator) / (2 * denominator), tail = String(value % 10000); return "\(value / 10000)." + String(repeating: "0", count: 4 - tail.count) + tail }
func percentage(_ numerator: Int, _ denominator: Int) -> String { if denominator == 0 { return "-" }; let value = (2 * numerator * 10000 + denominator) / (2 * denominator), tail = String(value % 100); return "\(value / 100)." + String(repeating: "0", count: 2 - tail.count) + tail }
func reducedFraction(_ numerator: Int, _ denominator: Int) -> String { var a = numerator, b = denominator; while b != 0 { let next = a % b; a = b; b = next }; return "\(numerator / a)/\(denominator / a)" }
func hexadecimal(_ value: Int) -> String { let text = String(value, radix: 16); return String(repeating: "0", count: 8 - text.count) + text }
func registerText(_ value: Int?) -> String { value.map { "r\($0)" } ?? "-" }
func cycleHeading(_ first: Int, _ last: Int) -> String { "cycle" + String(repeating: " ", count: 18) + (first...last).map { String($0 % 10) }.joined() }
func diagramRow(_ number: Int?, _ pc: Int, _ kind: String, _ characters: String, _ annotation: String) -> String { (number.map { padded(String($0), 6) } ?? "     -") + " " + hexadecimal(pc) + " " + padded(kind, 6, right: true) + " " + characters + annotation }
func joinParts(_ parts: [[String]]) -> [String] { var lines: [String] = []; for (i, part) in parts.enumerated() { if i > 0 { lines.append("") }; lines += part }; return lines }
func writeLines(_ name: String, _ lines: [String]) throws { try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true); try (lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) }
