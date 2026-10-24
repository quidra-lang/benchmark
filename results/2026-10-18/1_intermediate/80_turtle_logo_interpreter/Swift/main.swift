import Foundation

struct Token {
    let text: String
    let kind: String
    let line: Int
}

struct Problem: Error {
    let line: Int
    let reason: String
}

func fail(_ t: Token, _ reason: String) throws -> Never {
    throw Problem(line: t.line, reason: reason)
}
let signatures = ["FD": "E", "BK": "E", "RT": "E", "LT": "E", "SETH": "E", "PU": "", "PD": "", "PE": "", "SETPEN": "E", "SETXY": "EE", "SETX": "E", "SETY": "E", "HOME": "", "CS": "", "CLEAN": "", "FILL": "", "LABEL": "P", "SNAPSHOT": "", "REPEAT": "EL", "FOR": "QEEL", "WHILE": "EL", "IF": "EL", "IFELSE": "ELL", "TEST": "E", "IFTRUE": "L", "IFFALSE": "L", "STOP": "", "OUTPUT": "E", "MAKE": "QE", "LOCAL": "Q", "LOCALMAKE": "QE", "TRACE": "Q", "UNTRACE": "Q", "SEED": "E", "PRINT": "P"]
let aliases = ["FORWARD": "FD", "BACK": "BK", "RIGHT": "RT", "LEFT": "LT", "SETHEADING": "SETH", "PENUP": "PU", "PENDOWN": "PD", "PENERASE": "PE", "CLEARSCREEN": "CS", "IFT": "IFTRUE", "IFF": "IFFALSE", "OP": "OUTPUT", "PR": "PRINT"]
let functions = ["XCOR": 0, "YCOR": 0, "HEADING": 0, "REPCOUNT": 0, "RANDOM": 1, "ABS": 1, "NOT": 1, "AND": 2, "OR": 2, "MAX": 2, "MIN": 2]

func canonical(_ s: String) -> String {
    aliases[s] ?? s
}

func primitive(_ s: String) -> Bool {
    signatures[canonical(s)] != nil || functions[s] != nil || ["TO", "END", "MOD"].contains(s)
}

func name(_ s: String) -> Bool {
    let b = Array(s.utf8)
    return !b.isEmpty && b[0] >= 65 && b[0] <= 90 && b.allSatisfy {
        $0 >= 65 && $0 <= 90 || $0 >= 48 && $0 <= 57 || $0 == 95
    }
}

func lex(_ text: String, _ line: Int) throws -> [Token] {
    let s = text.components(separatedBy: ";")[0].uppercased()
    let b = Array(s.utf8)
    var out = [Token]()
    var i = 0
    let symbols = Array("[]()+-*/=<>".utf8)
    let delimiters = Array(" []()+-*/=<>".utf8)
    while i < b.count {
        let c = b[i]
        if c == 32 {
            i += 1
            continue
        }
        if symbols.contains(c) {
            let start = i
            let kind = c == 45 && (i == 0 || [UInt8(32), 91, 40].contains(b[i - 1])) && i + 1 < b.count && b[i + 1] != 32 ? "sign" : "symbol"
            if c == 60 && i + 1 < b.count && [UInt8(61), 62].contains(b[i + 1]) || c == 62 && i + 1 < b.count && b[i + 1] == 61 {
                i += 1
            }
            i += 1
            out.append(Token(text: String(decoding: b[start..<i], as: UTF8.self), kind: kind, line: line))
            continue
        }
        let start = i
        while i < b.count && !delimiters.contains(b[i]) {
            i += 1
        }
        let word = String(decoding: b[start..<i], as: UTF8.self)
        let kind: String
        if word.utf8.allSatisfy( {
            $0 >= 48 && $0 <= 57
        }) {
            kind = "number"
        } else if word.hasPrefix(":") && name(String(word.dropFirst())) {
            kind = "variable"
        } else if word.hasPrefix("\"") && name(String(word.dropFirst())) {
            kind = "quote"
        } else if name(word) {
            kind = "word"
        } else {
            throw Problem(line: line, reason: "bad token '\(word)'")
        }
        out.append(Token(text: word, kind: kind, line: line))
    }
    return out
}

