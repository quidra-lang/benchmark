import Foundation

struct CommandError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

enum Mode: String { case rne = "RNE", rna = "RNA", rtz = "RTZ", rup = "RUP", rdn = "RDN" }
enum Arithmetic: String {
    case add = "ADD", sub = "SUB", mul = "MUL", div = "DIV", sqrt = "SQRT", fma = "FMA"
    var arity: Int { self == .sqrt ? 1 : self == .fma ? 3 : 2 }
}

struct Flags: OptionSet, Sendable {
    let rawValue: Int
    static let invalid = Flags(rawValue: 1)
    static let divByZero = Flags(rawValue: 2)
    static let overflow = Flags(rawValue: 4)
    static let underflow = Flags(rawValue: 8)
    static let inexact = Flags(rawValue: 16)

    var text: String {
        let names: [(Flags, String)] = [
            (.invalid, "invalid"), (.divByZero, "divbyzero"), (.overflow, "overflow"),
            (.underflow, "underflow"), (.inexact, "inexact")
        ]
        let raised = names.filter { contains($0.0) }.map { $0.1 }
        return "flags=" + (raised.isEmpty ? "none" : raised.joined(separator: ","))
    }
}

struct Result {
    var pattern: Int
    var flags: Flags = []
}

struct Units {
    let integer: Int64
    let inexact: Bool
}

let integerTypes: [String: ClosedRange<Int64>] = [
    "I8": -128...127, "U8": 0...255, "I16": -32768...32767, "U16": 0...65535,
    "I32": -2147483648...2147483647, "U32": 0...4294967295
]

func parseMode(_ words: [String], at index: Int) throws -> Mode {
    if index == words.count { return .rne }
    guard let mode = Mode(rawValue: words[index]) else { throw CommandError("BAD MODE \(words[index])") }
    return mode
}

func padded(_ value: Int, radix: Int, width: Int) -> String {
    let text = String(value, radix: radix, uppercase: true)
    return String(repeating: "0", count: max(0, width - text.count)) + text
}

func bitLength(_ value: Int64) -> Int {
    var n = value, length = 0
    while n != 0 {
        n >>= 1
        length += 1
    }
    return length
}

func scaled(_ numerator: Int64, _ denominator: Int64, exponent: Int) -> (Int64, Int64) {
    exponent >= 0 ? (numerator << exponent, denominator) : (numerator, denominator << (-exponent))
}

func gcd(_ first: Int64, _ second: Int64) -> Int64 {
    var a = first, b = second
    while b != 0 { (a, b) = (b, a % b) }
    return a
}

func integerSqrt(_ value: Int64) -> Int64 {
    if value == 0 { return 0 }
    var root = Int64(1) << ((bitLength(value) + 1) / 2)
    while true {
        let next = (root + value / root) / 2
        if next >= root { return root }
        root = next
    }
}

struct Exact {
    let n: Int64
    let exponent: Int
    let denominator: Int64
    let negative: Bool

    init(_ n: Int64 = 0, exponent: Int = 0, denominator: Int64 = 1, negative: Bool = false) {
        self.n = n
        self.exponent = exponent
        self.denominator = denominator
        self.negative = negative
    }

    func negated() -> Exact { Exact(n, exponent: exponent, denominator: denominator, negative: !negative) }

    func log2Floor() -> Int {
        var t = bitLength(n) - bitLength(denominator) + exponent
        let (numerator, divisor) = scaled(n, denominator, exponent: exponent - t)
        if numerator < divisor { t -= 1 }
        return t
    }

    func fraction() -> String {
        if n == 0 { return "0" }
        var (numerator, divisor) = scaled(n, denominator, exponent: exponent)
        let factor = gcd(numerator, divisor)
        numerator /= factor
        divisor /= factor
        return (negative ? "-" : "") + String(numerator) + (divisor == 1 ? "" : "/\(divisor)")
    }

