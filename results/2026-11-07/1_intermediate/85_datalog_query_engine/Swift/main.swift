import Foundation
let reserved: Set<String> = ["not", "mod", "count", "sum", "min", "max", "retract", "dump", "why", "forget", "listing", "strata", "stats", "check", "predicates", "undo", "halt"]

struct Problem: Error {
    let reason: String
}
func fail(_ reason: String) throws -> Never {
    throw Problem(reason: reason)
}
enum Value: Hashable, Comparable {
    case integer(Int), symbol(String)
    static func < (a: Value, b: Value) -> Bool {
        switch (a, b) {
        case let (.integer(x), .integer(y)):
            return x < y
        case (.integer, .symbol):
            return true
        case (.symbol, .integer):
            return false
        case let (.symbol(x), .symbol(y)):
            return x < y
        }
    }
    var text: String {
        switch self {
        case let .integer(n):
            return String(n)
        case let .symbol(s):
            let b = Array(s.utf8)
            if let first = b.first, first >= 97 && first <= 122,
            b.allSatisfy(wordCharacter), !reserved.contains(s) {
                return s
            }
            return "\"\(s)\""
        }
    }
}
typealias Tuple = [Value]

typealias Database = [String: Set<Tuple>]

typealias Derivations = [String: [Tuple: Derivation]]

struct Environment: Hashable {
    var values = [String: Value]()

    func hash(into hasher: inout Hasher) {
        for n in values.keys.sorted() {
            hasher.combine(n)
            hasher.combine(values[n]!)
        }
    }
}
enum Term {
    case constant(Value), variable(String), anonymous

    func text(_ env: Environment? = nil) -> String {
        switch self {
        case let .constant(v):
            return v.text
        case let .variable(n):
            return env?.values[n]?.text ?? n
        case .anonymous:
            return "_"
        }
    }
    func value(_ env: Environment) -> Value? {
        switch self {
        case let .constant(v):
            return v
        case let .variable(n):
            return env.values[n]
        case .anonymous:
            return nil
        }
    }
    var variables: [String] {
        if case let .variable(n) = self {
            return [n]
        }
        return []
    }
    var isAnonymous: Bool {
        if case .anonymous = self {
            return true
        }
        return false
    }
}
indirect enum Expression {
    case term(Term), parentheses(Expression), operation(String, Expression, Expression)

    func text(_ env: Environment? = nil) -> String {
        switch self {
        case let .term(t):
            return t.text(env)
        case let .parentheses(e):
            return "(\(e.text(env)))"
        case let .operation(op, a, b):
            return "\(a.text(env)) \(op) \(b.text(env))"
        }
    }
    var variables: [String] {
        switch self {
        case let .term(t):
            return t.variables
        case let .parentheses(e):
            return e.variables
        case let .operation(_, a, b):
            return a.variables + b.variables
        }
    }
    var anonymous: Bool {
        switch self {
        case let .term(t):
            return t.isAnonymous
        case let .parentheses(e):
            return e.anonymous
        case let .operation(_, a, b):
            return a.anonymous || b.anonymous
        }
    }
    func value(_ env: Environment) -> Value? {
        switch self {
        case let .term(t):
            return t.value(env)
        case let .parentheses(e):
            return e.value(env)
        case let .operation(op, a, b):
            guard case let .integer(x)? = a.value(env), case let .integer(y)? = b.value(env) else {
                return nil
            }
            switch op {
            case "+":
                return .integer(x + y)
            case "-":
                return .integer(x - y)
            case "*":
                return .integer(x * y)
            default:
                if y == 0 {
                    return nil
                }
                let q = x / y - (x % y != 0 && (x < 0) != (y < 0) ? 1 : 0)
                return .integer(op == "/" ? q : x - y * q)
            }
        }
    }
}
struct Atom {
    let name: String
    let terms: [Term]

