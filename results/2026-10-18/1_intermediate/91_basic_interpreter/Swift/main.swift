import Foundation

struct SyntaxFault: Error {}
struct BasicFault: Error {
    let message: String
}

func syntax() throws -> Never {
    throw SyntaxFault()
}

func fault(_ message: String) throws -> Never {
    throw BasicFault(message: message)
}

enum Value: Equatable {
    case integer(Int)
    case text(String)

    var type: String {
        switch self {
        case .integer: return "I"
        case .text: return "S"
        }
    }

    var number: Int {
        switch self {
        case .integer(let value): return value
        case .text: preconditionFailure()
        }
    }

    var string: String {
        switch self {
        case .integer: preconditionFailure()
        case .text(let value): return value
        }
    }

    var rendered: String {
        switch self {
        case .integer(let value): return String(value)
        case .text(let value): return value
        }
    }
}

struct Token {
    let kind: String
    let text: String
    let value: Value
}

final class Expression {
    var kind: String
    let type: String
    let value: Value
    var args: [Expression]

    init(_ kind: String, _ type: String, _ value: Value = .text(""),
         _ args: [Expression] = []) {
        self.kind = kind
        self.type = type
        self.value = value
        self.args = args
    }
}

struct PrintItem {
    let kind: String
    let expression: Expression?
}

struct Clause {
    let number: Int?
    let body: [Statement]
}

final class Statement {
    var kind: String
    var line = 0
    var next: Statement?
    var expression: Expression?
    var target: Expression?
    var targets: [Expression] = []
    var expressions: [Expression] = []
    var values: [Value] = []
    var numbers: [Int] = []
    var name = ""
    var mode = ""
    var clauses: [Clause] = []
    var items: [PrintItem] = []

    init(_ kind: String) {
        self.kind = kind
    }
}

let signatures: [String: [String]] = [
    "ABS": ["I"], "SGN": ["I"], "INT": ["I"], "SQR": ["I"],
    "RND": ["I"], "LEN": ["S"], "ASC": ["S"], "VAL": ["S"],
    "CHR$": ["I"], "STR$": ["I"], "LEFT$": ["SI"],
    "RIGHT$": ["SI"], "MID$": ["SI", "SII"], "INSTR": ["SS"]
]

let errorCodes: [String: Int] = [
    "NEXT WITHOUT FOR": 1, "RETURN WITHOUT GOSUB": 3,
    "OUT OF DATA": 4, "ILLEGAL FUNCTION CALL": 5,
    "OVERFLOW": 6, "OUT OF MEMORY": 7,
    "UNDEFINED LINE NUMBER": 8, "SUBSCRIPT OUT OF RANGE": 9,
    "DUPLICATE DEFINITION": 10, "DIVISION BY ZERO": 11,
    "TYPE MISMATCH": 13, "STRING TOO LONG": 15,
    "RESUME WITHOUT ERROR": 20, "FOR WITHOUT NEXT": 26,
    "WHILE WITHOUT WEND": 29, "WEND WITHOUT WHILE": 30,
    "INPUT PAST END": 62
]

func digit(_ character: UInt8) -> Bool {
    character >= 48 && character <= 57
}

func upper(_ character: UInt8) -> Bool {
    character >= 65 && character <= 90
}

func variable(_ name: String) -> Bool {
    let bytes = Array(name.utf8)
    if bytes.isEmpty || !upper(bytes[0]) { return false }
    if bytes.count == 1 { return true }
    if bytes.count == 2 {
        return digit(bytes[1]) || bytes[1] == 36
    }
    return bytes.count == 3 && digit(bytes[1]) && bytes[2] == 36
}

func nameType(_ name: String) -> String {
    name.hasSuffix("$") ? "S" : "I"
}

