import Foundation

struct Problem: Error {
    let reason: String
}
func fail(_ reason: String) throws -> Never {
    throw Problem(reason: reason)
}
final class Formula {
    let op: String
    let left: Formula?
    let right: Formula?
    init(_ op: String, _ left: Formula? = nil, _ right: Formula? = nil) {
        self.op = op
        self.left = left
        self.right = right
    }
}
func leaf(_ op: String) -> Formula {
    Formula(op)
}
func negation(_ a: Formula) -> Formula {
    Formula("~", a)
}
func binary(_ op: String, _ a: Formula, _ b: Formula) -> Formula {
    Formula(op, a, b)
}
func same(_ a: Formula, _ b: Formula) -> Bool {
    if a === b {
        return true
    }
    if a.op != b.op {
        return false
    }
    guard let x = a.left, let y = b.left else {
        return a.left == nil && b.left == nil
    }
    if !same(x, y) {
        return false
    }
    guard let z = a.right, let w = b.right else {
        return a.right == nil && b.right == nil
    }
    return same(z, w)
}
func precedence(_ op: String) -> Int {
    ["<->": 1, "->": 2, "|": 3, "^": 4, "&": 5, "~": 6][op] ?? 7
}
func notation(_ f: Formula) -> String {
    guard let a = f.left else {
        return f.op
    }
    if f.op == "~" {
        return "~" + (a.right != nil ? "(\(notation(a)))" : notation(a))
    }
    let b = f.right!
    let left = a.right != nil && (precedence(a.op) < precedence(f.op) || a.op == "->" && f.op == "->") ? "(\(notation(a)))" : notation(a)
    let right = b.right != nil && (precedence(b.op) < precedence(f.op) || b.op == f.op && f.op != "->") ? "(\(notation(b)))" : notation(b)
    return "\(left) \(f.op) \(right)"
}
func variables(_ f: Formula) -> Set<Character> {
    guard let a = f.left else {
        return f.op.utf8.first! >= 65 && f.op.utf8.first! <= 90 ? [f.op.first!] : []
    }
    return variables(a).union(f.right.map(variables) ?? [])
}
func evaluate(_ f: Formula, _ vars: [Character], _ row: Int) -> Int {
    guard let a = f.left else {
        if f.op == "0" {
            return 0
        }
        if f.op == "1" {
            return 1
        }
        return row >> (vars.count - 1 - vars.firstIndex(of: f.op.first!)!) & 1
    }
    let x = evaluate(a, vars, row)
    if f.op == "~" {
        return 1 - x
    }
    let y = evaluate(f.right!, vars, row)
    switch f.op {
    case "&":
        return x & y
    case "|":
        return x | y
    case "^":
        return x ^ y
    case "->":
        return (1 - x) | y
    default:
        return x == y ? 1 : 0
    }
}
struct Token {
    let text: String
    let position: Int
}
final class Parser {
    var tokens = [Token]()
    var at = 0
    let end: Int
    let definitions: [String: Formula]
    init(_ text: String, _ start: Int, _ definitions: [String: Formula]) throws {
        end = start + text.utf8.count
        self.definitions = definitions
        let b = Array(text.utf8)
        var i = 0
        while i < b.count {
            if b[i] == 32 {
                i += 1
                continue
            }
            let begin = i
            if i + 2 < b.count && Array(b[i..<i + 3]) == Array("<->".utf8) {
                i += 3
            } else if i + 1 < b.count && Array(b[i..<i + 2]) == Array("->".utf8) {
                i += 2
            } else if b[i] >= 97 && b[i] <= 122 {
                i += 1
                while i < b.count && (b[i] >= 97 && b[i] <= 122 || b[i] >= 48 && b[i] <= 57) {
                    i += 1
                }
            } else if b[i] >= 65 && b[i] <= 90 || Array("01~&^|()".utf8).contains(b[i]) {
                i += 1
            } else {
                try fail("invalid character '\(Character(UnicodeScalar(b[i])))' at \(start + i)")
            }
            tokens.append(Token(text: String(decoding: b[begin..<i], as: UTF8.self), position: start + begin))
        }
    }
    var peek: String {
        at < tokens.count ? tokens[at].text : ""
    }
    func error() throws -> Never {
        try fail(at == tokens.count ? "unexpected end of formula at \(end)" : "unexpected '\(tokens[at].text)' at \(tokens[at].position)")
    }
    func unary() throws -> Formula {
        if peek == "~" {
            at += 1
            return negation(try unary())
        }
        if peek == "(" {
            at += 1
            let f = try expression(1)
            if peek != ")" {
                try error()
            }
            at += 1
            return f
        }
        if at == tokens.count {
            try error()
        }
        let t = tokens[at]
        let c = t.text.utf8.first!
        if c >= 97 && c <= 122 {
            guard let f = definitions[t.text] else {
                try fail("undefined name '\(t.text)' at \(t.position)")
            }
            at += 1
            return f
        }
        if t.text == "0" || t.text == "1" || t.text.count == 1 && c >= 65 && c <= 90 {
            at += 1
            return leaf(t.text)
        }
        try error()
    }
    func expression(_ level: Int) throws -> Formula {
        if level == 6 {
            return try unary()
        }
        var f = try expression(level + 1)
        let op = ["", "<->", "->", "|", "^", "&"][level]
        while peek == op {
            at += 1
            f = binary(op, f, try expression(op == "->" ? level : level + 1))
        }
        return f
    }
    func parse() throws -> Formula {
        let f = try expression(1)
        if at != tokens.count {
            try error()
        }
        return f
    }
}
func negate(_ a: Formula) -> Formula {
    switch a.op {
    case "0":
        return leaf("1")
    case "1":
        return leaf("0")
    case "~":
        return a.left!
    default:
        return negation(a)
    }
}
func simplifyPair(_ op: String, _ a: Formula, _ b: Formula) -> Formula {
    let eq = same(a, b)
    let complementary = a.op == "~" && same(a.left!, b) || b.op == "~" && same(a, b.left!)
    switch op {
    case "&":
        if a.op == "0" || b.op == "0" {
            return leaf("0")
        }
        if a.op == "1" {
            return b
        }
        if b.op == "1" || eq {
            return a
        }
        if complementary {
            return leaf("0")
        }
    case "|":
        if a.op == "1" || b.op == "1" {
            return leaf("1")
        }
        if a.op == "0" {
            return b
        }
        if b.op == "0" || eq {
            return a
        }
        if complementary {
            return leaf("1")
        }
    case "^":
        if a.op == "0" {
            return b
        }
        if b.op == "0" {
            return a
        }
        if a.op == "1" {
            return negate(b)
        }
        if b.op == "1" {
            return negate(a)
        }
        if eq {
            return leaf("0")
        }
        if complementary {
            return leaf("1")
        }
    case "->":
        if a.op == "0" || b.op == "1" {
            return leaf("1")
        }
        if a.op == "1" {
            return b
        }
        if b.op == "0" {
            return negate(a)
        }
        if eq {
            return leaf("1")
        }
        if complementary {
            return b
        }
    default:
        if a.op == "1" {
            return b
        }
        if b.op == "1" {
            return a
        }
        if a.op == "0" {
            return negate(b)
        }
        if b.op == "0" {
            return negate(a)
        }
        if eq {
            return leaf("1")
        }
        if complementary {
            return leaf("0")
        }
    }
    return binary(op, a, b)
}
func simplify(_ f: Formula, _ assignments: [Character: Int] = [:]) -> Formula {
    guard let child = f.left else {
        return assignments[f.op.first!].map {
            leaf(String($0))
        } ?? f
    }
    let a = simplify(child, assignments)
    return f.op == "~" ? negate(a) : simplifyPair(f.op, a, simplify(f.right!, assignments))
}
func dual(_ f: Formula) -> Formula {
    guard let child = f.left else {
        return f.op == "0" ? leaf("1") : f.op == "1" ? leaf("0") : f
    }
    let a = dual(child)
    if f.op == "~" {
        return negation(a)
    }
    let b = dual(f.right!)
    switch f.op {
    case "&":
        return binary("|", a, b)
    case "|":
        return binary("&", a, b)
    case "^":
        return binary("<->", a, b)
    case "<->":
        return binary("^", a, b)
    default:
        return binary("&", negation(a), b)
    }
}
struct NNFKey: Hashable {
    let node: ObjectIdentifier
    let positive: Bool
}
func nnf(_ f: Formula, _ positive: Bool, _ memo: inout [NNFKey: Formula]) -> Formula {
    let key = NNFKey(node: ObjectIdentifier(f), positive: positive)
    if let result = memo[key] {
        return result
    }
    let result: Formula
    if f.left == nil {
        result = positive ? f : f.op == "0" ? leaf("1") : f.op == "1" ? leaf("0") : negation(f)
    } else if f.op == "~" {
        result = nnf(f.left!, !positive, &memo)
    } else {
        let a = f.left!
        let b = f.right!
        if f.op == "&" || f.op == "|" {
            let left = nnf(a, positive, &memo)
            let right = nnf(b, positive, &memo)
            result = binary((f.op == "&") == positive ? "&" : "|", left, right)
        } else if f.op == "->" {
            let left = nnf(a, !positive, &memo)
            let right = nnf(b, positive, &memo)
            result = binary(positive ? "|" : "&", left, right)
        } else {
            let equal = (f.op == "<->") == positive
            let ap = nnf(a, true, &memo)
            let an = nnf(a, false, &memo)
            let bp = nnf(b, equal, &memo)
            let bn = nnf(b, !equal, &memo)
            result = binary("|", binary("&", ap, bp), binary("&", an, bn))
        }
    }
    memo[key] = result
    return result
}
func normalForm(_ f: Formula) -> Formula {
    var memo = [NNFKey: Formula]()
    return nnf(f, true, &memo)
}
func pattern(_ row: Int, _ n: Int) -> String {
    String((0..<n).map {
        row & (1 << (n - 1 - $0)) == 0 ? Character("0") : Character("1")
    })
}
func invert(_ p: String) -> String {
    String(p.map {
        $0 == "0" ? Character("1") : $0 == "1" ? Character("0") : Character("-")
    })
}
func patternKey(_ p: String) -> String {
    String(p.map {
        $0 == "1" ? Character("0") : $0 == "0" ? Character("1") : Character("2")
    })
}
func sortedPatterns(_ ps: [String]) -> [String] {
    ps.sorted {
        patternKey($0) < patternKey($1)
    }
}
func literals(_ p: String) -> Int {
    p.filter {
        $0 != "-"
    }.count
}
func contains(_ p: String, _ row: Int) -> Bool {
    zip(p, pattern(row, p.count)).allSatisfy {
        $0.0 == "-" || $0.0 == $0.1
    }
}
func termText(_ p: String, _ vars: [Character], _ clause: Bool) -> String {
    let parts: [String] = zip(p, vars).compactMap {
        c, v in c == "1" ? String(v) : c == "0" ? "~\(v)" : nil
    }
    return parts.isEmpty ? (clause ? "0" : "1") : parts.joined(separator: clause ? " | " : " & ")
}
func coverText(_ ps: [String], _ vars: [Character], _ clause: Bool) -> String {
    if ps.isEmpty {
        return clause ? "1" : "0"
    }
    return ps.map {
        p in let s = termText(p, vars, clause)
        return clause && ps.count >= 2 && literals(p) >= 2 ? "(\(s))" : s
    }.joined(separator: clause ? " & " : " | ")
}
func coefficients(_ values: [Int]) -> [Int] {
    var c = values
    var bit = 1
    while bit < c.count {
        for s in c.indices where s & bit != 0 {
            c[s] ^= c[s ^ bit]
        }
        bit *= 2
    }
    return c
}
func assignment(_ row: Int, _ vars: [Character]) -> String {
    "{" + zip(vars, pattern(row, vars.count)).map {
        "\($0.0)=\($0.1)"
    }.joined(separator: " ") + "}"
}
func minimize(_ vars: [Character], _ on: [Int], _ dc: [Int], _ pos: Bool) -> [String] {
    var stage = Set((on + dc).map {
        pattern($0, vars.count)
    })
    var primes = [String]()
    var output = [String]()
    var k = 0
    while true {
        let list = Array(stage)
        var used = Set<Int>()
        var next = Set<String>()
        for i in list.indices {
            for j in (i + 1)..<list.count {
                let a = Array(list[i])
                let b = Array(list[j])
                let different = a.indices.filter {
                    a[$0] != b[$0]
                }
                if different.count == 1 {
                    let d = different[0]
                    if a[d] != "-" && b[d] != "-" {
                        var p = a
                        p[d] = "-"
                        next.insert(String(p))
                        used.insert(i)
                        used.insert(j)
                    }
                }
            }
        }
        let added = list.indices.filter {
            !used.contains($0)
        }.map {
            list[$0]
        }
        if !pos {
            output.append("stage \(k): implicants \(stage.count) primes \(added.count)")
        }
        primes += added
        if next.isEmpty {
            break
        }
        stage = next
        k += 1
    }
    let targets = sortedPatterns(primes.filter {
        p in on.contains {
            contains(p, $0)
        }
    })
    var essential = Set<Int>()
    for r in on {
        let list = targets.indices.filter {
            contains(targets[$0], r)
        }
        if list.count == 1 {
            essential.insert(list[0])
        }
    }
    let optional = targets.indices.filter {
        !essential.contains($0)
    }
    var best: [String]?
    var bestLiterals = 0

    func earlier(_ a: [String], _ b: [String]) -> Bool {
        a.map(patternKey).lexicographicallyPrecedes(b.map(patternKey))
    }
    for mask in 0..<(1 << optional.count) {
        var chosen = essential
        for i in optional.indices where mask & (1 << i) != 0 {
            chosen.insert(optional[i])
        }
        if let best = best, chosen.count > best.count {
            continue
        }
        if !on.allSatisfy( {
            r in chosen.contains {
                contains(targets[$0], r)
            }
        }) {
            continue
        }
        let ps = sortedPatterns(chosen.map {
            pos ? invert(targets[$0]) : targets[$0]
        })
        let count = ps.reduce(0) {
            $0 + literals($1)
        }
        if best == nil || ps.count < best!.count || ps.count == best!.count && (count < bestLiterals || count == bestLiterals && earlier(ps, best!)) {
            best = ps
            bestLiterals = count
        }
    }
    let cover = best!
    if !pos {
        for (heading, ps) in [("primes", targets), ("essential", essential.sorted().map {
            targets[$0]
        })] {
            output.append("\(heading): " + (ps.isEmpty ? "none" : ps.map {
                termText($0, vars, false)
            }.joined(separator: ", ")))
        }
    }
    output.append("minimal: \(coverText(cover, vars, pos))")
    output.append("\(pos ? "clauses" : "terms") \(cover.count) literals \(bestLiterals)")
    return output
}
struct Clause: Hashable {
    var positive = 0
    var negative = 0
}
func tidy(_ cs: Set<Clause>) -> Set<Clause> {
    Set(cs.filter {
        c in c.positive & c.negative == 0 && !cs.contains {
            e in e != c && e.positive & c.positive == e.positive && e.negative & c.negative == e.negative
        }
    })
}
func clauses(_ f: Formula, _ vars: [Character], _ memo: inout [ObjectIdentifier: Set<Clause>]) -> Set<Clause> {
    let key = ObjectIdentifier(f)
    if let c = memo[key] {
        return c
    }
    let result: Set<Clause>
    if f.op == "1" {
        result = []
    } else if f.op == "0" {
        result = [Clause()]
    } else if f.op == "~" || f.left == nil {
        let bit = 1 << vars.firstIndex(of: f.op == "~" ? f.left!.op.first! : f.op.first!)!
        result = [Clause(positive: f.op == "~" ? 0 : bit, negative: f.op == "~" ? bit : 0)]
    } else {
        let a = clauses(f.left!, vars, &memo)
        let b = clauses(f.right!, vars, &memo)
        if f.op == "&" {
            result = tidy(a.union(b))
        } else {
            var combined = Set<Clause>()
            for x in a {
                for y in b {
                    let c = Clause(positive: x.positive | y.positive, negative: x.negative | y.negative)
                    if c.positive & c.negative == 0 {
                        combined.insert(c)
                    }
                }
            }
            result = tidy(combined)
        }
    }
    memo[key] = result
    return result
}
func clausePatterns(_ cs: Set<Clause>, _ n: Int) -> [String] {
    sortedPatterns(cs.map {
        c in String((0..<n).map {
            i in c.positive & (1 << i) != 0 ? Character("1") : c.negative & (1 << i) != 0 ? Character("0") : Character("-")
        })
    })
}
func validName(_ s: String) -> Bool {
    let b = Array(s.utf8)
    return !b.isEmpty && b.count <= 8 && b[0] >= 97 && b[0] <= 122 && b.allSatisfy {
        $0 >= 97 && $0 <= 122 || $0 >= 48 && $0 <= 57
    }
}
func words(_ s: String) -> [String] {
    s.split(separator: " ").map(String.init)
}
final class Workbench {
    var definitions = [String: Formula]()

