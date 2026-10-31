enum ToyType: String {
    case int, bool, void
}
struct Name {
    let text: String, position: Position
}
final class Variable {
    let type: ToyType, name: Name, size: Int?, sizePosition: Position?
    var initializer: Expr?, id = -1, address = -1, slot = -1
    init(_ type: ToyType, _ name: Name, _ initializer: Expr? = nil, _ size: Int? = nil, _ sizePosition: Position? = nil) {
        self.type = type;
        self.name = name;
        self.initializer = initializer;
        self.size = size;
        self.sizePosition = sizePosition
    }
}
final class Function {
    let type: ToyType, name: Name, parameters: [Variable], body: Stmt
    var id = -1
    init(_ type: ToyType, _ name: Name, _ parameters: [Variable], _ body: Stmt) {
        self.type = type;
        self.name = name;
        self.parameters = parameters;
        self.body = body
    }
}
enum Top {
    case variable(Variable), function(Function)
}
struct Program {
    let declarations: [Top], end: Position
}
final class Expr {
    let position: Position;
    var kind: ExprKind, reference: Int?, type: ToyType?
    init(_ position: Position, _ kind: ExprKind) {
        self.position = position;
        self.kind = kind
    }
}
indirect enum ExprKind {
    case integer(Int), boolean(Bool), read, variable(Name), element(Name, Expr), call(Name, [Expr]), unary(String, Expr), binary(String, Expr, Expr)
}
final class Stmt {
    let position: Position;
    var kind: StmtKind, reference: Int?
    init(_ position: Position, _ kind: StmtKind) {
        self.position = position;
        self.kind = kind
    }
}
indirect enum StmtKind {
    case block([Stmt], Position), declaration(Variable), assignment(Name, Expr?, Expr), call(Expr), conditional(Expr, Stmt, Stmt?), whileLoop(Expr, Stmt), forLoop(Stmt?, Expr?, Stmt?, Stmt), breakLoop, continueLoop, returnValue(Expr?), print([Expr]), empty
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
    var text: String {
        peek.text
    }
    func fail() -> CompileError {
        CompileError(kind: "syntax", position: peek.position, message: peek.kind == "end" ? "unexpected end of program" : "unexpected '\(peek.text)'")
    }
    @discardableResult func take() -> Token {
        let token = peek;
        if token.kind != "end" {
            index += 1
        };
        return token
    }
    @discardableResult func expect(_ text: String) throws -> Token {
        guard self.text == text else {
            throw fail()
        };
        return take()
    }
    func name() throws -> Name {
        guard peek.kind == "identifier" else {
            throw fail()
        };
        let token = take();
        return Name(text: token.text, position: token.position)
    }
    func type() throws -> ToyType {
        guard let type = ToyType(rawValue: text) else {
            throw fail()
        };
        take();
        return type
    }
    func program() throws -> Program {
        var declarations: [Top] = []
        while peek.kind != "end" {
            let type = try self.type(), name = try self.name()
            if text == "(" {
                take();
                var parameters: [Variable] = []
                if text != ")" {
                    while true {
                        let t = try self.type(), n = try self.name();
                        parameters.append(Variable(t, n));
                        if text != "," {
                            break
                        };
                        take()
                    }
                };
                try expect(")")
                declarations.append(.function(Function(type, name, parameters, try block())))
            } else {
                var initializer: Expr?, size: Int?, sizePosition: Position?
                if text == "[" {
                    take();
                    guard peek.kind == "integer" else {
                        throw fail()
                    };
                    sizePosition = peek.position;
                    size = Int(take().text)!;
                    try expect("]")
                }
                else if text == "=" {
                    take();
                    initializer = try expression()
                };
                try expect(";");
                declarations.append(.variable(Variable(type, name, initializer, size, sizePosition)))
            }
        };
        return Program(declarations: declarations, end: peek.position)
    }
    func declaration(_ requiredInitializer: Bool) throws -> Stmt {
        let position = peek.position, type = try self.type(), name = try self.name();
        var initializer: Expr?
        if text == "=" {
            take();
            initializer = try expression()
        } else if requiredInitializer {
            try expect("=")
        }
        return Stmt(position, .declaration(Variable(type, name, initializer)))
    }
    func block() throws -> Stmt {
        let position = try expect("{").position;
        var statements: [Stmt] = []
        while text != "}" {
            if ToyType(rawValue: text) != nil {
                let statement = try declaration(false);
                try expect(";");
                statements.append(statement)
            }
            else {
                statements.append(try statement())
            }
        };
        let close = take().position;
        return Stmt(position, .block(statements, close))
    }
    func statement() throws -> Stmt {
        let position = peek.position
        switch text {
            case "{": return try block()
            case "if": take();
            try expect("(");
            let condition = try expression();
            try expect(")");
            let yes = try statement();
            var no: Stmt?;
            if text == "else" {
                take();
                no = try statement()
            };
            return Stmt(position, .conditional(condition, yes, no))
            case "while": take();
            try expect("(");
            let condition = try expression();
            try expect(")");
            return Stmt(position, .whileLoop(condition, try statement()))
            case "for":
            take();
            try expect("(");
            var initial: Stmt?, condition: Expr?, update: Stmt?
            if text != ";" {
                initial = ToyType(rawValue: text) != nil ? try declaration(true) : try simple()
            };
            try expect(";")
            if text != ";" {
                condition = try expression()
            };
            try expect(";");
            if text != ")" {
                update = try simple()
            };
            try expect(")");
            return Stmt(position, .forLoop(initial, condition, update, try statement()))
            case "break": take();
            try expect(";");
            return Stmt(position, .breakLoop)
            case "continue": take();
            try expect(";");
            return Stmt(position, .continueLoop)
            case "return": take();
            let value = text == ";" ? nil : try expression();
            try expect(";");
            return Stmt(position, .returnValue(value))
            case "print": take();
            try expect("(");
            var values = [try expression()];
            while text == "," {
                take();
                values.append(try expression())
            };
            try expect(")");
            try expect(";");
            return Stmt(position, .print(values))
            default: let result = try simple();
            try expect(";");
            return result
        }
    }
    func simple() throws -> Stmt {
        let position = peek.position
        if text == "read" {
            take();
            try expect("(");
            try expect(")");
            return Stmt(position, .call(Expr(position, .read)))
        }
        let name = try self.name()
        if text == "(" {
            return Stmt(position, .call(Expr(position, .call(name, try arguments()))))
        }
        var index: Expr?;
        if text == "[" {
            take();
            index = try expression();
            try expect("]")
        };
        try expect("=");
        return Stmt(position, .assignment(name, index, try expression()))
    }
    func arguments() throws -> [Expr] {
        try expect("(");
        var values: [Expr] = []
        if text != ")" {
            values.append(try expression());
            while text == "," {
                take();
                values.append(try expression())
            }
        };
        try expect(")");
        return values
    }
    func expression(_ minimum: Int = 1) throws -> Expr {
        var left = try unary()
        func priority(_ op: String) -> Int {
            switch op {
                case "||": return 1;
                case "&&": return 2;
                case "==", "!=": return 3;
                case "<", "<=", ">", ">=": return 4;
                case "+", "-": return 5;
                case "*", "/", "%": return 6;
                default: return 0
            }
        }
        while priority(text) >= minimum {
            let op = take(), right = try expression(priority(op.text) + 1);
            left = Expr(op.position, .binary(op.text, left, right))
        };
        return left
    }
    func unary() throws -> Expr {
        if text == "-" || text == "!" {
            let op = take();
            return Expr(op.position, .unary(op.text, try unary()))
        };
        return try primary()
    }
    func primary() throws -> Expr {
        let token = peek
        if token.kind == "integer" {
            take();
            return Expr(token.position, .integer(Int(token.text)!))
        }
        if text == "true" || text == "false" {
            take();
            return Expr(token.position, .boolean(token.text == "true"))
        }
        if text == "read" {
            take();
            try expect("(");
            try expect(")");
            return Expr(token.position, .read)
        }
        if text == "(" {
            take();
            let value = try expression();
            try expect(")");
            return value
        }
        let name = try self.name()
        if text == "(" {
            return Expr(token.position, .call(name, try arguments()))
        }
        if text == "[" {
            take();
            let index = try expression();
            try expect("]");
            return Expr(token.position, .element(name, index))
        };
        return Expr(token.position, .variable(name))
    }
}
