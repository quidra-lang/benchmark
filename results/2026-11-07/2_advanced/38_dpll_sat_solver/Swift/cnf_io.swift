import Foundation

struct Formula {
    let variables: Int
    let clauses: [[Int]]
}

enum InputError: Error {
    case invalid(String)
}

func validNumber(_ token: String) -> Bool {
    guard !token.isEmpty, token.count <= 6, token.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return false }
    return token == "0" || token.first != "0"
}

func validLiteral(_ token: String) -> Bool {
    if token == "0" { return true }
    let digits = token.hasPrefix("-") ? String(token.dropFirst()) : token
    return validNumber(digits) && digits != "0"
}

func readInputLines(_ path: String) throws -> [String] {
    var lines = try String(contentsOfFile: path, encoding: .ascii).components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return lines
}

func readDIMACS(_ filename: String) throws -> Formula {
    var header: (variables: Int, clauses: Int)?
    var clauses: [[Int]] = []
    var partial: [Int] = []
    for (index, line) in try readInputLines("input/" + filename).enumerated() {
        let number = index + 1
        let tokens = line.split(separator: " ").map(String.init)
        if line.hasPrefix("c") || tokens.isEmpty { continue }
        if tokens[0] == "p" {
            if header != nil { throw InputError.invalid("duplicate header at line \(number)") }
            guard tokens.count == 4, tokens[1] == "cnf", validNumber(tokens[2]), validNumber(tokens[3]) else {
                throw InputError.invalid("bad header at line \(number)")
            }
            header = (Int(tokens[2])!, Int(tokens[3])!)
            continue
        }
        guard let header else { throw InputError.invalid("missing header") }
        for token in tokens {
            guard validLiteral(token) else { throw InputError.invalid("bad token \(token) at line \(number)") }
            let literal = Int(token)!
            if abs(literal) > header.variables { throw InputError.invalid("literal out of range \(token) at line \(number)") }
            if literal != 0 { partial.append(literal) }
            else {
                clauses.append(partial)
                partial = []
            }
        }
    }
    guard let header else { throw InputError.invalid("missing header") }
    if !partial.isEmpty { throw InputError.invalid("unterminated clause") }
    if clauses.count != header.clauses {
        throw InputError.invalid("clause count mismatch header=\(header.clauses) found=\(clauses.count)")
    }
    return Formula(variables: header.variables, clauses: clauses)
}

func modelLines(_ model: [Bool]) -> [String] {
    var tokens = (1..<model.count).map { String(model[$0] ? $0 : -$0) }
    tokens.append("0")
    return stride(from: 0, to: tokens.count, by: 10).map {
        "v " + tokens[$0..<min($0 + 10, tokens.count)].joined(separator: " ")
    }
}
