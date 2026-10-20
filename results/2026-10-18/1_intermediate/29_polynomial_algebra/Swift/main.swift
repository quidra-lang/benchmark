struct CalculatorError: Error {
    let message: String
}

func check(_ condition: Bool, _ message: String) throws {
    if condition { throw CalculatorError(message: message) }
}

func integerGcd(_ first: Int64, _ second: Int64) -> Int64 {
    var a = abs(first), b = abs(second)
    while b != 0 { (a, b) = (b, a % b) }
    return a
}

struct Fraction: Comparable, CustomStringConvertible {
    let n: Int64
    let d: Int64

    init(_ numerator: Int64 = 0, _ denominator: Int64 = 1) {
        let sign: Int64 = denominator < 0 ? -1 : 1
        let divisor = integerGcd(numerator, denominator)
        n = sign * numerator / divisor
        d = sign * denominator / divisor
    }

    static let zero = Fraction()
    static let one = Fraction(1)
    static let two = Fraction(2)

    static func parse(_ word: String) throws -> Fraction {
        let parts = word.split(separator: "/")
        let denominator = parts.count == 1 ? 1 : Int64(parts[1])!
        try check(denominator == 0, "ZERO DENOMINATOR")
        return Fraction(Int64(parts[0])!, denominator)
    }

    static func + (a: Fraction, b: Fraction) -> Fraction { Fraction(a.n * b.d + b.n * a.d, a.d * b.d) }
    static func - (a: Fraction, b: Fraction) -> Fraction { Fraction(a.n * b.d - b.n * a.d, a.d * b.d) }
    static func * (a: Fraction, b: Fraction) -> Fraction { Fraction(a.n * b.n, a.d * b.d) }
    static func / (a: Fraction, b: Fraction) -> Fraction { Fraction(a.n * b.d, a.d * b.n) }
    static prefix func - (value: Fraction) -> Fraction { Fraction(-value.n, value.d) }
    static func < (a: Fraction, b: Fraction) -> Bool { a.n * b.d < b.n * a.d }
    static func == (a: Fraction, b: Fraction) -> Bool { a.n * b.d == b.n * a.d }
    var magnitude: Fraction { n < 0 ? -self : self }
    var sign: Int { n < 0 ? -1 : n > 0 ? 1 : 0 }
    var description: String { d == 1 ? String(n) : "\(n)/\(d)" }

    func power(_ exponent: Int) -> Fraction {
        var result = Fraction.one
        for _ in 0..<exponent { result = result * self }
        return result
    }
}

struct Polynomial {
    let coefficients: [Fraction]

    init(_ values: [Fraction] = []) {
        var trimmed = values
        while trimmed.last?.n == 0 { trimmed.removeLast() }
        coefficients = trimmed
    }

    static let unit = Polynomial([.one])
    static let x = Polynomial([.zero, .one])
    static func constant(_ value: Fraction) -> Polynomial { Polynomial([value]) }
    var degree: Int { coefficients.count - 1 }
    var isZero: Bool { coefficients.isEmpty }
    var leading: Fraction { coefficients.last! }
    var isOne: Bool { degree == 0 && leading == .one }

    func coefficient(_ index: Int) -> Fraction {
        index >= 0 && index < coefficients.count ? coefficients[index] : .zero
    }

    static func + (a: Polynomial, b: Polynomial) -> Polynomial {
        Polynomial((0..<max(a.coefficients.count, b.coefficients.count)).map { a.coefficient($0) + b.coefficient($0) })
    }

    static func - (a: Polynomial, b: Polynomial) -> Polynomial {
        Polynomial((0..<max(a.coefficients.count, b.coefficients.count)).map { a.coefficient($0) - b.coefficient($0) })
    }

    static prefix func - (value: Polynomial) -> Polynomial { Polynomial(value.coefficients.map { -$0 }) }
    func scale(_ scalar: Fraction) -> Polynomial { Polynomial(coefficients.map { $0 * scalar }) }
    func divideScalar(_ scalar: Fraction) -> Polynomial { Polynomial(coefficients.map { $0 / scalar }) }