struct Expr {
    let token: Token
    let op: String
    let args: [Expr]

    init(_ token: Token, _ op: String, _ args: [Expr] = []) {
        self.token = token
        self.op = op
        self.args = args
    }
}

enum Item {
    case word(String), expression(Expr)
}

struct Command {
    let token: Token
    let op: String
    var exprs = [Expr]()
    var words = [String]()
    var lists = [[Command]]()
    var items = [Item]()

    init(_ token: Token, _ op: String) {
        self.token = token
        self.op = op
    }
}

final class Procedure {
    let token: Token
    let params: [String]
    var raw = [Token]()
    var body = [Command]()

    init(_ token: Token, _ params: [String]) {
        self.token = token
        self.params = params
    }
}

final class Parser {
    let tokens: [Token]
    let procedures: [String: Procedure]
    let inside: Bool
    var at = 0

    init(_ tokens: [Token], _ procedures: [String: Procedure], _ inside: Bool) {
        self.tokens = tokens
        self.procedures = procedures
        self.inside = inside
    }

    func unknown(_ t: Token) -> Bool {
        t.kind == "word" && !primitive(t.text) && procedures[t.text] == nil
    }

    func next(_ owner: Token) throws -> Token {
        if at == tokens.count || tokens[at].text == "]" || tokens[at].text == ")" {
            try fail(owner, "not enough inputs to \(owner.text)")
        }
        let t = tokens[at]
        if unknown(t) {
            try fail(t, "I don't know how to \(t.text)")
        }
        return t
    }

    func rejected(_ owner: Token, _ t: Token) throws -> Never {
        try fail(t, "\(owner.text) doesn't like \(t.text) as input")
    }

    func expression(_ owner: Token) throws -> Expr {
        try binary(owner, 0)
    }

    func binary(_ owner: Token, _ level: Int) throws -> Expr {
        if level == 3 {
            return try term(owner)
        }
        let operators = level == 0 ? ["=", "<>", "<", ">", "<=", ">="] : level == 1 ? ["+", "-"] : ["*", "/", "MOD"]
        var left = try binary(owner, level + 1)
        while at < tokens.count && operators.contains(tokens[at].text) && tokens[at].kind != "sign" {
            let t = tokens[at]
            at += 1
            let right = try binary(t, level + 1)
            left = Expr(t, t.text, [left, right])
        }
        return left
    }

    func expressions(_ owner: Token, _ count: Int) throws -> [Expr] {
        try (0..<count).map {
            _ in try expression(owner)
        }
    }

    func term(_ owner: Token) throws -> Expr {
        let t = try next(owner)
        at += 1
        if t.kind == "number" {
            return Expr(t, "NUMBER")
        }
        if t.kind == "variable" {
            return Expr(t, "VARIABLE")
        }
        if t.text == "-" {
            return Expr(t, "NEG", [try term(t)])
        }
        if t.text == "(" {
            let e = try expression(t)
            if at == tokens.count || tokens[at].text != ")" {
                try fail(t, "missing )")
            }
            at += 1
            return e
        }
        if t.kind == "word", let count = functions[t.text] {
            return Expr(t, "FUNCTION", try expressions(t, count))
        }
        if t.kind == "word", let p = procedures[t.text] {
            return Expr(t, "CALL", try expressions(t, p.params.count))
        }
        try rejected(owner, t)
    }

    func item(_ owner: Token) throws -> Item {
        let t = try next(owner)
        if t.kind == "quote" {
            at += 1
            return .word(String(t.text.dropFirst()))
        }
        return .expression(try expression(owner))
    }

    func list(_ owner: Token) throws -> [Command] {
        let open = try next(owner)
        if open.text != "[" {
            try rejected(owner, open)
        }
        at += 1
        var out = [Command]()
        while at < tokens.count && tokens[at].text != "]" {
            out.append(try command())
        }
        if at == tokens.count {
            try fail(open, "missing ]")
        }
        at += 1
        return out
    }

