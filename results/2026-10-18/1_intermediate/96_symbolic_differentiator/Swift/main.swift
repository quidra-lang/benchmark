import Foundation

enum CommandError: Error { case message(String) }
func fail(_ s: String) throws -> Never {
    throw CommandError.message(s)
}
struct Rational: Hashable, Comparable {
    let p: Int64, q: Int64
    init(_ n: Int64, _ d: Int64 = 1) {
        var p = n, q = d
        if q < 0 {
            p = -p
            q = -q
        }
        var a = abs(p), b = q
        while b != 0 {
            let t = a % b
            a = b
            b = t
        }
        self.p = p / a
        self.q = q / a
    }
    static func +(a: Self, b: Self) -> Self {
        Self(a.p * b.q + b.p * a.q, a.q * b.q)
    }
    static func *(a: Self, b: Self) -> Self {
        Self(a.p * b.p, a.q * b.q)
    }
    static prefix func -(a: Self) -> Self {
        Self(-a.p, a.q)
    }
    static func <(a: Self, b: Self) -> Bool {
        a.p * b.q < b.p * a.q
    }
}
indirect enum Expr: Hashable {
    case variable(String), sum([Expr]), product([Expr]), power(Expr, Expr), function(String, Expr), number(Rational)
    var kind: Int {
        switch self { case .variable:
            return 0
        case .sum:
            return 1
        case .product:
            return 2
        case .power:
            return 3
        case .function:
            return 4
        case .number:
            return 5 }
    }
}
func num(_ p: Int64, _ q: Int64 = 1) -> Expr {
    .number(Rational(p, q))
}
let zero = num(0), one = num(1), minus = num(-1), half = num(1, 2)
let functions: Set<String> = ["sin", "cos", "tan", "exp", "ln", "sqrt"]
func compare(_ a: Expr, _ b: Expr) -> Int {
    if a.kind != b.kind {
        return a.kind < b.kind ? -1 : 1
    }
    switch (a, b) {
    case let (.number(x), .number(y)):
        return x == y ? 0 : x < y ? -1 : 1
    case let (.variable(x), .variable(y)):
        return x == y ? 0 : x < y ? -1 : 1
    case let (.sum(x), .sum(y)), let (.product(x), .product(y)):
        for (s, t) in zip(x, y) {
            let c = compare(s, t)
            if c != 0 {
                return c
            }
        }
        return x.count == y.count ? 0 : x.count < y.count ? -1 : 1
    case let (.power(s, x), .power(t, y)):
        let c = compare(s, t)
        return c != 0 ? c : compare(x, y)
    case let (.function(s, x), .function(t, y)):
        return s == t ? compare(x, y) : s < t ? -1 : 1
    default:
        return 0
    }
}
func integer(_ f: Expr) -> Bool {
    if case let .number(q) = f {
        return q.q == 1
    }
    return false
}
func negative(_ f: Expr) -> Bool {
    if case let .power(_, .number(q)) = f {
        return q.p < 0
    }
    return false
}
func base(_ f: Expr) -> Expr {
    if case let .power(b, _) = f {
        return b
    }
    return f
}
func exponent(_ f: Expr) -> Expr {
    if case let .power(_, x) = f {
        return x
    }
    return one
}
func coefficient(_ f: Expr) -> (Rational, [Expr]) {
    if case let .number(q) = f {
        return (q, [])
    }
    if case let .product(a) = f {
        if case let .number(q) = a[0] {
            return (q, Array(a.dropFirst()))
        }
        return (Rational(1), a)
    }
    return (Rational(1), [f])
}
func product(_ c: Rational, _ a: [Expr]) -> Expr {
    if a.isEmpty {
        return .number(c)
    }
    let r = c == Rational(1) ? a : [.number(c)] + a
    return r.count == 1 ? r[0] : .product(r)
}
func exponentCompare(_ a: Expr, _ b: Expr) -> Int {
    if a.kind == 5 && b.kind != 5 {
        return -1
    }
    if a.kind != 5 && b.kind == 5 {
        return 1
    }
    return compare(a, b)
}
func termCompare(_ a: Expr, _ b: Expr) -> Int {
    var x: [Expr: Expr] = [:], y: [Expr: Expr] = [:]
    for f in coefficient(a).1 {
        x[base(f)] = exponent(f)
    }
    for f in coefficient(b).1 {
        y[base(f)] = exponent(f)
    }
    for f in Set(x.keys).union(y.keys).sorted(by: { compare($0, $1) < 0 }) {
        let c = exponentCompare(
            y[f] ?? zero,
            x[f] ?? zero
        )
        if c != 0 {
            return c
        }
    }
    return 0
}
func add(_ operands: [Expr]) throws -> Expr {
    var terms: [Expr] = []
    for f in operands {
        if case let .sum(a) = f {
            terms += a
        } else if case let .product(a) = f, a.count == 2, case .number = a[0],
                  case let .sum(ts) = a[1]
        {
            for t in ts {
                terms.append(try mul([
                    a[0],
                    t
                ]))
            }
        } else {
            terms.append(f)
        }
    }
    var keys: [[Expr]] = [], values: [Rational] = []
    for f in terms {
        let (c, m) = coefficient(f)
        if let i = keys.firstIndex(of: m) {
            values[i] = values[i] + c
        } else {
            keys.append(m)
            values.append(c)
        }
    }
    let built = keys.indices.filter { values[$0].p != 0 }.map { product(values[$0], keys[$0]) }.sorted { termCompare(
        $0,
        $1
    ) < 0 }
    return built.isEmpty ? zero : built.count == 1 ? built[0] : .sum(built)
}
func mul(_ operands: [Expr]) throws -> Expr {
    var c = Rational(1), bases: [Expr] = [], groups: [[Expr]] = []
    let factors = operands.flatMap {
        f -> [Expr] in if case let .product(a) = f {
            return a
        }
        return [f]
    }
    for f in factors {
        if case let .number(q) = f {
            c = c * q
        } else {
            let b = base(f)
            if let i = bases.firstIndex(of: b) {
                groups[i].append(f)
            } else {
                bases.append(b)
                groups.append([f])
            }
        }
    }
    if c.p == 0 {
        return zero
    }
    var results: [Expr] = []
    for i in groups.indices {
        if groups[i].count == 1 {
            results.append(groups[i][0])
        } else {
            results.append(try power(
                bases[i],
                add(groups[i].map(exponent))
            ))
        }
    }
    if results.contains(where: { $0.kind == 2 || $0.kind == 5 }) || Set(results.map(base)).count < results
        .count
    {
        return try mul([.number(c)] + results)
    }
    return product(c, results.sorted { compare(base($0), base($1)) < 0 })
}
func root(_ v: Int64, _ d: Int64) -> Int64? {
    if v == 1 {
        return 1
    }
    if d > 20 {
        return nil
    }
    let r = Int64(pow(Double(v), 1.0 / Double(d)).rounded())
    for s in max(0, r - 1)...r + 1 {
        var a: Int64 = 1, i: Int64 = 0
        while i < d && a <= v {
            a *= s
            i += 1
        }
        if a == v {
            return s
        }
    }
    return nil
}
func rationalPower(_ value: Rational, _ exponent: Int64) -> Expr {
    var b = value, n = exponent
    if n < 0 {
        b = Rational(b.q, b.p)
        n = -n
    }
    var r = Rational(1)
    while n > 0 {
        if n % 2 != 0 {
            r = r * b
        }
        n /= 2
        if n > 0 {
            b = b * b
        }
    }
    return .number(r)
}
func power(_ b: Expr, _ x: Expr) throws -> Expr {
    if x == zero {
        return one
    }
    if x == one {
        return b
    }
    if case let .number(q) = b {
        if b == one {
            return one
        }
        guard case let .number(e) = x else {
            return .power(b, x)
        }
        if q.p == 0 {
            if e.p > 0 {
                return zero
            }
            try fail("division by zero")
        }
        if integer(x) {
            return rationalPower(q, e.p)
        }
        if q.p > 0, let s = root(q.p, e.q), let t = root(q.q, e.q) {
            return rationalPower(Rational(s, t), e.p)
        }
    } else if integer(x) {
        if case let .power(a, e) = b {
            return try power(a, mul([e, x]))
        }
        if case let .product(a) = b {
            return try mul(a.map { try power($0, x) })
        }
    }
    return .power(b, x)
}
func fn(_ s: String, _ a: Expr) throws -> Expr {
    if s == "sqrt" {
        return try power(a, half)
    }
    if a == zero && ["sin", "tan"].contains(s) {
        return zero
    }
    if a == zero && ["cos", "exp"].contains(s) {
        return one
    }
    if a == one && s == "ln" {
        return zero
    }
    if ["sin", "cos", "tan"].contains(s) && coefficient(a).0.p < 0 {
        let r = try fn(s, mul([minus, a]))
        if s == "cos" {
            return r
        }
        return try mul([minus, r])
    }
    if case let .function(t, x) = a, (s == "exp" && t == "ln") || (s == "ln" && t == "exp") {
        return x
    }
    return .function(s, a)
}
func variables(_ f: Expr) -> Set<String> {
    switch f { case let .variable(s):
        return [s]
    case let .sum(a), let .product(a):
        return a.reduce(into: Set<String>()) { $0.formUnion(variables($1)) }
    case let .power(b, x):
        return variables(b).union(variables(x))
    case let .function(_, a):
        return variables(a)
    case .number:
        return [] }
}
func derivative(_ f: Expr, _ v: String) throws -> Expr {
    switch f {
    case .number:
        return zero
    case let .variable(s):
        return s == v ? one : zero
    case let .sum(a):
        return try add(a.map { try derivative($0, v) })
    case let .product(a):
        var r: [Expr] = []
        for i in a.indices {
            var p = a
            p[i] = try derivative(p[i], v)
            r.append(try mul(p))
        }
        return try add(r)
    case let .power(b, x):
        if !variables(x).contains(v) {
            return try mul([x, power(b, add([x, minus])), derivative(b, v)])
        }
        if !variables(b).contains(v) {
            return try mul([f, fn("ln", b), derivative(x, v)])
        }
        return try mul([f, add([mul([derivative(x, v), fn("ln", b)]), mul([x, derivative(b, v), power(b, minus)])])])
    case let .function(s, a):
        let h: Expr
        switch s { case "sin":
            h = try fn("cos", a)
        case "cos":
            h = try mul([minus, fn("sin", a)])
        case "tan":
            h = try power(fn("cos", a), num(-2))
        case "exp":
            h = f
        default:
            h = try power(a, minus) }
        return try mul([h, derivative(a, v)])
    }
}
func substitute(_ f: Expr, _ m: [String: Expr]) throws -> Expr {
    switch f { case .number:
        return f
    case let .variable(s):
        return m[s] ?? f
    case let .sum(a):
        return try add(a.map { try substitute($0, m) })
    case let .product(a):
        return try mul(a.map { try substitute($0, m) })
    case let .power(b, x):
        return try power(substitute(b, m), substitute(x, m))
    case let .function(s, a):
        return try fn(s, substitute(a, m)) }
}
func terms(_ f: Expr) -> [Expr] {
    if case let .sum(a) = f {
        return a
    }
    return [f]
}
func distribute(_ a: Expr, _ b: Expr) throws -> Expr {
    var r: [Expr] = []
    for x in terms(a) {
        for y in terms(b) {
            r.append(try mul([x, y]))
        }
    }
    return try add(r)
}
func expand(_ f: Expr) throws -> Expr {
    switch f { case .number, .variable:
        return f
    case let .function(s, a):
        return try fn(s, expand(a))
    case let .sum(a):
        return try add(a.map { try expand($0) })
    case let .product(a):
        var r = try expand(a[0])
        for t in a.dropFirst() {
            r = try distribute(r, expand(t))
        }
        return r
    case let .power(b, x):
        let eb = try expand(b), ex = try expand(x)
        if case .sum = eb, integer(ex), case let .number(q) = ex, q.p > 0 {
            var r = eb
            for _ in 1..<q.p {
                r = try distribute(r, eb)
            }
            return r
        }
        return try power(eb, ex) }
}
func numeric(_ f: Expr) throws -> Double {
    switch f {
    case let .number(q):
        return Double(q.p) / Double(q.q)
    case let .sum(a):
        return try a.reduce(0.0) { try $0 + numeric($1) }
    case let .product(a):
        return try a.reduce(1.0) { try $0 * numeric($1) }
    case let .power(b, x):
        let u = try numeric(b), z = try numeric(x)
        let integral = x.kind == 5 ? integer(x) : z == z.rounded(.towardZero)
        if u < 0 && !integral {
            try fail("domain error")
        }
        return x == half ? sqrt(u) : pow(u, z)
    case let .function(s, a):
        let value = try numeric(a)
        switch s { case "sin":
            return sin(value)
        case "cos":
            return cos(value)
        case "tan":
            return tan(value)
        case "exp":
            return exp(value)
        default:
            if value <= 0 {
                try fail("domain error")
            }
            return log(value) }
    case .variable:
        preconditionFailure("unassigned variable")
    }
}
func atomic(_ f: Expr) -> Bool {
    if f.kind == 0 || f.kind == 4 {
        return true
    }
    if case let .number(q) = f {
        return q.q == 1 && q.p >= 0
    }
    if case let .power(_, x) = f {
        return x == half
    }
    return false
}
func atom(_ f: Expr) -> String {
    atomic(f) ? show(f) : "(\(show(f)))"
}
func showPower(_ b: Expr, _ x: Expr) -> String {
    x == half ? "sqrt(\(show(b)))" : "\(atom(b))^\(atom(x))"
}
func factor(_ f: Expr) -> String {
    if case .sum = f {
        return "(\(show(f)))"
    }
    if case let .power(b, x) = f {
        return showPower(b, x)
    }
    return show(f)
}
func quotient(_ c: Rational, _ a: [Expr]) -> String {
    var top: [String] = abs(c.p) == 1 ? [] : [String(abs(c.p))], bottom: [String] = c.q == 1 ? [] : [String(c.q)]
    for f in a {
        if case let .power(b, .number(q)) = f, q.p < 0 {
            let r = Expr.number(-q)
            bottom.append(r == one ? factor(b) : showPower(b, r))
        } else {
            top.append(factor(f))
        }
    }
    var s = top.isEmpty ? "1" : top.joined(separator: "*")
    if bottom.count == 1 {
        s += "/" + bottom[0]
    } else if !bottom.isEmpty {
        s += "/(" + bottom.joined(separator: "*") + ")"
    }
    return (c.p < 0 ? "-" : "") + s
}
func show(_ f: Expr) -> String {
    switch f { case let .number(q):
        return String(q.p) + (q.q == 1 ? "" : "/\(q.q)")
    case let .variable(s):
        return s
    case let .function(s, a):
        return "\(s)(\(show(a)))"
    case let .power(b, x):
        return negative(f) ? quotient(Rational(1), [f]) : showPower(b, x)
    case .product:
        let (c, a) = coefficient(f)
        return quotient(c, a)
    case let .sum(a):
        return a.map(show).dropFirst()
            .reduce(show(a[0])) { $0 + ($1.hasPrefix("-") ? " - " + String($1.dropFirst()) : " + " + $1) }}
}
indirect enum Syntax { case value(Expr), operation(String, [Syntax]) }
final class Parser {
    var tokens: [String] = [], position = 0
    let names: [String: Expr]
    init(_ text: String, _ names: [String: Expr]) throws {
        self.names = names
        let bytes = Array(text.utf8)
        var p = 0
        while p < bytes.count {
            let c = bytes[p]
            if c == 32 {
                p += 1
                continue
            }
            let start = p
            p += 1
            if c >= 48 && c <= 57 {
                while p < bytes.count && bytes[p] >= 48 && bytes[p] <= 57 {
                    p += 1
                }
            } else if c >= 97 && c <=
                122
            {
                while p < bytes
                    .count && ((bytes[p] >= 97 && bytes[p] <= 122) || (bytes[p] >= 48 && bytes[p] <= 57))
                {
                    p += 1
                }
            } else if c >= 65 && c <=
                90
            {
                while p < bytes
                    .count && ((bytes[p] >= 65 && bytes[p] <= 90) || (bytes[p] >= 48 && bytes[p] <= 57))
                {
                    p += 1
                }
            } else if !Array("+-*/^()".utf8).contains(c) {
                try fail("invalid character '\(String(UnicodeScalar(c)))'")
            }
            tokens.append(String(decoding: bytes[start..<p], as: UTF8.self))
        }
    }
    func peek() -> String {
        position < tokens.count ? tokens[position] : ""
    }
    func unexpected() throws
        -> Never
    {
        try fail(position == tokens.count ? "unexpected end of expression" : "unexpected '\(peek())'")
    }
    func accept(_ s: String) -> Bool {
        if peek() != s {
            return false
        }
        position += 1
        return true
    }
    func expect(_ s: String) throws {
        if !accept(s) {
            try unexpected()
        }
    }
    func atomTree() throws -> Syntax {
        let t = peek()
        if t.isEmpty {
            try unexpected()
        }
        if accept("(") {
            let a = try expression()
            try expect(")")
            return a
        }
        let c = t.utf8.first!
        if !((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)) {
            try unexpected()
        }
        position += 1
        if c >= 48 && c <= 57 {
            return .value(num(Int64(t)!))
        }
        if c >= 65 && c <= 90 {
            guard let f = names[t]
            else {
                try fail("undefined name '\(t)'")
            }
            return .value(f)
        }
        if !functions.contains(t) {
            return .value(.variable(t))
        }
        try expect("(")
        let a = try expression()
        try expect(")")
        return .operation(t, [a])
    }
    func unary() throws -> Syntax {
        if accept("-") {
            return .operation("neg", [try unary()])
        }
        let a = try atomTree()
        return accept("^") ? .operation("^", [a, try unary()]) : a
    }
    func term() throws -> Syntax {
        var a = try unary()
        while ["*", "/"].contains(peek()) {
            let op = tokens[position]
            position += 1
            a = .operation(op, [a, try unary()])
        }
        return a
    }
    func expression() throws -> Syntax {
        var a = try term()
        while ["+", "-"].contains(peek()) {
            let op = tokens[position]
            position += 1
            a = .operation(op, [a, try term()])
        }
        return a
    }
    func evaluate(_ t: Syntax) throws -> Expr {
        switch t { case let .value(f):
            return f
        case let .operation(op, args):
            let a = try args.map { try evaluate($0) }
            switch op { case "+":
                return try add(a)
            case "-":
                return try add([a[0], mul([minus, a[1]])])
            case "*":
                return try mul(a)
            case "/":
                return try mul([a[0], power(a[1], minus)])
            case "^":
                return try power(a[0], a[1])
            case "neg":
                return try mul([minus, a[0]])
            default:
                return try fn(op, a[0]) }}
    }
    func parse() throws -> Expr {
        let t = try expression()
        if position < tokens.count {
            try unexpected()
        }
        return try evaluate(t)
    }
}
func matches(_ s: String, _ pattern: String) -> Bool {
    s.range(
        of: "\\A(?:" + pattern + ")\\z",
        options: .regularExpression
    ) != nil
}
func variable(_ s: String) -> Bool {
    matches(s, "[a-z][a-z0-9]*") && !functions.contains(s)
}
func rationalLiteral(_ s: String) -> Bool {
    matches(s, "-?[0-9]+(?:/[0-9]+)?")
}
func literal(_ s: String) throws -> Expr {
    if !rationalLiteral(s) {
        try fail("invalid number '\(s)'")
    }
    let a = s.split(separator: "/")
    let q = a.count == 1 ? 1 : Int64(a[1])!
    if q == 0 {
        try fail("division by zero")
    }
    return num(Int64(a[0])!, q)
}
let signatures = [
    "SIMPLIFY": "e",
    "EXPAND": "e",
    "DIFF": "ev",
    "DIFFN": "evn",
    "GRAD": "e",
    "HESSIAN": "e",
    "IMPLICIT": "evv",
    "SUBST": "eve",
    "EVAL": "ea",
    "TANGENT": "evc",
    "LIMIT": "evc",
    "TAYLOR": "evcn"
]
func command(_ line: String, _ names: inout [String: Expr]) throws -> [String] {
    let pieces = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init),
        c = pieces[0], arg = pieces.count == 1 ? "" : pieces[1]
    if c == "LET" {
        guard let p = arg.firstIndex(of: "=")
        else {
            try fail("wrong number of arguments")
        }
        let s = arg[..<p].trimmingCharacters(in: .whitespaces)
        if !matches(s, "[A-Z][A-Z0-9]*") {
            try fail("invalid name '\(s)'")
        }
        let f = try Parser(arg[arg.index(after: p)...].trimmingCharacters(in: .whitespaces), names).parse()
        names[s] = f
        return [s + " = " + show(f)]
    }
    guard let sig = signatures[c] else {
        try fail("unknown command \(c)")
    }
    let fields = pieces.count == 1 ? [] : arg.components(separatedBy: ";")
        .map { $0.trimmingCharacters(in: .whitespaces) }
    if c == "EVAL" ? ![1, 2].contains(fields.count) : fields.count != sig
        .count
    {
        try fail("wrong number of arguments")
    }
    var forms = Array(repeating: zero, count: fields.count), n = 0
    for (i, k) in sig.enumerated() {
        if i >= fields.count {
            break
        }
        let s = fields[i]
        switch k { case "e":
            forms[i] = try Parser(s, names).parse()
        case "v":
            if !variable(s) {
                try fail("invalid variable '\(s)'")
            }
        case "n":
            if !matches(s, "[1-8]") {
                try fail("invalid order '\(s)'")
            }
            n = Int(s)!
        case "c":
            forms[i] = try literal(s)
        default:
            break }
    }
    var f = forms[0]
    let v = fields.count > 1 ? fields[1] : ""
    var out: [String] = []
    if c == "SIMPLIFY" {
        return ["simplified: " + show(f)]
    }
    if c == "EXPAND" {
        return ["expanded: " + show(try expand(f))]
    }
    if c == "DIFF" {
        return ["d/d\(v) = " + show(try derivative(f, v))]
    }
    if c == "DIFFN" {
        for k in 1...n {
            f = try derivative(f, v)
            out.append("d^\(k)/d\(v)^\(k) = " + show(f))
        }
        return out
    }
    if c == "GRAD" || c == "HESSIAN" {
        let vs = variables(f).sorted()
        if vs.isEmpty {
            return ["no variables"]
        }
        for i in vs.indices {
            let d = try derivative(f, vs[i])
            if c == "GRAD" {
                out.append("d/d\(vs[i]) = " + show(d))
            } else {
                for j in i..<vs.count {
                    out.append("d2/d\(vs[i])d\(vs[j]) = " + show(try derivative(
                        d,
                        vs[j]
                    )))
                }
            }
        }
        return out
    }
    if c == "IMPLICIT" {
        let w = fields[2]
        if v == w {
            try fail("same variable")
        }
        return ["d\(w)/d\(v) = " + show(try mul([minus, derivative(f, v), power(derivative(f, w), minus)]))]
    }
    if c == "SUBST" {
        return ["substituted: " + show(try substitute(f, [v: forms[2]]))]
    }
    if c == "EVAL" {
        var values: [String: Expr] = [:]
        for word in v.split(separator: " ").map(String.init) {
            let a = word.components(separatedBy: "=")
            if a.count != 2 || !variable(a[0]) || !rationalLiteral(a[1]) {
                try fail("invalid assignment '\(word)'")
            }
            let q = try literal(a[1])
            if values[a[0]] != nil {
                try fail("duplicate variable \(a[0])")
            }
            values[a[0]] = q
        }
        for s in variables(f).sorted() {
            if values[s] == nil {
                try fail("no value for \(s)")
            }
        }
        let r = try substitute(f, values)
        return [r.kind == 5 ? "exact: " + show(r) : String(
            format: "approx: %.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            try numeric(r)
        )]
    }
    let x = forms[2], point = [v: forms[2]]
    guard case let .number(x0) = x else {
        preconditionFailure()
    }
    if c ==
        "TANGENT"
    {
        let m = try substitute(derivative(f, v), point), y = try substitute(f, point), z = Expr.variable(v)
        let t = "tangent: y = " + show(try add([mul([m, z]), y, mul([.number(-x0), m])]))
        if m == zero {
            return [t, "normal: \(v) = " + show(x)]
        }
        let k = try power(m, minus)
        return [t, "normal: y = " + show(try add([mul([minus, k, z]), y, mul([x, k])]))]
    }
    if c == "LIMIT" {
        var top: [Expr] = [], bottom: [Expr] = []
        let factors: [Expr]
        if case let .product(a) = f {
            factors = a
        } else {
            factors = [f]
        }
        for t in factors {
            if case let .power(b, .number(q)) = t,
               q.p < 0
            {
                bottom.append(try power(b, .number(-q)))
            } else {
                top.append(t)
            }
        }
        var g = try mul(top), h = try mul(bottom)
        for k in 0...5 {
            let a = try substitute(g, point), b = try substitute(h, point)
            if b != zero {
                return ["limit: " + show(try mul([a, power(b, minus)]))]
            }
            if a != zero {
                return ["limit: unbounded"]
            }
            if k < 5 {
                g = try derivative(g, v)
                h = try derivative(h, v)
            }
        }
        return ["limit: unknown"]
    }
    var ds = [f], ps: [Expr] = [], fac: Int64 = 1
    for _ in 0..<n {
        ds.append(try derivative(ds.last!, v))
    }
    for k in 0...n {
        if k > 0 {
            fac *= Int64(k)
        }
        let co = try mul([substitute(ds[k], point), num(1, fac)])
        ps.append(try mul([co, power(add([.variable(v), .number(-x0)]), num(Int64(k)))]))
    }
    return ["taylor: " + show(try expand(add(ps)))]
}
var names: [String: Expr] = [:]
let count = Int(readLine()!)!
for _ in 0..<count {
    let line = readLine()!
    do { for s in try command(line, &names) {
        print(s)
    }} catch CommandError
        .message(let s) { print("error: " + s) } catch { fatalError("unexpected error") }
}
