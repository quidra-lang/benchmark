import Foundation

struct Problem: Error {
    let reason: String
}

func fail(_ reason: String) throws -> Never {
    throw Problem(reason: reason)
}

indirect enum Term: Equatable {
    case variable(String), macro(String), numeral(Int), lambda(String, Term), application(Term, Term), index(Int)
}

func free(_ t: Term) -> Set<String> {
    switch t {
    case let .variable(n):
        return [n]
    case let .lambda(n, b):
        return free(b).subtracting([n])
    case let .application(a, b):
        return free(a).union(free(b))
    default:
        return []
    }
}

func references(_ t: Term) -> [String] {
    switch t {
    case let .macro(n):
        return [n]
    case let .lambda(_, b):
        return references(b)
    case let .application(a, b):
        return references(a) + references(b)
    default:
        return []
    }
}

func printed(_ t: Term, _ end: Bool = true, _ db: Bool = false) -> String {
    switch t {
    case let .variable(n), let .macro(n):
        return n
    case let .numeral(n):
        return "#\(n)"
    case let .index(i):
        return String(i)
    case .lambda:
        var body = t
        var names = [String]()
        while case let .lambda(n, b) = body {
            names.append(n)
            body = b
        }
        let s = db ? String(repeating: "\\", count: names.count) + printed(body, true, true) : "\\" + names.joined(separator: " ") + ". " + printed(body)
        return end ? s : "(\(s))"
    case let .application(a, b):
        let left: String
        if case .lambda = a {
            left = "(\(printed(a, true, db)))"
        } else {
            left = printed(a, false, db)
        }
        let right: String
        if case .application = b {
            right = "(\(printed(b, true, db)))"
        } else {
            right = printed(b, end, db)
        }
        return left + " " + right
    }
}

func sequenceName(_ n: Int) -> String {
    String(UnicodeScalar(97 + n % 26)!) + (n < 26 ? "" : String(n / 26))
}

func canonical(_ t: Term) -> Term {
    let f = free(t)
    var next = 0

    func visit(_ s: Term, _ env: [(String, String)]) -> Term {
        switch s {
        case let .variable(n):
            return .variable(env.last(where: {
                $0.0 == n
            })?.1 ?? n)
        case let .lambda(n, b):
            while f.contains(sequenceName(next)) {
                next += 1
            }
            let fresh = sequenceName(next)
            next += 1
            return .lambda(fresh, visit(b, env + [(n, fresh)]))
        case let .application(a, b):
            return .application(visit(a, env), visit(b, env))
        default:
            return s
        }
    }
    return visit(t, [])
}

func debruijn(_ t: Term, _ env: [String] = []) -> Term {
    switch t {
    case let .variable(n):
        if let i = env.lastIndex(of: n) {
            return .index(env.count - 1 - i)
        }
        return t
    case let .lambda(n, b):
        return .lambda("", debruijn(b, env + [n]))
    case let .application(a, b):
        return .application(debruijn(a, env), debruijn(b, env))
    default:
        return t
    }
}

func substitute(_ t: Term, _ x: String, _ n: Term) -> Term {
    switch t {
    case let .variable(v):
        return v == x ? n : t
    case let .application(a, b):
        return .application(substitute(a, x, n), substitute(b, x, n))
    case let .lambda(y, b):
        let fb = free(b)
        let fnn = free(n)
        if y == x || !fb.contains(x) {
            return t
        }
        if !fnn.contains(y) {
            return .lambda(y, substitute(b, x, n))
        }
        var base = y
        while let c = base.utf8.last, c >= 48 && c <= 57 {
            base.removeLast()
        }
        var i = 1
        while fb.contains(base + String(i)) || fnn.contains(base + String(i)) {
            i += 1
        }
        let z = base + String(i)
        return .lambda(z, substitute(substitute(b, y, .variable(z)), x, n))
    default:
        return t
    }
}

func eta(_ t: Term) -> Term? {
    if case let .lambda(x, .application(a, .variable(v))) = t, x == v, !free(a).contains(x) {
        return a
    }
    return nil
}