    func command() throws -> Command {
        let t = tokens[at]
        at += 1
        if t.text == "]" {
            try fail(t, "unexpected ]")
        }
        if t.text == "(" && at < tokens.count && tokens[at].kind == "word" && canonical(tokens[at].text) == "PRINT" {
            let owner = tokens[at]
            at += 1
            var result = Command(t, "MULTIPRINT")
            while at == tokens.count || tokens[at].text != ")" {
                if at == tokens.count || tokens[at].text == "]" {
                    try fail(t, "missing )")
                }
                result.items.append(try item(owner))
            }
            at += 1
            return result
        }
        if t.kind == "word" && ["TO", "END"].contains(t.text) {
            try fail(t, "misplaced \(t.text)")
        }
        let op = canonical(t.text)
        if t.kind == "word", let signature = signatures[op] {
            if !inside && ["STOP", "OUTPUT", "LOCAL", "LOCALMAKE"].contains(op) {
                try fail(t, "can only use \(t.text) inside a procedure")
            }
            var result = Command(t, op)
            for kind in signature {
                switch kind {
                case "E":
                    result.exprs.append(try expression(t))
                case "L":
                    result.lists.append(try list(t))
                case "P":
                    result.items.append(try item(t))
                default:
                    let q = try next(t)
                    if q.kind != "quote" {
                        try rejected(t, q)
                    }
                    at += 1
                    let word = String(q.text.dropFirst())
                    result.words.append(word)
                    if ["TRACE", "UNTRACE"].contains(op) && procedures[word] == nil {
                        try fail(q, "I don't know how to \(word)")
                    }
                }
            }
            return result
        }
        if t.kind == "word", let p = procedures[t.text] {
            var result = Command(t, "CALL")
            result.exprs = try expressions(t, p.params.count)
            return result
        }
        if unknown(t) {
            try fail(t, "I don't know how to \(t.text)")
        }
        try fail(t, "you don't say what to do with \(t.text)")
    }

    func sequence() throws -> [Command] {
        var out = [Command]()
        while at < tokens.count {
            out.append(try command())
        }
        return out
    }
}

struct Point: Hashable {
    let x: Int
    let y: Int
}

final class Environment {
    var values: [String: Int]
    var test: Bool?

    init(_ values: [String: Int] = [:]) {
        self.values = values
    }
}

enum Flow: Error {
    case stop, output(Int)
}

final class Runtime {
    let procedures: [String: Procedure]
    var output = [String]()
    var x = 0
    var y = 0
    var heading = 0
    var pen = "DOWN"
    var character: Character = "*"
    var random = 1
    var canvas = [Point: Character]()
    var envs = [Environment()]
    var calls = [String]()
    var repetitions = [Int]()
    var traced = Set<String>()
    let directions = [(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)]

    init(_ procedures: [String: Procedure]) {
        self.procedures = procedures
    }

    func variable(_ t: Token) throws -> Int {
        let name = String(t.text.dropFirst())
        for env in envs.reversed() {
            if let v = env.values[name] {
                return v
            }
        }
        try fail(t, "\(name) has no value")
    }

    func make(_ name: String, _ value: Int) {
        for i in (1..<envs.count).reversed() {
            if envs[i].values[name] != nil {
                envs[i].values[name] = value
                return
            }
        }
        envs[0].values[name] = value
    }

    func invoke(_ t: Token, _ values: [Int]) throws -> Int? {
        if calls.count == 100 {
            try fail(t, "recursion too deep")
        }
        let p = procedures[t.text]!
        let trace = traced.contains(t.text)
        let indent = String(repeating: "  ", count: calls.count)
        if trace {
            output.append(indent + "( " + t.text + values.map {
                " \($0)"
            }.joined() + " )")
        }
        envs.append(Environment(Dictionary(uniqueKeysWithValues: zip(p.params, values))))
        calls.append(t.text)
        let value: Int?
        do {
            try execute(p.body)
            value = nil
        } catch Flow.stop {
            value = nil
        } catch let Flow.output(v) {
            value = v
        }
        envs.removeLast()
        calls.removeLast()
        if trace {
            output.append(indent + t.text + (value.map {
                " outputs \($0)"
            } ?? " stops"))
        }
        return value
    }