func tokenize(_ source: String) throws -> [Token] {
    let bytes = Array(source.utf8)
    var position = 0
    var tokens: [Token] = []
    while position < bytes.count {
        let c = bytes[position]
        if c == 32 {
            position += 1
        } else if c == 34 {
            let start = position
            position += 1
            while position < bytes.count && bytes[position] != 34 {
                position += 1
            }
            if position == bytes.count { try syntax() }
            tokens.append(Token(
                kind: "S",
                text: String(decoding: bytes[start...position], as: UTF8.self),
                value: .text(String(decoding: bytes[(start + 1)..<position], as: UTF8.self))
            ))
            position += 1
        } else if digit(c) {
            let start = position
            while position < bytes.count && digit(bytes[position]) {
                position += 1
            }
            let word = String(decoding: bytes[start..<position], as: UTF8.self)
            guard let n = Int(word), n <= 32767 else { try syntax() }
            tokens.append(Token(kind: "I", text: word, value: .integer(n)))
        } else if upper(c) {
            if position + 2 < bytes.count &&
               bytes[position] == 82 && bytes[position + 1] == 69 &&
               bytes[position + 2] == 77 {
                tokens.append(Token(kind: "W", text: "REM", value: .text("REM")))
                break
            }
            let start = position
            while position < bytes.count && (upper(bytes[position]) || digit(bytes[position])) {
                position += 1
            }
            if position < bytes.count && bytes[position] == 36 {
                position += 1
            }
            let word = String(decoding: bytes[start..<position], as: UTF8.self)
            tokens.append(Token(kind: "W", text: word, value: .text(word)))
        } else {
            let candidate = String(decoding: bytes[position..<min(position + 2, bytes.count)], as: UTF8.self)
            let word = ["<>", "<=", ">="].contains(candidate)
                ? candidate : String(decoding: bytes[position...position], as: UTF8.self)
            if !"+-*/^=<>() ,;:".utf8.contains(c) {
                try syntax()
            }
            tokens.append(Token(kind: "P", text: word, value: .text(word)))
            position += word.utf8.count
        }
    }
    tokens.append(Token(kind: "E", text: "", value: .text("")))
    return tokens
}

final class Parser {
    private let tokens: [Token]
    private var index = 0

    init(_ tokens: [Token]) {
        self.tokens = tokens
    }

    private var current: Token { tokens[index] }

    private func at(_ word: String) -> Bool {
        (current.kind == "P" || current.kind == "W") && current.text == word
    }

    @discardableResult
    private func take(_ word: String) -> Bool {
        if !at(word) { return false }
        index += 1
        return true
    }

    private func expect(_ word: String) throws {
        if !take(word) { try syntax() }
    }

    private func number() throws -> Int {
        if current.kind != "I" { try syntax() }
        let result = current.value.number
        index += 1
        return result
    }

    private func integer(_ level: Int = 0) throws -> Expression {
        let result = try expression(level)
        if result.type != "I" { try syntax() }
        return result
    }

    private func target() throws -> Expression {
        let token = current
        if token.kind != "W" || !variable(token.text) { try syntax() }
        index += 1
        let result = Expression("variable", nameType(token.text), .text(token.text))
        if take("(") {
            result.kind = "array"
            result.args.append(try integer())
            if take(",") { result.args.append(try integer()) }
            try expect(")")
        }
        return result
    }

    private func primary() throws -> Expression {
        let token = current
        if token.kind == "I" || token.kind == "S" {
            index += 1
            return Expression("constant", token.kind, token.value)
        }
        if take("(") {
            let value = try expression()
            try expect(")")
            return value
        }
        if token.kind == "W" && variable(token.text) { return try target() }
        if take("ERR") { return Expression("builtin", "I", .text("ERR")) }
        if take("ERL") { return Expression("builtin", "I", .text("ERL")) }
        if token.kind == "W", let expected = signatures[token.text] {
            index += 1
            try expect("(")
            var arguments = [try expression()]
            while take(",") { arguments.append(try expression()) }
            try expect(")")
            if !expected.contains(arguments.map(\.type).joined()) { try syntax() }
            return Expression("call", nameType(token.text), .text(token.text), arguments)
        }
        try syntax()
    }