    static func * (a: Polynomial, b: Polynomial) -> Polynomial {
        if a.isZero || b.isZero { return Polynomial() }
        var result = [Fraction](repeating: .zero, count: a.degree + b.degree + 1)
        for i in a.coefficients.indices {
            for j in b.coefficients.indices { result[i + j] = result[i + j] + a.coefficients[i] * b.coefficients[j] }
        }
        return Polynomial(result)
    }

    func power(_ exponent: Int) -> Polynomial {
        if exponent == 0 { return .unit }
        if isZero { return self }
        if degree == 0 && leading.d == 1 && abs(leading.n) == 1 {
            return .constant(leading.n < 0 && exponent % 2 == 1 ? Fraction(-1) : .one)
        }
        var result = Polynomial.unit
        for _ in 0..<exponent { result = result * self }
        return result
    }

    func divide(_ divisor: Polynomial) -> (quotient: Polynomial, remainder: Polynomial) {
        var remainder = coefficients
        var quotient = [Fraction](repeating: .zero, count: max(0, degree - divisor.degree + 1))
        while !remainder.isEmpty && remainder.count >= divisor.coefficients.count {
            let value = remainder.last! / divisor.leading
            let shift = remainder.count - divisor.coefficients.count
            quotient[shift] = value
            for j in divisor.coefficients.indices { remainder[shift + j] = remainder[shift + j] - value * divisor.coefficients[j] }
            while remainder.last?.n == 0 { remainder.removeLast() }
        }
        return (Polynomial(quotient), Polynomial(remainder))
    }

    func mod(_ divisor: Polynomial) -> Polynomial { divide(divisor).remainder }
    func monic() -> Polynomial { isZero ? self : divideScalar(leading) }

    func derivative(_ count: Int = 1) -> Polynomial {
        var result = self
        for _ in 0..<count {
            if result.isZero { break }
            result = Polynomial(result.coefficients.dropFirst().enumerated().map { index, value in Fraction(Int64(index + 1)) * value })
        }
        return result
    }

    func integral() -> Polynomial {
        Polynomial([.zero] + coefficients.enumerated().map { index, value in value / Fraction(Int64(index + 1)) })
    }

    func evaluate(_ value: Fraction) -> Fraction {
        var result = Fraction.zero
        for coefficient in coefficients.reversed() { result = result * value + coefficient }
        return result
    }

    func compose(_ other: Polynomial) -> Polynomial {
        var result = Polynomial()
        for coefficient in coefficients.reversed() { result = result * other + .constant(coefficient) }
        return result
    }

    func content() -> Fraction {
        var multiple: Int64 = 1, divisor: Int64 = 0
        for value in coefficients {
            multiple = multiple * value.d / integerGcd(multiple, value.d)
            divisor = integerGcd(divisor, value.n)
        }
        return Fraction(leading.n < 0 ? -divisor : divisor, multiple)
    }

    func primitive() -> Polynomial { divideScalar(content()) }

    func notation(_ variable: String = "x") -> String {
        var result = ""
        for i in coefficients.indices.reversed() {
            let value = coefficients[i]
            if value.n == 0 { continue }
            result += result.isEmpty ? (value.n < 0 ? "-" : "") : (value.n < 0 ? " - " : " + ")
            if i == 0 || value.magnitude != .one { result += value.magnitude.description }
            if i > 0 { result += variable + (i == 1 ? "" : "^\(i)") }
        }
        return result.isEmpty ? "0" : result
    }
}

func linear(_ constant: Fraction, _ slope: Fraction = .one) -> Polynomial { Polynomial([constant, slope]) }
func requireNonzero(_ a: Polynomial) throws { try check(a.isZero, "ZERO POLYNOMIAL") }
func productLimit(_ a: Polynomial, _ b: Polynomial) throws {
    try check(!a.isZero && !b.isZero && a.degree + b.degree > 30, "DEGREE LIMIT")
}
func compositionLimit(_ a: Polynomial, _ b: Polynomial) throws {
    try check(a.degree >= 1 && b.degree >= 1 && a.degree * b.degree > 30, "DEGREE LIMIT")
}