    func decimal(keepZeroSign: Bool = false) -> String {
        let (numerator, divisor) = scaled(n, denominator, exponent: exponent)
        var text = String(numerator / divisor)
        var remainder = numerator % divisor
        if remainder != 0 {
            text += "."
            while remainder != 0 {
                remainder *= 10
                text += String(remainder / divisor)
                remainder %= divisor
            }
        }
        return (negative && (n != 0 || keepZeroSign) ? "-" : "") + text
    }
}

func exactProduct(_ a: Exact, _ b: Exact) -> Exact {
    Exact(a.n * b.n, exponent: a.exponent + b.exponent,
          denominator: a.denominator * b.denominator, negative: a.negative != b.negative)
}

func exactSum(_ terms: [Exact], mode: Mode) -> Exact {
    let nonzero = terms.filter { $0.n != 0 }
    if nonzero.isEmpty {
        let sign = terms.allSatisfy { $0.negative == terms[0].negative } ? terms[0].negative : mode == .rdn
        return Exact(negative: sign)
    }
    let exponent = nonzero.map(\.exponent).min()!
    var numerator: Int64 = 0
    for term in nonzero {
        let aligned = term.n << (term.exponent - exponent)
        numerator += term.negative ? -aligned : aligned
    }
    let negative = numerator < 0 || numerator == 0 && mode == .rdn
    return Exact(abs(numerator), exponent: exponent, negative: negative)
}

func shouldIncrement(_ mode: Mode, negative: Bool, integer: Int64, inexact: Bool, halfway: Int64) -> Bool {
    if !inexact { return false }
    switch mode {
    case .rne: return halfway > 0 || halfway == 0 && integer % 2 != 0
    case .rna: return halfway >= 0
    case .rtz: return false
    case .rup: return !negative
    case .rdn: return negative
    }
}

func roundedUnits(_ value: Exact, exponent: Int, mode: Mode) -> Units {
    let (n, d) = scaled(value.n, value.denominator, exponent: value.exponent - exponent)
    var integer = n / d
    let remainder = n % d
    if shouldIncrement(mode, negative: value.negative, integer: integer, inexact: remainder != 0, halfway: 2 * remainder - d) {
        integer += 1
    }
    return Units(integer: integer, inexact: remainder != 0)
}

func roundedSqrtUnits(_ value: Exact, exponent: Int, mode: Mode) -> Units {
    let (n, d) = scaled(value.n, value.denominator, exponent: value.exponent - 2 * exponent)
    var integer = integerSqrt(n / d)
    let inexact = integer * integer * d != n
    let midpoint = 2 * integer + 1
    if shouldIncrement(mode, negative: false, integer: integer, inexact: inexact, halfway: 4 * n - d * midpoint * midpoint) {
        integer += 1
    }
    return Units(integer: integer, inexact: inexact)
}

struct Fields {
    let negative: Bool
    let exponent: Int
    let fraction: Int
    let q: Int
}

struct Format {
    let name: String
    let e: Int
    let m: Int
    var w: Int { 1 + e + m }
    var bias: Int { (1 << (e - 1)) - 1 }
    var emin: Int { 1 - bias }
    var emax: Int { bias }
    var hidden: Int { 1 << m }
    var exponentMask: Int { (1 << e) - 1 }
    var signBit: Int { 1 << (e + m) }
    var infinity: Int { exponentMask * hidden }
    var nan: Int { infinity + hidden / 2 }
    var maximum: Int { infinity - 1 }

    func fields(_ pattern: Int) -> Fields {
        let exponent = (pattern >> m) & exponentMask
        return Fields(negative: pattern & signBit != 0, exponent: exponent,
                      fraction: pattern & (hidden - 1), q: (exponent == 0 ? emin : exponent - bias) - m)
    }

