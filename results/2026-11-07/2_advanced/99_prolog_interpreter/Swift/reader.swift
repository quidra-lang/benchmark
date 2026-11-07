import Foundation
struct Token {
    let kind: String
    let spelling: String
    let name: String
    let line: Int
    let column: Int
    let space: Bool
}
struct ReadError: Error {
    let line: Int
    let column: Int
    let message: String
    let index: Int
    let eof: Bool
}
struct Variable {
    let name: String
    let term: Term
    var count: Int
}
struct Parsed {
    let term: Term
    let variables: [Variable]
    let next: Int
}
func symbol(_ byte: UInt8) -> Bool {
    Array("+-*/\\^<>=~:.?@#&$".utf8).contains(byte)
}
func digit(_ byte: UInt8) -> Bool {
    byte >= 48 && byte <= 57
}
func lower(_ byte: UInt8) -> Bool {
    byte >= 97 && byte <= 122
}
func alpha(_ byte: UInt8) -> Bool {
    lower(byte) || (byte >= 65 && byte <= 90)
}
func infix(_ name: String) -> (Int, Int, Int)? {
    let p: Int
    let kind: String
    switch name {
        case ":-": p = 1200;
        kind = "xfx"
        case ";": p = 1100;
        kind = "xfy"
        case "->": p = 1050;
        kind = "xfy"
        case ",": p = 1000;
        kind = "xfy"
        case "=", "\\=", "==", "\\==", "is", "=:=", "=\\=", "<", ">", "=<", ">=", "=..":
        p = 700;
        kind = "xfx"
        case "+", "-": p = 500;
        kind = "yfx"
        case "*", "/", "//", "mod", "rem": p = 400;
        kind = "yfx"
        default: return nil
    }
    return (p, kind == "yfx" ? p : p - 1, kind == "xfy" ? p : p - 1)
}
func prefix(_ name: String) -> Int? {
    name == "\\+" ? 900 : name == "-" ? 200 : nil
}
func isOperator(_ name: String) -> Bool {
    infix(name) != nil || prefix(name) != nil
}
func lex(_ text: String, _ firstColumn: Int) -> [Token] {
    let bytes = Array(text.utf8)
    var tokens: [Token] = []
    var i = 0
    var line = 1
    var column = firstColumn
    var space = true
    while i < bytes.count {
        if bytes[i] == 32 {
            i += 1;
            column += 1;
            space = true;
            continue
        }
        if bytes[i] == 10 {
            i += 1;
            line += 1;
            column = 1;
            space = true;
            continue
        }
        if bytes[i] == 37 {
            while i < bytes.count && bytes[i] != 10 {
                i += 1;
                column += 1
            }
            space = true
            continue
        }
        let start = i
        let at = column
        var kind = ""
        var name = ""
        if digit(bytes[i]) {
            i += 1
            while i < bytes.count && digit(bytes[i]) {
                i += 1
            }
            let spelling = String(decoding: bytes[start..<i], as: UTF8.self)
            if let value = Int(spelling), value <= 2147483647 {
                kind = "integer"
            }
            else {
                kind = "invalid";
                name = "integer too large"
            }
        } else if alpha(bytes[i]) || bytes[i] == 95 {
            i += 1
            while i < bytes.count && (alpha(bytes[i]) || digit(bytes[i]) || bytes[i] == 95) {
                i += 1
            }
            kind = lower(bytes[start]) ? "name" : "variable"
        } else if symbol(bytes[i]) {
            i += 1
            while i < bytes.count && symbol(bytes[i]) {
                i += 1
            }
            kind = i - start == 1 && bytes[start] == 46 && (i == bytes.count || [32, 10, 37].contains(bytes[i])) ? "end" : "name"
        } else if bytes[i] == 33 || bytes[i] == 59 {
            i += 1;
            kind = "name"
        } else if Array(",|()[]".utf8).contains(bytes[i]) {
            i += 1;
            kind = "punctuation"
        } else if bytes[i] == 39 {
            i += 1
            var invalid = false
            var closed = false
            var value: [UInt8] = []
            while i < bytes.count && bytes[i] != 10 {
                if bytes[i] == 39 {
                    if i + 1 < bytes.count && bytes[i + 1] == 39 {
                        value.append(39);
                        i += 2
                    }
                    else {
                        i += 1;
                        closed = true;
                        break
                    }
                } else if bytes[i] == 92 {
                    i += 1
                    if i < bytes.count && bytes[i] != 10 {
                        switch bytes[i] {
                            case 110: value.append(10)
                            case 116: value.append(9)
                            case 92, 39: value.append(bytes[i])
                            default: invalid = true
                        }
                        i += 1
                    }
                } else {
                    value.append(bytes[i]);
                    i += 1
                }
            }
            if !closed {
                kind = "invalid";
                name = "unterminated quoted atom"
            }
            else if invalid {
                kind = "invalid";
                name = "undefined escape sequence"
            }
            else {
                kind = "quoted";
                name = String(decoding: value, as: UTF8.self)
            }
        } else {
            i += 1;
            kind = "invalid"
            name = "illegal character '\(String(decoding: [bytes[start]], as: UTF8.self))'"
        }
        let spelling = String(decoding: bytes[start..<i], as: UTF8.self)
        if name.isEmpty && kind != "quoted" {
            name = spelling
        }
        tokens.append(Token(kind: kind, spelling: spelling, name: name, line: line, column: at, space: space))
        column += i - start
        space = false
    }
    tokens.append(Token(kind: "eof", spelling: "", name: "", line: line, column: column, space: space))
    return tokens
}
final class Reader {
    let tokens: [Token]
    let store: Store
    var index: Int
    var variables: [Variable] = []
    var names: [String: Int] = [:]
    var peek: Token {
        tokens[index]
    }
    init(_ tokens: [Token], _ start: Int, _ store: Store) {
        self.tokens = tokens;
        self.index = start;
        self.store = store
    }
    func error(_ i: Int) -> ReadError {
        let token = tokens[i]
        let message: String
        if token.kind == "invalid" {
            message = token.name
        }
        else if token.kind == "eof" {
            message = "unexpected end of file"
        }
        else if token.kind == "end" {
            message = "unexpected end of clause"
        }
        else if token.kind == "name" && infix(token.name) != nil {
            message = "operator priority clash"
        }
        else {
            message = "unexpected \"\(token.spelling)\""
        }
        return ReadError(line: token.line, column: token.column, message: message, index: i, eof: token.kind == "eof")
    }
    @discardableResult func take() -> (Int, Token) {
        let result = (index, peek)
        if peek.kind != "eof" {
            index += 1
        }
        return result
    }
    func expect(_ name: String) throws {
        let (at, token) = take()
        if token.kind != "punctuation" || token.name != name {
            throw error(at)
        }
    }
    func term(_ limit: Int) throws -> (Term, Int) {
        var (term, priority) = try primary(limit)
        while peek.kind == "name" || (peek.kind == "punctuation" && peek.name == ",") {
            guard let (p, left, right) = infix(peek.name), p <= limit, priority <= left else {
                break
            }
            let name = take().1.name
            let argument = try self.term(right).0
            term = .compound(name, [term, argument]);
            priority = p
        }
        return (term, priority)
    }
    func starts(_ token: Token) -> Bool {
        ["integer", "variable", "quoted"].contains(token.kind) ||
        (token.kind == "punctuation" && ["(", "["].contains(token.name)) ||
        (token.kind == "name" && (infix(token.name) == nil || prefix(token.name) != nil))
    }
    func primary(_ limit: Int) throws -> (Term, Int) {
        let (at, token) = take()
        switch token.kind {
            case "integer": return (.integer(Int(token.name)!), 0)
            case "variable":
            if token.name == "_" {
                return (store.fresh(), 0)
            }
            if let i = names[token.name] {
                variables[i].count += 1;
                return (variables[i].term, 0)
            }
            let value = store.fresh()
            names[token.name] = variables.count
            variables.append(Variable(name: token.name, term: value, count: 1))
            return (value, 0)
            case "punctuation" where token.name == "(":
            let result = try term(1200).0
            try expect(")")
            return (result, 0)
            case "punctuation" where token.name == "[":
            if peek.kind == "punctuation" && peek.name == "]" {
                take();
                return (.atom("[]"), 0)
            }
            var elements = [try term(999).0]
            while peek.kind == "punctuation" && peek.name == "," {
                take();
                elements.append(try term(999).0)
            }
            var tail = Term.atom("[]")
            if peek.kind == "punctuation" && peek.name == "|" {
                take();
                tail = try term(999).0
            }
            try expect("]")
            return (list(elements, tail), 0)
            case "name", "quoted":
            if peek.kind == "punctuation" && peek.name == "(" && !peek.space {
                take()
                var args = [try term(999).0]
                while peek.kind == "punctuation" && peek.name == "," {
                    take();
                    args.append(try term(999).0)
                }
                try expect(")")
                return (.compound(token.name, args), 0)
            }
            if token.kind == "name" && token.name == "-" && peek.kind == "integer" && !peek.space {
                return (.integer(-Int(take().1.name)!), 0)
            }
            if token.kind == "name", let p = prefix(token.name), starts(peek) {
                if p > limit {
                    throw ReadError(line: token.line, column: token.column, message: "operator priority clash", index: at, eof: false)
                }
                return (.compound(token.name, [try term(p).0]), p)
            }
            return (.atom(token.name), 0)
            default: throw error(at)
        }
    }
    func clause(_ query: Bool = false) throws -> Parsed {
        let value = try term(1200).0
        let (at, token) = take()
        if token.kind != "end" {
            throw error(at)
        }
        if query && peek.kind != "eof" {
            throw error(index)
        }
        return Parsed(term: value, variables: variables, next: index)
    }
}