    func evaluate(_ e: Expr) throws -> Int {
        let t = e.token
        if e.op == "NUMBER" {
            return Int(t.text)!
        }
        if e.op == "VARIABLE" {
            return try variable(t)
        }
        let a = try e.args.map {
            try evaluate($0)
        }
        if e.op == "NEG" {
            return -a[0]
        }
        if e.op == "CALL" {
            guard let v = try invoke(t, a) else {
                try fail(t, "\(t.text) did not output")
            }
            return v
        }
        if e.op == "FUNCTION" {
            switch t.text {
            case "XCOR":
                return x
            case "YCOR":
                return y
            case "HEADING":
                return heading
            case "REPCOUNT":
                guard let n = repetitions.last else {
                    try fail(t, "REPCOUNT outside REPEAT")
                }
                return n
            case "RANDOM":
                if a[0] <= 0 {
                    try fail(t, "RANDOM doesn't like \(a[0]) as input")
                }
                random = 48271 * random % 2147483647
                return random % a[0]
            case "ABS":
                return abs(a[0])
            case "NOT":
                return a[0] == 0 ? 1 : 0
            case "AND":
                return a[0] != 0 && a[1] != 0 ? 1 : 0
            case "OR":
                return a[0] != 0 || a[1] != 0 ? 1 : 0
            case "MAX":
                return max(a[0], a[1])
            default:
                return min(a[0], a[1])
            }
        }
        if (e.op == "/" || e.op == "MOD") && a[1] == 0 {
            try fail(t, "\(t.text) doesn't like 0 as input")
        }
        switch e.op {
        case "+":
            return a[0] + a[1]
        case "-":
            return a[0] - a[1]
        case "*":
            return a[0] * a[1]
        case "/":
            return a[0] / a[1]
        case "MOD":
            return a[0] % a[1]
        case "=":
            return a[0] == a[1] ? 1 : 0
        case "<>":
            return a[0] != a[1] ? 1 : 0
        case "<":
            return a[0] < a[1] ? 1 : 0
        case ">":
            return a[0] > a[1] ? 1 : 0
        case "<=":
            return a[0] <= a[1] ? 1 : 0
        default:
            return a[0] >= a[1] ? 1 : 0
        }
    }

    func item(_ p: Item) throws -> String {
        switch p {
        case let .word(s):
            return s
        case let .expression(e):
            return String(try evaluate(e))
        }
    }

    func apply(_ x: Int, _ y: Int) {
        let p = Point(x: x, y: y)
        if pen == "DOWN" {
            canvas[p] = character
        } else if pen == "ERASE" {
            canvas.removeValue(forKey: p)
        }
    }

    func move(_ n: Int) {
        let (dx, dy) = directions[heading / 45]
        let sign = n < 0 ? -1 : 1
        apply(x, y)
        for _ in 0..<abs(n) {
            x += sign * dx
            y += sign * dy
            apply(x, y)
        }
    }

    func floor(_ n: Int, _ d: Int) -> Int {
        n / d - (n < 0 && n % d != 0 ? 1 : 0)
    }

    func straight(_ xx: Int, _ yy: Int) {
        let dx = xx - x
        let dy = yy - y
        let size = max(abs(dx), abs(dy))
        if size == 0 {
            apply(x, y)
        } else {
            for i in 0...size {
                apply(x + floor(2 * i * dx + size, 2 * size), y + floor(2 * i * dy + size, 2 * size))
            }
        }
        x = xx
        y = yy
    }

    func bounds() -> (Int, Int, Int, Int)? {
        if canvas.isEmpty {
            return nil
        }
        return (canvas.keys.map(\.x).min()!, canvas.keys.map(\.y).min()!, canvas.keys.map(\.x).max()!, canvas.keys.map(\.y).max()!)
    }