func step(_ t: Term, _ strategy: String, _ useEta: Bool) -> (Term, String)? {
    switch t {
    case let .application(a, b):
        if ["NORMAL", "CBN"].contains(strategy), case let .lambda(x, body) = a {
            return (substitute(body, x, b), "beta")
        }
        if let (n, kind) = step(a, strategy, useEta) {
            return (.application(n, b), kind)
        }
        if strategy != "CBN", let (n, kind) = step(b, strategy, useEta) {
            return (.application(a, n), kind)
        }
        if ["APPLICATIVE", "CBV"].contains(strategy), case let .lambda(x, body) = a {
            let value: Bool
            switch b {
            case .variable, .lambda:
                value = true
            default:
                value = false
            }
            if strategy != "CBV" || value {
                return (substitute(body, x, b), "beta")
            }
        }
    case let .lambda(x, b) where ["NORMAL", "APPLICATIVE"].contains(strategy):
        if strategy == "NORMAL" && useEta, let n = eta(t) {
            return (n, "eta")
        }
        if let (n, kind) = step(b, strategy, useEta) {
            return (.lambda(x, n), kind)
        }
        if strategy == "APPLICATIVE" && useEta, let n = eta(t) {
            return (n, "eta")
        }
    default:
        break
    }
    return nil
}

final class Ty {
    let id: Int
    let left: Ty?
    let right: Ty?

    init(_ id: Int = -1, _ left: Ty? = nil, _ right: Ty? = nil) {
        self.id = id
        self.left = left
        self.right = right
    }
}

struct Untypable: Error {
}

func infer(_ t: Term) -> String {
    var next = 0
    var bindings = [Int: Ty]()
    var globals = [String: Ty]()

    func fresh() -> Ty {
        defer {
            next += 1
        }
        return Ty(next)
    }

    func resolve(_ t: Ty) -> Ty {
        if let b = bindings[t.id] {
            return resolve(b)
        }
        return t
    }

    func occurs(_ id: Int, _ t: Ty) -> Bool {
        let a = resolve(t)
        return a.id >= 0 ? a.id == id : occurs(id, a.left!) || occurs(id, a.right!)
    }

    func unify(_ a0: Ty, _ b0: Ty) throws {
        let a = resolve(a0)
        let b = resolve(b0)
        if a === b || a.id >= 0 && a.id == b.id {
            return
        }
        if a.id >= 0 {
            if occurs(a.id, b) {
                throw Untypable()
            }
            bindings[a.id] = b
        } else if b.id >= 0 {
            if occurs(b.id, a) {
                throw Untypable()
            }
            bindings[b.id] = a
        } else {
            try unify(a.left!, b.left!)
            try unify(a.right!, b.right!)
        }
    }

    func visit(_ t: Term, _ env: [(String, Ty)]) throws -> Ty {
        switch t {
        case let .variable(n):
            if let a = env.last(where: {
                $0.0 == n
            })?.1 {
                return a
            }
            if let a = globals[n] {
                return a
            }
            let a = fresh()
            globals[n] = a
            return a
        case let .lambda(n, b):
            let a = fresh()
            return Ty(-1, a, try visit(b, env + [(n, a)]))
        case let .application(a, b):
            let f = try visit(a, env)
            let x = try visit(b, env)
            let result = fresh()
            try unify(f, Ty(-1, x, result))
            return result
        default:
            fatalError("pure term required")
        }
    }
    do {
        let result = try visit(t, [])
        var names = [Int: String]()

        func show(_ t: Ty) -> String {
            let a = resolve(t)
            if a.id >= 0 {
                if names[a.id] == nil {
                    names[a.id] = sequenceName(names.count)
                }
                return names[a.id]!
            }
            let l = resolve(a.left!)
            let text = show(l)
            return (l.id < 0 ? "(\(text))" : text) + " -> " + show(a.right!)
        }
        return show(result)
    } catch {
        return "not typable"
    }
}