func polynomialGcd(_ first: Polynomial, _ second: Polynomial) -> Polynomial {
    var a = first, b = second
    while !b.isZero { (a, b) = (b, a.mod(b)) }
    return a.monic()
}

func extendedGcd(_ first: Polynomial, _ second: Polynomial) -> (Polynomial, Polynomial, Polynomial) {
    var a = first, b = second
    var s0 = Polynomial.unit, s1 = Polynomial(), t0 = Polynomial(), t1 = Polynomial.unit
    while !b.isZero {
        let (quotient, remainder) = a.divide(b)
        (a, b) = (b, remainder)
        (s0, s1) = (s1, s0 - quotient * s1)
        (t0, t1) = (t1, t0 - quotient * t1)
    }
    return a.isZero ? (a, s0, t0) : (a.monic(), s0.divideScalar(a.leading), t0.divideScalar(a.leading))
}

func divisors(_ number: Int64) -> [Int64] {
    var result: [Int64] = [], divisor: Int64 = 1
    while divisor * divisor <= number {
        if number % divisor == 0 {
            result.append(divisor)
            if divisor * divisor != number { result.append(number / divisor) }
        }
        divisor += 1
    }
    return result
}

struct Root {
    let value: Fraction
    let multiplicity: Int
}

func rationalRoots(_ a: Polynomial) -> (roots: [Root], remaining: Polynomial) {
    var remaining = a.primitive(), zeros = 0
    while remaining.coefficient(0).n == 0 {
        remaining = Polynomial(Array(remaining.coefficients.dropFirst()))
        zeros += 1
    }
    var candidates: [Fraction] = []
    let numerators = divisors(abs(remaining.coefficient(0).n)), denominators = divisors(remaining.leading.n)
    for numerator in numerators {
        for denominator in denominators where integerGcd(numerator, denominator) == 1 {
            let root = Fraction(numerator, denominator)
            candidates.append(root)
            candidates.append(-root)
        }
    }
    candidates.sort()
    var roots: [Root] = []
    for root in candidates {
        var multiplicity = 0
        let factor = linear(Fraction(-root.n), Fraction(root.d))
        while remaining.degree >= 1 && remaining.evaluate(root).n == 0 {
            remaining = remaining.divide(factor).quotient
            multiplicity += 1
        }
        if multiplicity > 0 { roots.append(Root(value: root, multiplicity: multiplicity)) }
    }
    if zeros > 0 { roots.append(Root(value: .zero, multiplicity: zeros)) }
    roots.sort { $0.value < $1.value }
    return (roots, remaining)
}

func squareFreePart(_ a: Polynomial) -> Polynomial {
    a.degree < 1 ? a : a.divide(polynomialGcd(a, a.derivative())).quotient
}

func sturmSequence(_ a: Polynomial) -> [Polynomial] {
    var previous = squareFreePart(a)
    var current = previous.derivative()
    var sequence = [previous]
    while !current.isZero {
        sequence.append(current)
        (previous, current) = (current, -previous.mod(current))
    }
    return sequence
}

enum Endpoint: Comparable, CustomStringConvertible {
    case negativeInfinity
    case finite(Fraction)
    case positiveInfinity

    static func parse(_ word: String) throws -> Endpoint {
        if word == "-inf" { return .negativeInfinity }
        if word == "inf" { return .positiveInfinity }
        return .finite(try Fraction.parse(word))
    }

    static func < (a: Endpoint, b: Endpoint) -> Bool {
        switch (a, b) {
        case (.negativeInfinity, .negativeInfinity), (.positiveInfinity, .positiveInfinity): return false
        case (.negativeInfinity, _), (_, .positiveInfinity): return true
        case (.positiveInfinity, _), (_, .negativeInfinity): return false
        case let (.finite(left), .finite(right)): return left < right
        }
    }

