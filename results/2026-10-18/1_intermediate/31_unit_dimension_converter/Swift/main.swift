import Foundation

struct CommandError: Error { let message: String }
func fail(_ message: String) throws -> Never {
    throw CommandError(message: message)
}

struct Fraction: CustomStringConvertible {
    let n: Int64
    let d: Int64

    init(_ numerator: Int64 = 0, _ denominator: Int64 = 1) {
        let sign: Int64 = denominator < 0 ? -1 : 1
        var a = Swift.abs(numerator), b = Swift.abs(denominator)
        while b != 0 {
            (a, b) = (b, a % b)
        }
        n = numerator * sign / a
        d = denominator * sign / a
    }
    static let one = Fraction(1)
    static func + (a: Self, b: Self) -> Self {
        Self(a.n * b.d + b.n * a.d, a.d * b.d)
    }
    static func - (a: Self, b: Self) -> Self {
        Self(a.n * b.d - b.n * a.d, a.d * b.d)
    }
    static func * (a: Self, b: Self) -> Self {
        Self(a.n * b.n, a.d * b.d)
    }
    static func / (a: Self, b: Self) -> Self {
        Self(a.n * b.d, a.d * b.n)
    }
    static prefix func - (value: Self) -> Self {
        Self(-value.n, value.d)
    }
    var absolute: Self {
        n < 0 ? -self : self
    }
    func compare(_ other: Self) -> Int {
        let left = n * other.d, right = other.n * d
        return left < right ? -1 : left > right ? 1 : 0
    }
    func power(_ exponent: Int64) -> Self {
        let factor = exponent < 0 ? Self.one / self : self
        var result = Self.one
        for _ in 0..<Swift.abs(exponent) {
            result = result * factor
        }
        return result
    }
    var description: String {
        d == 1 ? String(n) : "\(n)/\(d)"
    }
    var decimal: String {
        let magnitude = Swift.abs(n)
        let whole = magnitude / d, tail = magnitude % d * 1_000_000 / d
        let digits = String(tail)
        return (n < 0 ? "-" : "") + "\(whole)." + String(repeating: "0", count: 6 - digits.count) + digits
    }
    func notation(_ unit: String) -> String {
        "\(self) \(unit) (\(decimal))"
    }
}

func matches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: .regularExpression) != nil
}
func numberValue(_ text: String) throws -> Fraction {
    guard matches(text, "^-?[0-9]+([./][0-9]+)?$") else {
        try fail("BAD NUMBER \(text)")
    }
    let negative = text.hasPrefix("-")
    let body = negative ? String(text.dropFirst()) : text
    let value: Fraction
    if body.contains("/") {
        let parts = body.components(separatedBy: "/")
        let denominator = Int64(parts[1])!
        guard denominator != 0 else {
            try fail("BAD NUMBER \(text)")
        }
        value = Fraction(Int64(parts[0])!, denominator)
    } else if body.contains(".") {
        let parts = body.components(separatedBy: ".")
        var scale: Int64 = 1
        for _ in parts[1] {
            scale *= 10
        }
        value = Fraction(Int64(parts[0])! * scale + Int64(parts[1])!, scale)
    } else {
        value = Fraction(Int64(body)!)
    }
    return negative ? -value : value
}
func checkedExponent(_ text: String) throws -> Int64 {
    let value = Int64(text)!
    guard value != 0 && (-3...3).contains(value) else {
        try fail("BAD EXPONENT \(text)")
    }
    return value
}
let functions = ["abs": 1, "sqrt": 1, "min": 2, "max": 2]
func checkName(_ name: String, variable: Bool = false) throws {
    guard matches(name, "^[A-Za-z]{1,12}$"), !variable || functions[name] == nil else {
        try fail("BAD NAME \(name)")
    }
}

struct Dimension: Equatable, CustomStringConvertible {
    let exponents: [Int64]

