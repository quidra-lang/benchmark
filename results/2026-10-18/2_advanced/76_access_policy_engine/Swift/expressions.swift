import Foundation

indirect enum Expression {
    case literal(Value)
    case attribute(String)
    case current
    case operation(String, [Expression])
}

final class ExpressionParser {
    let tokens: [String]
    var position = 0

    init(_ text: String) {
        let bytes = Array(text.utf8)
        var tokens: [String] = [], p = 0
        func letter(_ b: UInt8) -> Bool { (65...90).contains(b) || (97...122).contains(b) }
        while p < bytes.count {
            if bytes[p] == 32 { p += 1; continue }
            let start = p
            if bytes[p] == 34 {
                p += 1
                while bytes[p] != 34 { p += 1 }
                p += 1
            } else if (48...57).contains(bytes[p]) {
                while p < bytes.count && (48...57).contains(bytes[p]) { p += 1 }
            } else if letter(bytes[p]) {
                while p < bytes.count && (letter(bytes[p]) || (48...57).contains(bytes[p])
                    || bytes[p] == 95 || bytes[p] == 46) { p += 1 }
            } else {
                p += 1
                if p < bytes.count && bytes[p] == 61 && [33, 60, 61, 62].contains(bytes[start]) { p += 1 }
            }
            tokens.append(String(bytes: bytes[start..<p], encoding: .ascii)!)
        }
        self.tokens = tokens
    }

    var peek: String { position < tokens.count ? tokens[position] : "" }
    func take() -> String { defer { position += 1 }; return tokens[position] }

    func joined(_ next: () -> Expression, _ operators: Set<String>) -> Expression {
        var result = next()
        while operators.contains(peek) {
            let name = take()
            result = .operation(name, [result, next()])
        }
        return result
    }

    func disjunction() -> Expression { joined(conjunction, ["or"]) }
    func conjunction() -> Expression { joined(negation, ["and"]) }
    func negation() -> Expression {
        if peek == "not" { _ = take(); return .operation("not", [negation()]) }
        return comparison()
    }
    func comparison() -> Expression {
        let left = sum()
        if ["==", "!=", "<", "<=", ">", ">=", "in"].contains(peek) {
            let name = take()
            return .operation(name, [left, sum()])
        }
        return left
    }
    func sum() -> Expression { joined(product, ["+", "-"]) }
    func product() -> Expression { joined(unary, ["*"]) }
    func unary() -> Expression {
        if peek == "-" { _ = take(); return .operation("-", [unary()]) }
        return primary()
    }
    func primary() -> Expression {
        let token = take()
        if let number = Int(token) { return .literal(.integer(number)) }
        if token.hasPrefix("\"") { return .literal(.string(String(token.dropFirst().dropLast()))) }
        if token == "true" || token == "false" { return .literal(.boolean(token == "true")) }
        if token == "it" { return .current }
        if token.contains(".") { return .attribute(token) }
        if token == "(" {
            let result = disjunction()
            _ = take()
            return result
        }
        if token == "[" {
            var values: [String] = []
            while peek != "]" {
                values.append(String(take().dropFirst().dropLast()))
                if peek != "]" { _ = take() }
            }
            _ = take()
            return .literal(.bag(values))
        }
        _ = take()
        var arguments: [Expression] = []
        while peek != ")" {
            arguments.append(disjunction())
            if peek != ")" { _ = take() }
        }
        _ = take()
        return .operation(token, arguments)
    }
}

func parseExpression(_ text: String) -> Expression { ExpressionParser(text).disjunction() }