    func text(_ env: Environment? = nil) -> String {
        name + (terms.isEmpty ? "" : "(" + terms.map {
            $0.text(env)
        }.joined(separator: ", ") + ")")
    }
    var variables: [String] {
        terms.flatMap(\.variables)
    }
    func tuple(_ env: Environment) -> Tuple {
        terms.map {
            $0.value(env)!
        }
    }
    func matching(_ tuple: Tuple, _ env: Environment) -> Environment? {
        var result = env
        for (term, value) in zip(terms, tuple) {
            switch term {
            case let .constant(v):
                if v != value {
                    return nil
                }
            case let .variable(n):
                if let old = result.values[n], old != value {
                    return nil
                }
                result.values[n] = value
            case .anonymous:
                break
            }
        }
        return result
    }
}
func tupleText(_ name: String, _ tuple: Tuple) -> String {
    Atom(name: name, terms: tuple.map(Term.constant)).text()
}
enum Literal {
    case atom(Atom, Bool), comparison(String, Expression, Expression)
    var positive: Bool {
        if case .atom(_, false) = self {
            return true
        }
        return false
    }
    var atomValue: Atom? {
        if case let .atom(a, _) = self {
            return a
        }
        return nil
    }
    var variables: [String] {
        switch self {
        case let .atom(a, _):
            return a.variables
        case let .comparison(_, a, b):
            return a.variables + b.variables
        }
    }
    func text(_ env: Environment? = nil) -> String {
        switch self {
        case let .atom(a, negative):
            return (negative ? "not " : "") + a.text(env)
        case let .comparison(op, a, b):
            return "\(a.text(env)) \(op) \(b.text(env))"
        }
    }
    func holds(_ env: Environment, _ data: Database) -> Bool {
        switch self {
        case let .atom(a, negative):
            return !negative || !data[a.name]!.contains {
                a.matching($0, env) != nil
            }
        case let .comparison(op, a, b):
            guard let x = a.value(env), let y = b.value(env) else {
                return false
            }
            if op == "=" {
                return x == y
            }
            if op == "!=" {
                return x != y
            }
            guard case let .integer(xi) = x, case let .integer(yi) = y else {
                return false
            }
            switch op {
            case "<":
                return xi < yi
            case "<=":
                return xi <= yi
            case ">":
                return xi > yi
            default:
                return xi >= yi
            }
        }
    }
}
struct Rule {
    var number = 0
    var head: Atom?
    let body: [Literal]
    var text: String {
        (head.map {
            $0.text() + " "
        } ?? "") + ":- " + body.map {
            $0.text()
        }.joined(separator: ", ") + "."
    }
    var variables: [String] {
        (head?.variables ?? []) + body.flatMap(\.variables)
    }
    var atoms: [Atom] {
        (head.map {
            [$0]
        } ?? []) + body.compactMap(\.atomValue)
    }
}
struct Token {
    let kind: String
    let text: String
}
func wordCharacter(_ c: UInt8) -> Bool {
    c >= 97 && c <= 122 || c >= 65 && c <= 90 || c >= 48 && c <= 57 || c == 95
}
func lex(_ line: String) throws -> [Token] {
    let b = Array(line.utf8)
    var at = 0
    var result = [Token]()
    while at < b.count {
        if b[at] == 32 {
            at += 1
            continue
        }
        if b[at] == 37 {
            break
        }
        let start = at
        let kind: String
        if b[at] == 34 {
            at += 1
            while at < b.count && b[at] != 34 {
                at += 1
            }
            if at == b.count {
                try fail("unterminated string")
            }
            at += 1
            kind = "string"
        } else if at + 1 < b.count && [":-", "?-", "!=", "<=", ">="].contains(String(decoding: b[at..<at + 2], as: UTF8.self)) {
            at += 2
            kind = String(decoding: b[start..<at], as: UTF8.self)
        } else if Array("(),.:=<>+-*/".utf8).contains(b[at]) {
            at += 1
            kind = String(UnicodeScalar(b[start]))
        } else if wordCharacter(b[at]) {
            at += 1
            while at < b.count && wordCharacter(b[at]) {
                at += 1
            }
            let word = String(decoding: b[start..<at], as: UTF8.self)
            if b[start] >= 97 && b[start] <= 122 {
                kind = reserved.contains(word) ? word : "name"
            } else if b[start] >= 65 && b[start] <= 90 {
                kind = "variable"
            } else if word == "_" {
                kind = "anonymous"
            } else if word.utf8.allSatisfy( {
                $0 >= 48 && $0 <= 57
            }) {
                if Int(word)! > 1000000000 {
                    try fail("integer out of range '\(word)'")
                }
                kind = "integer"
            } else {
                try fail("bad token '\(word)'")
            }
        } else {
            try fail("bad character '\(Character(UnicodeScalar(b[at])))'")
        }
        result.append(Token(kind: kind, text: String(decoding: b[start..<at], as: UTF8.self)))
    }
    return result
}
struct Statement {
    let kind: String
    var rule: Rule?
    var atom: Atom?
    var aggregate = ""
    var argument = ""
}
final class Parser {
    let tokens: [Token]
    var at = 0
    init(_ tokens: [Token]) {
        self.tokens = tokens
    }
    var kind: String {
        at < tokens.count ? tokens[at].kind : "end"
    }
    func error() throws -> Never {
        try fail(at == tokens.count ? "syntax error at end of line" : "syntax error at '\(tokens[at].text)'")
    }
    @discardableResult
    func take(_ expected: String) throws -> Token {
        if kind != expected {
            try error()
        }
        let t = tokens[at]
        at += 1
        return t
    }
    func term() throws -> Term {
        switch kind {
        case "name":
            return .constant(.symbol(try take("name").text))
        case "string":
            return .constant(.symbol(String(try take("string").text.dropFirst().dropLast())))
        case "integer":
            return .constant(.integer(Int(try take("integer").text)!))
        case "-":
            try take("-")
            return .constant(.integer(-Int(try take("integer").text)!))
        case "variable":
            return .variable(try take("variable").text)
        case "anonymous":
            try take("anonymous")
            return .anonymous
        default:
            try error()
        }
    }
    func atom() throws -> Atom {
        let name = try take("name").text
        var terms = [Term]()
        if kind == "(" {
            try take("(")
            terms.append(try term())
            while kind == "," {
                try take(",")
                terms.append(try term())
            }
            try take(")")
        }
        return Atom(name: name, terms: terms)
    }
    func factor() throws -> Expression {
        if kind == "(" {
            try take("(")
            let e = try expression()
            try take(")")
            return .parentheses(e)
        }
        return .term(try term())
    }
    func product() throws -> Expression {
        var e = try factor()
        while ["*", "/", "mod"].contains(kind) {
            let op = tokens[at].text
            at += 1
            e = .operation(op, e, try factor())
        }
        return e
    }
    func expression() throws -> Expression {
        var e = try product()
        while ["+", "-"].contains(kind) {
            let op = tokens[at].text
            at += 1
            e = .operation(op, e, try product())
        }
        return e
    }
    func literal() throws -> Literal {
        if kind == "not" {
            try take("not")
            return .atom(try atom(), true)
        }
        let following = at + 1 < tokens.count ? tokens[at + 1].kind : "end"
        if kind == "name" && !["=", "!=", "<", "<=", ">", ">=", "+", "-", "*", "/", "mod"].contains(following) {
            return .atom(try atom(), false)
        }
        let a = try expression()
        if !["=", "!=", "<", "<=", ">", ">="].contains(kind) {
            try error()
        }
        let op = tokens[at].text
        at += 1
        return .comparison(op, a, try expression())
    }
    func body() throws -> [Literal] {
        var result = [try literal()]
        while kind == "," {
            try take(",")
            result.append(try literal())
        }
        return result
    }
    func statement() throws -> Statement {
        let result: Statement
        switch kind {
        case "name":
            let head = try atom()
            var literals = [Literal]()
            if kind == ":-" {
                try take(":-")
                literals = try body()
            }
            result = Statement(kind: "clause", rule: Rule(head: head, body: literals))
        case ":-":
            try take(":-")
            result = Statement(kind: "clause", rule: Rule(body: try body()))
        case "?-":
            try take("?-")
            var aggregate = ""
            var variable = ""
            if ["count", "sum", "min", "max"].contains(kind) {
                aggregate = tokens[at].text
                at += 1
                if aggregate != "count" {
                    variable = try take("variable").text
                    try take(":")
                }
            }
            result = Statement(kind: "query", rule: Rule(body: try body()), aggregate: aggregate, argument: variable)
        case "retract", "why":
            let command = tokens[at].text
            at += 1
            result = Statement(kind: command, atom: try atom())
        case "dump", "forget", "listing", "strata", "stats", "check", "predicates", "undo", "halt":
            let command = tokens[at].text
            at += 1
            var argument = ""
            if command == "dump" {
                argument = try take("name").text
            } else if command == "forget" {
                argument = try take("integer").text
            } else if command == "listing" && kind == "name" {
                argument = try take("name").text
            }
            result = Statement(kind: command, argument: argument)
        default:
            try error()
        }
        try take(".")
        if kind != "end" {
            try error()
        }
        return result
    }
}
struct State {
    var predicates = [String: Int]()
    var facts = Database()
    var rules = [Rule]()
}
func unique(_ names: [String]) -> [String] {
    var seen = Set<String>()
    return names.filter {
        seen.insert($0).inserted
    }
}
func safety(_ rule: Rule, _ aggregate: String = "") throws {
    if rule.head?.terms.contains(where: \.isAnonymous) == true {
        try fail("anonymous variable in head")
    }
    for l in rule.body {
        if case let .comparison(_, a, b) = l, a.anonymous || b.anonymous {
            try fail("anonymous variable in comparison")
        }
    }
    let bound = Set(rule.body.filter(\.positive).flatMap(\.variables))
    let required = (rule.head?.variables ?? (aggregate.isEmpty ? [] : [aggregate])) + rule.body.filter {
        !$0.positive
    }.flatMap(\.variables)
    for n in required where !bound.contains(n) {
        try fail("unsafe variable \(n)")
    }
}
func strata(_ state: State) -> [String: Int]? {
    var result = Dictionary(uniqueKeysWithValues: state.predicates.keys.map {
        ($0, 0)
    })
    if result.isEmpty {
        return result
    }
    for _ in 0..<result.count {
        var changed = false
        for r in state.rules {
            guard let h = r.head else {
                continue
            }
            for l in r.body {
                if case let .atom(a, negative) = l {
                    let value = result[a.name]! + (negative ? 1 : 0)
                    if value > result[h.name]! {
                        result[h.name] = value
                        changed = true
                    }
                }
            }
        }
        if !changed {
            return result
        }
    }
    return nil
}
func solutions(_ body: [Literal], _ data: Database, _ derivations: Derivations, _ before: Int? = nil) -> Set<Environment> {
    var output = Set<Environment>()

    func visit(_ remaining: [Int], _ env: Environment) {
        for l in body where !l.positive {
            if l.variables.allSatisfy( {
                env.values[$0] != nil
            }) && !l.holds(env, data) {
                return
            }
        }
        if remaining.isEmpty {
            output.insert(env)
            return
        }
        var best: Int?
        var candidates = Set<Environment>()
        for i in remaining {
            let a = body[i].atomValue!
            let possible = Set(data[a.name]!.filter {
                before == nil || derivations[a.name]![$0]!.round < before!
            }.compactMap {
                a.matching($0, env)
            })
            if best == nil || possible.count < candidates.count {
                best = i
                candidates = possible
            }
        }
        let rest = remaining.filter {
            $0 != best!
        }
        for next in candidates {
            visit(rest, next)
        }
    }
    visit(body.indices.filter {
        body[$0].positive
    },
    Environment())
    return output
}
struct Derivation {
    let round: Int
    let rule: Int
}
final class Model {
    let state: State
    let levels: [String: Int]
    var data: Database
    var derivations = Derivations()
    var rounds: [Int]
    var additions: [Int]
    init(_ state: State) {
        self.state = state
        let initialLevels = strata(state)!
        let initialRounds = Array(repeating: 0, count: (initialLevels.values.max() ?? 0) + 1)
        levels = initialLevels
        data = state.facts
        rounds = initialRounds
        additions = initialRounds
        for (p, tuples) in state.facts {
            derivations[p] = Dictionary(uniqueKeysWithValues: tuples.map {
                ($0, Derivation(round: 0, rule: 0))
            })
        }
        var serial = 0
        for k in rounds.indices {
            while true {
                var added = [String: [Tuple: Int]]()
                for r in state.rules {
                    guard let h = r.head, levels[h.name] == k else {
                        continue
                    }
                    for env in solutions(r.body, data, derivations) {
                        let tuple = h.tuple(env)
                        if !data[h.name]!.contains(tuple) {
                            added[h.name, default: [:]][tuple] = min(added[h.name]?[tuple] ?? r.number, r.number)
                        }
                    }
                }
                let count = added.values.reduce(0) {
                    $0 + $1.count
                }
                if count == 0 {
                    break
                }
                serial += 1
                rounds[k] += 1
                additions[k] += count
                for (p, tuples) in added {
                    for (tuple, rule) in tuples {
                        data[p]!.insert(tuple)
                        derivations[p]![tuple] = Derivation(round: serial, rule: rule)
                    }
                }
            }
        }
    }
    func answers(_ body: [Literal]) -> ([String], [Tuple]) {
        let names = unique(body.flatMap(\.variables))
        let tuples = Set(solutions(body, data, derivations).map {
            env in names.map {
                env.values[$0]!
            }
        })
        return (names, tuples.sorted {
            $0.lexicographicallyPrecedes($1)
        })
    }
    func proof(_ name: String, _ tuple: Tuple, _ depth: Int, _ output: inout [String]) {
        let round = derivations[name]![tuple]!.round
        let prefix = String(repeating: "  ", count: depth) + tupleText(name, tuple)
        if round == 0 {
            output.append(prefix + " [fact]")
            return
        }
        for r in state.rules where r.head?.name == name {
            let order = unique(r.variables)
            let candidates = solutions(r.body, data, derivations, round).filter {
                r.head!.tuple($0) == tuple
            }
            let chosen = candidates.min {
                a, b in order.map {
                    a.values[$0]!
                }.lexicographicallyPrecedes(order.map {
                    b.values[$0]!
                })
            }
            guard let env = chosen else {
                continue
            }
            output.append("\(prefix) [rule \(r.number)]")
            for l in r.body {
                if l.positive {
                    let a = l.atomValue!
                    let child = data[a.name]!.filter {
                        derivations[a.name]![$0]!.round < round && a.matching($0, env) != nil
                    }.min {
                        $0.lexicographicallyPrecedes($1)
                    }!
                    proof(a.name, child, depth + 1, &output)
                } else {
                    output.append(String(repeating: "  ", count: depth + 1) + l.text(env))
                }
            }
            return
        }
    }
}
func answerText(_ names: [String], _ tuple: Tuple) -> String {
    zip(names, tuple).map {
        "\($0.0) = \($0.1.text)"
    }.joined(separator: ", ")
}
final class Engine {
    var state = State()
    var nextRule = 1
    var history = [(State, Int)]()