    private func expression(_ level: Int = 0) throws -> Expression {
        if level == 2 && take("NOT") {
            return Expression("unary", "I", .text("NOT"), [try integer(2)])
        }
        if level == 6 && take("-") {
            return Expression("unary", "I", .text("-"), [try integer(6)])
        }
        if level == 8 { return try primary() }
        var left = try expression(level + 1)
        let operators = [
            ["OR"], ["AND"], [],
            ["=", "<>", "<", ">", "<=", ">="],
            ["+", "-"], ["*", "/", "MOD"], [], ["^"]
        ][level]
        while operators.contains(where: { at($0) }) {
            let op = current.text
            index += 1
            let right = try expression(level == 7 ? 6 : level + 1)
            if left.type != right.type ||
               (left.type == "S" && level != 3 && op != "+") { try syntax() }
            left = Expression("binary", level == 3 ? "I" : left.type,
                              .text(op), [left, right])
            if level == 7 { break }
        }
        return left
    }

    private func clause() throws -> Clause {
        if current.kind == "I" { return Clause(number: try number(), body: []) }
        return Clause(number: nil, body: try list(true))
    }

    private func list(_ insideClause: Bool = false) throws -> [Statement] {
        var result = [try statement(insideClause)]
        while take(":") { result.append(try statement(insideClause)) }
        return result
    }

    private func statement(_ insideClause: Bool) throws -> Statement {
        let word = current.text
        if insideClause && ["IF", "FOR", "NEXT", "WHILE", "WEND", "DATA"].contains(word) {
            try syntax()
        }
        let s = Statement(word)
        if take("REM") || take("RETURN") || take("WEND") ||
           take("END") || take("STOP") {
            return s
        }
        if take("PRINT") {
            var lastWasValue = false
            while current.kind != "E" && !at(":") && !at("ELSE") {
                if take(";") {
                    s.items.append(PrintItem(kind: ";", expression: nil))
                    lastWasValue = false
                } else if take(",") {
                    s.items.append(PrintItem(kind: ",", expression: nil))
                    lastWasValue = false
                } else {
                    let mode = at("TAB") ? "TAB" : at("SPC") ? "SPC" : "value"
                    if mode == "value" && lastWasValue { try syntax() }
                    let value: Expression
                    if mode == "value" {
                        value = try expression()
                    } else {
                        index += 1
                        try expect("(")
                        value = try integer()
                        try expect(")")
                    }
                    s.items.append(PrintItem(kind: mode, expression: value))
                    lastWasValue = mode == "value"
                }
            }
            return s
        }
        if take("INPUT") || take("READ") || take("DIM") {
            repeat {
                let target = try self.target()
                if word == "DIM" && target.kind != "array" { try syntax() }
                s.targets.append(target)
            } while take(",")
            return s
        }
        if take("DATA") {
            repeat {
                let negative = take("-")
                let token = current
                if token.kind != "I" && (token.kind != "S" || negative) {
                    try syntax()
                }
                index += 1
                s.values.append(negative ? .integer(-token.value.number) : token.value)
            } while take(",")
            return s
        }
        if take("IF") {
            s.expression = try integer()
            try expect("THEN")
            s.clauses.append(try clause())
            if take("ELSE") { s.clauses.append(try clause()) }
            if current.kind != "E" { try syntax() }
            return s
        }
        if take("GOTO") || take("GOSUB") {
            s.numbers.append(try number())
            return s
        }
        if take("ON") {
            if take("ERROR") {
                s.kind = "handler"
                try expect("GOTO")
                s.numbers.append(try number())
            } else {
                s.expression = try integer()
                if take("GOTO") {
                    s.mode = "GOTO"
                } else {
                    try expect("GOSUB")
                    s.mode = "GOSUB"
                }
                repeat { s.numbers.append(try number()) } while take(",")
            }
            return s
        }
        if take("RESUME") {
            if take("NEXT") {
                s.mode = "NEXT"
            } else if current.kind == "I" {
                s.mode = "line"
                s.numbers.append(try number())
            }
            return s
        }
        if take("FOR") {
            let token = current
            if token.kind != "W" || !variable(token.text) ||
               nameType(token.text) != "I" { try syntax() }
            s.name = token.text
            index += 1
            try expect("=")
            s.expressions.append(try integer())
            try expect("TO")
            s.expressions.append(try integer())
            s.expressions.append(take("STEP") ? try integer() :
                                 Expression("constant", "I", .integer(1)))
            return s
        }
        if take("NEXT") {
            if current.kind == "W" && variable(current.text) &&
               nameType(current.text) == "I" {
                s.name = current.text
                index += 1
            }
            return s
        }
        if take("WHILE") || take("RANDOMIZE") {
            s.expression = try integer()
            return s
        }
        if take("RESTORE") {
            if current.kind == "I" { s.numbers.append(try number()) }
            return s
        }
        _ = take("LET")
        s.kind = "assign"
        s.target = try target()
        try expect("=")
        s.expression = try expression()
        if s.expression!.type != s.target!.type { try syntax() }
        return s
    }