    init(_ kg: Int64 = 0, _ m: Int64 = 0, _ s: Int64 = 0, _ a: Int64 = 0,
         _ k: Int64 = 0, _ mol: Int64 = 0, _ cd: Int64 = 0)
    {
        exponents = [kg, m, s, a, k, mol, cd]
    }
    init(exponents: [Int64]) {
        self.exponents = exponents
    }
    static func + (a: Self, b: Self) -> Self {
        Self(exponents: zip(a.exponents, b.exponents).map { $0.0 + $0.1 })
    }
    static func - (a: Self, b: Self) -> Self {
        Self(exponents: zip(a.exponents, b.exponents).map { $0.0 - $0.1 })
    }
    func scaled(_ factor: Int64) -> Self {
        Self(exponents: exponents.map { $0 * factor })
    }
    func match(_ other: Self) throws {
        guard self == other else {
            try fail("DIMENSION MISMATCH \(self) vs \(other)")
        }
    }
    var description: String {
        let symbols = ["kg", "m", "s", "A", "K", "mol", "cd"]
        let parts = exponents.enumerated().compactMap { index, value -> String? in
            value == 0 ? nil : symbols[index] + (value == 1 ? "" : "^\(value)")
        }
        return parts.isEmpty ? "1" : parts.joined(separator: " ")
    }
}
struct Quantity {
    let value: Fraction
    let dimension: Dimension
    init(_ value: Fraction = .one, _ dimension: Dimension = Dimension()) {
        self.value = value
        self.dimension = dimension
    }
}
let kinds: [(String, Dimension)] = [
    ("dimensionless", Dimension()), ("length", Dimension(0, 1)), ("mass", Dimension(1)), ("time", Dimension(0, 0, 1)),
    ("current", Dimension(0, 0, 0, 1)), ("temperature", Dimension(0, 0, 0, 0, 1)),
    ("amount", Dimension(0, 0, 0, 0, 0, 1)), ("luminous_intensity", Dimension(0, 0, 0, 0, 0, 0, 1)),
    ("area", Dimension(0, 2)), ("volume", Dimension(0, 3)), ("speed", Dimension(0, 1, -1)),
    ("acceleration", Dimension(0, 1, -2)), ("density", Dimension(1, -3)), ("momentum", Dimension(1, 1, -1)),
    ("force", Dimension(1, 1, -2)), ("energy", Dimension(1, 2, -2)), ("power", Dimension(1, 2, -3)),
    ("pressure", Dimension(1, -1, -2)), ("frequency", Dimension(0, 0, -1)), ("charge", Dimension(0, 0, 1, 1)),
    ("voltage", Dimension(1, 2, -3, -1)), ("resistance", Dimension(1, 2, -3, -2)),
    ("conductance", Dimension(-1, -2, 3, 2)), ("capacitance", Dimension(-1, -2, 4, 2)),
    ("magnetic_flux", Dimension(1, 2, -2, -1)), ("flux_density", Dimension(1, 0, -2, -1)),
    ("inductance", Dimension(1, 2, -2, -2)), ("illuminance", Dimension(0, -2, 0, 0, 0, 0, 1)),
    ("catalytic_activity", Dimension(0, 0, -1, 0, 0, 1)),
]
func kindDimension(_ name: String) -> Dimension? {
    kinds.first { $0.0 == name }?.1
}
func kindName(_ dimension: Dimension) -> String {
    kinds.first { $0.1 == dimension }?.0 ?? "-"
}

