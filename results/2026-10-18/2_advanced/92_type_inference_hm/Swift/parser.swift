final class Expr {
    let position: Position, kind: ExprKind
    init(_ position: Position, _ kind: ExprKind) {
        self.position = position;
        self.kind = kind
    }
}
indirect enum ExprKind {
    case integer(Int), boolean(Bool), string(String), name(String), fun(Parameter, Expr), apply(Expr, Expr), binary(String, Position, Expr, Expr), negate(Position, Expr), conditional(Expr, Expr, Expr), pair(Expr, Expr), list([Expr]), match(Expr, [(Pattern, Expr)]), letIn(Group, Expr)
}
struct Parameter {
    let name: String?, position: Position
}
struct Binding {
    let name: String, position: Position, expression: Expr
}
struct Group {
    let recursive: Position?, bindings: [Binding]
}
struct Pattern {
    let position: Position, kind: PatternKind
}
indirect enum PatternKind {
    case wildcard, name(String), integer(Int), boolean(Bool), string(String), nilList, cons(Pattern, Pattern), list([Pattern]), pair(Pattern, Pattern)
}
indirect enum TypeExpression {
    case primitive(String), variable(String), list(TypeExpression), pair(TypeExpression, TypeExpression), function(TypeExpression, TypeExpression)
}
enum Item {
    case signature(String, Position, TypeExpression), declaration(Group), expression(Expr)
}
func precedence(_ op: String) -> Int {
    switch op {
        case "||": return 1;
        case "&&": return 2;
        case "=", "<>", "<", ">", "<=", ">=": return 3;
        case "::", "^": return 4;
        case "+", "-": return 5;
        case "*", "/", "mod": return 6;
        default: return 0
    }
}
func rightAssociative(_ op: String) -> Bool {
    ["||", "&&", "::", "^"].contains(op)
}
final class Parser {
    let tokens: [Token];
    var index = 0
    init(_ tokens: [Token]) {
        self.tokens = tokens
    }
    var peek: Token {
        tokens[index]
    };
    var spelling: String {
        peek.value
    }
    @discardableResult func take() -> Token {
        let token = peek;
        if token.kind != "eof" {
            index += 1
        };
        return token
    }
    @discardableResult func expect(_ word: String) throws -> Token {
        guard spelling == word && peek.kind != "invalid" else {
            throw peek
        };
        return take()
    }
    func name() throws -> Token {
        guard peek.kind == "identifier" && spelling != "_" else {
            throw peek
        };
        return take()
    }
    func parameter() throws -> Parameter {
        guard peek.kind == "identifier" else {
            throw peek
        };
        let token = take();
        return Parameter(name: token.value == "_" ? nil : token.value, position: token.position)
    }
    var atomicStart: Bool {
        ["integer", "string"].contains(peek.kind) || peek.kind == "identifier" && spelling != "_" || peek.kind != "invalid" && ["true", "false", "(", "["].contains(spelling)
    }
    func group() throws -> Group {
        try expect("let");
        let recursive = spelling == "rec" ? take().position : nil
        var bindings: [Binding] = []
        while true {
            let token = try name();
            var parameters: [Parameter] = []
            while peek.kind == "identifier" {
                parameters.append(try parameter())
            }
            try expect("=");
            var body = try expr()
            for parameter in parameters.reversed() {
                body = Expr(parameter.position, .fun(parameter, body))
            }
            bindings.append(Binding(name: token.value, position: token.position, expression: body))
            if spelling != "and" {
                break
            };
            take()
        }
        return Group(recursive: recursive, bindings: bindings)
    }
    func item() throws -> Item {
        let result: Item
        if spelling == "val" {
            take();
            let token = try name();
            try expect(":");
            result = .signature(token.value, token.position, try typeExpression())
        }
        else if spelling == "let" {
            let position = peek.position, group = try self.group()
            if spelling == "in" {
                take();
                result = .expression(Expr(position, .letIn(group, try expr())))
            } else {
                result = .declaration(group)
            }
        } else {
            result = .expression(try expr())
        }
        try expect(";;");
        return result
    }
    func expr() throws -> Expr {
        let position = peek.position
        switch spelling {
            case "let": let group = try self.group();
            try expect("in");
            return Expr(position, .letIn(group, try expr()))
            case "fun":
            take();
            var parameters = [try parameter()]
            while peek.kind == "identifier" {
                parameters.append(try parameter())
            }
            try expect("->");
            var body = try expr()
            for (i, parameter) in parameters.enumerated().reversed() {
                body = Expr(i == 0 ? position : parameter.position, .fun(parameter, body))
            };
            return body
            case "if": take();
            let condition = try expr();
            try expect("then");
            let yes = try expr();
            try expect("else");
            let no = try expr();
            return Expr(position, .conditional(condition, yes, no))
            case "match":
            take();
            let value = try expr();
            try expect("with");
            if spelling == "|" {
                take()
            };
            var arms: [(Pattern, Expr)] = []
            while true {
                let pattern = try self.pattern();
                try expect("->");
                let body = try expr();
                arms.append((pattern, body));
                if spelling != "|" {
                    break
                };
                take()
            }
            return Expr(position, .match(value, arms))
            default: return try binary(1)
        }
    }
    func binary(_ minimum: Int) throws -> Expr {
        var left = try unary()
        while true {
            let priority = precedence(spelling);
            if priority == 0 || priority < minimum {
                break
            }
            let op = take(), right = try binary(rightAssociative(op.value) ? priority : priority + 1)
            left = Expr(left.position, .binary(op.value, op.position, left, right))
        };
        return left
    }
    func unary() throws -> Expr {
        if spelling == "-" {
            let token = take();
            return Expr(token.position, .negate(token.position, try unary()))
        }
        var function = try atomic()
        while atomicStart {
            let argument = try atomic();
            function = Expr(function.position, .apply(function, argument))
        };
        return function
    }
    func atomic() throws -> Expr {
        let token = peek, position = peek.position
        switch token.kind {
            case "integer": take();
            return Expr(position, .integer(Int(token.value)!))
            case "string": take();
            return Expr(position, .string(token.value))
            case "identifier" where token.value != "_": take();
            return Expr(position, .name(token.value))
            default: break
        }
        guard token.kind != "invalid" else {
            throw token
        }
        switch token.value {
            case "true", "false": take();
            return Expr(position, .boolean(token.value == "true"))
            case "(": take();
            let first = try expr();
            if spelling == "," {
                take();
                let second = try expr();
                try expect(")");
                return Expr(position, .pair(first, second))
            };
            try expect(")");
            return first
            case "[":
            take();
            var elements: [Expr] = []
            if spelling != "]" {
                elements.append(try expr());
                while spelling == ";" {
                    take();
                    elements.append(try expr())
                }
            };
            try expect("]");
            return Expr(position, .list(elements))
            default: throw token
        }
    }
    func pattern() throws -> Pattern {
        let head = try atomicPattern()
        if spelling == "::" {
            take();
            return Pattern(position: head.position, kind: .cons(head, try pattern()))
        };
        return head
    }
    func atomicPattern() throws -> Pattern {
        let token = peek, position = peek.position, kind: PatternKind
        switch token.kind {
            case "integer": take();
            kind = .integer(Int(token.value)!)
            case "string": take();
            kind = .string(token.value)
            case "identifier": take();
            kind = token.value == "_" ? .wildcard : .name(token.value)
            default:
            guard token.kind != "invalid" else {
                throw token
            }
            switch token.value {
                case "true", "false": take();
                kind = .boolean(token.value == "true")
                case "-": take();
                guard peek.kind == "integer" else {
                    throw peek
                };
                kind = .integer(-Int(take().value)!)
                case "(": take();
                let first = try pattern();
                if spelling == "," {
                    take();
                    let second = try pattern();
                    try expect(")");
                    kind = .pair(first, second)
                } else {
                    try expect(")");
                    return first
                }
                case "[":
                take();
                var elements: [Pattern] = []
                if spelling != "]" {
                    elements.append(try pattern());
                    while spelling == ";" {
                        take();
                        elements.append(try pattern())
                    }
                };
                try expect("]");
                kind = elements.isEmpty ? .nilList : .list(elements)
                default: throw token
            }
        };
        return Pattern(position: position, kind: kind)
    }
    func typeExpression() throws -> TypeExpression {
        let first = try productType();
        if spelling == "->" {
            take();
            return .function(first, try typeExpression())
        };
        return first
    }
    func productType() throws -> TypeExpression {
        let first = try listType();
        if spelling == "*" {
            take();
            return .pair(first, try listType())
        };
        return first
    }
    func listType() throws -> TypeExpression {
        var type = try typeAtom();
        while peek.kind == "identifier" && spelling == "list" {
            take();
            type = .list(type)
        };
        return type
    }
    func typeAtom() throws -> TypeExpression {
        if peek.kind == "type_variable" {
            return .variable(take().value)
        }
        if peek.kind == "identifier" && ["int", "bool", "string"].contains(spelling) {
            return .primitive(take().value)
        }
        if peek.kind == "symbol" && spelling == "(" {
            take();
            let type = try typeExpression();
            try expect(")");
            return type
        };
        throw peek
    }
    func recover() {
        while peek.kind != "eof" && spelling != ";;" {
            take()
        };
        if spelling == ";;" {
            take()
        }
    }
}