    func parse() throws -> [Statement] {
        let result = try list()
        if current.kind != "E" { try syntax() }
        return result
    }
}

struct BasicArray {
    let bounds: [Int]
    var values: [Value]
}

struct Address {
    let name: String
    let index: Int?
}

struct Frame {
    let kind: String
    let position: Statement?
    let name: String
    let limit: Int
    let step: Int

    init(_ kind: String, _ position: Statement?, name: String = "",
         limit: Int = 0, step: Int = 0) {
        self.kind = kind
        self.position = position
        self.name = name
        self.limit = limit
        self.step = step
    }
}

final class Machine {
    private let inputs: [String]
    private var variables: [String: Value] = [:]
    private var arrays: [String: BasicArray] = [:]
    private var stack: [Frame] = []
    private var entries: [Int: Statement] = [:]
    private var sequence: [Statement] = []
    private var data: [(line: Int, value: Value)] = []
    private var dataPosition = 0
    private var inputPosition = 0
    private var randomState = 1
    private var handler = 0
    private var handling = false
    private var remembered: Statement?
    private var err = 0
    private var erl = 0
    private var buffer = ""
    private var output: [String] = []

    init(_ inputs: [String]) {
        self.inputs = inputs
    }

    private func endLine() {
        while buffer.hasSuffix(" ") { buffer.removeLast() }
        output.append(buffer)
        buffer = ""
    }

    private func message(_ text: String) {
        if !buffer.isEmpty { endLine() }
        output.append(text)
    }

    private func checked(_ value: Int) throws -> Int {
        if value < -32768 || value > 32767 { try fault("OVERFLOW") }
        return value
    }

    private func get(_ name: String) -> Value {
        variables[name] ?? (nameType(name) == "S" ? .text("") : .integer(0))
    }

    private func declare(_ name: String, _ bounds: [Int]) {
        let count = bounds.reduce(1) { $0 * ($1 + 1) }
        let zero: Value = nameType(name) == "S" ? .text("") : .integer(0)
        arrays[name] = BasicArray(bounds: bounds, values: Array(repeating: zero, count: count))
    }

    private func address(_ expression: Expression) throws -> Address {
        let name = expression.value.string
        if expression.kind == "variable" { return Address(name: name, index: nil) }
        let indices = try expression.args.map { try evaluate($0).number }
        if arrays[name] == nil { declare(name, Array(repeating: 10, count: indices.count)) }
        let array = arrays[name]!
        if indices.count != array.bounds.count { try fault("SUBSCRIPT OUT OF RANGE") }
        var index = 0
        for (i, value) in indices.enumerated() {
            if value < 0 || value > array.bounds[i] { try fault("SUBSCRIPT OUT OF RANGE") }
            index = index * (array.bounds[i] + 1) + value
        }
        return Address(name: name, index: index)
    }

