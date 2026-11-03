struct SyntaxNode {
    let kind: String, tokens: [Int], children: [SyntaxNode], start: Int, end: Int
    var trailing: Int?
    init(_ kind: String, _ tokens: [Int], _ children: [SyntaxNode], _ start: Int, _ end: Int) {
        self.kind = kind;
        self.tokens = tokens;
        self.children = children;
        self.start = start;
        self.end = end
    }
}
final class Parser {
    let tokens: [Token]
    var index = 0
    init(_ tokens: [Token]) {
        self.tokens = tokens
    }
    static func isType(_ text: String) -> Bool {
        ["int", "float", "bool", "string", "void"].contains(text)
    }
    static func precedence(_ text: String) -> Int {
        switch text {
            case "||": return 1;
            case "&&": return 2;
            case "==", "!=": return 3;
            case "<", "<=", ">", ">=": return 4;
            case "+", "-": return 5;
            case "*", "/", "%": return 6;
            default: return 0
        }
    }
    var peek: Token {
        tokens[index]
    }
    var text: String {
        peek.text
    }
    func take() -> Int {
        let i = index;
        index += 1;
        return i
    }
    func error(_ expected: String) -> SourceError {
        SourceError(line: peek.line, column: peek.column, message: "expected \(expected), found \(peek.kind == "end" ? "end of file" : "'\(text)'")")
    }
    func symbol(_ text: String) throws -> Int {
        if self.text != text {
            throw error("'\(text)'")
        };
        return take()
    }
    func identifier() throws -> Int {
        if peek.kind != "identifier" {
            throw error("identifier")
        };
        return take()
    }
    func readType() throws -> Int {
        if !Self.isType(text) {
            throw error("type")
        };
        return take()
    }
    func node(_ kind: String, _ tokens: [Int], _ children: [SyntaxNode], _ start: Int) -> SyntaxNode {
        SyntaxNode(kind, tokens, children, start, max(0, index - 1))
    }
    func empty() -> SyntaxNode {
        SyntaxNode("empty", [], [], index, index)
    }
    func list(_ kind: String, _ open: String, _ close: String, _ trailing: Bool) throws -> SyntaxNode {
        let start = index
        var tokens = [try symbol(open)], children: [SyntaxNode] = [], tail: Int?
        if text != close {
            children.append(try listElement(kind))
            while text == "," {
                let comma = take()
                if trailing && text == close {
                    tail = comma;
                    break
                }
                tokens.append(comma);
                children.append(try listElement(kind))
            }
        }
        tokens.append(try symbol(close))
        var result = node(kind, tokens, children, start)
        result.trailing = tail
        return result
    }
    func listElement(_ kind: String) throws -> SyntaxNode {
        if kind == "params" {
            let start = index, tokens = [try readType(), try identifier()]
            var children: [SyntaxNode] = []
            while text == "[" {
                let s = index, pair = [take(), try symbol("]")];
                children.append(node("dimension", pair, [], s))
            }
            return node("parameter", tokens, children, start)
        }
        return kind == "initlist" ? try initializer() : try expression()
    }
    func initializer() throws -> SyntaxNode {
        text == "{" ? try list("initlist", "{", "}", true) : try expression()
    }
    func declaration(_ semicolon: Bool) throws -> SyntaxNode {
        let start = index, tokens = [try readType(), try identifier()];
        return try declarationRest(start, tokens, semicolon)
    }
    func declarationRest(_ start: Int, _ original: [Int], _ semicolon: Bool) throws -> SyntaxNode {
        var tokens = original, children: [SyntaxNode] = []
        while text == "[" {
            let s = index, open = take()
            let content = text == "]" ? [] : [try expression()], close = try symbol("]")
            children.append(node("dimension", [open, close], content, s))
        }
        if text == "=" {
            tokens.append(take());
            children.append(try initializer())
        }
        if semicolon {
            tokens.append(try symbol(";"))
        }
        return node("decl", tokens, children, start)
    }
    func item() throws -> SyntaxNode {
        let start = index, tokens = [try readType(), try identifier()]
        if text == "(" {
            let parameters = try list("params", "(", ")", false), block = try self.block();
            return node("function", tokens, [parameters, block], start)
        }
        return try declarationRest(start, tokens, true)
    }
    func block() throws -> SyntaxNode {
        let start = index, open = try symbol("{")
        var statements: [SyntaxNode] = []
        while text != "}" && peek.kind != "end" {
            statements.append(try statement())
        }
        let close = try symbol("}")
        return node("block", [open, close], statements, start)
    }
    func statement() throws -> SyntaxNode {
        let start = index
        if text == "{" {
            return try block()
        }
        if Self.isType(text) {
            return try declaration(true)
        }
        switch text {
            case "if":
            let keyword = take(), open = try symbol("("), condition = try expression(), close = try symbol(")"), body = try statement()
            var tokens = [keyword, open, close], children = [condition, body]
            if text == "else" {
                tokens.append(take());
                children.append(try statement())
            }
            return node("if", tokens, children, start)
            case "while":
            let keyword = take(), open = try symbol("("), condition = try expression(), close = try symbol(")"), body = try statement()
            return node("while", [keyword, open, close], [condition, body], start)
            case "for":
            let keyword = take(), open = try symbol("("), initial: SyntaxNode
            if text == ";" {
                initial = empty()
            } else if Self.isType(text) {
                initial = try declaration(false)
            } else {
                initial = try simple()
            }
            let first = try symbol(";"), condition = text == ";" ? empty() : try expression(), second = try symbol(";"), update = text == ")" ? empty() : try simple(), close = try symbol(")"), body = try statement()
            return node("for", [keyword, open, first, second, close], [initial, condition, update, body], start)
            case "switch":
            let keyword = take(), open = try symbol("("), condition = try expression(), close = try symbol(")"), left = try symbol("{")
            var children = [condition]
            while text == "case" || text == "default" {
                let s = index, label = take(), kind = tokens[label].text
                var body: [SyntaxNode] = []
                if kind == "case" {
                    body.append(try expression())
                }
                let colon = try symbol(":")
                while !["case", "default", "}"].contains(text) && peek.kind != "end" {
                    body.append(try statement())
                }
                children.append(node(kind, [label, colon], body, s))
            }
            let right = try symbol("}")
            return node("switch", [keyword, open, close, left, right], children, start)
            case "return":
            let keyword = take(), children = text == ";" ? [] : [try expression()], semi = try symbol(";")
            return node("return", [keyword, semi], children, start)
            case "break", "continue": let keyword = take(), kind = tokens[keyword].text, semi = try symbol(";");
            return node(kind, [keyword, semi], [], start)
            default: let expression = try simple(), semi = try symbol(";");
            return node("statement", [semi], [expression], start)
        }
    }
    func simple() throws -> SyntaxNode {
        let start = index, left = try expression()
        if ["=", "+=", "-=", "*=", "/=", "%="].contains(text) {
            let op = take(), right = try expression();
            return node("assign", [op], [left, right], start)
        }
        return node("exprstmt", [], [left], start)
    }
    func expression() throws -> SyntaxNode {
        let start = index, condition = try binary(1)
        if text == "?" {
            let question = take(), yes = try expression(), colon = try symbol(":"), no = try expression();
            return node("conditional", [question, colon], [condition, yes, no], start)
        }
        return condition
    }
    func binary(_ precedence: Int) throws -> SyntaxNode {
        let start = index
        var left = precedence == 6 ? try unary() : try binary(precedence + 1)
        while Self.precedence(text) == precedence {
            let op = take(), right = precedence == 6 ? try unary() : try binary(precedence + 1);
            left = node("binary", [op], [left, right], start)
        }
        return left
    }
    func unary() throws -> SyntaxNode {
        let start = index
        if text == "-" || text == "!" {
            let op = take(), child = try unary();
            return node("unary", [op], [child], start)
        }
        var target = try primary()
        while true {
            switch text {
                case "(": let list = try self.list("args", "(", ")", false);
                target = node("call", [], [target, list], start)
                case "[": let open = take(), expression = try self.expression(), close = try symbol("]");
                target = node("index", [open, close], [target, expression], start)
                case ".": let dot = take(), name = try identifier();
                target = node("member", [dot, name], [target], start)
                default: return target
            }
        }
    }
    func primary() throws -> SyntaxNode {
        let start = index
        if ["identifier", "number", "string"].contains(peek.kind) || text == "true" || text == "false" {
            let token = take();
            return node("atom", [token], [], start)
        }
        if text == "(" {
            let open = take(), child = try expression(), close = try symbol(")");
            return node("paren", [open, close], [child], start)
        }
        throw error("expression")
    }
    static func parse(_ tokens: [Token]) throws -> [SyntaxNode] {
        let parser = Parser(tokens)
        var items: [SyntaxNode] = []
        while parser.peek.kind != "end" {
            items.append(try parser.item())
        }
        return items
    }
}
