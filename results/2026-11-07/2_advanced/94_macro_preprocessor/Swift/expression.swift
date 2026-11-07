indirect enum PPExpression {
    case value(Int), name(String), unary(String, PPExpression), binary(String, PPExpression, PPExpression), conditional(PPExpression, PPExpression, PPExpression)
}
final class ExpressionParser {
    let tokens: [Token];
    var index = 0
    init(_ tokens: [Token]) {
        self.tokens = tokens
    };
    var text: String {
        index < tokens.count ? tokens[index].text : ""
    }
    func priority(_ op: String) -> Int {
        switch op {
            case "||": return 1;
            case "&&": return 2;
            case "|": return 3;
            case "^": return 4;
            case "&": return 5;
            case "==", "!=": return 6;
            case "<", ">", "<=", ">=": return 7;
            case "<<", ">>": return 8;
            case "+", "-": return 9;
            case "*", "/", "%": return 10;
            default: return 0
        }
    }
    func expression() throws -> PPExpression {
        let left = try binary(1)
        if text == "?" {
            index += 1;
            let yes = try expression();
            if text != ":" {
                throw PPError("'?' without following ':'")
            };
            index += 1;
            return .conditional(left, yes, try expression())
        };
        return left
    }
    func binary(_ minimum: Int) throws -> PPExpression {
        var left = try unary()
        while priority(text) >= minimum {
            let op = text;
            index += 1;
            left = .binary(op, left, try binary(priority(op) + 1))
        };
        return left
    }
    func unary() throws -> PPExpression {
        if ["+", "-", "!", "~"].contains(text) {
            let op = text;
            index += 1;
            return .unary(op, try unary())
        }
        guard index < tokens.count else {
            throw PPError("expected value at end of expression")
        };
        let token = tokens[index];
        index += 1
        if token.kind == "number" || token.kind == "character" {
            return .value(try Self.constant(token))
        }
        if token.kind == "identifier" {
            return .name(token.text)
        }
        if token.text == "(" {
            let value = try expression();
            if text != ")" {
                throw PPError("missing ')' in expression")
            };
            index += 1;
            return value
        };
        throw PPError("expected value before \"\(token.text)\"")
    }
    static func constant(_ token: Token) throws -> Int {
        let original = token.text
        if token.kind == "character" {
            let body = Array(original.utf8.dropFirst().dropLast())
            if body.count == 1 && body[0] != 39 && body[0] != 92 {
                return Int(body[0])
            }
            if body.count == 2 && body[0] == 92, let value = [UInt8(110): 10, 116: 9, 92: 92, 39: 39, 34: 34, 48: 0][body[1]] {
                return value
            };
            throw PPError("invalid character constant \(original)")
        }
        var body = original
        for suffix in ["ll", "LL", "l", "L"] where body.count > suffix.count && body.hasSuffix(suffix) {
            body = String(body.dropLast(suffix.count));
            break
        }
        let base: Int, digits: String
        if body.hasPrefix("0x") || body.hasPrefix("0X") {
            base = 16;
            digits = String(body.dropFirst(2))
        } else if body.first == "0" {
            base = 8;
            digits = body
        } else {
            base = 10;
            digits = body
        }
        let valid = !digits.isEmpty && digits.utf8.allSatisfy {
            c in base == 16 ? (48...57).contains(c) || (65...70).contains(c) || (97...102).contains(c) : base == 8 ? (48...55).contains(c) : (48...57).contains(c)
        }
        if valid, let value = Int(digits, radix: base) {
            return value
        };
        throw PPError("invalid integer constant \"\(original)\"")
    }
    static func evaluate(_ expression: PPExpression, _ diagnostics: inout [(String, String)]) throws -> Int {
        switch expression {
            case .value(let value): return value
            case .name(let name): diagnostics.append(("warning", "identifier \"\(name)\" evaluates to 0"));
            return 0
            case .unary(let op, let operand): let value = try evaluate(operand, &diagnostics);
            switch op {
                case "+": return value;
                case "-": return -value;
                case "!": return value == 0 ? 1 : 0;
                default: return -value - 1
            }
            case .conditional(let condition, let yes, let no): let value = try evaluate(condition, &diagnostics);
            return try evaluate(value != 0 ? yes : no, &diagnostics)
            case .binary(let op, let left, let right):
            let a = try evaluate(left, &diagnostics);
            if op == "&&" && a == 0 {
                return 0
            };
            if op == "||" && a != 0 {
                return 1
            };
            let b = try evaluate(right, &diagnostics)
            if (op == "/" || op == "%") && b == 0 {
                throw PPError("division by zero in #if")
            }
            switch op {
                case "+": return a + b;
                case "-": return a - b;
                case "*": return a * b;
                case "/": return a / b;
                case "%": return a % b;
                case "<<": return a << b;
                case ">>": return a >> b;
                case "&": return a & b;
                case "|": return a | b;
                case "^": return a ^ b;
                case "&&", "||": return b == 0 ? 0 : 1;
                case "<": return a < b ? 1 : 0;
                case ">": return a > b ? 1 : 0;
                case "<=": return a <= b ? 1 : 0;
                case ">=": return a >= b ? 1 : 0;
                case "==": return a == b ? 1 : 0;
                default: return a != b ? 1 : 0
            }
        }
    }
    static func test(_ tokens: [Token], _ directive: String) -> (Int?, [(String, String)]) {
        let parser = ExpressionParser(tokens);
        var diagnostics: [(String, String)] = []
        do {
            if tokens.isEmpty {
                throw PPError("#\(directive) with no expression")
            };
            let expression = try parser.expression()
            if parser.index != tokens.count {
                throw PPError("missing binary operator before \"\(tokens[parser.index].text)\"")
            };
            return (try evaluate(expression, &diagnostics), diagnostics)
        } catch let error as PPError {
            diagnostics.append(("error", error.message));
            return (nil, diagnostics)
        } catch {
            preconditionFailure()
        }
    }
}
