import Foundation

func fractionGCD(_ first: Int64, _ second: Int64) -> Int64 { var a = abs(first), b = abs(second); while b != 0 { let remainder = a % b; a = b; b = remainder }; return a }
struct Rational: Comparable {
    let numerator: Int64
    let denominator: Int64
    init(_ numerator: Int, _ denominator: Int = 1) { self.init(numerator: Int64(numerator), denominator: Int64(denominator)) }
    init(numerator: Int64, denominator: Int64) { let sign: Int64 = denominator < 0 ? -1 : 1, divisor = fractionGCD(numerator, denominator); self.numerator = numerator / divisor * sign; self.denominator = denominator / divisor * sign }
    static func + (_ first: Rational, _ second: Rational) -> Rational { Rational(numerator: first.numerator * second.denominator + second.numerator * first.denominator, denominator: first.denominator * second.denominator) }
    static func - (_ first: Rational, _ second: Rational) -> Rational { Rational(numerator: first.numerator * second.denominator - second.numerator * first.denominator, denominator: first.denominator * second.denominator) }
    static func * (_ first: Rational, _ second: Rational) -> Rational { Rational(numerator: first.numerator * second.numerator, denominator: first.denominator * second.denominator) }
    static func / (_ first: Rational, _ second: Rational) -> Rational { Rational(numerator: first.numerator * second.denominator, denominator: first.denominator * second.numerator) }
    static func < (_ first: Rational, _ second: Rational) -> Bool { first.numerator * second.denominator < second.numerator * first.denominator }
}
func parseRational(_ text: String) -> Rational { let fields = text.split(separator: "/"); return Rational(Int(fields[0])!, fields.count == 2 ? Int(fields[1])! : 1) }
func fraction(_ value: Rational) -> String { let numerator = abs(value.numerator), denominator = value.denominator, scaled = 10000 * numerator / denominator, sign = value.numerator < 0 ? "-" : "", decimalSign = scaled == 0 ? "" : sign, remainder = String(scaled % 10000); return "\(sign)\(numerator)/\(denominator)=\(decimalSign)\(scaled / 10000)." + String(repeating: "0", count: 4 - remainder.count) + remainder }
func percentage(_ count: Int, _ total: Int) -> String { let scaled = Int64(10000) * Int64(count) / Int64(total), remainder = String(scaled % 100); return "\(scaled / 100)." + (remainder.count == 1 ? "0" : "") + remainder + "%" }
func names<S: Sequence>(_ values: S) -> String where S.Element == String { let text = values.joined(separator: ","); return text.isEmpty ? "-" : text }
func writeOutputs(_ outputs: [(String, [String])]) throws { try FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true); for (name, lines) in outputs { try (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii) } }