    var description: String {
        switch self {
        case .negativeInfinity: return "-inf"
        case .positiveInfinity: return "inf"
        case .finite(let value): return value.description
        }
    }
}

func signChanges(_ signs: [Int]) -> Int {
    var previous = 0, changes = 0
    for sign in signs where sign != 0 {
        if previous != 0 && previous != sign { changes += 1 }
        previous = sign
    }
    return changes
}

func variations(_ sequence: [Polynomial], _ endpoint: Endpoint) -> Int {
    signChanges(sequence.map { polynomial in
        switch endpoint {
        case .finite(let value): return polynomial.evaluate(value).sign
        case .positiveInfinity: return polynomial.leading.sign
        case .negativeInfinity: return polynomial.leading.sign * (polynomial.degree % 2 == 0 ? 1 : -1)
        }
    })
}

func isolate(_ a: Polynomial, _ precision: Int) -> [(Fraction, Fraction)] {
    let sequence = sturmSequence(a)
    let first = sequence[0]
    var maximum = Fraction.zero
    for i in 0..<first.degree { maximum = max(maximum, (first.coefficients[i] / first.leading).magnitude) }
    let bound = Fraction.one + maximum, width = Fraction(1, Int64(1) << precision)
    var intervals: [(Fraction, Fraction)] = []
    func count(_ left: Fraction, _ right: Fraction) -> Int {
        variations(sequence, .finite(left)) - variations(sequence, .finite(right))
    }
    func examine(_ lower: Fraction, _ upper: Fraction) {
        var left = lower, right = upper
        let roots = count(left, right)
        if roots >= 2 {
            let middle = (left + right) / .two
            examine(left, middle)
            examine(middle, right)
        } else if roots == 1 {
            while right - left > width {
                let middle = (left + right) / .two
                if count(left, middle) >= 1 { right = middle }
                else { left = middle }
            }
            intervals.append((left, right))
        }
    }
    examine(-bound, bound)
    return intervals
}

func resultant(_ first: Polynomial, _ second: Polynomial) -> Fraction {
    var a = first, b = second, result = Fraction.one
    while b.degree >= 1 {
        let remainder = a.mod(b)
        if remainder.isZero { return .zero }
        result = result * b.leading.power(a.degree - remainder.degree)
        if a.degree * b.degree % 2 == 1 { result = -result }
        (a, b) = (b, remainder)
    }
    return result * b.coefficient(0).power(a.degree)
}

func interpolate(_ values: [Fraction]) throws -> Polynomial {
    let xs = stride(from: 0, to: values.count, by: 2).map { values[$0] }
    var differences = stride(from: 1, to: values.count, by: 2).map { values[$0] }
    for j in 1..<xs.count {
        try check(xs[..<j].contains(xs[j]), "DUPLICATE X \(xs[j])")
    }
    for j in 1..<xs.count {
        for i in stride(from: xs.count - 1, through: j, by: -1) {
            differences[i] = (differences[i] - differences[i - 1]) / (xs[i] - xs[i - j])
        }
    }
    var result = Polynomial()
    for i in xs.indices.reversed() { result = result * linear(-xs[i]) + .constant(differences[i]) }
    return result
}

func special(_ kind: String, _ order: Int) throws -> Polynomial {
    let kinds: Set<String> = ["chebyshev", "chebyshev2", "legendre", "hermite", "laguerre"]
    try check(!kinds.contains(kind), "UNKNOWN KIND \(kind)")
    try check(order > 30, "DEGREE LIMIT")
    if order == 0 { return .unit }
    var previous = Polynomial.unit
    var current: Polynomial = kind == "laguerre" ? linear(.one, Fraction(-1))
        : kind == "chebyshev2" || kind == "hermite" ? Polynomial.x.scale(.two) : .x
    for j in 1..<order {
        let next: Polynomial
        if kind == "chebyshev" || kind == "chebyshev2" { next = Polynomial.x.scale(.two) * current - previous }
        else if kind == "hermite" { next = Polynomial.x.scale(.two) * current - previous.scale(Fraction(Int64(2 * j))) }
        else {
            let multiplier = kind == "legendre" ? Polynomial.x.scale(Fraction(Int64(2 * j + 1))) : linear(Fraction(Int64(2 * j + 1)), Fraction(-1))
            next = (multiplier * current - previous.scale(Fraction(Int64(j)))).scale(Fraction(1, Int64(j + 1)))
        }
        (previous, current) = (current, next)
    }
    return current
}

