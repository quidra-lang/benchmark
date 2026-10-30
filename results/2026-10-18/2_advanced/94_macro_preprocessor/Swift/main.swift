import Foundation
struct Header {
    let name: String, rendering: String, quoted: Bool, end: Int
}
func readHeader(_ tokens: [Token], _ index: Int = 0) throws -> Header? {
    guard index < tokens.count else {
        return nil
    };
    let token = tokens[index]
    if token.kind == "string" || token.kind == "header" {
        return Header(name: String(token.text.dropFirst().dropLast()), rendering: token.text, quoted: token.kind == "string", end: index + 1)
    }
    if token.text == "<" {
        guard let end = ((index + 1)..<tokens.count).first(where: {
            tokens[$0].text == ">"
        }) else {
            throw PPError("missing terminating > character")
        }
        let name = Lexer.render(Array(tokens[(index + 1)..<end]));
        return Header(name: name, rendering: "<" + name + ">", quoted: false, end: end + 1)
    };
    return nil
}
final class ConditionalBlock {
    let kind: String, start: Position, parent: Bool
    var chosen = false, active = false, elseSeen = false, skipStart: Int?
    init(_ kind: String, _ start: Position, _ parent: Bool) {
        self.kind = kind;
        self.start = start;
        self.parent = parent
    }
}
final class Inclusion {
    let path: String, depth: Int
    var file: String, offset = 0, blocks: [ConditionalBlock] = [], segment: [Token] = []
    init(_ path: String, _ depth: Int) {
        self.path = path;
        self.depth = depth;
        file = path
    }
    var active: Bool {
        blocks.last?.active ?? true
    }
    func position(_ physical: Int) -> Position {
        Position(file: file, line: physical + offset)
    }
}
final class Preprocessor {
    let expander = Expander(), includes = IncludeManager()
    var history: [String] = [], ever: Set<String> = [], poison: Set<String> = [], saves: [String: [Macro?]] = [:]
    var output: [String] = [], tree = ["main.c"], records: [String] = [], results: [String] = [], regions: [String] = [], previous = Position(file: "main.c", line: 0)
    func diagnostic(_ position: Position, _ kind: String, _ message: String) {
        expander.diagnostic(position, kind, message)
    }
    func event(_ position: Position, _ text: String) {
        history.append("\(position): \(text)")
    }
    func poisonCheck(_ tokens: [Token], _ state: Inclusion) {
        for token in tokens where token.kind == "identifier" && poison.contains(token.text) {
            diagnostic(state.position(token.line), "error", "attempt to use poisoned \"\(token.text)\"")
        }
    }
    func unused(_ definition: Macro) {
        if definition.main && definition.expanded == 0 && definition.tested == 0 {
            diagnostic(definition.position, "warning", "macro \"\(definition.name)\" is not used")
        }
    }
    func define(_ tokens: [Token], _ position: Position, _ main: Bool) throws {
        let definition = try Definitions.parse(tokens, position, main), name = definition.name
        if let old = expander.table[name] {
            if old.identical(definition) {
                event(position, "identical " + definition.signature);
                return
            }
            unused(old);
            diagnostic(position, "warning", "\"\(name)\" redefined (previous definition at \(old.position))");
            event(position, "redefine " + definition.signature)
        } else {
            event(position, "define " + definition.signature)
        }
        expander.table[name] = definition;
        ever.insert(name)
    }
    func undef(_ tokens: [Token], _ position: Position) throws {
        let name = try Definitions.name(tokens, "undef")
        if tokens.count > 1 {
            diagnostic(position, "warning", "extra tokens at end of #undef directive")
        }
        if let old = expander.table.removeValue(forKey: name) {
            unused(old);
            event(position, "undef " + name)
        } else {
            event(position, "undef \(name) (not defined)")
        }
    }
    func marker(_ file: String, _ line: Int, _ flag: String = "") {
        output.append("# \(line) \"\(file)\"" + flag);
        previous = Position(file: file, line: line - 1)
    }
    func outputLine(_ text: String, _ physical: Int, _ state: Inclusion) {
        let position = state.position(physical)
        if previous.file == position.file && previous.line < position.line && position.line <= previous.line + 8 {
            output += Array(repeating: "", count: position.line - previous.line - 1)
        }
        else {
            marker(position.file, position.line)
        }
        output.append(text);
        previous = position;
        includes.files[state.path]!.output += 1
    }
    func flush(_ state: Inclusion) {
        poisonCheck(state.segment, state);
        let tokens = expander.expand(state.segment, state.file, state.offset);
        state.segment = []
        var i = 0
        while i < tokens.count {
            var end = i + 1;
            while end < tokens.count && tokens[end].line == tokens[i].line {
                end += 1
            };
            outputLine(Lexer.render(Array(tokens[i..<end]), true), tokens[i].line, state);
            i = end
        }
    }
    func defined(_ name: String) -> Bool {
        if let definition = expander.table[name] {
            definition.tested += 1;
            return true
        };
        return builtin(name) || name == "__has_include"
    }
    func replaceOperators(_ tokens: [Token]) throws -> [Token] {
        var result: [Token] = [], i = 0
        while i < tokens.count {
            let token = tokens[i]
            if token.kind == "identifier" && token.text == "defined" {
                i += 1;
                let parenthesis = i < tokens.count && tokens[i].text == "(";
                if parenthesis {
                    i += 1
                }
                guard i < tokens.count && tokens[i].kind == "identifier" else {
                    throw PPError("operator \"defined\" requires an identifier")
                };
                let name = tokens[i].text;
                i += 1
                if parenthesis {
                    guard i < tokens.count && tokens[i].text == ")" else {
                        throw PPError("missing ')' after \"defined\"")
                    };
                    i += 1
                }
                result.append(Token("number", defined(name) ? "1" : "0", token.line, token.space))
            } else if token.kind == "identifier" && token.text == "__has_include" {
                i += 1;
                guard i < tokens.count && tokens[i].text == "(" else {
                    throw PPError("missing '(' after \"__has_include\"")
                };
                i += 1
                guard let header = try readHeader(tokens, i), !header.name.isEmpty else {
                    throw PPError("operator \"__has_include\" requires a header-name")
                };
                i = header.end
                guard i < tokens.count && tokens[i].text == ")" else {
                    throw PPError("missing ')' after \"__has_include\" operand")
                };
                i += 1
                result.append(Token("number", IncludeManager.search(header.name, header.quoted) == nil ? "0" : "1", token.line, token.space))
            } else {
                result.append(token);
                i += 1
            }
        };
        return result
    }
    func test(_ directive: String, _ tokens: [Token], _ position: Position, _ state: Inclusion) -> (Bool, String) {
        poisonCheck(tokens, state)
        if directive != "if" && directive != "elif" {
            if tokens.isEmpty {
                diagnostic(position, "error", "no macro name given in #\(directive) directive");
                return (false, "not taken (error)")
            }
            if tokens[0].kind != "identifier" {
                diagnostic(position, "error", "macro names must be identifiers");
                return (false, "not taken (error)")
            }
            if tokens.count > 1 {
                diagnostic(position, "warning", "extra tokens at end of #\(directive) directive")
            }
            let value = defined(tokens[0].text), taken = directive == "ifndef" || directive == "elifndef" ? !value : value;
            return (taken, taken ? "taken" : "not taken")
        }
        let replaced: [Token]
        do {
            replaced = try replaceOperators(tokens)
        } catch let error as PPError {
            diagnostic(position, "error", error.message);
            return (false, "not taken (error)")
        } catch {
            preconditionFailure()
        }
        let expanded = expander.expand(replaced, state.file, state.offset), (value, diagnostics) = ExpressionParser.test(expanded, directive)
        for (kind, message) in diagnostics {
            diagnostic(position, kind, message)
        }
        let result = value.map {
            ($0 != 0 ? "taken" : "not taken") + " (value \($0))"
        } ?? "not taken (error)"
        return ((value ?? 0) != 0, result + " [" + Lexer.render(expanded, true) + "]")
    }
    func close(_ block: ConditionalBlock, _ end: Int, _ state: Inclusion) {
        if let start = block.skipStart, end >= start {
            regions.append("\(state.file):\(start + state.offset)-\(end + state.offset) lines=\(end - start + 1)");
            includes.files[state.path]!.skippedLines += end - start + 1
        };
        block.skipStart = nil
    }
    func conditional(_ directive: String, _ operands: [Token], _ line: LogicalLine, _ state: Inclusion) {
        let position = state.position(line.tokens[0].line), opening = ["if", "ifdef", "ifndef"].contains(directive), level = opening ? state.blocks.count : state.blocks.count - 1
        let result: String
        if opening {
            let block = ConditionalBlock(directive, position, state.active)
            if block.parent {
                let (taken, text) = test(directive, operands, position, state);
                block.chosen = taken;
                block.active = taken;
                if !taken {
                    block.skipStart = line.end + 1
                };
                result = text
            } else {
                result = "skipped"
            }
            state.blocks.append(block)
        } else {
            guard let block = state.blocks.last else {
                diagnostic(position, "error", "#\(directive) without #if");
                return
            }
            close(block, line.start - 1, state)
            if directive == "endif" {
                state.blocks.removeLast();
                if block.parent && !operands.isEmpty {
                    diagnostic(position, "warning", "extra tokens at end of #endif directive")
                };
                result = "closes #\(block.kind) at line \(block.start.line)"
            } else {
                if block.elseSeen {
                    diagnostic(position, "error", "#\(directive) after #else")
                }
                if directive == "else" {
                    if block.parent && !operands.isEmpty {
                        diagnostic(position, "warning", "extra tokens at end of #else directive")
                    };
                    block.elseSeen = true
                    if block.parent {
                        block.active = !block.chosen;
                        block.chosen = true;
                        result = block.active ? "taken" : "not taken"
                    } else {
                        result = "skipped"
                    }
                } else if !block.parent {
                    block.active = false;
                    result = "skipped"
                }
                else if block.chosen {
                    block.active = false;
                    result = "not evaluated"
                }
                else {
                    let (taken, text) = test(directive, operands, position, state);
                    block.active = taken;
                    if taken {
                        block.chosen = true
                    };
                    result = text
                }
                if block.parent && !block.active {
                    block.skipStart = line.end + 1
                }
            }
        }
        let rendering = "#" + directive + (operands.isEmpty ? "" : " " + Lexer.render(operands))
        records.append("\(position): " + String(repeating: " ", count: 2 * level) + rendering + " => " + result);
        results.append(result)
    }
    func include(_ operands: [Token], _ line: LogicalLine, _ state: Inclusion) throws {
        let position = state.position(line.tokens[0].line);
        var tokens = operands, header = try readHeader(tokens)
        if header == nil && !tokens.isEmpty {
            tokens = expander.expand(tokens, state.file, state.offset);
            header = try readHeader(tokens)
        }
        guard let header else {
            throw PPError("#include expects \"FILENAME\" or <FILENAME>")
        }
        if header.end < tokens.count {
            diagnostic(position, "warning", "extra tokens at end of #include directive")
        }
        if header.name.isEmpty {
            throw PPError("empty filename in #include")
        }
        let prefix = String(repeating: " ", count: 2 * (state.depth + 1)) + "\(line.tokens[0].line): "
        guard let path = IncludeManager.search(header.name, header.quoted) else {
            tree.append(prefix + header.rendering + " [not found]");
            throw PPError("cannot find include file " + header.rendering)
        }
        if let file = includes.files[path] {
            if file.once {
                tree.append(prefix + path + " [skipped: pragma once]");
                file.skipped += 1;
                return
            }
            if let guardName = file.guardName, expander.table[guardName] != nil {
                tree.append(prefix + path + " [skipped: guard \(guardName)]");
                file.skipped += 1;
                return
            }
        }
        if state.depth + 1 > 8 {
            tree.append(prefix + path + " [too deep]");
            throw PPError("#include nested too deeply")
        }
        tree.append(prefix + path);
        marker(path, 1, " 1");
        process(path, state.depth + 1);
        marker(state.file, line.end + 1 + state.offset, " 2")
    }
    func pragma(_ operands: [Token], _ line: LogicalLine, _ position: Position, _ state: Inclusion) throws {
        let first = operands.first
        if first?.kind == "identifier" && first?.text == "once" {
            if operands.count > 1 {
                diagnostic(position, "warning", "extra tokens at end of #pragma once directive")
            }
            if state.depth == 0 {
                diagnostic(position, "warning", "#pragma once in main file")
            };
            includes.files[state.path]!.once = true
        } else if operands.count >= 2 && operands[0].text == "GCC" && operands[1].text == "poison" {
            if operands.dropFirst(2).contains(where: {
                $0.kind != "identifier"
            }) {
                throw PPError("invalid #pragma GCC poison directive")
            }
            for token in operands.dropFirst(2) {
                if expander.table[token.text] != nil {
                    diagnostic(position, "warning", "poisoning existing macro \"\(token.text)\"")
                };
                poison.insert(token.text)
            }
        } else if first?.kind == "identifier" && ["push_macro", "pop_macro"].contains(first!.text) {
            let command = first!.text
            guard operands.count == 4 && operands[1].text == "(" && operands[2].kind == "string" && operands[3].text == ")" else {
                throw PPError("invalid #pragma \(command) directive")
            }
            let name = String(operands[2].text.dropFirst().dropLast())
            if command == "push_macro" {
                saves[name, default: []].append(expander.table[name]);
                event(position, "push " + name)
            }
            else if saves[name, default: []].isEmpty {
                diagnostic(position, "warning", "no matching push_macro for \"\(name)\"")
            }
            else {
                let old = saves[name]!.removeLast();
                expander.table[name] = old;
                event(position, "pop " + name + (old == nil ? " (undefined)" : ""))
            }
        } else {
            outputLine("#pragma" + (operands.isEmpty ? "" : " " + Lexer.render(operands)), line.tokens[0].line, state)
        }
    }
    func directive(_ name: String, _ operands: [Token], _ line: LogicalLine, _ state: Inclusion) {
        let position = state.position(line.tokens[0].line)
        if line.tokens.count == 1 {
            return
        }
        if !(name == "pragma" && operands.count >= 2 && operands[0].text == "GCC" && operands[1].text == "poison") {
            poisonCheck(operands, state)
        }
        do {
            switch name {
                case "define": try define(operands, position, state.depth == 0)
                case "undef": try undef(operands, position)
                case "include": try include(operands, line, state)
                case "line":
                func decimal(_ token: Token) -> Bool {
                    token.kind == "number" && !token.text.isEmpty && token.text.utf8.allSatisfy {
                        (48...57).contains($0)
                    }
                }
                let tokens = operands.first.map(decimal) ?? false ? operands : expander.expand(operands, state.file, state.offset)
                guard (1...2).contains(tokens.count), decimal(tokens[0]), tokens.count == 1 || tokens[1].kind == "string" else {
                    throw PPError("invalid #line directive")
                }
                guard let number = Int(tokens[0].text), (1...2147483647).contains(number) else {
                    throw PPError("line number out of range")
                }
                state.offset = number - line.end - 1;
                if tokens.count == 2 {
                    state.file = String(tokens[1].text.dropFirst().dropLast())
                }
                case "error", "warning": diagnostic(position, name == "error" ? "error" : "warning", "#" + name + (operands.isEmpty ? "" : " " + Lexer.render(operands)))
                case "pragma": try pragma(operands, line, position, state)
                default: throw PPError("invalid preprocessing directive #" + line.tokens[1].text)
            }
        } catch let error as PPError {
            diagnostic(position, "error", error.message)
        } catch {
            preconditionFailure()
        }
    }
    func process(_ path: String, _ depth: Int) {
        let file = includes.enter(path), state = Inclusion(path, depth)
        for line in file.lines {
            let tokens = line.tokens
            if tokens.first?.text == "#" {
                let name = tokens.count >= 2 && tokens[1].kind == "identifier" ? tokens[1].text : "", operands = Array(tokens.dropFirst(2))
                if ["if", "ifdef", "ifndef", "elif", "elifdef", "elifndef", "else", "endif"].contains(name) {
                    flush(state);
                    conditional(name, operands, line, state)
                }
                else if state.active {
                    flush(state);
                    directive(name, operands, line, state)
                }
            } else if state.active {
                state.segment += tokens
            }
        }
        flush(state)
        for block in state.blocks {
            close(block, file.physicalLines, state)
        }
        for block in state.blocks {
            diagnostic(block.start, "error", "unterminated #" + block.kind)
        }
    }
    func run() {
        let definitions = try! String(contentsOfFile: "input/defines.txt", encoding: .ascii).components(separatedBy: "\n")
        for (i, line) in definitions.enumerated() where !line.isEmpty {
            var text = line
            if let equals = text.firstIndex(of: "=") {
                text.replaceSubrange(equals...equals, with: " ")
            } else {
                text += " 1"
            }
            let position = Position(file: "defines.txt", line: i + 1), tokens = Lexer.lex(text + "\n").flatMap(\.tokens)
            do {
                try define(tokens, position, false)
            } catch let error as PPError {
                diagnostic(position, "error", error.message)
            } catch {
                preconditionFailure()
            }
        }
        marker("main.c", 1);
        process("main.c", 0)
        for name in expander.table.keys.sorted() {
            unused(expander.table[name]!)
        };
        finish()
    }
    func finish() {
        var includeLines = tree + ["", "== files =="]
        for path in includes.files.keys.sorted() {
            let file = includes.files[path]!;
            includeLines.append("\(path) entered=\(file.entered) skipped=\(file.skipped) lines=\(file.physicalLines) output_lines=\(file.output) skipped_lines=\(file.skippedLines) guard=\(file.guardName ?? "-") once=\(file.once ? "yes" : "no")")
        }
        includeLines.append("");
        var dependency = "main.o:", hasPath = false
        for path in includes.order {
            if dependency.count + 1 + path.count > 76 && hasPath {
                includeLines.append(dependency + " \\");
                dependency = " ";
                hasPath = false
            };
            dependency += " " + path;
            hasPath = true
        };
        includeLines.append(dependency)
        let table = expander.table;
        var references: [String: [String]] = [:]
        for (name, definition) in table {
            let parameters = Set(definition.parameters ?? []);
            references[name] = Set(definition.replacement.filter {
                $0.kind == "identifier" && table[$0.text] != nil && !parameters.contains($0.text)
            }.map(\.text)).sorted()
        }
        func recursive(_ name: String) -> Bool {
            var seen: Set<String> = [], pending = references[name]!;
            while let current = pending.popLast() {
                if current == name {
                    return true
                };
                if seen.insert(current).inserted {
                    pending += references[current]!
                }
            };
            return false
        }
        var macros = ["== history =="] + history + ["", "== table =="]
        for name in table.keys.sorted() {
            let definition = table[name]!;
            macros += [definition.definition, "  at \(definition.position) expanded=\(definition.expanded) tested=\(definition.tested) recursive=\(recursive(name) ? "yes" : "no")", "  refs:" + references[name]!.map {
                " " + $0
            }.joined()]
        }
        let functionLike = table.values.filter {
            $0.parameters != nil
        }.count
        macros += ["", "macros=\(table.count) object_like=\(table.count - functionLike) function_like=\(functionLike)", "undefined:" + ever.subtracting(Set(table.keys)).sorted().map {
            " " + $0
        }.joined(), "builtins: __COUNTER__=\(expander.uses["__COUNTER__"]!) __FILE__=\(expander.uses["__FILE__"]!) __LINE__=\(expander.uses["__LINE__"]!)"]
        func count(_ prefix: String) -> Int {
            results.filter {
                $0.hasPrefix(prefix)
            }.count
        }
        let conditionals = records + ["", "== skipped regions =="] + regions + ["", "directives=\(records.count) taken=\(count("taken")) not_taken=\(count("not taken")) skipped=\(count("skipped")) not_evaluated=\(count("not evaluated")) endif=\(count("closes")) regions=\(regions.count)"]
        let errors = expander.diagnostics.filter {
            $0.kind == "error"
        }.count
        let diagnostics = expander.diagnostics.map {
            "\($0.position): \($0.kind): \($0.message)"
        } + ["errors=\(errors) warnings=\(expander.diagnostics.count - errors)"]
        write("preprocessed.txt", output);
        write("includes.txt", includeLines);
        write("macros.txt", macros);
        write("conditionals.txt", conditionals);
        write("diagnostics.txt", diagnostics)
    }
}
func write(_ name: String, _ lines: [String]) {
    try! FileManager.default.createDirectory(atPath: "output", withIntermediateDirectories: true)
    try! (lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n").write(toFile: "output/" + name, atomically: true, encoding: .utf8)
}
Preprocessor().run()