    func fill() {
        guard let (x1, y1, x2, y2) = bounds(), canvas[Point(x: x, y: y)] == nil, x >= x1, x <= x2, y >= y1, y <= y2 else {
            return
        }
        var queue = [Point(x: x, y: y)]
        var at = 0
        canvas[queue[0]] = character
        while at < queue.count {
            let p = queue[at]
            at += 1
            for (dx, dy) in [(0, 1), (1, 0), (0, -1), (-1, 0)] {
                let q = Point(x: p.x + dx, y: p.y + dy)
                if q.x >= x1 && q.x <= x2 && q.y >= y1 && q.y <= y2 && canvas[q] == nil {
                    canvas[q] = character
                    queue.append(q)
                }
            }
        }
    }

    func picture() {
        guard let (x1, y1, x2, y2) = bounds() else {
            output.append("CANVAS 0 0 0")
            return
        }
        output.append("CANVAS \(x2 - x1 + 1) \(y2 - y1 + 1) \(canvas.count)")
        for yy in (y1...y2).reversed() {
            var line = String((x1...x2).map {
                canvas[Point(x: $0, y: yy)] ?? " "
            })
            while line.last == " " {
                line.removeLast()
            }
            output.append(line)
        }
    }

    func execute(_ commands: [Command]) throws {
        for c in commands {
            try command(c)
        }
    }

    func command(_ c: Command) throws {
        let t = c.token
        let op = c.op
        if op == "WHILE" {
            while try evaluate(c.exprs[0]) != 0 {
                try execute(c.lists[0])
            }
            return
        }
        if op == "PRINT" || op == "MULTIPRINT" {
            let values = try c.items.map {
                try item($0)
            }
            output.append(values.joined(separator: " "))
            return
        }
        if op == "LABEL" {
            let text = try item(c.items[0])
            let (dx, dy) = directions[heading / 45]
            for (i, ch) in text.enumerated() {
                canvas[Point(x: x + i * dx, y: y + i * dy)] = ch
            }
            return
        }
        let a = try c.exprs.map {
            try evaluate($0)
        }
        switch op {
        case "CALL":
            if let v = try invoke(t, a) {
                try fail(t, "you don't say what to do with \(v)")
            }
        case "FD":
            move(a[0])
        case "BK":
            move(-a[0])
        case "RT", "LT", "SETH":
            let angle = a[0]
            if angle % 45 != 0 {
                try fail(t, "\(t.text) doesn't like \(angle) as input")
            }
            let h = op == "SETH" ? angle : heading + (op == "RT" ? angle : -angle)
            heading = (h % 360 + 360) % 360
        case "PU":
            pen = "UP"
        case "PD":
            pen = "DOWN"
        case "PE":
            pen = "ERASE"
        case "SETPEN":
            if !(33...126).contains(a[0]) {
                try fail(t, "SETPEN doesn't like \(a[0]) as input")
            }
            character = Character(UnicodeScalar(a[0])!)
        case "SETXY":
            straight(a[0], a[1])
        case "SETX":
            straight(a[0], y)
        case "SETY":
            straight(x, a[0])
        case "HOME":
            straight(0, 0)
            heading = 0
        case "CS":
            canvas = [:]
            x = 0
            y = 0
            heading = 0
        case "CLEAN":
            canvas = [:]
        case "FILL":
            fill()
        case "SNAPSHOT":
            picture()
        case "MAKE":
            make(c.words[0], a[0])
        case "LOCAL":
            envs.last!.values[c.words[0]] = 0
        case "LOCALMAKE":
            envs.last!.values[c.words[0]] = a[0]
        case "TRACE":
            traced.insert(c.words[0])
        case "UNTRACE":
            traced.remove(c.words[0])
        case "SEED":
            if a[0] <= 0 {
                try fail(t, "SEED doesn't like \(a[0]) as input")
            }
            random = a[0]
        case "STOP":
            throw Flow.stop
        case "OUTPUT":
            throw Flow.output(a[0])
        case "REPEAT":
            if c.lists[0].isEmpty {
                return
            }
            if a[0] > 0 {
                for i in 1...a[0] {
                    repetitions.append(i)
                    do {
                        defer {
                            repetitions.removeLast()
                        }
                        try execute(c.lists[0])
                    }
                }
            }
        case "FOR":
            if c.lists[0].isEmpty {
                make(c.words[0], a[1])
                return
            }
            let step = a[0] <= a[1] ? 1 : -1
            var i = a[0]
            while true {
                make(c.words[0], i)
                try execute(c.lists[0])
                if i == a[1] {
                    break
                }
                i += step
            }
        case "IF":
            if a[0] != 0 {
                try execute(c.lists[0])
            }
        case "IFELSE":
            try execute(c.lists[a[0] != 0 ? 0 : 1])
        case "TEST":
            envs.last!.test = a[0] != 0
        case "IFTRUE", "IFFALSE":
            guard let test = envs.last!.test else {
                try fail(t, "\(t.text) without TEST")
            }
            if test == (op == "IFTRUE") {
                try execute(c.lists[0])
            }
        default:
            break
        }
    }