    func isNaN(_ pattern: Int) -> Bool {
        let f = fields(pattern)
        return f.exponent == exponentMask && f.fraction != 0
    }
    func isSignaling(_ pattern: Int) -> Bool { isNaN(pattern) && fields(pattern).fraction < hidden / 2 }
    func isInfinity(_ pattern: Int) -> Bool { pattern & (signBit - 1) == infinity }
    func isZero(_ pattern: Int) -> Bool { pattern & (signBit - 1) == 0 }
    func isFinite(_ pattern: Int) -> Bool { fields(pattern).exponent != exponentMask }
    func zero(_ negative: Bool) -> Int { negative ? signBit : 0 }
    func inf(_ negative: Bool) -> Int { zero(negative) + infinity }
    func flip(_ pattern: Int) -> Int { pattern ^ signBit }

    func exact(_ pattern: Int) -> Exact {
        let f = fields(pattern)
        return Exact(Int64(f.exponent == 0 ? f.fraction : hidden + f.fraction), exponent: f.q, negative: f.negative)
    }

    func bits(_ pattern: Int) -> String {
        let f = fields(pattern)
        return "\(f.negative ? 1 : 0)|\(padded(f.exponent, radix: 2, width: e))|\(padded(f.fraction, radix: 2, width: m))"
    }

    func hex(_ pattern: Int) -> String { "0x" + padded(pattern, radix: 16, width: (w + 3) / 4) }

    func value(_ pattern: Int) -> String {
        if isNaN(pattern) { return "nan" }
        if isInfinity(pattern) { return fields(pattern).negative ? "-inf" : "inf" }
        return exact(pattern).decimal(keepZeroSign: true)
    }

    func patternText(_ pattern: Int) -> String { "\(bits(pattern)) \(hex(pattern)) \(value(pattern))" }
    func resultText(_ result: Result) -> String { "\(patternText(result.pattern)) \(result.flags.text)" }

    func overflow(negative: Bool, mode: Mode) -> Result {
        let toInfinity = mode == .rne || mode == .rna || mode == .rup && !negative || mode == .rdn && negative
        return Result(pattern: zero(negative) + (toInfinity ? infinity : maximum), flags: [.overflow, .inexact])
    }

    private func roundNonzero(negative: Bool, t: Int, mode: Mode, unitsAt: (Int) -> Units) -> Result {
        if t > emax { return overflow(negative: negative, mode: mode) }
        var exponent = max(t, emin) - m
        let units = unitsAt(exponent)
        var n = units.integer
        if n == 2 * Int64(hidden) {
            n = Int64(hidden)
            exponent += 1
        }
        if exponent > emax - m { return overflow(negative: negative, mode: mode) }
        let magnitude = n >= Int64(hidden) ? (exponent + m + bias) * hidden + Int(n) - hidden : Int(n)
        var flags: Flags = units.inexact ? .inexact : []
        if units.inexact && t < emin && (t < emin - 1 || unitsAt(t - m).integer < 2 * Int64(hidden)) {
            flags.formUnion(.underflow)
        }
        return Result(pattern: zero(negative) + magnitude, flags: flags)
    }

    func round(_ value: Exact, mode: Mode) -> Result {
        if value.n == 0 { return Result(pattern: zero(value.negative)) }
        return roundNonzero(negative: value.negative, t: value.log2Floor(), mode: mode) {
            roundedUnits(value, exponent: $0, mode: mode)
        }
    }

    func sqrt(_ value: Exact, mode: Mode) -> Result {
        let log = value.log2Floor()
        let t = log >= 0 ? log / 2 : -((-log + 1) / 2)
        return roundNonzero(negative: false, t: t, mode: mode) {
            roundedSqrtUnits(value, exponent: $0, mode: mode)
        }
    }
}

enum RealInput {
    case finite(Exact), infinity(Bool), nan

    var text: String {
        switch self {
        case let .finite(value): return value.fraction()
        case let .infinity(negative): return negative ? "-inf" : "inf"
        case .nan: return "nan"
        }
    }
}

