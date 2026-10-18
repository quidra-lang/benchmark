import Foundation

enum EvaluationError: Error { case failure(String) }
func tokenize(_ text: String) -> [String] {
    let characters = Array(text)
    var tokens = [String](), i = 0
    while i < characters.count {
        let ch = characters[i]
        if ch == " " {
            i += 1
            continue
        }
        let number = ch >= "0" && ch <= "9", name = ch >= "a" && ch <= "z"
        var j = i + 1
        if number || name {
            while j < characters.count {
                let next = characters[j]
                let matches = number ? (next >= "0" && next <= "9") : (next >= "a" && next <= "z")
                if !matches { break }
                j += 1
            }
        }
        tokens.append(String(characters[i..<j]))
        i = j
    }
    return tokens
}
class Parser {
    let tokens: [String], variables: [String:Int]
    var position: Int
    init(_ tokens: [String], _ position: Int, _ variables: [String:Int]) {
        self.tokens = tokens
        self.position = position
        self.variables = variables
    }
    func take(_ token: String) -> Bool {
        if position >= tokens.count || tokens[position] != token { return false }
        position += 1
        return true
    }
    func expression() throws -> Int {
        var result = try term()
        while position < tokens.count && (tokens[position] == "+" || tokens[position] == "-") {
            let operation = tokens[position]
            position += 1
            let right = try term()
            result = operation == "+" ? result + right : result - right
        }
        return result
    }
    func term() throws -> Int {
        var result = try unary()
        while position < tokens.count && (tokens[position] == "*" || tokens[position] == "/") {
            let operation = tokens[position]
            position += 1
            let right = try unary()
            if operation == "/" && right == 0 { throw EvaluationError.failure("division by zero") }
            result = operation == "*" ? result * right : result / right
        }
        return result
    }
    func unary() throws -> Int {
        if take("-") { return -(try unary()) }
        if take("(") {
            let result = try expression()
            _ = take(")")
            return result
        }
        let token = tokens[position]
        position += 1
        if let number = Int(token) { return number }
        guard let value = variables[token] else { throw EvaluationError.failure("undefined variable " + token) }
        return value
    }
}
let lines = ["width = 12", "height = width - 5", "area = width * height", "(area + 6) / 4",
    "shift = -area / 8 + 3", "height = 100 / (height - 7) + bonus", "volume = area * depth",
    "width = (width+3)*-(2-4)", "width * shift - height"]
var variables = [String:Int]()
for line in lines {
    let tokens = tokenize(line), assignment = tokens.count > 1 && tokens[1] == "="
    let name = assignment ? tokens[0] : nil
    do {
        let result = try Parser(tokens,assignment ? 2 : 0,variables).expression()
        if let name = name {
            variables[name] = result
            print("\(name) = \(result)")
        } else { print(result) }
    } catch EvaluationError.failure(let message) {
        print("error: \(message)")
    } catch { fatalError("Unexpected evaluation error") }
}
