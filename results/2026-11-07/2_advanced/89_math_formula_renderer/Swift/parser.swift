indirect enum Node {
    case atom(String, String, Int), row([Node]), binary(String, Node, Node), root(Node?, Node)
    case script(Node, Node?, Node?), delimited(String, String, Node, Int), matrix(String, [[Node]]), accent(String, Node)
    static var empty: Self {
        .row([])
    }
    var isEmpty: Bool {
        if case .row(let elements) = self {
            return elements.isEmpty
        };
        return false
    }
}
struct Formula {
    let elements: [Node], tag: (String, Int)?, label: (String, Int)?
}
final class Parser {
    let tokens: [Token], eof: Token
    var index = 0, tag: (String, Int)?, label: (String, Int)?
    init(_ tokens: [Token], _ end: Int) {
        self.tokens = tokens;
        eof = Token(kind: "eof", value: "", column: end)
    }
    var peek: Token {
        index < tokens.count ? tokens[index] : eof
    }
    @discardableResult func take() -> Token {
        let token = peek;
        if index < tokens.count {
            index += 1
        };
        return token
    }
    func unexpected() -> FormulaError {
        let message: String
        switch peek.kind {
            case "right": message = "unexpected \\right"
            case "end": message = "unexpected \\end"
            case "&": message = "misplaced &"
            case "newline": message = "misplaced \\\\"
            default: message = "unexpected end of input"
        }
        return FormulaError(peek.column, message)
    }
    static func collapse(_ nodes: [Node]) -> Node {
        nodes.count == 1 ? nodes[0] : .row(nodes)
    }
    func list(_ top: Bool = false, _ rootIndex: Bool = false) throws -> [Node] {
        var result: [Node] = []
        while true {
            let token = peek
            if ["}", "&", "newline", "right", "end", "eof"].contains(token.kind) || rootIndex && token.kind == "symbol" && token.value == "]" {
                return result
            }
            if token.kind == "tag" || token.kind == "label" {
                if !top {
                    throw FormulaError(token.column, "misplaced \\\(token.kind)")
                }
                if (token.kind == "tag" ? tag : label) != nil {
                    throw FormulaError(token.column, "duplicate \\\(token.kind)")
                }
                if token.kind == "tag" {
                    tag = (token.value, token.column)
                } else {
                    label = (token.value, token.column)
                }
                take();
                continue
            }
            result.append(try element())
        }
    }
    func element() throws -> Node {
        let base = peek.kind == "^" || peek.kind == "_" ? Node.empty : try nucleus()
        var sub: Node?, sup: Node?
        while peek.kind == "^" || peek.kind == "_" {
            let token = take()
            if (token.kind == "^" ? sup : sub) != nil {
                throw FormulaError(token.column, token.kind == "^" ? "double superscript" : "double subscript")
            }
            let value = try argument(token.kind)
            if token.kind == "^" {
                sup = value
            } else {
                sub = value
            }
        }
        return sub != nil || sup != nil ? .script(base, sub, sup) : base
    }
    func argument(_ name: String) throws -> Node {
        if ["identifier", "number", "symbol", "command", "text", "eqref", "{", "frac", "binom", "overset", "underset", "sqrt", "accent"].contains(peek.kind) {
            return try nucleus()
        }
        throw FormulaError(peek.column, "missing argument for \(name)")
    }
    func delimiter() throws -> String {
        let token = take()
        if token.kind == "symbol" && ["(", ")", "[", "]", "|", "."].contains(token.value) || token.kind == "command" && ["\\{", "\\}"].contains(token.value) {
            return token.value
        }
        throw FormulaError(token.column, "invalid delimiter")
    }
    func nucleus() throws -> Node {
        let token = take()
        switch token.kind {
            case "identifier", "number", "symbol", "command", "text", "eqref": return .atom(token.kind, token.value, token.column)
            case "{":
            let nodes = try list()
            if peek.kind != "}" {
                throw unexpected()
            }
            take();
            return Self.collapse(nodes)
            case "frac", "binom", "overset", "underset":
            let name = "\\" + token.kind, first = try argument(name), second = try argument(name)
            return .binary(token.kind, first, second)
            case "sqrt":
            var rootIndex: Node?
            if peek.kind == "symbol" && peek.value == "[" {
                let column = take().column, nodes = try list(false, true)
                if peek.kind != "symbol" || peek.value != "]" {
                    throw FormulaError(column, "missing ]")
                }
                take();
                rootIndex = Self.collapse(nodes)
            }
            return .root(rootIndex, try argument("\\sqrt"))
            case "accent": return .accent(token.value, try argument("\\" + token.value))
            case "left":
            let left = try delimiter(), nodes = try list()
            if peek.kind != "right" {
                throw FormulaError(token.column, "missing \\right")
            }
            let column = take().column, right = try delimiter()
            return .delimited(left, right, Self.collapse(nodes), column)
            case "begin":
            var rows: [[Node]] = [[]]
            while true {
                rows[rows.count - 1].append(Self.collapse(try list()))
                let end = take()
                if end.kind == "&" {
                    continue
                }
                if end.kind == "newline" {
                    rows.append([]);
                    continue
                }
                if end.kind == "end" {
                    if end.value != token.value {
                        throw FormulaError(end.column, "mismatched \\end")
                    };
                    break
                }
                throw FormulaError(token.column, "missing \\end")
            }
            if rows.count > 1 && rows.last!.count == 1 && rows.last![0].isEmpty {
                rows.removeLast()
            }
            let width = rows.map(\.count).max()!
            for i in rows.indices {
                rows[i] += Array(repeating: Node.empty, count: width - rows[i].count)
            }
            return .matrix(token.value, rows)
            default: preconditionFailure()
        }
    }
    static func parse(_ tokens: [Token], _ end: Int) throws -> Formula {
        var braces: [Int] = []
        for token in tokens {
            if token.kind == "{" {
                braces.append(token.column)
            }
            else if token.kind == "}" && braces.popLast() == nil {
                throw FormulaError(token.column, "unmatched }")
            }
        }
        if let column = braces.last {
            throw FormulaError(column, "unclosed {")
        }
        let parser = Parser(tokens, end), elements = try parser.list(true)
        if parser.peek.kind != "eof" {
            throw parser.unexpected()
        }
        return Formula(elements: elements, tag: parser.tag, label: parser.label)
    }
}
