final class Expr {
    let position: Position, kind: ExprKind
    init(_ position: Position, _ kind: ExprKind) {
        self.position = position;
        self.kind = kind
    }
    var lvalue: Bool {
        switch kind {
            case .name, .index, .field: return true;
            default: return false
        }
    }
}
indirect enum ExprKind {
    case number(Int), string(String), name(String), index(String, [Expr]), field(Expr), parentheses(Expr), unary(String, Expr), binary(String, Expr, Expr), assignment(String, Expr, Expr), increment(Int, Bool, Expr), conditional(Expr, Expr, Expr), member([Expr], String, Position), call(String, Bool, [Expr]), getline(Expr?, Expr?)
}
final class Stmt {
    let position: Position, kind: StmtKind;
    init(_ position: Position, _ kind: StmtKind) {
        self.position = position;
        self.kind = kind
    }
}
struct Redirect {
    let append: Bool, expression: Expr, position: Position
}
indirect enum StmtKind {
    case block([Stmt]), empty, expression(Expr), conditional(Expr, Stmt, Stmt?), whileLoop(Expr, Stmt), doLoop(Stmt, Expr), forLoop(Expr?, Expr?, Expr?, Stmt), forIn(String, Position, String, Position, Stmt), output(Bool, [Expr], Redirect?), delete(String, Position, [Expr]?), next, breakLoop, continueLoop, exit(Expr?), returnValue(Expr?)
}
struct Function {
    let name: String, position: Position, parameters: [(String, Position)], body: Stmt
}
struct Rule {
    let kind: String, position: Position, start: Expr?, end: Expr?, action: Stmt?
}
struct Program {
    let rules: [Rule], functions: [Function]
}
final class Parser {
    let tokens: [Token];
    var index = 0, function = false, special = false, loops = 0
    init(_ tokens: [Token]) {
        self.tokens = tokens
    };
    var peek: Token {
        tokens[index]
    };
    var text: String {
        peek.text
    }
    @discardableResult func take() -> Token {
        let token = peek;
        if token.kind != "end" {
            index += 1
        };
        return token
    }
    @discardableResult func expect(_ text: String) throws -> Token {
        guard self.text == text && peek.kind != "end" else {
            throw peek.position
        };
        return take()
    }
    func name() throws -> Token {
        guard peek.kind == "name" else {
            throw peek.position
        };
        return take()
    }
    func newlines() {
        while peek.kind == "newline" {
            take()
        }
    }
    func terminator() throws {
        if text == ";" || peek.kind == "newline" {
            take()
        } else if text != "}" {
            throw peek.position
        }
    }
    func expressions(_ suppress: Bool) throws -> [Expr] {
        var result = [try expression(suppress)];
        while text == "," {
            take();
            newlines();
            result.append(try expression(suppress))
        };
        return result
    }
    func expression(_ suppress: Bool = false) throws -> Expr {
        let left = try conditional(suppress)
        if left.lvalue && ["=", "+=", "-=", "*=", "/=", "%=", "^="].contains(text) {
            let token = take();
            return Expr(token.position, .assignment(token.text, left, try expression(suppress)))
        };
        return left
    }
    func conditional(_ suppress: Bool) throws -> Expr {
        let condition = try binary(1, suppress)
        if text == "?" {
            let token = take(), yes = try conditional(suppress);
            try expect(":");
            return Expr(token.position, .conditional(condition, yes, try conditional(suppress)))
        };
        return condition
    }
    func binary(_ minimum: Int, _ suppress: Bool) throws -> Expr {
        var left = try unary(suppress)
        while true {
            let explicit: Int
            switch text {
                case "||": explicit = 1;
                case "&&": explicit = 2;
                case "in": explicit = 3;
                case "<", "<=", "==", "!=", ">=": explicit = 4;
                case ">" where !suppress: explicit = 4;
                case "+", "-": explicit = 6;
                case "*", "/", "%": explicit = 7;
                default: explicit = 0
            }
            let concat = explicit == 0 && (["number", "string", "name", "function", "builtin"].contains(peek.kind) || ["$", "(", "++", "--"].contains(text)), priority = concat ? 5 : explicit
            if priority == 0 || priority < minimum {
                return left
            }
            if explicit == 3 {
                let token = take(), name = try self.name();
                left = Expr(token.position, .member([left], name.text, name.position));
                continue
            }
            let position = peek.position, op = concat ? "concat" : take().text
            if op == "||" || op == "&&" {
                newlines()
            };
            let right = try binary(priority + 1, suppress);
            left = Expr(position, .binary(op, left, right))
        }
    }
    func unary(_ suppress: Bool) throws -> Expr {
        if ["!", "-", "+"].contains(text) {
            let token = take();
            return Expr(token.position, .unary(token.text, try unary(suppress)))
        }
        let left = try postfix(suppress)
        if text == "^" {
            let token = take();
            return Expr(token.position, .binary(token.text, left, try unary(suppress)))
        };
        return left
    }
    func prefix(_ suppress: Bool) throws -> Expr {
        let token = take(), value = try lvalue(suppress);
        return Expr(token.position, .increment(token.text == "++" ? 1 : -1, true, value))
    }
    func postfix(_ suppress: Bool) throws -> Expr {
        if text == "++" || text == "--" {
            return try prefix(suppress)
        };
        let body = try atom(suppress)
        if body.lvalue && (text == "++" || text == "--") {
            let token = take();
            return Expr(token.position, .increment(token.text == "++" ? 1 : -1, false, body))
        };
        return body
    }
    func lvalue(_ suppress: Bool) throws -> Expr {
        guard peek.kind == "name" || text == "$" else {
            throw peek.position
        };
        return try atom(suppress)
    }
    func atom(_ suppress: Bool) throws -> Expr {
        let token = peek, kind: ExprKind
        switch token.kind {
            case "number": take();
            kind = .number(Int(token.text)!)
            case "string": take();
            kind = .string(token.value)
            case "name": take();
            if text == "[" {
                take();
                let indices = try expressions(false);
                try expect("]");
                kind = .index(token.text, indices)
            } else {
                kind = .name(token.text)
            }
            case "function", "builtin":
            take();
            let builtin = token.kind == "builtin";
            var arguments: [Expr] = []
            if text == "(" {
                take();
                if text != ")" {
                    arguments = try expressions(false)
                };
                try expect(")")
            }
            else if !builtin || token.text != "length" {
                throw peek.position
            }
            if builtin {
                let n = arguments.count, valid: Bool
                switch token.text {
                    case "length": valid = n <= 1;
                    case "substr": valid = n == 2 || n == 3;
                    case "index": valid = n == 2;
                    case "split": if (n == 2 || n == 3), case .name = arguments[1].kind {
                        valid = true
                    } else {
                        valid = false
                    };
                    case "sprintf": valid = n >= 1;
                    default: valid = n == 1
                }
                if !valid {
                    throw token.position
                }
            };
            kind = .call(token.text, builtin, arguments)
            default:
            switch token.text {
                case "$": take();
                kind = .field(text == "++" || text == "--" ? try prefix(suppress) : try atom(suppress))
                case "(": take();
                let values = try expressions(false);
                try expect(")");
                if values.count == 1 {
                    kind = .parentheses(values[0])
                } else {
                    try expect("in");
                    let name = try self.name();
                    kind = .member(values, name.text, name.position)
                }
                case "getline":
                take();
                let target = peek.kind == "name" || text == "$" ? try lvalue(suppress) : nil;
                var file: Expr?
                if text == "<" {
                    take();
                    file = try atom(suppress)
                };
                kind = .getline(target, file)
                default: throw token.position
            }
        };
        return Expr(token.position, kind)
    }
    func block() throws -> Stmt {
        let position = try expect("{").position;
        var statements: [Stmt] = []
        while text != "}" {
            if peek.kind == "newline" || text == ";" {
                take()
            } else {
                statements.append(try statement())
            }
        };
        try expect("}");
        return Stmt(position, .block(statements))
    }
    func loopBody() throws -> Stmt {
        newlines();
        loops += 1;
        let body = try statement();
        loops -= 1;
        return body
    }
    func statement() throws -> Stmt {
        let token = peek, position = peek.position, kind: StmtKind
        switch text {
            case "{": return try block()
            case ";": take();
            return Stmt(position, .empty)
            case "if": take();
            try expect("(");
            let condition = try expression();
            try expect(")");
            newlines();
            let yes = try statement();
            newlines();
            var no: Stmt?;
            if text == "else" {
                take();
                newlines();
                no = try statement()
            };
            return Stmt(position, .conditional(condition, yes, no))
            case "while": take();
            try expect("(");
            let condition = try expression();
            try expect(")");
            return Stmt(position, .whileLoop(condition, try loopBody()))
            case "do": take();
            let body = try loopBody();
            newlines();
            try expect("while");
            try expect("(");
            let condition = try expression();
            try expect(")");
            kind = .doLoop(body, condition)
            case "for":
            take();
            try expect("(")
            if index + 3 < tokens.count && tokens[index].kind == "name" && tokens[index + 1].text == "in" && tokens[index + 2].kind == "name" && tokens[index + 3].text == ")" {
                let variable = try name();
                take();
                let array = try name();
                take();
                return Stmt(position, .forIn(variable.text, variable.position, array.text, array.position, try loopBody()))
            }
            let initial = text == ";" ? nil : try expression();
            try expect(";");
            newlines();
            let condition = text == ";" ? nil : try expression();
            try expect(";");
            newlines();
            let update = text == ")" ? nil : try expression();
            try expect(")");
            return Stmt(position, .forLoop(initial, condition, update, try loopBody()))
            case "print", "printf":
            take();
            let printf = token.text == "printf", empty = [";", "\n", "}", ">", ">>"].contains(text);
            var parenthesized = false
            if text == "(" {
                var depth = 0;
                for i in index..<tokens.count {
                    if tokens[i].text == "(" {
                        depth += 1
                    } else if tokens[i].text == ")" {
                        depth -= 1;
                        if depth == 0 {
                            parenthesized = i + 1 < tokens.count && ([";", "\n", "}", ">", ">>"].contains(tokens[i + 1].text) || tokens[i + 1].kind == "end");
                            break
                        }
                    }
                }
            }
            if empty && printf {
                throw peek.position
            }
            let arguments: [Expr]
            if empty {
                arguments = []
            } else if parenthesized {
                take();
                arguments = try expressions(false);
                try expect(")")
            } else {
                arguments = try expressions(true)
            }
            var redirect: Redirect?;
            if text == ">" || text == ">>" {
                let op = take();
                redirect = Redirect(append: op.text == ">>", expression: try binary(5, false), position: op.position)
            };
            kind = .output(printf, arguments, redirect)
            case "delete": take();
            let name = try self.name();
            var indices: [Expr]?;
            if text == "[" {
                take();
                indices = try expressions(false);
                try expect("]")
            };
            kind = .delete(name.text, name.position, indices)
            case "next": take();
            if special && !function {
                throw position
            };
            kind = .next
            case "break", "continue": take();
            if loops == 0 {
                throw position
            };
            kind = token.text == "break" ? .breakLoop : .continueLoop
            case "exit", "return": take();
            if token.text == "return" && !function {
                throw position
            };
            let value = [";", "\n", "}"].contains(text) ? nil : try expression();
            kind = token.text == "exit" ? .exit(value) : .returnValue(value)
            default: kind = .expression(try expression())
        };
        try terminator();
        return Stmt(position, kind)
    }
    func program() throws -> Program {
        var rules: [Rule] = [], functions: [Function] = []
        while peek.kind != "end" {
            if text == ";" || peek.kind == "newline" {
                take();
                continue
            };
            let position = peek.position
            if text == "function" {
                take();
                guard peek.kind == "name" || peek.kind == "function" else {
                    throw peek.position
                };
                let name = take();
                try expect("(");
                var parameters: [(String, Position)] = []
                if text != ")" {
                    while true {
                        let parameter = try self.name();
                        parameters.append((parameter.text, parameter.position));
                        if text != "," {
                            break
                        };
                        take();
                        newlines()
                    }
                };
                try expect(")");
                newlines();
                function = true;
                let body = try block();
                function = false;
                functions.append(Function(name: name.text, position: name.position, parameters: parameters, body: body))
            } else if text == "BEGIN" || text == "END" {
                let kind = take().text;
                special = true;
                let action = try block();
                special = false;
                rules.append(Rule(kind: kind, position: position, start: nil, end: nil, action: action))
            }
            else if text == "{" {
                rules.append(Rule(kind: "all", position: position, start: nil, end: nil, action: try block()))
            }
            else {
                let start = try expression();
                var end: Expr?, action: Stmt?
                if text == "," {
                    take();
                    newlines();
                    end = try expression()
                }
                if text == "{" {
                    action = try block()
                } else if text != ";" && peek.kind != "newline" && peek.kind != "end" {
                    throw peek.position
                }
                rules.append(Rule(kind: end == nil ? "pattern" : "range", position: position, start: start, end: end, action: action))
            }
        };
        return Program(rules: rules, functions: functions)
    }
}
