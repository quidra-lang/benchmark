import Foundation


let expressions = ["3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3",
    "15 7 1 1 + - / 3 * 2 1 1 + + -", "4 2 5 * + 1 3 2 * - 5 + /",
    "2 3 4 + 5", "46341 46339 * -2 /"]
for expression in expressions {
    var stack = [Int]()
    var error: String? = nil
    for raw in expression.split(separator: " ") {
        let token = String(raw)
        if token.count == 1 && "+-*/".contains(token) {
            if stack.count < 2 {
                error = "stack underflow"
                break
            }
            let b = stack.removeLast(), a = stack.removeLast()
            if token == "/" && b == 0 {
                error = "division by zero"
                break
            }
            switch token {
            case "+": stack.append(a + b)
            case "-": stack.append(a - b)
            case "*": stack.append(a * b)
            default: stack.append(a / b)
            }
        } else { stack.append(Int(token)!) }
    }
    if error == nil && stack.count != 1 { error = "leftover operands" }
    let result = error.map { "error: " + $0 } ?? String(stack[0])
    print("\(expression) => \(result)")
}