func abstract(_ x: String, _ e: Term) -> Term {
    if !free(e).contains(x) {
        return .application(.macro("K"), e)
    }
    if case let .variable(v) = e, v == x {
        return .macro("I")
    }
    guard case let .application(a, b) = e else {
        fatalError("abstraction invariant")
    }
    if case let .variable(v) = b, v == x, !free(a).contains(x) {
        return a
    }
    return .application(.application(.macro("S"), abstract(x, a)), abstract(x, b))
}

func ski(_ t: Term) -> Term {
    switch t {
    case .variable:
        return t
    case let .lambda(n, b):
        return abstract(n, ski(b))
    case let .application(a, b):
        return .application(ski(a), ski(b))
    default:
        fatalError("pure term required")
    }
}

func build(_ head: Term, _ args: [Term]) -> Term {
    args.reduce(head) {
        .application($0, $1)
    }
}

func skiStep(_ t: Term) -> (Term, String)? {
    var h = t
    var args = [Term]()
    while case let .application(a, b) = h {
        args.insert(b, at: 0)
        h = a
    }
    if case let .macro(n) = h {
        if n == "I" && args.count >= 1 {
            return (build(args[0], Array(args.dropFirst())), "I")
        }
        if n == "K" && args.count >= 2 {
            return (build(args[0], Array(args.dropFirst(2))), "K")
        }
        if n == "S" && args.count >= 3 {
            return (build(.application(.application(args[0], args[2]), .application(args[1], args[2])), Array(args.dropFirst(3))), "S")
        }
    }
    for i in args.indices {
        if let (n, kind) = skiStep(args[i]) {
            args[i] = n
            return (build(h, args), kind)
        }
    }
    return nil
}

func church(_ t: Term) -> String {
    if case let .lambda(f, .lambda(x, body)) = t {
        var b = body
        var count = 0
        while case let .application(.variable(v), n) = b, v == f {
            count += 1
            b = n
        }
        if case let .variable(v) = b, v == x {
            return String(count)
        }
        if case let .variable(v) = body, v == f {
            return "true"
        }
    }
    if case let .lambda(f, .application(.application(.variable(v), p), q)) = t, f == v, !free(p).contains(f), !free(q).contains(f) {
        return "(\(church(p)), \(church(q)))"
    }
    return printed(canonical(t))
}

struct Token {
    let kind: String
    let text: String
    let column: Int
}

final class Parser {
    var tokens = [Token]()
    var at = 0

    init(_ line: String, _ arg: String, _ offset: Int) throws {
        let b = Array(arg.utf8)
        var i = 0

        func digit(_ c: UInt8) -> Bool {
            c >= 48 && c <= 57
        }

        func lower(_ c: UInt8) -> Bool {
            c >= 97 && c <= 122
        }

        func upper(_ c: UInt8) -> Bool {
            c >= 65 && c <= 90
        }
        while i < b.count {
            let c = b[i]
            if c == 32 {
                i += 1
                continue
            }
            let start = i
            let kind: String
            if Array("\\.()=;".utf8).contains(c) {
                i += 1
                kind = String(UnicodeScalar(c))
            } else if lower(c) {
                i += 1
                while i < b.count && (lower(b[i]) || digit(b[i])) {
                    i += 1
                }
                kind = "var"
            } else if upper(c) {
                i += 1
                while i < b.count && (upper(b[i]) || digit(b[i]) || b[i] == 95) {
                    i += 1
                }
                kind = "macro"
            } else if c == 35 && i + 1 < b.count && digit(b[i + 1]) {
                i += 2
                while i < b.count && digit(b[i]) {
                    i += 1
                }
                kind = "num"
            } else {
                try fail("column \(offset + i): unexpected character '\(Character(UnicodeScalar(c)))'")
            }
            tokens.append(Token(kind: kind, text: String(decoding: b[start..<i], as: UTF8.self), column: offset + start))
        }
        tokens.append(Token(kind: "end", text: "", column: line.utf8.count + 1))
    }