func parseReal(_ word: String) throws -> RealInput {
    if word == "nan" { return .nan }
    if word == "inf" || word == "-inf" { return .infinity(word == "-inf") }
    if word.hasPrefix("0b") || word.hasPrefix("0x") { throw CommandError("BAD OPERAND \(word)") }
    let negative = word.hasPrefix("-")
    let body = negative ? String(word.dropFirst()) : word
    if body.contains("/") {
        let parts = body.split(separator: "/")
        let n = Int64(parts[0])!, d = Int64(parts[1])!
        if d == 0 { throw CommandError("BAD OPERAND \(word)") }
        return .finite(Exact(n, denominator: d, negative: negative))
    }
    let parts = body.split(separator: ".")
    let fraction = parts.count == 2 ? String(parts[1]) : ""
    var denominator: Int64 = 1
    for _ in fraction { denominator *= 10 }
    let n = Int64(String(parts[0]) + fraction)!
    return .finite(Exact(n, denominator: denominator, negative: negative))
}

func encoded(_ format: Format, _ input: RealInput, mode: Mode) -> Result {
    switch input {
    case .nan: return Result(pattern: format.nan)
    case let .infinity(negative): return Result(pattern: format.inf(negative))
    case let .finite(value): return format.round(value, mode: mode)
    }
}

func operand(_ format: Format, _ word: String) throws -> Int {
    if word.hasPrefix("0b") || word.hasPrefix("0x") {
        let bits = word.hasPrefix("0b")
        let width = bits ? format.w : (format.w + 3) / 4
        if word.utf8.count - 2 != width { throw CommandError("BAD OPERAND \(word)") }
        let pattern = Int(word.dropFirst(2), radix: bits ? 2 : 16)!
        if pattern >= (1 << format.w) { throw CommandError("BAD OPERAND \(word)") }
        return pattern
    }
    return encoded(format, try parseReal(word), mode: .rne).pattern
}

func operation(_ format: Format, _ requested: Arithmetic, _ arguments: [Int], mode: Mode) -> Result {
    var op = requested, inputs = arguments
    if op == .sub {
        inputs[1] = format.flip(inputs[1])
        op = .add
    }
    if inputs.contains(where: { format.isNaN($0) }) {
        return Result(pattern: format.nan, flags: inputs.contains(where: { format.isSignaling($0) }) ? .invalid : [])
    }
    let a = inputs[0]
    let negative = format.fields(a).negative
    let invalid = Result(pattern: format.nan, flags: .invalid)
    if op == .sqrt {
        if format.isZero(a) { return Result(pattern: a) }
        if negative { return invalid }
        if format.isInfinity(a) { return Result(pattern: a) }
        return format.sqrt(format.exact(a), mode: mode)
    }
    let b = inputs[1]
    let sigma = negative != format.fields(b).negative
    if op == .add {
        if format.isInfinity(a) && format.isInfinity(b) && sigma { return invalid }
        if format.isInfinity(a) { return Result(pattern: a) }
        if format.isInfinity(b) { return Result(pattern: b) }
        return format.round(exactSum([format.exact(a), format.exact(b)], mode: mode), mode: mode)
    }
    if op == .mul {
        if format.isInfinity(a) || format.isInfinity(b) {
            return format.isZero(a) || format.isZero(b) ? invalid : Result(pattern: format.inf(sigma))
        }
        if format.isZero(a) || format.isZero(b) { return Result(pattern: format.zero(sigma)) }
        return format.round(exactProduct(format.exact(a), format.exact(b)), mode: mode)
    }
    if op == .div {
        if format.isInfinity(a) { return format.isInfinity(b) ? invalid : Result(pattern: format.inf(sigma)) }
        if format.isInfinity(b) { return Result(pattern: format.zero(sigma)) }
        if format.isZero(b) { return format.isZero(a) ? invalid : Result(pattern: format.inf(sigma), flags: .divByZero) }
        if format.isZero(a) { return Result(pattern: format.zero(sigma)) }
        let x = format.exact(a), y = format.exact(b)
        let quotient = Exact(x.n * y.denominator, exponent: x.exponent - y.exponent,
                             denominator: x.denominator * y.n, negative: sigma)
        return format.round(quotient, mode: mode)
    }
    let c = inputs[2]
    if format.isInfinity(a) || format.isInfinity(b) {
        if format.isZero(a) || format.isZero(b) || format.isInfinity(c) && format.fields(c).negative != sigma { return invalid }
        return Result(pattern: format.inf(sigma))
    }
    if format.isInfinity(c) { return Result(pattern: c) }
    return format.round(exactSum([exactProduct(format.exact(a), format.exact(b)), format.exact(c)], mode: mode), mode: mode)
}