    private func load(_ address: Address) -> Value {
        if let index = address.index { return arrays[address.name]!.values[index] }
        return get(address.name)
    }

    private func store(_ address: Address, _ value: Value) {
        if let index = address.index {
            arrays[address.name]!.values[index] = value
        } else {
            variables[address.name] = value
        }
    }

    private func power(_ base: Int, _ exponent: Int) throws -> Int {
        if exponent < 0 { try fault("ILLEGAL FUNCTION CALL") }
        var n = exponent
        var x = base
        var result = 1
        while n > 0 {
            if n % 2 != 0 { result = try checked(result * x) }
            n /= 2
            if n > 0 { x = try checked(x * x) }
        }
        return result
    }

    private func evaluate(_ expression: Expression) throws -> Value {
        let op = expression.value.stringIfText
        if expression.kind == "constant" { return expression.value }
        if expression.kind == "variable" || expression.kind == "array" {
            return load(try address(expression))
        }
        if expression.kind == "builtin" {
            return .integer(op == "ERR" ? err : erl)
        }
        if expression.kind == "unary" {
            let a = try evaluate(expression.args[0]).number
            return .integer(op == "NOT" ? ~a : try checked(-a))
        }
        let args = try expression.args.map { try evaluate($0) }
        if expression.kind == "call" { return try call(op, args) }
        let a = args[0], b = args[1]
        if ["=", "<>", "<", ">", "<=", ">="].contains(op) {
            let order: Int
            if a == b { order = 0 }
            else if a.type == "S" {
                order = a.string < b.string ? -1 : 1
            } else {
                order = a.number < b.number ? -1 : 1
            }
            let answer: Bool
            switch op {
            case "=": answer = order == 0
            case "<>": answer = order != 0
            case "<": answer = order < 0
            case ">": answer = order > 0
            case "<=": answer = order <= 0
            default: answer = order >= 0
            }
            return .integer(answer ? -1 : 0)
        }
        if expression.type == "S" {
            let result = a.string + b.string
            if result.utf8.count > 255 { try fault("STRING TOO LONG") }
            return .text(result)
        }
        let x = a.number, y = b.number
        switch op {
        case "+": return .integer(try checked(x + y))
        case "-": return .integer(try checked(x - y))
        case "*": return .integer(try checked(x * y))
        case "/":
            if y == 0 { try fault("DIVISION BY ZERO") }
            return .integer(try checked(x / y))
        case "MOD":
            if y == 0 { try fault("DIVISION BY ZERO") }
            return .integer(x % y)
        case "^": return .integer(try power(x, y))
        case "AND": return .integer(x & y)
        case "OR": return .integer(x | y)
        default: try syntax()
        }
    }

