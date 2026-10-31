import Foundation
struct Profile {
    var values: [String: String] = [:]
    func yes(_ key: String) -> Bool {
        values[key] == "yes"
    }
    func number(_ key: String) -> Int {
        Int(values[key]!)!
    }
    var kr: Bool {
        values["brace_style"] == "kr"
    }
}
func attach(_ lexed: Lexed) -> ([Token], Int) {
    var tokens = lexed.tokens
    for (k, entry) in lexed.order.enumerated() where !entry.0 {
        var comment = lexed.comments[entry.1]
        let previous = lexed.order[..<k].last {
            $0.0
        }?.1, next = lexed.order.dropFirst(k + 1).first {
            $0.0
        }?.1
        let nextLine: Int?
        if k + 1 < lexed.order.count {
            let entry = lexed.order[k + 1];
            nextLine = entry.0 ? tokens[entry.1].line : lexed.comments[entry.1].line
        }
        else {
            nextLine = nil
        }
        comment.own = comment.lineComment || (nextLine.map {
            $0 > comment.line
        } ?? true)
        let trailing = previous.map {
            tokens[$0].line == comment.line
        } == true && (next.map {
            tokens[$0].line > comment.line
        } ?? true)
        if trailing {
            tokens[previous!].trailing.append(comment)
        } else {
            tokens[next ?? tokens.count - 1].leading.append(comment)
        }
    }
    return (tokens, lexed.comments.count)
}
func checkComments(_ items: [SyntaxNode], _ tokens: [Token]) throws {
    var allowed: Set<Int> = [tokens.count - 1], tails: Set<Int> = []
    func walk(_ node: SyntaxNode) {
        switch node.kind {
            case "block": allowed.insert(node.tokens[1]);
            for child in node.children {
                allowed.insert(child.start)
            }
            case "switch":
            allowed.insert(node.tokens[4])
            for clause in node.children.dropFirst() {
                allowed.insert(clause.tokens[0]);
                for statement in clause.children.dropFirst(clause.kind == "case" ? 1 : 0) {
                    allowed.insert(statement.start)
                }
            }
            case "if":
            if node.children[1].kind != "block" {
                allowed.insert(node.children[1].start)
            }
            if node.children.count == 3 && node.children[2].kind != "block" && node.children[2].kind != "if" {
                allowed.insert(node.children[2].start)
            }
            case "while": if node.children[1].kind != "block" {
                allowed.insert(node.children[1].start)
            }
            case "for": if node.children[3].kind != "block" {
                allowed.insert(node.children[3].start)
            }
            case "params", "args", "initlist": for child in node.children {
                allowed.insert(child.start)
            };
            if let tail = node.trailing {
                tails.insert(tail)
            }
            default: break
        }
        for child in node.children {
            walk(child)
        }
    }
    for item in items {
        allowed.insert(item.start);
        walk(item)
    }
    for (i, token) in tokens.enumerated() {
        for comment in token.leading where comment.own && !allowed.contains(i) || tails.contains(i) {
            throw SourceError(line: comment.line, column: comment.column, message: "comment not allowed here")
        }
    }
}
final class Construction {
    var tokens: [Token]
    let originalTrailing: [Bool], profile: Profile, docs = DocBuilder()
    init(_ tokens: [Token], _ profile: Profile) {
        self.tokens = tokens;
        self.profile = profile;
        originalTrailing = tokens.map {
            !$0.trailing.isEmpty
        }
    }
    func space() -> Document {
        text(profile.yes("space_around_operators") ? " " : "")
    }
    func keywordSpace() -> Document {
        text(profile.yes("space_after_keyword") ? " " : "")
    }
    func operatorLine() -> Document {
        profile.yes("space_around_operators") ? line() : softline()
    }
    func separator(_ blank: Int) -> Document {
        concat((0...min(blank, profile.number("max_blank_lines"))).map {
            _ in hardline()
        })
    }
    func preblank(_ token: Int) -> Int {
        tokens[token].leading.first?.blank ?? tokens[token].blank
    }
    func comments(_ comments: [Comment], _ next: Int?) -> Document {
        var parts: [Document] = []
        for (i, comment) in comments.enumerated() {
            parts.append(text(comment.text))
            if let blank = i + 1 < comments.count ? comments[i + 1].blank : next {
                parts.append(comment.own ? separator(blank) : text(" "))
            }
        }
        return concat(parts)
    }
    func trailing(_ token: Int) -> Document {
        tokens[token].trailing.isEmpty ? text("") : suffix(tokens[token].trailing.map(\.text).joined(separator: " "))
    }
    func tokenWith(_ token: Int, _ leading: [Comment]) -> Document {
        concat([comments(leading, tokens[token].blank), text(tokens[token].text), trailing(token)])
    }
    func token(_ token: Int) -> Document {
        tokenWith(token, tokens[token].leading)
    }
    func group(_ child: Document) -> Document {
        docs.group(child)
    }
    func level(_ node: SyntaxNode) -> Int {
        node.kind == "conditional" ? 0 : node.kind == "binary" ? Parser.precedence(tokens[node.tokens[0]].text) : node.kind == "unary" ? 7 : 8
    }
    func open(_ node: SyntaxNode, _ level: Int) -> SyntaxNode {
        var current = node
        while profile.yes("remove_parens") && current.kind == "paren" && self.level(current.children[0]) >= level && tokens[current.tokens[0]].leading.isEmpty && tokens[current.tokens[1]].leading.isEmpty {
            let child = current.children[0], open = current.tokens[0], close = current.tokens[1], first = tokens[open].trailing, last = tokens[close].trailing
            tokens[open].trailing = [];
            tokens[close].trailing = []
            tokens[child.start].trailing = first + tokens[child.start].trailing
            tokens[child.end].trailing += last
            current = child
        }
        return current
    }
    func list(_ node: SyntaxNode) -> Document {
        let open = node.tokens[0], close = node.tokens.last!
        if node.children.isEmpty {
            return concat([token(open), token(close)])
        }
        let forced = originalTrailing[node.start..<node.end].contains(true)
        var inside = [softline()]
        for (i, child) in node.children.enumerated() {
            if i > 0 {
                inside += [token(node.tokens[i]), line()]
            }
            inside.append(node.kind == "params" ? parameter(child) : node.kind == "initlist" ? initializer(child) : expression(child, 0))
        }
        if node.kind == "initlist" {
            inside.append(ifBreak(",", ""));
            if let tail = node.trailing {
                inside.append(trailing(tail))
            }
        }
        return group(concat([forced ? breakParent() : text(""), token(open), nest(profile.number("indent"), concat(inside)), softline(), token(close)]))
    }
    func parameter(_ node: SyntaxNode) -> Document {
        var parts = [token(node.tokens[0]), text(" "), token(node.tokens[1])]
        for dimension in node.children {
            parts += [token(dimension.tokens[0]), token(dimension.tokens[1])]
        }
        return concat(parts)
    }
    func declaration(_ node: SyntaxNode) -> Document {
        var parts = [token(node.tokens[0]), text(" "), token(node.tokens[1])], initial: SyntaxNode?
        for child in node.children {
            if child.kind == "dimension" {
                parts.append(token(child.tokens[0]));
                if let expr = child.children.first {
                    parts.append(expression(expr, 0))
                };
                parts.append(token(child.tokens[1]))
            }
            else {
                initial = child
            }
        }
        for t in node.tokens.dropFirst(2) {
            if tokens[t].text == "=" {
                parts += [space(), token(t), space(), initializer(initial!)]
            }
            else {
                parts.append(token(t))
            }
        }
        return concat(parts)
    }
    func initializer(_ node: SyntaxNode) -> Document {
        node.kind == "initlist" ? list(node) : expression(node, 0)
    }
    func closing(_ token: Int) -> ([Comment], [Comment]) {
        let comments = tokens[token].leading, split = comments.lastIndex {
            $0.own
        }.map {
            $0 + 1
        } ?? 0
        return (Array(comments[..<split]), Array(comments[split...]))
    }
    func block(_ node: SyntaxNode) -> Document {
        let close = node.tokens[1], (h, g) = closing(close)
        if node.children.isEmpty && h.isEmpty {
            return concat([token(node.tokens[0]), tokenWith(close, g)])
        }
        var inside = [hardline()]
        for (i, statement) in node.children.enumerated() {
            if i > 0 {
                inside.append(separator(preblank(statement.start)))
            };
            inside.append(self.statement(statement))
        }
        if !h.isEmpty {
            if !node.children.isEmpty {
                inside.append(separator(h[0].blank))
            };
            inside.append(comments(h, nil))
        }
        return concat([token(node.tokens[0]), nest(profile.number("indent"), concat(inside)), hardline(), tokenWith(close, g)])
    }
    func body(_ node: SyntaxNode) -> Document {
        let separator = profile.kr ? text(" ") : hardline()
        if node.kind == "block" {
            return concat([separator, block(node)])
        }
        let document = statement(node)
        if profile.yes("add_braces") {
            return concat([separator, text("{"), nest(profile.number("indent"), concat([hardline(), document])), hardline(), text("}")])
        }
        return nest(profile.number("indent"), concat([hardline(), document]))
    }
    func simple(_ node: SyntaxNode) -> Document {
        if node.kind == "assign" {
            let left = expression(node.children[0], 0), right = expression(node.children[1], 0);
            return concat([left, space(), token(node.tokens[0]), space(), right])
        }
        return expression(node.children[0], 0)
    }
    func clause(_ node: SyntaxNode) -> Document {
        var parts = [token(node.tokens[0])]
        let first = node.kind == "case" ? 1 : 0
        if first == 1 {
            parts += [text(" "), expression(node.children[0], 0)]
        }
        parts.append(token(node.tokens[1]))
        if node.children.count > first {
            var statements = [hardline()]
            for (i, statement) in node.children.dropFirst(first).enumerated() {
                if i > 0 {
                    statements.append(separator(preblank(statement.start)))
                };
                statements.append(self.statement(statement))
            }
            parts.append(nest(profile.number("indent"), concat(statements)))
        }
        return concat(parts)
    }
    func statement(_ node: SyntaxNode) -> Document {
        switch node.kind {
            case "block": return block(node)
            case "decl": return declaration(node)
            case "statement": return concat([simple(node.children[0]), token(node.tokens[0])])
            case "break", "continue": return concat(node.tokens.map(token))
            case "return":
            var parts = [token(node.tokens[0])]
            if let expr = node.children.first {
                parts += [text(" "), expression(expr, 0)]
            }
            return concat(parts + [token(node.tokens[1])])
            case "while", "if":
            let condition = expression(node.children[0], 0), body = self.body(node.children[1])
            var parts = [token(node.tokens[0]), keywordSpace(), token(node.tokens[1]), condition, token(node.tokens[2]), body]
            if node.kind == "if" && node.children.count == 3 {
                parts.append(profile.kr && (node.children[1].kind == "block" || profile.yes("add_braces")) ? text(" ") : hardline());
                parts.append(token(node.tokens[3]))
                if node.children[2].kind == "if" {
                    parts += [text(" "), statement(node.children[2])]
                } else {
                    parts.append(self.body(node.children[2]))
                }
            }
            return concat(parts)
            case "for":
            var inner: [Document] = []
            let initial = node.children[0]
            if initial.kind != "empty" {
                inner.append(initial.kind == "decl" ? declaration(initial) : simple(initial))
            }
            inner.append(token(node.tokens[2]))
            if node.children[1].kind != "empty" {
                inner += [line(), expression(node.children[1], 0)]
            }
            inner.append(token(node.tokens[3]))
            if node.children[2].kind != "empty" {
                inner += [line(), simple(node.children[2])]
            }
            let group = self.group(align(concat(inner))), body = self.body(node.children[3])
            return concat([token(node.tokens[0]), keywordSpace(), token(node.tokens[1]), group, token(node.tokens[4]), body])
            case "switch":
            let close = node.tokens[4], (h, g) = closing(close), condition = expression(node.children[0], 0)
            var parts = [token(node.tokens[0]), keywordSpace(), token(node.tokens[1]), condition, token(node.tokens[2]), profile.kr ? text(" ") : hardline(), token(node.tokens[3])]
            if node.children.count > 1 || !h.isEmpty {
                var inside = [hardline()]
                for (i, clause) in node.children.dropFirst().enumerated() {
                    if i > 0 {
                        inside.append(separator(preblank(clause.start)))
                    };
                    inside.append(self.clause(clause))
                }
                if !h.isEmpty {
                    if node.children.count > 1 {
                        inside.append(separator(h[0].blank))
                    };
                    inside.append(comments(h, nil))
                }
                parts += [nest(profile.yes("indent_case_labels") ? profile.number("indent") : 0, concat(inside)), hardline()]
            }
            return concat(parts + [tokenWith(close, g)])
            default: preconditionFailure()
        }
    }
    func function(_ node: SyntaxNode) -> Document {
        let parameters = list(node.children[0]), block = self.block(node.children[1])
        return concat([token(node.tokens[0]), text(" "), token(node.tokens[1]), parameters, hardline(), block])
    }
    func postfix(_ node: SyntaxNode) -> Document {
        switch node.kind {
            case "call": return list(node.children[1])
            case "index": let index = expression(node.children[1], 0);
            return concat([token(node.tokens[0]), index, token(node.tokens[1])])
            case "member": return concat([token(node.tokens[0]), token(node.tokens[1])])
            default: preconditionFailure()
        }
    }
    func expression(_ original: SyntaxNode, _ required: Int) -> Document {
        let node = open(original, required)
        switch node.kind {
            case "atom": return token(node.tokens[0])
            case "paren": let inner = expression(node.children[0], 0);
            return concat([token(node.tokens[0]), inner, token(node.tokens[1])])
            case "unary": let operand = expression(node.children[0], 8);
            return concat([token(node.tokens[0]), operand])
            case "binary":
            let p = level(node)
            var current = node, entries: [(Int, SyntaxNode)] = []
            while current.kind == "binary" && level(current) == p {
                entries.append((current.tokens[0], current.children[1]));
                current = open(current.children[0], p)
            }
            let head = expression(current, p)
            var rest: [Document] = []
            for (op, right) in entries.reversed() {
                rest += [operatorLine(), token(op), space(), expression(right, p + 1)]
            }
            return group(concat([head, nest(profile.number("indent"), concat(rest))]))
            case "conditional":
            let head = expression(node.children[0], 1)
            var current = node, rest: [Document] = []
            while true {
                rest += [operatorLine(), token(current.tokens[0]), space(), expression(current.children[1], 0), operatorLine(), token(current.tokens[1]), space()]
                let next = open(current.children[2], 0)
                if next.kind == "conditional" {
                    rest.append(expression(next.children[0], 1));
                    current = next
                }
                else {
                    rest.append(expression(next, 0));
                    break
                }
            }
            return group(concat([head, nest(profile.number("indent"), concat(rest))]))
            case "call", "index", "member":
            var current = node, operations: [SyntaxNode] = []
            while ["call", "index", "member"].contains(current.kind) {
                let target = current.children[0];
                operations.append(current);
                current = open(target, 8)
            }
            var segments: [[SyntaxNode]] = [[]]
            for operation in operations.reversed() {
                if operation.kind == "member" {
                    segments.append([])
                };
                segments[segments.count - 1].append(operation)
            }
            let calls = segments.indices.dropFirst().filter {
                segments[$0].contains {
                    $0.kind == "call"
                }
            }
            var parts = [expression(current, 8)]
            if calls.count < 2 {
                for operation in segments.flatMap({
                    $0
                }) {
                    parts.append(postfix(operation))
                };
                return concat(parts)
            }
            let first = calls[0]
            for operation in segments[..<first].flatMap({
                $0
            }) {
                parts.append(postfix(operation))
            }
            var rest: [Document] = []
            for segment in segments[first...] {
                rest.append(softline());
                for operation in segment {
                    rest.append(postfix(operation))
                }
            }
            parts.append(nest(profile.number("indent"), concat(rest)))
            return group(concat(parts))
            default: preconditionFailure()
        }
    }
}
struct Formatted {
    let lines: [String], firstFunction: (String, Document)?, modes: [Int: String], comments: Int
}
func formatSource(_ lines: [String], _ profile: Profile) throws -> Formatted {
    let (tokens, commentCount) = attach(try Lexer.lex(lines)), items = try Parser.parse(tokens)
    try checkComments(items, tokens)
    let empty = items.isEmpty && tokens.last!.leading.isEmpty, builder = Construction(tokens, profile)
    var parts: [Document] = [], firstFunction: (String, Document)?
    for (i, node) in items.enumerated() {
        if i > 0 {
            parts.append(builder.separator(builder.preblank(node.start)))
        }
        let document = node.kind == "function" ? builder.function(node) : builder.declaration(node)
        if node.kind == "function" && firstFunction == nil {
            firstFunction = (builder.tokens[node.tokens[1]].text, document)
        }
        parts.append(document)
    }
    let closing = builder.tokens.last!.leading
    if !closing.isEmpty {
        if !items.isEmpty {
            parts.append(builder.separator(closing[0].blank))
        };
        parts.append(builder.comments(closing, nil))
    }
    if empty {
        return Formatted(lines: [], firstFunction: firstFunction, modes: [:], comments: commentCount)
    }
    let printed = Printer.print(concat(parts), profile.number("width"), profile.number("comment_column"))
    return Formatted(lines: printed.lines, firstFunction: firstFunction, modes: printed.modes, comments: commentCount)
}
struct Source {
    let header: String, name: String, profile: String;
    var lines: [String] = []
}
func inputs() -> ([String: Profile], [Source]) {
    var profiles: [String: Profile] = [:], current = ""
    for line in (try! String(contentsOfFile: "input/style.txt", encoding: .ascii)).split(separator: "\n") {
        if line.first == "[" {
            current = String(line.dropFirst().dropLast());
            profiles[current] = Profile()
        }
        else {
            let a = line.split(separator: "=", omittingEmptySubsequences: false).map(String.init);
            profiles[current, default: Profile()].values[a[0]] = a[1]
        }
    }
    var sources: [Source] = []
    let text = try! String(contentsOfFile: "input/sources.txt", encoding: .ascii)
    for line in text.components(separatedBy: "\n").dropLast() {
        if line.hasPrefix("=== ") {
            let a = line.split(separator: " ").map(String.init);
            sources.append(Source(header: line, name: a[1], profile: a[2]))
        }
        else {
            sources[sources.count - 1].lines.append(line)
        }
    }
    return (profiles, sources)
}
func write(_ name: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: false, encoding: .ascii)
}
func runProgram() {
    let (profiles, sources) = inputs()
    var formatted: [String] = [], idempotency: [String] = [], diagnostics: [String] = [], docTree: [String] = [], changes: [String] = []
    for source in sources {
        let profile = profiles[source.profile]!, original = source.lines.map(Lexer.trim)
        formatted.append(source.header);
        docTree.append("=== \(source.name)");
        changes.append("=== \(source.name)")
        do {
            let first = try formatSource(source.lines, profile)
            formatted += first.lines
            do {
                let second = try formatSource(first.lines, profile)
                if first.lines == second.lines {
                    idempotency.append("\(source.name): stable")
                }
                else {
                    let index = zip(first.lines, second.lines).enumerated().first {
                        $0.element.0 != $0.element.1
                    }?.offset ?? min(first.lines.count, second.lines.count)
                    idempotency.append("\(source.name): unstable at line \(index + 1)")
                }
            } catch let error as SourceError {
                idempotency.append("\(source.name): unstable (second pass: \(error.line):\(error.column): \(error.message))")
            }
            catch {
                preconditionFailure()
            }
            let width = profile.number("width")
            for (i, line) in first.lines.enumerated() where line.count > width {
                diagnostics.append("\(source.name):\(i + 1): warning: line too long (\(line.count) > \(width))")
            }
            let longest = first.lines.map(\.count).max() ?? 0, broken = first.modes.values.filter {
                $0 != "flat"
            }.count, forced = first.modes.values.filter {
                $0 == "forced"
            }.count
            docTree.append("metrics lines=\(first.lines.count) longest=\(longest) comments=\(first.comments) groups=\(first.modes.count) broken=\(broken) forced=\(forced)")
            if let (name, document) = first.firstFunction {
                docTree.append("function \(name)");
                Report.tree(document, 0, first.modes, &docTree)
            }
            else {
                docTree.append("no function")
            }
            changes += Report.diff(original, first.lines)
        } catch let error as SourceError {
            formatted += original;
            idempotency.append("\(source.name): skipped (syntax error)")
            diagnostics.append("\(source.name):\(error.line):\(error.column): error: \(error.message)")
            docTree.append("syntax error");
            changes.append("skipped (syntax error)")
        } catch {
            preconditionFailure()
        }
    }
    if diagnostics.isEmpty {
        diagnostics.append("no diagnostics")
    }
    write("formatted.txt", formatted);
    write("idempotency.txt", idempotency);
    write("diagnostics.txt", diagnostics);
    write("doc_tree.txt", docTree);
    write("changes.txt", changes)
}
runProgram()