struct Definition { let value: Fraction
    let expression: String
}
struct Unit {
    let symbol: String
    let quantity: Quantity
    let prefixable: Bool
    let definition: Definition?
}
struct BuiltinRow {
    let symbol: String
    let numerator: Int64
    let denominator: Int64
    let kind: String
    let prefixable: Bool
    init(_ symbol: String, _ n: Int64, _ d: Int64, _ kind: String, _ prefixable: Bool) {
        self.symbol = symbol
        numerator = n
        denominator = d
        self.kind = kind
        self.prefixable = prefixable
    }
}
let builtinRows: [BuiltinRow] = [
    .init("m", 1, 1, "length", true), .init("g", 1, 1000, "mass", true), .init("s", 1, 1, "time", true),
    .init("A", 1, 1, "current", true), .init("K", 1, 1, "temperature", true), .init("mol", 1, 1, "amount", true),
    .init("cd", 1, 1, "luminous_intensity", true), .init("N", 1, 1, "force", true), .init("J", 1, 1, "energy", true),
    .init("W", 1, 1, "power", true), .init("Pa", 1, 1, "pressure", true), .init("Hz", 1, 1, "frequency", true),
    .init("C", 1, 1, "charge", true), .init("V", 1, 1, "voltage", true), .init("ohm", 1, 1, "resistance", true),
    .init("S", 1, 1, "conductance", true), .init("F", 1, 1, "capacitance", true), .init(
        "Wb",
        1,
        1,
        "magnetic_flux",
        true
    ),
    .init("T", 1, 1, "flux_density", true), .init("H", 1, 1, "inductance", true), .init(
        "lx",
        1,
        1,
        "illuminance",
        true
    ),
    .init("kat", 1, 1, "catalytic_activity", true), .init("L", 1, 1000, "volume", true), .init(
        "t",
        1000,
        1,
        "mass",
        false
    ),
    .init("min", 60, 1, "time", false), .init("h", 3600, 1, "time", false), .init("day", 86400, 1, "time", false),
    .init("in", 127, 5000, "length", false), .init("ft", 381, 1250, "length", false), .init(
        "yd",
        1143,
        1250,
        "length",
        false
    ),
    .init("mi", 201168, 125, "length", false), .init("nmi", 1852, 1, "length", false), .init(
        "ha",
        10000,
        1,
        "area",
        false
    ),
    .init("kn", 463, 900, "speed", false), .init("bar", 100000, 1, "pressure", true), .init(
        "atm",
        101325,
        1,
        "pressure",
        false
    ),
    .init("Torr", 20265, 152, "pressure", false), .init("cal", 523, 125, "energy", true), .init(
        "Wh",
        3600,
        1,
        "energy",
        true
    ),
    .init("Ah", 3600, 1, "charge", true), .init("dC", 1, 1, "temperature", false), .init(
        "dF",
        5,
        9,
        "temperature",
        false
    ),
]
let builtins = builtinRows.map { row in
    Unit(symbol: row.symbol, quantity: Quantity(Fraction(row.numerator, row.denominator), kindDimension(row.kind)!),
         prefixable: row.prefixable, definition: nil)
}
let prefixes: [(String, Fraction)] = [
    ("G", Fraction(1_000_000_000)), ("M", Fraction(1_000_000)), ("k", Fraction(1000)), ("h", Fraction(100)), (
        "da",
        Fraction(10)
    ),
    ("d", Fraction(1, 10)), ("c", Fraction(1, 100)), ("m", Fraction(1, 1000)), ("u", Fraction(1, 1_000_000)), (
        "n",
        Fraction(1, 1_000_000_000)
    ),
]

final class Database {
    var units = builtins
    var variables: [String: Quantity] = [:]

    func resolve(_ name: String) -> Quantity? {
        if let exact = units.first(where: { $0.symbol == name }) {
            return exact.quantity
        }
        for (prefix, factor) in prefixes where name.hasPrefix(prefix) {
            let suffix = String(name.dropFirst(prefix.count))
            if let unit = builtins.first(where: { $0.prefixable && $0.symbol == suffix }) {
                return Quantity(factor * unit.quantity.value, unit.quantity.dimension)
            }
        }
        return nil
    }
    func simplified(_ dimension: Dimension) -> String {
        units.first { $0.quantity.value.compare(.one) == 0 && $0.quantity.dimension == dimension }?.symbol ?? dimension
            .description
    }
    func selected(_ dimension: Dimension) -> [Unit] {
        units.filter { $0.quantity.dimension == dimension }.sorted { a, b in
            let comparison = a.quantity.value.compare(b.quantity.value)
            return comparison == 0 ? a.symbol < b.symbol : comparison < 0
        }
    }
}

enum TokenKind { case name, number, unit, symbol, invalid, end }
struct Token { let kind: TokenKind
    let text: String
    let position: Int
}
enum Operation: String { case add = "+", subtract = "-", multiply = "*", divide = "/" }
indirect enum UnitExpr {
    case name(String)
    case integer(Int64)
    case power(UnitExpr, String)
    case product([UnitTerm])
}
struct UnitTerm { let divide: Bool
    let expression: UnitExpr
}
indirect enum QuantityExpr {
    case literal(String, String?)
    case variable(String)
    case negative(QuantityExpr)
    case power(QuantityExpr, String)
    case binary(Operation, QuantityExpr, QuantityExpr)
    case call(String, [QuantityExpr])
}
func letter(_ byte: UInt8) -> Bool {
    (65...90).contains(byte) || (97...122).contains(byte)
}
func digit(_ byte: UInt8) -> Bool {
    (48...57).contains(byte)
}
func ascii<C: Collection>(_ bytes: C) -> String where C.Element == UInt8 {
    String(decoding: bytes, as: UTF8.self)
}