    private func call(_ name: String, _ args: [Value]) throws -> Value {
        let n = args[0].type == "I" ? args[0].number : 0
        let s = args[0].type == "S" ? args[0].string : ""
        let k = args.count > 1 && args[1].type == "I" ? args[1].number : 0
        switch name {
        case "ABS": return .integer(try checked(abs(n)))
        case "SGN": return .integer(n == 0 ? 0 : n > 0 ? 1 : -1)
        case "INT": return .integer(n)
        case "SQR":
            if n < 0 { try fault("ILLEGAL FUNCTION CALL") }
            return .integer(Int(sqrt(Double(n))))
        case "RND":
            if n < 1 { try fault("ILLEGAL FUNCTION CALL") }
            randomState = randomState * 48271 % 2147483647
            return .integer(randomState % n + 1)
        case "LEN": return .integer(s.utf8.count)
        case "ASC":
            if s.isEmpty { try fault("ILLEGAL FUNCTION CALL") }
            return .integer(Int(s.utf8.first!))
        case "VAL":
            let bytes = Array(s.utf8)
            var i = 0
            while i < bytes.count && bytes[i] == 32 { i += 1 }
            let start = i
            if i < bytes.count && (bytes[i] == 43 || bytes[i] == 45) { i += 1 }
            let digits = i
            while i < bytes.count && digit(bytes[i]) { i += 1 }
            if digits == i { return .integer(0) }
            let value = Int(String(decoding: bytes[start..<i], as: UTF8.self))
            guard let value else { try fault("OVERFLOW") }
            return .integer(try checked(value))
        case "CHR$":
            if n < 32 || n > 126 { try fault("ILLEGAL FUNCTION CALL") }
            return .text(String(UnicodeScalar(n)!))
        case "STR$": return .text(String(n))
        case "LEFT$":
            if k < 0 { try fault("ILLEGAL FUNCTION CALL") }
            return .text(String(s.prefix(k)))
        case "RIGHT$":
            if k < 0 { try fault("ILLEGAL FUNCTION CALL") }
            return .text(String(s.suffix(k)))
        case "MID$":
            let length = args.count == 3 ? args[2].number : s.count
            if k < 1 || length < 0 { try fault("ILLEGAL FUNCTION CALL") }
            return .text(String(s.dropFirst(k - 1).prefix(length)))
        case "INSTR":
            guard let range = s.range(of: args[1].string) else { return .integer(0) }
            return .integer(s.distance(from: s.startIndex, to: range.lowerBound) + 1)
        default: try syntax()
        }
    }

    private func line(_ number: Int) throws -> Statement {
        guard let value = entries[number] else { try fault("UNDEFINED LINE NUMBER") }
        return value
    }

    private func push(_ frame: Frame) throws {
        if stack.count == 100 { try fault("OUT OF MEMORY") }
        stack.append(frame)
    }

    private func search(_ kind: String, _ name: String = "") -> Int {
        for i in stack.indices.reversed() {
            let frame = stack[i]
            if frame.kind == "GOSUB" { break }
            if frame.kind == kind && (name.isEmpty || frame.name == name) { return i }
        }
        return -1
    }

    private func matching(_ s: Statement, _ open: String, _ close: String) throws -> Statement? {
        let index = sequence.firstIndex { $0 === s }!
        var depth = 0
        if index + 1 < sequence.count {
            for i in (index + 1)..<sequence.count {
                let candidate = sequence[i]
                if candidate.kind == open { depth += 1 }
                else if candidate.kind == close {
                    if depth == 0 { return candidate.next }
                    depth -= 1
                }
            }
        }
        try fault(open + " WITHOUT " + close)
    }

    private func subroutine(_ number: Int, _ after: Statement?) throws -> Statement {
        let destination = try line(number)
        try push(Frame("GOSUB", after))
        return destination
    }