enum BinaryOperation { case add, subtract, multiply, divide, compose }
indirect enum Expression {
    case number(Fraction)
    case variable
    case reference(String, Int)
    case negate(Expression)
    case power(Expression, Int)
    case binary(BinaryOperation, Expression, Expression)
}

enum TokenKind: Equatable { case number, name, symbol(Character), end }
struct Token {
    let kind: TokenKind
    let word: String
    let position: Int
}

final class ExpressionParser {
    private let tokens: [Token]
    private var position = 0
    private var token: Token { tokens[position] }

    init(_ source: String) {
        let characters = Array(source)
        func digit(_ ch: Character) -> Bool { ch >= "0" && ch <= "9" }
        func uppercase(_ ch: Character) -> Bool { ch >= "A" && ch <= "Z" }
        var result: [Token] = [], i = 0
        while i < characters.count {
            if characters[i] == " " { i += 1; continue }
            let start = i, ch = characters[i]
            i += 1
            let kind: TokenKind
            if digit(ch) {
                kind = .number
                while i < characters.count && digit(characters[i]) { i += 1 }
            } else if uppercase(ch) {
                kind = .name
                while i < characters.count && (uppercase(characters[i]) || digit(characters[i])) { i += 1 }
            } else { kind = .symbol(ch) }
            result.append(Token(kind: kind, word: String(characters[start..<i]), position: start + 1))
        }
        result.append(Token(kind: .end, word: "", position: characters.count + 1))
        tokens = result
    }

    private func take(_ kind: TokenKind) -> Bool {
        if token.kind != kind { return false }
        position += 1
        return true
    }
    private func take(_ symbol: Character) -> Bool { take(.symbol(symbol)) }
    private func syntaxError() -> CalculatorError {
        CalculatorError(message: "SYNTAX AT " + (token.kind == .end ? "END" : String(token.position)))
    }
    private func expect(_ symbol: Character) throws {
        if !take(symbol) { throw syntaxError() }
    }

    func parse() throws -> Expression {
        let result = try expression()
        if token.kind != .end { throw syntaxError() }
        return result
    }

    private func expression() throws -> Expression {
        let negative = take("-")
        var result = try term()
        if negative { result = .negate(result) }
        while token.kind == .symbol("+") || token.kind == .symbol("-") {
            let operation: BinaryOperation = token.kind == .symbol("+") ? .add : .subtract
            position += 1
            result = .binary(operation, result, try term())
        }
        return result
    }

    private func term() throws -> Expression {
        var result = try factor()
        let starts: [TokenKind] = [.symbol("*"), .symbol("/"), .symbol("x"), .name, .symbol("(")]
        while starts.contains(token.kind) {
            var operation = BinaryOperation.multiply
            if token.kind == .symbol("*") || token.kind == .symbol("/") {
                if token.kind == .symbol("/") { operation = .divide }
                position += 1
            }
            result = .binary(operation, result, try factor())
        }
        return result
    }

    private func factor() throws -> Expression {
        var result = try primary()
        if take("^") {
            if token.kind != .number { throw syntaxError() }
            let exponent = Int(token.word)!
            position += 1
            result = .power(result, exponent)
        }
        return result
    }

    private func primary() throws -> Expression {
        let current = token
        if take(.number) { return .number(Fraction(Int64(current.word)!)) }
        if take("x") { return .variable }
        if take(.name) {
            var derivatives = 0
            while take("'") { derivatives += 1 }
            let reference = Expression.reference(current.word, derivatives)
            if !take("(") { return reference }
            let argument = try expression()
            try expect(")")
            return .binary(.compose, reference, argument)
        }
        if take("(") {
            let result = try expression()
            try expect(")")
            return result
        }
        throw syntaxError()
    }
}