func nextUp(_ format: Format, _ pattern: Int) -> Int {
    if pattern == format.infinity { return pattern }
    if format.isZero(pattern) { return 1 }
    return pattern + (format.fields(pattern).negative ? -1 : 1)
}

func difference(_ format: Format, _ pattern: Int, _ exact: Exact) -> String {
    if !format.isFinite(pattern) { return format.value(pattern) }
    return exactSum([format.exact(pattern), exact.negated()], mode: .rne).fraction()
}

func relation(_ a: Int, _ b: Int) -> String { a < b ? "LT" : a > b ? "GT" : "EQ" }

final class Laboratory {
    var formats: [String: Format] = [
        "HALF": Format(name: "HALF", e: 5, m: 10),
        "E5M2": Format(name: "E5M2", e: 5, m: 2),
        "E4M3": Format(name: "E4M3", e: 4, m: 3)
    ]
    var output: [String] = []
    func emit(_ line: String) { output.append(line) }

    func format(_ name: String) throws -> Format {
        guard let format = formats[name] else { throw CommandError("UNKNOWN FORMAT \(name)") }
        return format
    }

    func summary(_ format: Format, mode: Mode, patterns: [Int], result: Result) {
        let exact = exactSum(patterns.map { format.exact($0) }, mode: mode)
        emit("RESULT \(format.resultText(result))")
        emit("EXACT \(exact.decimal())")
        emit("ROUNDED \(format.resultText(format.round(exact, mode: mode)))")
        emit("DIFF \(difference(format, result.pattern, exact))")
    }

    func summation(_ command: String, format: Format, mode: Mode, patterns: [Int]) throws {
        guard patterns.allSatisfy({ format.isFinite($0) }) else { throw CommandError("NOT FINITE") }
        emit("\(command) \(format.name) \(mode.rawValue) count=\(patterns.count)")
        var sum = patterns[0], compensation = 0
        var flags: Flags = []
        for i in 1..<patterns.count {
            if command == "SUM" {
                let added = operation(format, .add, [sum, patterns[i]], mode: mode)
                sum = added.pattern
                flags.formUnion(added.flags)
                emit("PARTIAL \(i + 1) \(format.resultText(added))")
            } else {
                let y = operation(format, .sub, [patterns[i], compensation], mode: mode)
                let t = operation(format, .add, [sum, y.pattern], mode: mode)
                let d = operation(format, .sub, [t.pattern, sum], mode: mode)
                let c = operation(format, .sub, [d.pattern, y.pattern], mode: mode)
                sum = t.pattern
                compensation = c.pattern
                let stepFlags = y.flags.union(t.flags).union(d.flags).union(c.flags)
                flags.formUnion(stepFlags)
                emit("KSTEP \(i + 1) sum=\(format.value(sum)) comp=\(format.value(compensation)) \(stepFlags.text)")
            }
        }
        summary(format, mode: mode, patterns: patterns, result: Result(pattern: sum, flags: flags))
    }