final class Parser {
    private let source: String
    private var tokens: [Token] = []
    private var position = 0

    init(_ source: String, quantity: Bool) {
        self.source = source
        let bytes = Array(source.utf8)
        var i = 0
        while i < bytes.count {
            let start = i, character = bytes[i]
            i += 1
            var kind = TokenKind.invalid
            if letter(character) {
                kind = .name
                while i < bytes.count && letter(bytes[i]) {
                    i += 1
                }
            } else if digit(character) {
                kind = .number
                while i < bytes.count && digit(bytes[i]) {
                    i += 1
                }
                if quantity && i + 1 < bytes.count && bytes[i] == 46 && digit(bytes[i + 1]) {
                    i += 1
                    while i < bytes.count && digit(bytes[i]) {
                        i += 1
                    }
                }
            } else if quantity && character == 91 {
                if let closing = bytes[i...].firstIndex(of: 93), closing > i {
                    kind = .unit
                    i = closing + 1
                }
            } else if (quantity ? "+-*/^()," : "*/^()-").utf8.contains(character) {
                kind = .symbol
            }
            tokens.append(Token(kind: kind, text: ascii(bytes[start..<i]), position: start + 1))
        }
        tokens.append(Token(kind: .end, text: "", position: bytes.count + 1))
    }
    private var current: Token {
        tokens[position]
    }
    private func syntax() throws -> Never {
        try fail("SYNTAX \(source) AT \(current.kind == .end ? "END" : String(current.position))")
    }
    private func advance() -> Token {
        defer { position += 1 }
        return current
    }
    private func take(_ text: String) -> Bool {
        guard current.text == text else {
            return false
        }
        position += 1
        return true
    }
    private func expect(_ text: String) throws {
        if !take(text) {
            try syntax()
        }
    }
    private func exponent() throws -> String {
        let sign = take("-") ? "-" : ""
        guard current.kind == .number && !current.text.contains(".") else {
            try syntax()
        }
        return sign + advance().text
    }
    private func unitTerm() throws -> UnitExpr {
        let value: UnitExpr
        if current.kind == .name {
            value = .name(advance().text)
        } else if current.kind == .number && !current.text.hasPrefix("0") {
            value = .integer(Int64(advance().text)!)
        } else if take("(") {
            value = try unitExpression()
            try expect(")")
        } else {
            try syntax()
        }
        return take("^") ? .power(value, try exponent()) : value
    }
    private func unitExpression() throws -> UnitExpr {
        var terms = [UnitTerm(divide: false, expression: try unitTerm())]
        while current.text == "*" || current.text == "/" {
            let divide = advance().text == "/"
            terms.append(UnitTerm(divide: divide, expression: try unitTerm()))
        }
        return .product(terms)
    }
    func unit() throws -> UnitExpr {
        let value = try unitExpression()
        if current.kind != .end {
            try syntax()
        }
        return value
    }
    private func primary() throws -> QuantityExpr {
        let token = current
        let value: QuantityExpr
        if token.kind == .number {
            _ = advance()
            let unit = current.kind == .unit ? String(advance().text.dropFirst().dropLast()) : nil
            value = .literal(token.text, unit)
        } else if token.kind == .unit {
            _ = advance()
            value = .literal("1", String(token.text.dropFirst().dropLast()))
        } else if token.kind == .name {
            _ = advance()
            if take("(") {
                var arguments = [try expression()]
                while take(",") {
                    arguments.append(try expression())
                }
                try expect(")")
                value = .call(token.text, arguments)
            } else {
                value = .variable(token.text)
            }
        } else if take("(") {
            value = try expression()
            try expect(")")
        } else {
            try syntax()
        }
        return take("^") ? .power(value, try exponent()) : value
    }
    private func unary() throws -> QuantityExpr {
        if take("-") {
            return .negative(try unary())
        }
        return try primary()
    }
    private func product() throws -> QuantityExpr {
        var value = try unary()
        while current.text == "*" || current.text == "/" {
            let operation = Operation(rawValue: advance().text)!
            value = .binary(operation, value, try unary())
        }
        return value
    }
    private func expression() throws -> QuantityExpr {
        var value = try product()
        while current.text == "+" || current.text == "-" {
            let operation = Operation(rawValue: advance().text)!
            value = .binary(operation, value, try product())
        }
        return value
    }
    func quantity() throws -> QuantityExpr {
        let value = try expression()
        if current.kind != .end {
            try syntax()
        }
        return value
    }
}