    func parse(_ text: String, _ start: Int) throws -> Formula {
        try Parser(text, start, definitions).parse()
    }
    func define(_ name: String, _ f: Formula) -> [String] {
        let heading = definitions[name] == nil ? "defined" : "redefined"
        definitions[name] = f
        return ["\(heading) \(name) = \(notation(f))"]
    }
    func command(_ line: String) throws -> [String] {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let command = parts[0]
        let argument = parts.count == 2 ? parts[1] : ""
        let known: Set<String> = ["DEF", "DEFSUM", "DEL", "LIST", "PRINT", "TABLE", "MINTERMS", "MAXTERMS", "DNF", "CNF", "NNF", "DUAL", "ANF", "SIMPLIFY", "RESTRICT", "COFACTOR", "MINIMIZE", "MINDC", "MINPOS", "KMAP", "SAT", "TAUT", "COUNT", "EQUIV", "IMPLIES", "PROPS", "BDD", "CLAUSES", "DP"]
        if !known.contains(command) {
            try fail("unknown command \(command)")
        }
        if command == "LIST" {
            if parts.count == 2 {
                try fail("unexpected argument")
            }
            return ["names: \(definitions.count)"] + definitions.keys.sorted().map {
                "\($0) = \(notation(definitions[$0]!))"
            }
        }
        if parts.count == 1 {
            try fail("missing argument")
        }
        if command == "DEL" {
            if !validName(argument) {
                try fail("invalid name '\(argument)'")
            }
            if definitions.removeValue(forKey: argument) == nil {
                try fail("undefined name '\(argument)'")
            }
            return ["deleted \(argument)"]
        }
        if command == "DEF" {
            guard let at = argument.firstIndex(of: " ") else {
                try fail("missing argument")
            }
            let name = String(argument[..<at])
            if !validName(name) {
                try fail("invalid name '\(name)'")
            }
            return define(name, try parse(String(argument[argument.index(after: at)...]), name.count + 6))
        }
        if command == "DEFSUM" {
            guard let at = argument.firstIndex(of: ";") else {
                try fail("missing ';'")
            }
            let front = words(String(argument[..<at]))
            if front.isEmpty {
                try fail("missing argument")
            }
            let name = front[0]
            if !validName(name) {
                try fail("invalid name '\(name)'")
            }
            let list = Array(front.dropFirst())
            if list.isEmpty || list.contains(where: {
                $0.count != 1 || $0.utf8.first! < 65 || $0.utf8.first! > 90
            }) || zip(list, list.dropFirst()).contains(where: {
                $0.0 >= $0.1
            }) {
                try fail("bad variable list")
            }
            if list.count >= 9 {
                try fail("too many variables: \(list.count)")
            }
            var terms = [Formula]()
            var previous = -1
            for word in words(String(argument[argument.index(after: at)...])) {
                if !word.utf8.allSatisfy( {
                    $0 >= 48 && $0 <= 57
                }) || word.count > 1 && word.hasPrefix("0") {
                    try fail("bad minterm '\(word)'")
                }
                let row = Int(word)!
                if row >= 1 << list.count || row <= previous {
                    try fail("bad minterm '\(word)'")
                }
                previous = row
                let nodes = zip(list, pattern(row, list.count)).map {
                    v, n in n == "1" ? leaf(v) : negation(leaf(v))
                }
                terms.append(nodes.dropFirst().reduce(nodes[0]) {
                    binary("&", $0, $1)
                })
            }
            return define(name, terms.isEmpty ? leaf("0") : terms.dropFirst().reduce(terms[0]) {
                binary("|", $0, $1)
            })
        }
        let split = ["RESTRICT", "COFACTOR", "MINDC", "EQUIV", "IMPLIES"].contains(command)
        let semicolon = argument.firstIndex(of: ";")
        if split && semicolon == nil {
            try fail("missing ';'")
        }
        let front = split ? String(argument[..<semicolon!]) : argument
        let back = split ? String(argument[argument.index(after: semicolon!)...]) : ""
        let f = try parse(front, command.count + 2)
        let g = ["MINDC", "EQUIV", "IMPLIES"].contains(command) ? try parse(back, command.count + argument.distance(from: argument.startIndex, to: semicolon!) + 3) : nil
        if command == "RESTRICT" || command == "COFACTOR" {
            let list = words(back)
            if command == "RESTRICT" {
                if list.isEmpty {
                    try fail("missing assignment")
                }
                var assignments = [Character: Int]()
                for word in list {
                    let b = Array(word.utf8)
                    if b.count != 3 || b[0] < 65 || b[0] > 90 || b[1] != 61 || ![48, 49].contains(b[2]) {
                        try fail("bad assignment '\(word)'")
                    }
                    let v = Character(UnicodeScalar(b[0]))
                    if assignments[v] != nil {
                        try fail("duplicate variable \(v)")
                    }
                    assignments[v] = Int(b[2] - 48)
                }
                return ["restricted: \(notation(simplify(f, assignments)))"]
            }
            if list.count != 1 || list[0].count != 1 || list[0].utf8.first! < 65 || list[0].utf8.first! > 90 {
                try fail("bad variable")
            }
            let x = list[0].first!
            let high = simplify(f, [x: 1])
            let low = simplify(f, [x: 0])
            return ["cofactor \(x)=1: \(notation(high))", "cofactor \(x)=0: \(notation(low))", "difference: \(notation(simplifyPair("^", high, low)))"]
        }
        let vars = variables(f).union(g.map(variables) ?? []).sorted()
        if !["PRINT", "NNF", "DUAL", "SIMPLIFY", "CLAUSES", "DP"].contains(command) && vars.count >= 9 {
            try fail("too many variables: \(vars.count)")
        }
        switch command {
        case "PRINT":

            func measure(_ f: Formula) -> (Int, Int) {
                let a = f.left.map(measure) ?? (0, 0)
                let b = f.right.map(measure) ?? (0, 0)
                return (1 + a.0 + b.0, 1 + max(a.1, b.1))
            }
            let (size, depth) = measure(f)
            return ["formula: \(notation(f))", "variables: " + (vars.isEmpty ? "none" : vars.map(String.init).joined(separator: " ")), "size \(size) depth \(depth)"]
        case "NNF":
            return ["nnf: \(notation(normalForm(f)))"]
        case "DUAL":
            return ["dual: \(notation(dual(f)))"]
        case "SIMPLIFY":
            return ["simplified: \(notation(simplify(f)))"]
        case "CLAUSES", "DP":
            let normal = normalForm(f)
            var memo = [ObjectIdentifier: Set<Clause>]()
            var cs = clauses(normal, vars, &memo)
            if command == "CLAUSES" {
                return ["clauses: \(coverText(clausePatterns(cs, vars.count), vars, true))"]
            }
            var output = ["start: clauses \(cs.count)"]
            for i in vars.indices {
                if cs.isEmpty || cs.contains(Clause()) {
                    break
                }
                let bit = 1 << i
                let p = cs.filter {
                    $0.positive & bit != 0
                }
                let q = cs.filter {
                    $0.negative & bit != 0
                }
                var resolvents = Set<Clause>()
                for a in p {
                    for b in q {
                        let c = Clause(positive: (a.positive | b.positive) & ~bit, negative: (a.negative | b.negative) & ~bit)
                        if c.positive & c.negative == 0 {
                            resolvents.insert(c)
                        }
                    }
                }
                cs = tidy(Set(cs.filter {
                    ($0.positive | $0.negative) & bit == 0
                }).union(resolvents))
                output.append("eliminate \(vars[i]): resolvents \(resolvents.count) clauses \(cs.count)")
            }
            output.append("result: \(cs.contains(Clause()) ? "unsatisfiable" : "satisfiable")")
            return output
        default:
            break
        }
        let values = (0..<(1 << vars.count)).map {
            evaluate(f, vars, $0)
        }
        let other = g.map {
            g in values.indices.map {
                evaluate(g, vars, $0)
            }
        } ?? []
        let models = values.indices.filter {
            values[$0] == 1
        }
        let falseRows = values.indices.filter {
            values[$0] == 0
        }
        switch command {
        case "TABLE":
            return [vars.map {
                "\($0) "
            }.joined() + "| F"] + values.indices.map {
                r in pattern(r, vars.count).map {
                    "\($0) "
                }.joined() + "| \(values[r])"
            }
        case "MINTERMS", "MAXTERMS":
            let rows = command == "MINTERMS" ? models : falseRows
            return ["\(command.lowercased()): " + (rows.isEmpty ? "none" : rows.map(String.init).joined(separator: " "))]
        case "DNF", "CNF":
            let pos = command == "CNF"
            let ps = (pos ? falseRows : models).map {
                r in let p = pattern(r, vars.count)
                return pos ? invert(p) : p
            }
            return ["\(command.lowercased()): \(coverText(ps, vars, pos))"]
        case "ANF":
            let c = coefficients(values)
            let ps = c.indices.filter {
                c[$0] == 1
            }.map {
                pattern($0, vars.count).replacingOccurrences(of: "0", with: "-")
            }.sorted {
                literals($0) == literals($1) ? patternKey($0) < patternKey($1) : literals($0) < literals($1)
            }
            return ["anf: " + (ps.isEmpty ? "0" : ps.map {
                termText($0, vars, false)
            }.joined(separator: " ^ "))]
        case "SAT":
            return [models.first.map {
                "satisfiable: \(assignment($0, vars))"
            } ?? "unsatisfiable"]
        case "TAUT":
            return [falseRows.first.map {
                "not a tautology: \(assignment($0, vars))"
            } ?? "tautology"]
        case "COUNT":
            return ["models: \(models.count) of \(values.count)"]
        case "EQUIV", "IMPLIES":
            let r = values.indices.first {
                command == "EQUIV" ? values[$0] != other[$0] : values[$0] == 1 && other[$0] == 0
            }
            guard let r = r else {
                return [command == "EQUIV" ? "equivalent" : "implies"]
            }
            return [command == "EQUIV" ? "not equivalent: \(assignment(r, vars)) f=\(values[r]) g=\(other[r])" : "does not imply: \(assignment(r, vars))"]
        case "MINIMIZE", "MINDC", "MINPOS":
            let on = values.indices.filter {
                command == "MINPOS" ? values[$0] == 0 : values[$0] == 1 && (other.isEmpty || other[$0] == 0)
            }
            return minimize(vars, on, other.indices.filter {
                other[$0] == 1
            },
            command == "MINPOS")
        case "PROPS":
            let depends = vars.indices.filter {
                i in values.indices.contains {
                    values[$0] != values[$0 ^ (1 << (vars.count - 1 - i))]
                }
            }.map {
                vars[$0]
            }
            let c = coefficients(values)
            var byWeight = [Int: Int]()
            var symmetric = true
            for r in values.indices {
                if let old = byWeight[r.nonzeroBitCount], old != values[r] {
                    symmetric = false
                }
                byWeight[r.nonzeroBitCount] = values[r]
            }
            let props: [(String, Bool)] = [("zero-preserving", values[0] == 0), ("one-preserving", values.last! == 1), ("self-dual", values.indices.allSatisfy {
                values[$0] != values[values.count - 1 - $0]
            }), ("monotone", values.indices.allSatisfy {
                r in vars.indices.allSatisfy {
                    i in r & (1 << i) != 0 || values[r] <= values[r | (1 << i)]
                }
            }), ("linear", c.indices.allSatisfy {
                c[$0] == 0 || $0.nonzeroBitCount <= 1
            }), ("symmetric", symmetric)]
            return ["depends: " + (depends.isEmpty ? "none" : depends.map(String.init).joined(separator: " "))] + props.map {
                "\($0.0): \($0.1 ? "yes" : "no")"
            }
        case "KMAP":
            if vars.count < 2 || vars.count > 4 {
                try fail("kmap needs 2 to 4 variables")
            }
            let p = vars.count / 2
            let q = vars.count - p
            var output = [String(vars[..<p]) + "\\" + String(vars[p...]) + (0..<(1 << q)).map {
                " " + pattern($0 ^ ($0 / 2), q)
            }.joined()]
            for i in 0..<(1 << p) {
                let r = i ^ (i / 2)
                output.append(pattern(r, p) + String(repeating: " ", count: q + 1) + (0..<(1 << q)).map {
                    j in String(repeating: " ", count: q) + String(values[(r << q) | (j ^ (j / 2))])
                }.joined())
            }
            return output
        case "BDD":
            var nodes = [(Int, Int, Int)]()

            func build(_ level: Int, _ list: [Int]) -> Int {
                if list.count == 1 {
                    return list[0]
                }
                let lo = build(level + 1, Array(list.prefix(list.count / 2)))
                let hi = build(level + 1, Array(list.suffix(list.count / 2)))
                if lo == hi {
                    return lo
                }
                if let i = nodes.firstIndex(where: {
                    $0.0 == level && $0.1 == lo && $0.2 == hi
                }) {
                    return i + 2
                }
                nodes.append((level, lo, hi))
                return nodes.count + 1
            }
            let root = build(0, values)
            var paths = [0, 1]
            var output = ["nodes: \(nodes.count)"]
            for (i, node) in nodes.enumerated() {
                let (v, lo, hi) = node
                output.append("\(i + 2) = ite(\(vars[v]), \(hi), \(lo))")
                paths.append(paths[lo] + paths[hi])
            }
            output += ["root: \(root)", "paths: \(paths[root])"]
            return output
        default:
            return []
        }
    }
}
let count = Int(readLine()!)!
let workbench = Workbench()
for _ in 0..<count {
    do {
        for line in try workbench.command(readLine()!) {
            print(line)
        }
    } catch let e as Problem {
        print("error: \(e.reason)")
    } catch {
    }
}