    func predicateCheck(_ atoms: [Atom], _ register: Bool) throws -> [String: Int] {
        var predicates = state.predicates
        for a in atoms {
            if let arity = predicates[a.name] {
                if arity != a.terms.count {
                    try fail("arity mismatch for \(a.name): expected \(arity), got \(a.terms.count)")
                }
            } else {
                if !register {
                    try fail("unknown predicate \(a.name)")
                }
                predicates[a.name] = a.terms.count
            }
        }
        return predicates
    }
    func save(_ line: Int) {
        history.append((state, line))
    }
    func clause(_ raw: Rule, _ line: Int) throws -> [String] {
        var rule = raw
        let predicates = try predicateCheck(rule.atoms, true)
        try safety(rule)
        if rule.body.isEmpty {
            let h = rule.head!
            let tuple = h.tuple(Environment())
            if !(state.facts[h.name] ?? []).contains(tuple) {
                save(line)
                state.predicates = predicates
                state.facts[h.name, default: []].insert(tuple)
            }
            return []
        }
        if let old = state.rules.first(where: {
            $0.text == rule.text
        }) {
            try fail("duplicate of rule \(old.number)")
        }
        rule.number = nextRule
        var proposed = state
        proposed.predicates = predicates
        proposed.rules.append(rule)
        for n in predicates.keys where proposed.facts[n] == nil {
            proposed.facts[n] = []
        }
        if strata(proposed) == nil {
            try fail("negative cycle through \(rule.head!.name)")
        }
        save(line)
        state = proposed
        nextRule += 1
        let all = rule.variables
        return unique(all).filter {
            n in all.filter {
                $0 == n
            }.count == 1
        }.map {
            "WARNING line \(line): singleton variable \($0)"
        }
    }
    func execute(_ statement: Statement, _ line: Int) throws -> [String] {
        let kind = statement.kind
        if kind == "clause" {
            return try clause(statement.rule!, line)
        }
        if kind == "query" {
            let rule = statement.rule!
            _ = try predicateCheck(rule.atoms, false)
            try safety(rule, statement.argument)
            let (names, answers) = Model(state).answers(rule.body)
            if statement.aggregate == "count" {
                return [String(answers.count)]
            }
            if ["sum", "min", "max"].contains(statement.aggregate) {
                let i = names.firstIndex(of: statement.argument)!
                if statement.aggregate == "sum" {
                    var total = 0
                    for row in answers {
                        guard case let .integer(n) = row[i] else {
                            try fail("non-integer value in sum")
                        }
                        total += n
                    }
                    return [String(total)]
                }
                let values = answers.map {
                    $0[i]
                }.sorted()
                return [values.isEmpty ? "no answers" : (statement.aggregate == "min" ? values.first! : values.last!).text]
            }
            if names.isEmpty {
                return [answers.isEmpty ? "false." : "true."]
            }
            return answers.map {
                answerText(names, $0)
            } + ["\(answers.count) \(answers.count == 1 ? "answer" : "answers")"]
        }
        if kind == "retract" || kind == "why" {
            let a = statement.atom!
            _ = try predicateCheck([a], false)
            if kind == "retract" {
                let removed = state.facts[a.name]!.filter {
                    a.matching($0, Environment()) != nil
                }
                if removed.isEmpty {
                    try fail("no matching facts")
                }
                save(line)
                state.facts[a.name]!.subtract(removed)
                return ["\(removed.count) \(removed.count == 1 ? "fact" : "facts") retracted"]
            }
            if a.terms.contains(where: {
                t in if case .constant = t {
                    return false
                }
                return true
            }) {
                try fail("why needs a ground atom")
            }
            let model = Model(state)
            let tuple = a.tuple(Environment())
            if !model.data[a.name]!.contains(tuple) {
                return ["false."]
            }
            var output = [String]()
            model.proof(a.name, tuple, 0, &output)
            return output
        }
        return try command(kind, statement.argument, line)
    }
    func command(_ command: String, _ argument: String, _ line: Int) throws -> [String] {
        if command == "undo" {
            guard let (previous, number) = history.popLast() else {
                try fail("nothing to undo")
            }
            state = previous
            return ["undid line \(number)"]
        }
        if command == "forget" {
            let n = Int(argument)!
            guard let i = state.rules.firstIndex(where: {
                $0.number == n
            }) else {
                try fail("no rule \(n)")
            }
            save(line)
            state.rules.remove(at: i)
            return []
        }
        if ["dump", "listing"].contains(command) && !argument.isEmpty && state.predicates[argument] == nil {
            try fail("unknown predicate \(argument)")
        }
        if command == "listing" {
            let out = state.rules.filter {
                argument.isEmpty || $0.head?.name == argument
            }.map {
                "\($0.number): \($0.text)"
            }
            return out.isEmpty ? ["no rules"] : out
        }
        let model = Model(state)
        var output = [String]()
        switch command {
        case "dump":
            let tuples = model.data[argument]!.sorted {
                $0.lexicographicallyPrecedes($1)
            }
            output = tuples.map {
                tupleText(argument, $0) + "."
            }
            output.append("\(tuples.count) \(tuples.count == 1 ? "tuple" : "tuples")")
        case "strata":
            if state.predicates.isEmpty {
                return ["no predicates"]
            }
            let edges = Dictionary(uniqueKeysWithValues: state.predicates.keys.map {
                p in
                (p, state.rules.filter {
                    $0.head?.name == p
                }.flatMap {
                    $0.body.compactMap {
                        $0.atomValue?.name
                    }
                })
            })

            func recursive(_ p: String) -> Bool {
                var visited = Set<String>()

                func visit(_ n: String) -> Bool {
                    if !visited.insert(n).inserted {
                        return false
                    }
                    return edges[n]!.contains {
                        $0 == p || visit($0)
                    }
                }
                return visit(p)
            }
            for k in model.rounds.indices {
                let names = model.levels.keys.filter {
                    model.levels[$0] == k
                }.sorted().map {
                    $0 + (recursive($0) ? "*" : "")
                }
                output.append("stratum \(k): " + names.joined(separator: ", "))
            }
        case "stats":
            let constraints = state.rules.filter {
                $0.head == nil
            }.count
            output.append("facts \(state.facts.values.reduce(0) { $0 + $1.count }), rules \(state.rules.count - constraints), constraints \(constraints), tuples \(model.data.values.reduce(0) { $0 + $1.count })")
            if !state.predicates.isEmpty {
                for k in model.rounds.indices {
                    output.append("stratum \(k): rounds \(model.rounds[k]), new \(model.additions[k])")
                }
            }
            for r in state.rules where r.head != nil {
                let count = model.derivations.values.reduce(0) {
                    $0 + $1.values.filter {
                        $0.rule == r.number
                    }.count
                }
                output.append("rule \(r.number): new \(count)")
            }
        case "predicates":
            if state.predicates.isEmpty {
                return ["no predicates"]
            }
            for p in state.predicates.keys.sorted() {
                output.append("\(p)/\(state.predicates[p]!): facts \(state.facts[p]!.count), rules \(state.rules.filter { $0.head?.name == p }.count), tuples \(model.data[p]!.count)")
            }
        case "check":
            for r in state.rules where r.head == nil {
                let (names, answers) = model.answers(r.body)
                output.append(answers.isEmpty ? "constraint \(r.number): ok" : "constraint \(r.number): \(answers.count) \(answers.count == 1 ? "violation" : "violations")")
                if !names.isEmpty {
                    output += answers.map {
                        "  " + answerText(names, $0)
                    }
                }
            }
            if output.isEmpty {
                output = ["no constraints"]
            }
        default:
            break
        }
        return output
    }
}
let engine = Engine()
var lineNumber = 0
while let line = readLine() {
    lineNumber += 1
    do {
        let tokens = try lex(line)
        if tokens.isEmpty {
            continue
        }
        let statement = try Parser(tokens).statement()
        if statement.kind == "halt" {
            break
        }
        for result in try engine.execute(statement, lineNumber) {
            print(result)
        }
    } catch let e as Problem {
        print("ERROR line \(lineNumber): \(e.reason)")
    } catch {
    }
}