    func errors() {
        var i = calls.count
        while i > 0 {
            let p = calls[i - 1]
            var count = 0
            while i > 0 && calls[i - 1] == p {
                i -= 1
                count += 1
            }
            output.append("  in \(p)" + (count == 1 ? "" : " x\(count)"))
        }
    }
}

func process(_ source: [(Int, String)]) -> [String] {
    do {
        var procedures = [String: Procedure]()
        var order = [Procedure]()
        var top = [Token]()
        var current: Procedure?
        for (line, text) in source {
            let tokens = try lex(text, line)
            if tokens.isEmpty {
                continue
            }
            let start = tokens[0]
            if start.kind == "word" && start.text == "TO" {
                if let p = current {
                    try fail(start, "TO inside definition of \(p.token.text)")
                }
                if tokens.count < 2 || tokens[1].kind != "word" {
                    try fail(start, "bad procedure header")
                }
                let name = tokens[1]
                if primitive(name.text) {
                    try fail(start, "\(name.text) is a primitive")
                }
                if procedures[name.text] != nil {
                    try fail(start, "\(name.text) is already defined")
                }
                var params = [String]()
                for t in tokens.dropFirst(2) {
                    if t.kind != "variable" {
                        try fail(start, "bad procedure header")
                    }
                    let p = String(t.text.dropFirst())
                    if params.contains(p) {
                        try fail(start, "duplicate input \(t.text)")
                    }
                    params.append(p)
                }
                let p = Procedure(name, params)
                procedures[name.text] = p
                order.append(p)
                current = p
            } else if tokens.count == 1 && start.kind == "word" && start.text == "END" {
                if current == nil {
                    try fail(start, "END without TO")
                }
                current = nil
            } else if let p = current {
                p.raw += tokens
            } else {
                top += tokens
            }
        }
        if let p = current {
            try fail(p.token, "missing END for \(p.token.text)")
        }
        for p in order {
            p.body = try Parser(p.raw, procedures, true).sequence()
        }
        let body = try Parser(top, procedures, false).sequence()
        let runtime = Runtime(procedures)
        do {
            try runtime.execute(body)
            runtime.output.append("TURTLE \(runtime.x) \(runtime.y) \(runtime.heading) \(runtime.pen) \(runtime.character)")
            runtime.picture()
        } catch let e as Problem {
            runtime.output.append("ERROR line \(e.line): \(e.reason)")
            runtime.errors()
        } catch {
        }
        return runtime.output
    } catch let e as Problem {
        return ["ERROR line \(e.line): \(e.reason)"]
    } catch {
        return []
    }
}
var lines = [String]()
while let line = readLine() {
    lines.append(line)
}
var at = 0
while at < lines.count && lines[at] != "#EOF" {
    print("PROGRAM " + String(lines[at].dropFirst(9)))
    at += 1
    var source = [(Int, String)]()
    while at < lines.count && lines[at] != "#EOF" && !lines[at].hasPrefix("#PROGRAM ") {
        source.append((at + 1, lines[at]))
        at += 1
    }
    for line in process(source) {
        print(line)
    }
}
