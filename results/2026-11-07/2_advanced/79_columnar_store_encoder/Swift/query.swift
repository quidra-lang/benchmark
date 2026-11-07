import Foundation

struct Literal {
    let type: ColumnType
    let value: Value
}
struct SelectItem {
    let operation: String
    let name: String?
}
struct Comparison {
    let operation: String
    let name: String
    let literals: [Literal]
}
indirect enum RawCondition {
    case comparison(Comparison)
    case not(RawCondition)
    case pair(String, RawCondition, RawCondition)
}
struct RawQuery {
    let items: [SelectItem]?
    let condition: RawCondition?
    let group: String?
    let order: String?
    let descending: Bool
    let limit: Int?
}
final class QueryParser {
    let tokens: [String]
    var position = 0
    init(_ text: String) {
        let bytes = Array(text.utf8)
        var tokens: [String] = [], p = 0
        func letter(_ b: UInt8) -> Bool { (65...90).contains(b) || (97...122).contains(b) || b == 95 }
        while p < bytes.count {
            if bytes[p] == 32 { p += 1; continue }
            let start = p
            if bytes[p] == 39 { p += 1; while bytes[p] != 39 { p += 1 }; p += 1 }
            else if letter(bytes[p]) { repeat { p += 1 } while p < bytes.count && (letter(bytes[p]) || (48...57).contains(bytes[p])) }
            else if (48...57).contains(bytes[p]) || bytes[p] == 45 { repeat { p += 1 } while p < bytes.count && (48...57).contains(bytes[p]) }
            else {
                p += 1
                if p < bytes.count && ((bytes[start] == 60 && (bytes[p] == 61 || bytes[p] == 62)) || (bytes[start] == 62 && bytes[p] == 61)) { p += 1 }
            }
            tokens.append(String(bytes: bytes[start..<p], encoding: .ascii)!)
        }
        self.tokens = tokens
    }
    var peek: String { position < tokens.count ? tokens[position] : "" }
    func take() -> String { defer { position += 1 }; return tokens[position] }
    func accept(_ token: String) -> Bool { if peek == token { position += 1; return true }; return false }
    func parse() -> RawQuery {
        _ = take()
        var items: [SelectItem]?
        if !accept("*") { items = [item()]; while accept(",") { items!.append(item()) } }
        let condition = accept("WHERE") ? self.condition() : nil
        var group: String?, order: String?, descending = false
        if accept("GROUP") { _ = take(); group = take() }
        if accept("ORDER") { _ = take(); order = take(); descending = accept("DESC"); if !descending { _ = accept("ASC") } }
        let limit = accept("LIMIT") ? Int(take())! : nil
        return RawQuery(items: items, condition: condition, group: group, order: order, descending: descending, limit: limit)
    }
    func item() -> SelectItem {
        let name = take()
        if let first = name.utf8.first, (97...122).contains(first) { return SelectItem(operation: "COLUMN", name: name) }
        _ = take()
        let operation = accept("DISTINCT") ? "COUNT_DISTINCT" : name
        let column = accept("*") ? nil : take()
        _ = take()
        return SelectItem(operation: operation, name: column)
    }
    func literal() -> Literal {
        let token = take()
        if token.hasPrefix("'") { return Literal(type: .string, value: .string(String(token.dropFirst().dropLast()))) }
        if token == "TRUE" || token == "FALSE" { return Literal(type: .bool, value: .boolean(token == "TRUE")) }
        return Literal(type: .int, value: .integer(Int(token)!))
    }
    func condition() -> RawCondition {
        var tree = conjunction()
        while accept("OR") { tree = .pair("OR", tree, conjunction()) }
        return tree
    }
    func conjunction() -> RawCondition {
        var tree = negation()
        while accept("AND") { tree = .pair("AND", tree, negation()) }
        return tree
    }
    func negation() -> RawCondition {
        if accept("NOT") { return .not(negation()) }
        if accept("(") { let tree = condition(); _ = take(); return tree }
        let name = take()
        var operation = take(), literals: [Literal] = []
        if operation == "IS" { operation = accept("NOT") ? "IS_NOT_NULL" : "IS_NULL"; _ = take() }
        else if operation == "BETWEEN" { let first = literal(); _ = take(); literals = [first, literal()] }
        else if operation == "IN" { _ = take(); literals = [literal()]; while accept(",") { literals.append(literal()) }; _ = take() }
        else { literals = [literal()] }
        return .comparison(Comparison(operation: operation, name: name, literals: literals))
    }
}