    func dot(_ format: Format, mode: Mode, a: [Int], b: [Int]) throws {
        guard a.count == b.count else { throw CommandError("LENGTH MISMATCH") }
        guard (a + b).allSatisfy({ format.isFinite($0) }) else { throw CommandError("NOT FINITE") }
        var naive = operation(format, .mul, [a[0], b[0]], mode: mode)
        var chained = naive
        for i in 1..<a.count {
            let product = operation(format, .mul, [a[i], b[i]], mode: mode)
            let added = operation(format, .add, [naive.pattern, product.pattern], mode: mode)
            naive = Result(pattern: added.pattern, flags: naive.flags.union(product.flags).union(added.flags))
            let fused = operation(format, .fma, [a[i], b[i], chained.pattern], mode: mode)
            chained = Result(pattern: fused.pattern, flags: chained.flags.union(fused.flags))
        }
        let terms = a.indices.map { exactProduct(format.exact(a[$0]), format.exact(b[$0])) }
        let exact = exactSum(terms, mode: mode)
        emit("DOT \(format.name) \(mode.rawValue) n=\(a.count)")
        emit("NAIVE \(format.resultText(naive))")
        emit("CHAINED \(format.resultText(chained))")
        emit("EXACT \(exact.decimal())")
        emit("FUSED \(format.resultText(format.round(exact, mode: mode)))")
        emit("DIFF naive=\(difference(format, naive.pattern, exact)) chained=\(difference(format, chained.pattern, exact))")
    }

    func table(_ format: Format) throws {
        if format.w > 8 { throw CommandError("TABLE TOO LARGE") }
        let count = format.infinity
        emit("TABLE \(format.name) count=\(count)")
        for pattern in 0..<count {
            let gap = pattern == count - 1 ? "-"
                : exactSum([format.exact(pattern + 1), format.exact(pattern).negated()], mode: .rne).decimal()
            emit("ENTRY \(pattern) \(format.patternText(pattern)) gap=\(gap)")
        }
        emit("MAX \(format.patternText(format.maximum))")
        emit("MINNORMAL \(format.patternText(format.hidden))")
        emit("MINSUBNORMAL \(format.patternText(1))")
        emit("EPSILON \(Exact(1, exponent: -format.m).decimal())")
        emit("PATTERNS finite=\(2 * count) infinite=2 nan=\(2 * (format.hidden - 1)) total=\(1 << format.w)")
    }