func validateUnit(_ database: Database, _ node: UnitExpr) throws {
    switch node {
    case .name(let name):
        guard database.resolve(name) != nil else {
            try fail("UNKNOWN UNIT \(name)")
        }
    case .integer:
        break
    case .power(let child, let exponent):
        try validateUnit(database, child)
        _ = try checkedExponent(exponent)
    case .product(let terms):
        for term in terms {
            try validateUnit(database, term.expression)
        }
    }
}
func evaluateUnit(_ database: Database, _ node: UnitExpr) -> Quantity {
    switch node {
    case .name(let name):
        return database.resolve(name)!
    case .integer(let value):
        return Quantity(Fraction(value))
    case .power(let child, let text):
        let value = evaluateUnit(database, child), exponent = Int64(text)!
        return Quantity(value.value.power(exponent), value.dimension.scaled(exponent))
    case .product(let terms):
        var value = Quantity()
        for term in terms {
            let right = evaluateUnit(database, term.expression)
            value = term.divide ? Quantity(value.value / right.value, value.dimension - right.dimension) :
                Quantity(value.value * right.value, value.dimension + right.dimension)
        }
        return value
    }
}
func parseUnit(_ database: Database, _ text: String) throws -> UnitExpr {
    let tree = try Parser(text, quantity: false).unit()
    try validateUnit(database, tree)
    return tree
}
func unitValue(_ database: Database, _ text: String) throws -> Quantity {
    evaluateUnit(database, try parseUnit(database, text))
}
struct Reduced {
    var coefficient = Fraction.one
    var powers: [(String, Int64)] = []
}
func reduceUnit(_ node: UnitExpr) -> Reduced {
    switch node {
    case .name(let name):
        return Reduced(powers: [(name, 1)])
    case .integer(let value):
        return Reduced(coefficient: Fraction(value))
    case .power(let child, let text):
        let value = reduceUnit(child), exponent = Int64(text)!
        return Reduced(
            coefficient: value.coefficient.power(exponent),
            powers: value.powers.map { ($0.0, $0.1 * exponent) }
        )
    case .product(let terms):
        var result = Reduced()
        for term in terms {
            let right = reduceUnit(term.expression)
            result.coefficient = term.divide ? result.coefficient / right.coefficient : result.coefficient * right
                .coefficient
            for (name, power) in right.powers {
                let amount = term.divide ? -power : power
                if let index = result.powers.firstIndex(where: { $0.0 == name }) {
                    result.powers[index].1 += amount
                } else {
                    result.powers.append((name, amount))
                }
            }
        }
        return result
    }
}
func reducedText(_ tree: UnitExpr) -> String {
    let value = reduceUnit(tree)
    var parts = value.coefficient.compare(.one) == 0 ? [] : [value.coefficient.description]
    for (name, power) in value.powers where power != 0 {
        parts.append(power == 1 ? name : "\(name)^\(power)")
    }
    return parts.isEmpty ? "1" : parts.joined(separator: " ")
}
func integerSqrt(_ value: Int64) -> Int64 {
    if value < 2 {
        return value
    }
    var current = value, next = (value + 1) / 2
    while next < current {
        current = next
        next = (current + value / current) / 2
    }
    return current
}
func evaluateQuantity(_ database: Database, _ node: QuantityExpr) throws -> Quantity {
    switch node {
    case .literal(let text, let unitText):
        let unit = try unitText.map { try unitValue(database, $0) } ?? Quantity()
        return Quantity(try numberValue(text) * unit.value, unit.dimension)
    case .variable(let name):
        guard let value = database.variables[name] else {
            try fail("UNKNOWN VARIABLE \(name)")
        }
        return value
    case .negative(let child):
        let value = try evaluateQuantity(database, child)
        return Quantity(-value.value, value.dimension)
    case .power(let child, let text):
        let value = try evaluateQuantity(database, child)
        let exponent = try checkedExponent(text)
        if value.value.n == 0 && exponent < 0 {
            try fail("DIVISION BY ZERO")
        }
        return Quantity(value.value.power(exponent), value.dimension.scaled(exponent))
    case .binary(let operation, let first, let second):
        let left = try evaluateQuantity(database, first)
        let right = try evaluateQuantity(database, second)
        switch operation {
        case .add, .subtract:
            try left.dimension.match(right.dimension)
            return Quantity(operation == .add ? left.value + right.value : left.value - right.value, left.dimension)
        case .multiply:
            return Quantity(left.value * right.value, left.dimension + right.dimension)
        case .divide:
            guard right.value.n != 0 else {
                try fail("DIVISION BY ZERO")
            }
            return Quantity(left.value / right.value, left.dimension - right.dimension)
        }
    case .call(let name, let arguments):
        guard let arity = functions[name] else {
            try fail("UNKNOWN FUNCTION \(name)")
        }
        guard arguments.count == arity else {
            try fail("BAD ARGUMENTS \(name)")
        }
        let first = try evaluateQuantity(database, arguments[0])
        if name == "abs" {
            return Quantity(first.value.absolute, first.dimension)
        }
        if name == "sqrt" {
            guard first.value.n >= 0 else {
                try fail("NEGATIVE ROOT")
            }
            guard first.dimension.exponents.allSatisfy({ $0 % 2 == 0 })
            else {
                try fail("ODD DIMENSION \(first.dimension)")
            }
            let n = integerSqrt(first.value.n), d = integerSqrt(first.value.d)
            guard n * n == first.value.n && d * d == first.value.d else {
                try fail("NOT EXACT")
            }
            return Quantity(Fraction(n, d), Dimension(exponents: first.dimension.exponents.map { $0 / 2 }))
        }
        let second = try evaluateQuantity(database, arguments[1])
        try first.dimension.match(second.dimension)
        let comparison = first.value.compare(second.value)
        return (name == "min" ? comparison <= 0 : comparison >= 0) ? first : second
    }
}
func quantityValue(_ database: Database, _ text: String) throws -> Quantity {
    try evaluateQuantity(database, Parser(text, quantity: true).quantity())
}