    func expect(_ kind: String) throws -> Token {
        let t = tokens[at]
        if t.kind != kind {
            let expected = kind == "var" ? "variable" : kind == "macro" ? "macro name" : "'\(kind)'"
            try fail("column \(t.column): expected \(expected)")
        }
        at += 1
        return t
    }

    func term() throws -> Term {
        var elements = [Term]()
        while ["var", "macro", "num", "("].contains(tokens[at].kind) {
            let t = tokens[at]
            at += 1
            switch t.kind {
            case "(":
                let e = try term()
                _ = try expect(")")
                elements.append(e)
            case "num":
                elements.append(.numeral(Int(t.text.dropFirst())!))
            case "var":
                elements.append(.variable(t.text))
            default:
                elements.append(.macro(t.text))
            }
        }
        if tokens[at].kind == "\\" {
            at += 1
            var names = [try expect("var").text]
            while tokens[at].kind == "var" {
                names.append(tokens[at].text)
                at += 1
            }
            _ = try expect(".")
            var body = try term()
            for n in names.reversed() {
                body = .lambda(n, body)
            }
            elements.append(body)
        }
        if elements.isEmpty {
            try fail("column \(tokens[at].column): expected term")
        }
        return build(elements[0], Array(elements.dropFirst()))
    }

    func end() throws {
        let t = tokens[at]
        if t.kind != "end" {
            try fail("column \(t.column): unexpected '\(t.text)'")
        }
    }
}

final class Closure {
    let code: Term
    let env: [Closure]

    init(_ code: Term, _ env: [Closure]) {
        self.code = code
        self.env = env
    }
}

func reify(_ initialTerm: Term, _ initialEnvironment: [Closure], _ initialDepth: Int = 0) -> Term {
    var term = initialTerm
    var environment = initialEnvironment
    var depth = initialDepth
    while case let .index(i) = term {
        if i < depth {
            break
        }
        let closure = environment[i - depth]
        term = closure.code
        environment = closure.env
        depth = 0
    }
    switch term {
    case let .lambda(_, body):
        return .lambda("", reify(body, environment, depth + 1))
    case let .application(left, right):
        return .application(reify(left, environment, depth), reify(right, environment, depth))
    default:
        return term
    }
}

func namedDB(_ t: Term) -> Term {
    let f = free(t)
    var next = 0

    func visit(_ t: Term, _ env: [String]) -> Term {
        switch t {
        case let .index(i):
            return .variable(env[env.count - 1 - i])
        case let .lambda(_, b):
            while f.contains(sequenceName(next)) {
                next += 1
            }
            let n = sequenceName(next)
            next += 1
            return .lambda(n, visit(b, env + [n]))
        case let .application(a, b):
            return .application(visit(a, env), visit(b, env))
        default:
            return t
        }
    }
    return visit(t, [])
}

final class Workbench {
    var macros: [String: Term] = ["I": .lambda("x", .variable("x")), "K": .lambda("x", .lambda("y", .variable("x"))), "S": .lambda("x", .lambda("y", .lambda("z", .application(.application(.variable("x"), .variable("z")), .application(.variable("y"), .variable("z"))))))]
    let reserved: Set<String> = ["S", "K", "I", "NORMAL", "APPLICATIVE", "CBN", "CBV"]
    var display = false
    var etaMode = false
    var limit = 10000

    func expand(_ t: Term) throws -> Term {
        switch t {
        case let .macro(n):
            guard let t = macros[n] else {
                try fail("unbound macro \(n)")
            }
            return try expand(t)
        case let .numeral(n):
            var b = Term.variable("x")
            for _ in 0..<n {
                b = .application(.variable("f"), b)
            }
            return .lambda("f", .lambda("x", b))
        case let .lambda(n, b):
            return .lambda(n, try expand(b))
        case let .application(a, b):
            let left = try expand(a)
            let right = try expand(b)
            return .application(left, right)
        default:
            return t
        }
    }

    func depends(_ name: String, _ target: String) -> Bool {
        var visited = Set<String>()

        func visit(_ n: String) -> Bool {
            if !visited.insert(n).inserted {
                return false
            }
            guard let t = macros[n] else {
                return false
            }
            return references(t).contains {
                $0 == target || visit($0)
            }
        }
        return visit(name)
    }