    func command(_ line: String) throws {
        let words = line.split(separator: " ").map(String.init)
        let command = words[0]
        if command == "FORMAT" {
            let name = words[1], e = Int(words[2])!, m = Int(words[3])!
            if formats[name] != nil { throw CommandError("FORMAT EXISTS \(name)") }
            guard (2...5).contains(e), (1...10).contains(m) else { throw CommandError("BAD FORMAT") }
            let format = Format(name: name, e: e, m: m)
            formats[name] = format
            emit("FORMAT \(name) e=\(e) m=\(m) bits=\(format.w) bias=\(format.bias) emin=\(format.emin) emax=\(format.emax)")
            return
        }
        let f = try format(words[1])
        if command == "ENCODE" {
            let value = try parseReal(words[2])
            let mode = try parseMode(words, at: 3)
            emit("ENCODE \(f.name) \(mode.rawValue) \(value.text) \(f.resultText(encoded(f, value, mode: mode)))")
        } else if command == "CONVERT" {
            let g = try format(words[2])
            let a = try operand(f, words[3])
            let mode = try parseMode(words, at: 4)
            let result: Result
            if f.isNaN(a) { result = Result(pattern: g.nan, flags: f.isSignaling(a) ? .invalid : []) }
            else if f.isInfinity(a) { result = Result(pattern: g.inf(f.fields(a).negative)) }
            else { result = g.round(f.exact(a), mode: mode) }
            emit("CONVERT \(f.name) \(g.name) \(mode.rawValue) \(g.resultText(result))")
        } else if command == "SUM" || command == "KAHAN" || command == "DOT" {
            let mode = try parseMode(words, at: 2)
            if command == "DOT" {
                let separator = words.firstIndex(of: "|")!
                let a = try words[3..<separator].map { try operand(f, $0) }
                let b = try words[(separator + 1)...].map { try operand(f, $0) }
                try dot(f, mode: mode, a: a, b: b)
            } else {
                let patterns = try words[3...].map { try operand(f, $0) }
                try summation(command, format: f, mode: mode, patterns: patterns)
            }
        } else if command == "TABLE" { try table(f) }
        else if let op = Arithmetic(rawValue: command) {
            let patterns = try words[2..<(2 + op.arity)].map { try operand(f, $0) }
            let mode = try parseMode(words, at: 2 + op.arity)
            emit("\(command) \(f.name) \(mode.rawValue) \(f.resultText(operation(f, op, patterns, mode: mode)))")
        } else {
            let a = try operand(f, words[2])
            let fields = f.fields(a)
            if command == "DECODE" {
                let classification = f.isNaN(a) ? (f.isSignaling(a) ? "snan" : "qnan")
                    : f.isInfinity(a) ? "infinity" : f.isZero(a) ? "zero" : fields.exponent == 0 ? "subnormal" : "normal"
                emit("DECODE \(f.name) \(f.bits(a)) \(f.hex(a)) \(classification) sign=\(fields.negative ? 1 : 0)")
                var line = "FIELDS exponent=\(fields.exponent) fraction=\(fields.fraction)"
                if f.isFinite(a) {
                    line += " unbiased=\(fields.q + f.m) significand=\(fields.exponent == 0 ? 0 : 1).\(padded(fields.fraction, radix: 2, width: f.m))"
                    emit(line)
                    emit("VALUE \(f.exact(a).fraction()) \(f.value(a))")
                } else {
                    if f.isNaN(a) { line += " payload=\(fields.fraction % (f.hidden / 2))" }
                    emit(line)
                }
            } else if command == "COMPARE" {
                let b = try operand(f, words[3])
                func key(_ pattern: Int) -> Int { f.fields(pattern).negative ? -(pattern - f.signBit) - 1 : pattern }
                let order = relation(key(a), key(b))
                let numeric = f.isNaN(a) || f.isNaN(b) ? "UN" : f.isZero(a) && f.isZero(b) ? "EQ" : order
                let flags: Flags = f.isSignaling(a) || f.isSignaling(b) ? .invalid : []
                emit("COMPARE \(f.name) \(f.hex(a)) \(f.hex(b)) \(numeric) total=\(order) \(flags.text)")
            } else if command == "TOINT" {
                guard let range = integerTypes[words[3]] else { throw CommandError("BAD TYPE \(words[3])") }
                let mode = try parseMode(words, at: 4)
                let prefix = "TOINT \(f.name) \(words[3]) \(mode.rawValue)"
                if !f.isFinite(a) { emit("\(prefix) invalid flags=invalid") }
                else {
                    let units = roundedUnits(f.exact(a), exponent: 0, mode: mode)
                    let integer = fields.negative ? -units.integer : units.integer
                    if !range.contains(integer) { emit("\(prefix) invalid flags=invalid") }
                    else {
                        let flags: Flags = units.inexact ? .inexact : []
                        emit("\(prefix) \(integer) \(flags.text)")
                    }
                }
            } else {
                let result: Result
                if f.isNaN(a) { result = Result(pattern: f.nan, flags: f.isSignaling(a) ? .invalid : []) }
                else if command == "NEXTUP" { result = Result(pattern: nextUp(f, a)) }
                else if command == "NEXTDOWN" { result = Result(pattern: f.flip(nextUp(f, f.flip(a)))) }
                else {
                    let pattern = f.isInfinity(a) ? f.infinity : f.round(Exact(1, exponent: fields.q), mode: .rne).pattern
                    result = Result(pattern: pattern)
                }
                emit("\(command) \(f.name) \(f.resultText(result))")
            }
        }
    }
}

let commandCount = Int(readLine()!)!
let lab = Laboratory()
for _ in 0..<commandCount {
    do {
        try lab.command(readLine()!)
    } catch let error as CommandError {
        lab.emit("ERROR \(error.message)")
    } catch {
        fatalError("Unexpected error: \(error)")
    }
}
FileHandle.standardOutput.write(Data((lab.output.joined(separator: "\n") + "\n").utf8))