let references: [String: [Int]] = [
    "PRINT": [1], "DELETE": [1], "DEGREE": [1], "ADD": [2, 3], "SUB": [2, 3], "MUL": [2, 3],
    "POW": [2], "DIV": [3, 4], "GCD": [2, 3], "XGCD": [4, 5], "LCM": [2, 3], "INVMOD": [2, 3],
    "CRT": [2, 3, 4, 5], "MODPOW": [2, 4], "DERIV": [2], "INTEG": [2], "AREA": [1],
    "TANGENT": [2], "TAYLOR": [1], "COMPOSE": [2, 3], "EVAL": [1], "ROOTS": [1], "FACTOR": [1],
    "SQFREE": [1], "DESCARTES": [1], "STURM": [1], "ISOLATE": [1], "RESULTANT": [1, 2],
    "DISCRIM": [1], "POWERSUM": [1]
]

final class Calculator {
    private var polynomials: [String: Polynomial] = [:]

    private func lookup(_ name: String) throws -> Polynomial {
        guard let value = polynomials[name] else { throw CalculatorError(message: "UNKNOWN \(name)") }
        return value
    }

    private func evaluate(_ expression: Expression) throws -> Polynomial {
        switch expression {
        case .number(let value): return .constant(value)
        case .variable: return .x
        case let .reference(name, count): return try lookup(name).derivative(count)
        case .negate(let operand): return -(try evaluate(operand))
        case let .power(operand, exponent):
            let value = try evaluate(operand)
            try check(!value.isZero && value.degree * exponent > 30, "DEGREE LIMIT")
            return value.power(exponent)
        case let .binary(operation, left, right):
            let a = try evaluate(left)
            let b = try evaluate(right)
            switch operation {
            case .add: return a + b
            case .subtract: return a - b
            case .multiply: try productLimit(a, b); return a * b
            case .compose: try compositionLimit(a, b); return a.compose(b)
            case .divide:
                try check(b.isZero, "DIVISION BY ZERO")
                try check(b.degree > 0, "NONCONSTANT DIVISOR")
                return a.divideScalar(b.leading)
            }
        }
    }