    func reduce(_ term: Term, _ strategy: String, _ useEta: Bool, _ show: Bool, _ combinators: Bool, _ output: inout [String]) -> (Term, Int)? {
        var t = term
        var count = 0
        while true {
            let next = combinators ? skiStep(t) : step(t, strategy, useEta)
            guard let (n, kind) = next else {
                return (t, count)
            }
            if count == limit {
                return nil
            }
            t = n
            count += 1
            if show && display {
                output.append("step \(count) (\(kind)): \(printed(t))")
            }
        }
    }

    func kam(_ term: Term) -> [String] {
        var code = debruijn(term)
        var env = [Closure]()
        var stack = [Closure]()
        var count = 0
        var out = [String]()
        while true {
            let kind: String
            switch code {
            case .application:
                kind = "push"
            case .lambda where !stack.isEmpty:
                kind = "grab"
            case .index:
                kind = "access"
            default:
                kind = ""
            }
            if kind.isEmpty {
                break
            }
            if count == limit {
                out.append("no result within \(limit) transitions")
                return out
            }
            switch code {
            case let .application(a, b):
                stack.append(Closure(b, env))
                code = a
            case let .lambda(_, b):
                env.insert(stack.removeLast(), at: 0)
                code = b
            case let .index(i):
                let c = env[i]
                code = c.code
                env = c.env
            default:
                break
            }
            count += 1
            if display {
                out.append("step \(count) (\(kind)): \(printed(code, true, true)) [env \(env.count), stack \(stack.count)]")
            }
        }
        var result = reify(code, env)
        for c in stack.reversed() {
            result = .application(result, reify(c.code, c.env))
        }
        out.append("result: \(printed(namedDB(result))) (transitions: \(count))")
        return out
    }