    private func execute(_ s: Statement) throws -> Statement? {
        var next = s.next
        switch s.kind {
        case "REM", "DATA": break
        case "assign":
            let place = try address(s.target!)
            store(place, try evaluate(s.expression!))
        case "PRINT":
            for item in s.items {
                if item.kind == "," {
                    buffer += String(repeating: " ", count: 10 - buffer.utf8.count % 10)
                } else if item.kind != ";" {
                    let value = try evaluate(item.expression!)
                    if item.kind == "value" {
                        buffer += value.rendered
                    } else {
                        let amount = value.number
                        if amount < 0 { try fault("ILLEGAL FUNCTION CALL") }
                        let spaces = item.kind == "SPC"
                            ? amount : max(0, amount - buffer.utf8.count)
                        buffer += String(repeating: " ", count: spaces)
                    }
                }
            }
            if s.items.isEmpty || ![";", ","].contains(s.items.last!.kind) { endLine() }
        case "INPUT", "READ":
            for target in s.targets {
                let place = try address(target)
                let value: Value
                if s.kind == "READ" {
                    if dataPosition == data.count { try fault("OUT OF DATA") }
                    value = data[dataPosition].value
                    dataPosition += 1
                    if value.type != target.type { try fault("TYPE MISMATCH") }
                } else {
                    var input: Value
                    while true {
                        if inputPosition == inputs.count { try fault("INPUT PAST END") }
                        let text = inputs[inputPosition]
                        inputPosition += 1
                        if target.type == "S" {
                            input = .text(text)
                            break
                        }
                        let bytes = Array(text.utf8)
                        let start = bytes.first == 45 ? 1 : 0
                        if start < bytes.count &&
                           bytes[start...].allSatisfy({ digit($0) }),
                           let number = Int(text), number >= -32768 && number <= 32767 {
                            input = .integer(number)
                            break
                        }
                        message("?REDO FROM START")
                    }
                    value = input
                }
                store(place, value)
            }
        case "RESTORE":
            if let number = s.numbers.first {
                _ = try line(number)
                dataPosition = data.firstIndex { $0.line >= number } ?? data.count
            } else {
                dataPosition = 0
            }
        case "IF":
            let index = try evaluate(s.expression!).number != 0 ? 0 : 1
            if index < s.clauses.count {
                let clause = s.clauses[index]
                next = try clause.number.map { try line($0) } ?? clause.body.first
            }
        case "GOTO": next = try line(s.numbers[0])
        case "GOSUB": next = try subroutine(s.numbers[0], next)
        case "ON":
            let number = try evaluate(s.expression!).number
            if number < 0 { try fault("ILLEGAL FUNCTION CALL") }
            if number >= 1 && number <= s.numbers.count {
                let destination = s.numbers[number - 1]
                next = try s.mode == "GOTO" ? line(destination) : subroutine(destination, next)
            }
        case "RETURN":
            guard let i = stack.lastIndex(where: { $0.kind == "GOSUB" })
            else { try fault("RETURN WITHOUT GOSUB") }
            next = stack[i].position
            stack.removeSubrange(i..<stack.count)
        case "FOR":
            let values = try s.expressions.map { try evaluate($0).number }
            let start = values[0], last = values[1], step = values[2]
            if step == 0 { try fault("ILLEGAL FUNCTION CALL") }
            let found = search("FOR", s.name)
            if found >= 0 { stack.removeSubrange(found..<stack.count) }
            variables[s.name] = .integer(start)
            if step > 0 ? start > last : start < last {
                next = try matching(s, "FOR", "NEXT")
            } else {
                try push(Frame("FOR", next, name: s.name, limit: last, step: step))
            }
        case "NEXT":
            let found = search("FOR", s.name)
            if found < 0 { try fault("NEXT WITHOUT FOR") }
            stack.removeSubrange((found + 1)..<stack.count)
            let frame = stack[found]
            let value = try checked(get(frame.name).number + frame.step)
            variables[frame.name] = .integer(value)
            if frame.step > 0 ? value > frame.limit : value < frame.limit {
                stack.removeLast()
            } else {
                next = frame.position
            }
        case "WHILE":
            if try evaluate(s.expression!).number != 0 {
                try push(Frame("WHILE", s))
            } else {
                next = try matching(s, "WHILE", "WEND")
            }
        case "WEND":
            let found = search("WHILE")
            if found < 0 { try fault("WEND WITHOUT WHILE") }
            next = stack[found].position
            stack.removeSubrange(found..<stack.count)
        case "DIM":
            for target in s.targets {
                let name = target.value.string
                let bounds = try target.args.map { try evaluate($0).number }
                if arrays[name] != nil { try fault("DUPLICATE DEFINITION") }
                if bounds.contains(where: { $0 < 0 }) { try fault("ILLEGAL FUNCTION CALL") }
                if bounds.reduce(1, { $0 * ($1 + 1) }) > 10000 { try fault("OUT OF MEMORY") }
                declare(name, bounds)
            }
        case "RANDOMIZE":
            let n = try evaluate(s.expression!).number
            if n < 1 { try fault("ILLEGAL FUNCTION CALL") }
            randomState = n
        case "handler":
            if s.numbers[0] != 0 { _ = try line(s.numbers[0]) }
            handler = s.numbers[0]
        case "RESUME":
            if !handling { try fault("RESUME WITHOUT ERROR") }
            if s.mode == "line" {
                next = try line(s.numbers[0])
            } else if s.mode == "NEXT" {
                next = remembered!.next
            } else {
                next = remembered
            }
            handling = false
        case "STOP":
            message("BREAK IN LINE " + String(s.line))
            return nil
        case "END": return nil
        default: break
        }
        return next
    }