    func execute(_ source: String) throws -> [String] {
        let words = source.split(separator: " ").map(String.init)
        let command = words[0], name = words.count > 1 ? words[1] : ""
        var pending: [(String, Polynomial)] = [], output: [String] = []
        func store(_ target: String, _ value: Polynomial) {
            pending.append((target, value))
            output.append("\(target) = \(value.notation())")
        }
        if command == "DEF" {
            let syntax = try ExpressionParser(String(source.dropFirst(name.count + 5))).parse()
            store(name, try evaluate(syntax))
        } else {
            if command == "DIV" { try check(words[1] == words[2], "SAME NAME") }
            if command == "XGCD" { try check(Set(words[1..<4]).count < 3, "SAME NAME") }
            let operands = try (references[command] ?? []).map { try lookup(words[$0]) }
            let a = operands.first ?? Polynomial(), b = operands.count > 1 ? operands[1] : Polynomial()
            var values: [Fraction] = [], endpoints: [Endpoint] = []
            if command == "STURM" {
                endpoints = try words[2..<4].map { try Endpoint.parse($0) }
            } else {
                var start = words.count, end = words.count
                if command == "AREA" { start = 2; end = 4 }
                else if command == "TANGENT" { start = 3; end = 4 }
                else if command == "TAYLOR" { start = 2; end = 3 }
                else if command == "EVAL" || command == "INTERP" { start = 2 }
                values = try words[start..<end].map { try Fraction.parse($0) }
            }
            switch command {
            case "PRINT": output.append("\(name) = \(a.notation())")
            case "DELETE": polynomials.removeValue(forKey: name); output.append("deleted \(name)")
            case "LIST":
                for key in polynomials.keys.sorted() { output.append("\(key) = \(polynomials[key]!.notation())") }
                if output.isEmpty { output.append("no polynomials") }
            case "DEGREE": output.append("deg(\(name)) = " + (a.isZero ? "-inf" : String(a.degree)))
            case "ADD": store(name, a + b)
            case "SUB": store(name, a - b)
            case "MUL": try productLimit(a, b); store(name, a * b)
            case "POW":
                let exponent = Int(words[3])!
                try check(!a.isZero && a.degree * exponent > 30, "DEGREE LIMIT")
                store(name, a.power(exponent))
            case "DIV":
                try check(b.isZero, "DIVISION BY ZERO")
                let (quotient, remainder) = a.divide(b)
                store(name, quotient)
                store(words[2], remainder)
            case "GCD": store(name, polynomialGcd(a, b))
            case "XGCD":
                let (common, s, t) = extendedGcd(a, b)
                store(name, common); store(words[2], s); store(words[3], t)
            case "LCM":
                if a.isZero || b.isZero { store(name, Polynomial()) }
                else {
                    let common = polynomialGcd(a, b)
                    try check(a.degree + b.degree - common.degree > 30, "DEGREE LIMIT")
                    store(name, (a.divide(common).quotient * b).monic())
                }
            case "INVMOD":
                try check(b.isZero, "DIVISION BY ZERO")
                try check(b.degree == 0, "DEGREE TOO LOW")
                let (common, inverse, _) = extendedGcd(a, b)
                try check(!common.isOne, "NOT COPRIME")
                store(name, inverse.mod(b))
            case "CRT":
                let c = operands[2], d = operands[3]
                try check(b.isZero || d.isZero, "DIVISION BY ZERO")
                try check(b.degree + d.degree > 30, "DEGREE LIMIT")
                let (common, inverse, _) = extendedGcd(b, d)
                try check(!common.isOne, "NOT COPRIME")
                let first = a.mod(b), second = c.mod(d)
                let correction = ((second - first) * inverse).mod(d)
                store(name, first + b * correction)
            case "MODPOW":
                try check(b.isZero, "DIVISION BY ZERO")
                try check(2 * b.degree - 2 > 30, "DEGREE LIMIT")
                var result = Polynomial.unit.mod(b), base = a.mod(b), exponent = Int(words[3])!
                while exponent > 0 {
                    if exponent % 2 == 1 { result = (result * base).mod(b) }
                    exponent /= 2
                    if exponent > 0 { base = (base * base).mod(b) }
                }
                store(name, result)
            case "DERIV": store(name, a.derivative(Int(words[3])!))
            case "INTEG":
                try check(!a.isZero && a.degree + 1 > 30, "DEGREE LIMIT")
                store(name, a.integral())
            case "AREA":
                let integral = a.integral(), u = values[0], v = values[1]
                output.append("integral(\(name), \(u), \(v)) = \(integral.evaluate(v) - integral.evaluate(u))")
            case "TANGENT":
                let point = values[0]
                let value = a.evaluate(point)
                let slope = a.derivative().evaluate(point)
                store(name, linear(value - slope * point, slope))
            case "TAYLOR":
                let point = values[0]
                let symbol = point.n == 0 ? "x" : point.n > 0 ? "(x - \(point))" : "(x + \(-point))"
                output.append("taylor(\(name), \(point)) = \(a.compose(linear(point)).notation(symbol))")
            case "COMPOSE": try compositionLimit(a, b); store(name, a.compose(b))
            case "EVAL":
                for point in values { output.append("\(name)(\(point)) = \(a.evaluate(point))") }
            case "ROOTS", "FACTOR":
                try requireNonzero(a)
                let (roots, remaining) = rationalRoots(a)
                if command == "ROOTS" {
                    let descriptions = roots.map { "\($0.value) (\($0.multiplicity))" }
                    output.append("roots(\(name)) = " + (descriptions.isEmpty ? "none" : descriptions.joined(separator: ", ")))
                } else {
                    var result = "factor(\(name)) = \(a.content())"
                    for root in roots {
                        let factor = root.value.n == 0 ? "x" : "(\(linear(Fraction(-root.value.n), Fraction(root.value.d)).notation()))"
                        result += " * " + factor + (root.multiplicity > 1 ? "^\(root.multiplicity)" : "")
                    }
                    if remaining.degree >= 1 { result += " * (\(remaining.notation()))" }
                    output.append(result)
                }
            case "SQFREE":
                try requireNonzero(a)
                var result = "sqfree(\(name)) = \(a.content())"
                if a.degree >= 1 {
                    let monic = a.monic()
                    var common = polynomialGcd(monic, monic.derivative())
                    var remaining = monic.divide(common).quotient
                    var multiplicity = 1
                    while remaining.degree >= 1 {
                        let shared = polynomialGcd(remaining, common)
                        let factor = remaining.divide(shared).quotient
                        if factor.degree >= 1 {
                            let notation = factor.primitive().notation()
                            result += " * " + (notation == "x" ? "x" : "(\(notation))") + (multiplicity > 1 ? "^\(multiplicity)" : "")
                        }
                        common = common.divide(shared).quotient
                        remaining = shared
                        multiplicity += 1
                    }
                }
                output.append(result)
            case "DESCARTES":
                try requireNonzero(a)
                let positive = a.coefficients.reversed().map(\.sign)
                let negative = a.coefficients.enumerated().map { i, value in i % 2 == 0 ? value.sign : -value.sign }.reversed()
                output.append("descartes(\(name)) = positive \(signChanges(positive)), negative \(signChanges(Array(negative)))")
            case "STURM":
                try requireNonzero(a)
                let u = endpoints[0], v = endpoints[1]
                try check(u >= v, "BAD INTERVAL")
                let sequence = sturmSequence(a)
                output.append("sturm(\(name), \(u), \(v)) = \(variations(sequence, u) - variations(sequence, v))")
            case "ISOLATE":
                try requireNonzero(a)
                let precision = Int(words[2])!
                let intervals = isolate(a, precision).map { "(\($0.0), \($0.1)]" }
                output.append("isolate(\(name), \(precision)) = " + (intervals.isEmpty ? "none" : intervals.joined(separator: ", ")))
            case "RESULTANT":
                try requireNonzero(a); try requireNonzero(b)
                output.append("res(\(name), \(words[2])) = \(resultant(a, b))")
            case "DISCRIM":
                try requireNonzero(a)
                try check(a.degree == 0, "DEGREE TOO LOW")
                var discriminant = resultant(a, a.derivative()) / a.leading
                if a.degree * (a.degree - 1) / 2 % 2 == 1 { discriminant = -discriminant }
                output.append("disc(\(name)) = \(discriminant)")
            case "POWERSUM":
                try requireNonzero(a)
                try check(a.degree == 0, "DEGREE TOO LOW")
                let monic = a.monic(), count = Int(words[2])!
                var sums: [Fraction] = [.zero]
                for j in 1...count {
                    var sum = j <= a.degree ? Fraction(Int64(j)) * monic.coefficient(a.degree - j) : .zero
                    for i in 1..<(min(j - 1, a.degree) + 1) { sum = sum + monic.coefficient(a.degree - i) * sums[j - i] }
                    sums.append(-sum)
                }
                output.append("powersum(\(name)) = \(sums.dropFirst().map(\.description).joined(separator: ", "))")
            case "INTERP": store(name, try interpolate(values))
            case "SPECIAL": store(name, try special(words[2], Int(words[3])!))
            default: preconditionFailure("Unknown command")
            }
        }
        for (target, value) in pending { polynomials[target] = value }
        return output
    }
}

let commandCount = Int(readLine()!)!
let calculator = Calculator()
for _ in 0..<commandCount {
    let source = readLine()!
    do {
        let output = try calculator.execute(source)
        for line in output { print(line) }
    } catch let error as CalculatorError {
        print("ERROR \(error.message)")
    } catch {
        fatalError(String(describing: error))
    }
}