    func command(_ line: String) throws -> [String] {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let command = String(parts[0])
        let arg = parts.count == 2 ? String(parts[1]) : ""
        let known: Set<String> = ["let", "unlet", "macros", "steps", "eta", "limit", "expand", "subst", "reduce", "equal", "alpha", "debruijn", "fv", "size", "depth", "type", "church", "ski", "skireduce", "kam"]
        if !known.contains(command) {
            try fail("unknown command \(command)")
        }
        let words = arg.split(separator: " ").map(String.init)
        if command == "steps" || command == "eta" {
            if words.count != 1 || !["on", "off"].contains(words[0]) {
                try fail("bad argument")
            }
            if command == "steps" {
                display = words[0] == "on"
            } else {
                etaMode = words[0] == "on"
            }
            return []
        }
        if command == "limit" {
            if words.count != 1 || words[0].count < 1 || words[0].count > 5 || !words[0].utf8.allSatisfy( {
                $0 >= 48 && $0 <= 57
            }) || Int(words[0])! < 1 || Int(words[0])! > 10000 {
                try fail("bad argument")
            }
            limit = Int(words[0])!
            return []
        }
        if command == "macros" {
            if !words.isEmpty {
                try fail("bad argument")
            }
            let names = macros.keys.filter {
                !reserved.contains($0)
            }.sorted()
            return names.isEmpty ? ["(none)"] : names.map {
                "\($0) = \(printed(macros[$0]!))"
            }
        }
        if command == "unlet" {
            if words.count != 1 {
                try fail("bad argument")
            }
            let n = words[0]
            let bytes = Array(n.utf8)
            if bytes.isEmpty || bytes[0] < 65 || bytes[0] > 90 || !bytes.allSatisfy( {
                $0 >= 65 && $0 <= 90 || $0 >= 48 && $0 <= 57 || $0 == 95
            }) {
                try fail("bad argument")
            }
            if reserved.contains(n) {
                try fail("reserved name \(n)")
            }
            if macros[n] == nil {
                try fail("unbound macro \(n)")
            }
            for used in macros.keys.sorted() where !reserved.contains(used) {
                if references(macros[used]!).contains(n) {
                    try fail("\(n) is used by \(used)")
                }
            }
            macros.removeValue(forKey: n)
            return ["removed \(n)"]
        }
        let p = try Parser(line, arg, parts.count == 2 ? command.count + 2 : line.count + 1)
        var name = ""
        var strategy = "NORMAL"
        var terms = [Term]()
        switch command {
        case "let":
            name = try p.expect("macro").text
            _ = try p.expect("=")
            terms.append(try p.term())
        case "subst":
            name = try p.expect("var").text
            _ = try p.expect("=")
            terms.append(try p.term())
            _ = try p.expect(";")
            terms.append(try p.term())
        case "equal", "alpha":
            terms.append(try p.term())
            _ = try p.expect(";")
            terms.append(try p.term())
        case "reduce":
            if p.tokens[p.at].kind == "macro" && ["NORMAL", "APPLICATIVE", "CBN", "CBV"].contains(p.tokens[p.at].text) {
                strategy = p.tokens[p.at].text
                p.at += 1
            }
            terms.append(try p.term())
        default:
            terms.append(try p.term())
        }
        try p.end()
        if command == "let" {
            let t = terms[0]
            if reserved.contains(name) {
                try fail("reserved name \(name)")
            }
            for r in references(t) {
                if r == name || depends(r, name) {
                    try fail("recursive definition of \(name)")
                }
                if macros[r] == nil {
                    try fail("unbound macro \(r)")
                }
            }
            if let v = free(t).sorted().first {
                try fail("free variable \(v) in definition of \(name)")
            }
            let exists = macros[name] != nil
            macros[name] = t
            return ["\(exists ? "redefined" : "defined") \(name)"]
        }
        let expanded = try terms.map {
            try expand($0)
        }
        let t = expanded[0]
        var out = [String]()
        let failure = "no normal form within \(limit) steps"
        switch command {
        case "expand":
            return [printed(t)]
        case "subst":
            return [printed(substitute(expanded[1], name, t))]
        case "alpha":
            return [debruijn(t) == debruijn(expanded[1]) ? "yes" : "no"]
        case "debruijn":
            return [printed(debruijn(t), true, true)]
        case "fv":
            let f = free(t).sorted()
            return [f.isEmpty ? "(none)" : f.joined(separator: " ")]
        case "size", "depth":

            func measure(_ t: Term) -> Int {
                switch t {
                case .variable:
                    return 1
                case let .lambda(_, b):
                    return 1 + measure(b)
                case let .application(a, b):
                    return 1 + (command == "size" ? measure(a) + measure(b) : max(measure(a), measure(b)))
                default:
                    fatalError("pure term required")
                }
            }
            return [String(measure(t))]
        case "type":
            return [infer(t)]
        case "ski":
            return [printed(ski(t))]
        case "kam":
            return kam(t)
        case "equal":
            let a = reduce(t, "NORMAL", etaMode, false, false, &out)
            let b = reduce(expanded[1], "NORMAL", etaMode, false, false, &out)
            if let a = a, let b = b {
                return [debruijn(a.0) == debruijn(b.0) ? "yes" : "no"]
            }
            return ["unknown"]
        case "church":
            if let result = reduce(t, "NORMAL", false, false, false, &out) {
                return [church(canonical(result.0))]
            }
            return [failure]
        default:
            let combinators = command == "skireduce"
            let result = reduce(combinators ? ski(t) : t, strategy, etaMode, true, combinators, &out)
            if let (r, n) = result {
                out.append("result: \(printed(combinators ? r : canonical(r))) (steps: \(n))")
            } else {
                out.append(failure)
            }
            return out
        }
    }
}
let workbench = Workbench()
while let line = readLine() {
    if line == "quit" {
        break
    }
    if line.isEmpty || line.hasPrefix("--") {
        continue
    }
    do {
        for result in try workbench.command(line) {
            print(result)
        }
    } catch let e as Problem {
        print("error: \(e.reason)")
    } catch {
    }
}