func execute(_ database: Database, _ line: String) throws -> [String] {
    let words = line.components(separatedBy: " "), command = words[0]
    switch command {
    case "DEFINE":
        let name = words[1]
        try checkName(name)
        let value = try numberValue(words[3])
        let unit = try unitValue(database, words[4])
        guard kindDimension(name) == nil && database.resolve(name) == nil else {
            try fail("NAME TAKEN \(name)")
        }
        guard value.n > 0 else {
            try fail("NOT POSITIVE \(words[3])")
        }
        let result = Quantity(value * unit.value, unit.dimension)
        database.units.append(Unit(
            symbol: name,
            quantity: result,
            prefixable: false,
            definition: Definition(value: value, expression: words[4])
        ))
        return ["DEFINE \(name) factor=\(result.value) dim=\(result.dimension) kind=\(kindName(result.dimension))"]
    case "UNDEF":
        guard let index = database.units.firstIndex(where: { $0.symbol == words[1] })
        else {
            try fail("NOT DEFINED \(words[1])")
        }
        guard index >= builtins.count else {
            try fail("BUILTIN UNIT \(words[1])")
        }
        database.units.remove(at: index)
        return ["UNDEF \(words[1])"]
    case "DEFS":
        return ["DEFS count=\(database.units.count - builtins.count)"] + database.units.dropFirst(builtins.count)
            .map { unit in
                "DEF \(unit.symbol) = \(unit.definition!.value) \(unit.definition!.expression) factor=\(unit.quantity.value) dim=\(unit.quantity.dimension)"
            }
    case "CONVERT", "INVERT":
        let value = try numberValue(words[1])
        let source = try unitValue(database, words[2])
        let target = try unitValue(database, words[4])
        if command == "INVERT" {
            guard source.dimension != Dimension(), source.dimension + target.dimension == Dimension() else {
                try fail("NOT RECIPROCAL \(source.dimension) vs \(target.dimension)")
            }
            guard value.n != 0 else {
                try fail("DIVISION BY ZERO")
            }
        } else {
            try source.dimension.match(target.dimension)
        }
        var result = value * source.value
        if command == "INVERT" {
            result = .one / result
        }
        return ["\(command) \(value) \(words[2]) = \((result / target.value).notation(words[4]))"]
    case "DIM", "REDUCE", "SIMPLIFY":
        let tree = try parseUnit(database, words[1])
        let unit = evaluateUnit(database, tree)
        let result = command == "DIM" ? "\(unit.dimension) factor=\(unit.value) kind=\(kindName(unit.dimension))" :
            command == "REDUCE" ? reducedText(tree) : unit.value.notation(database.simplified(unit.dimension))
        return ["\(command) \(words[1]) = \(result)"]
    case "ADD", "SUB", "MUL", "DIV", "COMPARE":
        let a = try numberValue(words[1])
        let first = try unitValue(database, words[2])
        let b = try numberValue(words[3])
        let second = try unitValue(database, words[4])
        let hasTarget = words.count == 7
        let target = hasTarget ? try unitValue(database, words[6]) : first
        let prefix = "\(command) \(a) \(words[2])", suffix = "\(b) \(words[4])"
        if command == "ADD" || command == "SUB" || command == "COMPARE" {
            try first.dimension.match(second.dimension)
            if hasTarget {
                try first.dimension.match(target.dimension)
            }
            let left = a * first.value, right = b * second.value
            if command == "COMPARE" {
                let relation = ["<", "=", ">"][left.compare(right) + 1]
                let ratio = right.n == 0 ? "undefined" : (left / right).description
                return ["\(prefix) \(relation) \(suffix) ratio=\(ratio)"]
            }
            let add = command == "ADD"
            let result = add ? left + right : left - right
            let operation = add ? "+" : "-"
            return [
                "\(prefix) \(operation) \(suffix) = \((result / target.value).notation(hasTarget ? words[6] : words[2]))"
            ]
        }
        let multiply = command == "MUL"
        let dimension = multiply ? first.dimension + second.dimension : first.dimension - second.dimension
        if !multiply && b.n == 0 {
            try fail("DIVISION BY ZERO")
        }
        if hasTarget {
            try dimension.match(target.dimension)
        }
        let raw = multiply ? a * b : a / b
        let left = a * first.value, right = b * second.value
        let coherent = multiply ? left * right : left / right
        let operation = multiply ? "*" : "/"
        let heading = "\(prefix) \(operation) \(suffix) ="
        if hasTarget {
            return ["\(heading) \((coherent / target.value).notation(words[6]))"]
        }
        let rightUnit = !multiply && (words[4].contains("*") || words[4].contains("/")) ? "(\(words[4]))" : words[4]
        return [
            "\(heading) \(raw) \(words[2])\(operation)\(rightUnit) = \(coherent.notation(database.simplified(dimension)))"
        ]
    case "TEMP":
        let value = try numberValue(words[1])
        for scale in [words[2], words[4]]
            where !["C", "F", "K", "R"].contains(scale)
        {
            try fail("UNKNOWN SCALE \(scale)")
        }
        let celsius = Fraction(5463, 20), fahrenheit = Fraction(45967, 100)
        let kelvin = words[2] == "C" ? value + celsius : words[2] == "F" ? (value + fahrenheit) * Fraction(5, 9) :
            words[2] == "R" ? value * Fraction(5, 9) : value
        guard kelvin.n >= 0 else {
            try fail("BELOW ABSOLUTE ZERO")
        }
        let result = words[4] == "C" ? kelvin - celsius : words[4] == "F" ? kelvin * Fraction(9, 5) - fahrenheit :
            words[4] == "R" ? kelvin * Fraction(9, 5) : kelvin
        return ["TEMP \(value) \(words[2]) = \(result.notation(words[4]))"]
    case "LIST":
        let dimension = try kindDimension(words[1]) ?? unitValue(database, words[1]).dimension
        let units = database.selected(dimension)
        return ["LIST \(words[1]) dim=\(dimension) kind=\(kindName(dimension)) count=\(units.count)"] + units
            .map { unit in
                "UNIT \(unit.symbol) factor=\(unit.quantity.value) origin=\(unit.definition == nil ? "builtin" : "user") prefix=\(unit.prefixable ? "yes" : "no")"
            }
    case "TABLE":
        let value = try numberValue(words[1])
        let unit = try unitValue(database, words[2])
        let units = database.selected(unit.dimension)
        return ["TABLE \(value) \(words[2]) dim=\(unit.dimension) count=\(units.count)"] + units.map { item in
            "ROW \((value * unit.value / item.quantity.value).notation(item.symbol))"
        }
    case "AUTO":
        let value = try numberValue(words[1])
        let unit = try unitValue(database, words[2])
        guard let reference = builtins.first(where: { $0.prefixable && $0.quantity.dimension == unit.dimension }) else {
            try fail("NO PREFIXABLE UNIT \(unit.dimension)")
        }
        let scaled = value * unit.value / reference.quantity.value
        let magnitude = scaled.absolute
        var exponent: Int64 = 0
        if magnitude.compare(.one) >= 0 {
            while exponent < 9 && magnitude.compare(Fraction(10).power(exponent + 3)) >= 0 {
                exponent += 3
            }
        } else if magnitude.n > 0 {
            while exponent > -9 && magnitude.compare(Fraction(10).power(exponent)) < 0 {
                exponent -= 3
            }
        }
        let prefix = ["n", "u", "m", "", "k", "M", "G"][Int((exponent + 9) / 3)]
        return [
            "AUTO \(value) \(words[2]) = \((scaled / Fraction(10).power(exponent)).notation(prefix + reference.symbol))"
        ]
    case "SPLIT":
        let value = try numberValue(words[1])
        let unit = try unitValue(database, words[2])
        let parts = words[4].components(separatedBy: ",")
        let targets = try parts.map { try unitValue(database, $0) }
        guard value.n >= 0 else {
            try fail("NEGATIVE VALUE")
        }
        for target in targets {
            try unit.dimension.match(target.dimension)
        }
        for i in 0..<(targets.count - 1)
            where targets[i].value.compare(targets[i + 1].value) <= 0
        {
            try fail("UNIT ORDER")
        }
        var remaining = value * unit.value
        var pieces: [String] = []
        for i in 0..<(targets.count - 1) {
            let quotient = remaining / targets[i].value
            let whole = quotient.n / quotient.d
            remaining = remaining - Fraction(whole) * targets[i].value
            pieces.append("\(whole) \(parts[i])")
        }
        pieces.append((remaining / targets.last!.value).notation(parts.last!))
        return ["SPLIT \(value) \(words[2]) = \(pieces.joined(separator: " "))"]
    case "LET":
        try checkName(words[1], variable: true)
        let value = try quantityValue(database, words[3])
        database.variables[words[1]] = value
        return ["LET \(words[1]) = \(value.value.notation(database.simplified(value.dimension)))"]
    case "EVAL":
        let value = try quantityValue(database, words[1])
        var result = value.value, label = database.simplified(value.dimension)
        if words.count == 4 {
            let target = try unitValue(database, words[3])
            try value.dimension.match(target.dimension)
            result = result / target.value
            label = words[3]
        }
        return ["EVAL \(words[1]) = \(result.notation(label))"]
    case "VARS":
        return ["VARS count=\(database.variables.count)"] + database.variables.keys.sorted().map { name in
            let value = database.variables[name]!
            return "VAR \(name) = \(value.value.notation(database.simplified(value.dimension)))"
        }
    default:
        try fail("UNKNOWN COMMAND \(command)")
    }
}

let count = Int(readLine()!)!
let database = Database()
var output: [String] = []
for _ in 0..<count {
    let line = readLine()!
    do { output.append(contentsOf: try execute(database, line)) }
    catch let error as CommandError { output.append("ERROR \(error.message)") }
    catch { fatalError("Unexpected error: \(error)") }
}
print(output.joined(separator: "\n"))