    private func connect(_ body: [Statement], _ after: Statement?, _ number: Int) {
        var next = after
        for statement in body.reversed() {
            statement.line = number
            statement.next = next
            for clause in statement.clauses {
                connect(clause.body, next, number)
            }
            next = statement
        }
    }

    private func finish() -> [String] {
        if !buffer.isEmpty { endLine() }
        output.append("READY")
        return output
    }

    func run(_ source: [Int: String]) -> [String] {
        var parsed: [(line: Int, statements: [Statement])] = []
        for number in source.keys.sorted() {
            do {
                let statements = try Parser(try tokenize(source[number]!)).parse()
                parsed.append((number, statements))
            } catch is SyntaxFault {
                message("ERROR IN LINE " + String(number) + ": SYNTAX ERROR")
                return finish()
            } catch {
                message("ERROR IN LINE " + String(number) + ": SYNTAX ERROR")
                return finish()
            }
        }
        var after: Statement?
        for (number, statements) in parsed.reversed() {
            connect(statements, after, number)
            entries[number] = statements.first!
            after = statements.first
        }
        for (number, statements) in parsed {
            for statement in statements {
                sequence.append(statement)
                if statement.kind == "DATA" {
                    for value in statement.values { data.append((number, value)) }
                }
            }
        }
        var position = after
        while let statement = position {
            do {
                position = try execute(statement)
            } catch let error as BasicFault {
                if handler != 0 && !handling {
                    err = errorCodes[error.message] ?? 0
                    erl = statement.line
                    remembered = statement
                    handling = true
                    position = try? line(handler)
                } else {
                    message("ERROR IN LINE " + String(statement.line) + ": " + error.message)
                    position = nil
                }
            } catch {
                position = nil
            }
        }
        return finish()
    }
}

extension Value {
    var stringIfText: String {
        if case .text(let value) = self { return value }
        return ""
    }
}

let input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
let lines = input.components(separatedBy: "\n")
var cursor = 0
let sessions = Int(lines[cursor].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
cursor += 1
var output = ""
for _ in 0..<sessions {
    var source: [Int: String] = [:]
    while cursor < lines.count && lines[cursor] != "RUN" {
        let text = lines[cursor]
        cursor += 1
        let bytes = Array(text.utf8)
        var p = 0
        while p < bytes.count && digit(bytes[p]) { p += 1 }
        guard p > 0, let number = Int(String(decoding: bytes[0..<p], as: UTF8.self))
        else { continue }
        if p == bytes.count {
            source.removeValue(forKey: number)
        } else {
            while p < bytes.count && bytes[p] == 32 { p += 1 }
            source[number] = String(decoding: bytes[p..<bytes.count], as: UTF8.self)
        }
    }
    cursor += 1
    var data: [String] = []
    while cursor < lines.count && lines[cursor] != "END" {
        data.append(lines[cursor])
        cursor += 1
    }
    cursor += 1
    for line in Machine(data).run(source) {
        output += line + "\n"
    }
}
print(output, terminator: "")
